# System-Service → `/var/lib/dsh` Multi-Tenant Migration (dsh)

**Status:** Entwurf / Migrationsplan — noch nicht implementiert  
**Ziel:** dsh läuft als **persistenter System-Service** eines dedizierten `dsh`-System-Users mit **`DSH_HOME=/var/lib/dsh`** (MTAA-konform, `multi-tenancy.md §3`), d. h. die Config-Dokumente werden **systemseitig** gerendert statt im Home-Manager-Benutzerverzeichnis.
**Ausgangslage (erreicht & stabil):** `ai.rls.ancoris.ovh` läuft als `systemd.services.dsh-web` (`User=philipp`, `DSH_HOME=/home/philipp/.dsh`), OIDC-Login funktioniert. Diese Funktionalität MUSS während der Migration erhalten bleiben.

---

## 0. Warum und was ist zu ändern

Heute materialisiert **Home-Manager** die dsh-Config unter `~/.dsh` (`home.file`): `settings.yaml`, `cordis.patch.yml`, `.credentials.yaml` (sops-Symlink), `profiles/`, `node_modules/`. Der System-Service (als philipp) liest das.

Für **Multi-Tenancy** nach MTAA soll dsh einem dedizierten `dsh`-System-User gehören und die Config unter `/var/lib/dsh` liegen (`/var/lib/dsh/tenants/<u>/`). Das erfordert, die **Config-Doc-Berechnung** vom Home-Manager-Modul auf **NixOS-Systemebene** zu heben, sodass die Dokumente dort gerendert werden können.

---

## 1. Architektur-Ziel

```
systemd.services.dsh-web  (User=dsh, Group=dsh)
  ├── DSH_HOME=/var/lib/dsh
  ├── settings.yaml, cordis.patch.yml   ← NixOS-generiert, nicht home-manager
  ├── .credentials.yaml                  ← sops-Template (systemseitig)
  ├── profiles/<name>/{package.json,cordis.patch.yml} ← NixOS-generiert
  ├── node_modules/<plugin>              ← Store-Symlinks
  └── Memory: /var/lib/dsh/… (memory.db, tenants/<u>/, auth/presence.db)
```

**Kein** Home-Manager-`~/.dsh`-User-Service mehr für den öffentlichen Node; nur der System-Daemon.

---

## 2. Design-Entscheidungen

- **Operator-Config:** `settingsDoc`/`homePatch`/`pluginConfigs`/`profiles`/`node_modules` werden aus `systemCfg` (+ einem expliziten Operator) auf NixOS-Ebene berechnet — **nicht** mehr aus dem Home-Manager-`userCfg`, da die Instanz multi-tenant ist.
- **Secrets:** `dsh-oidc.env` (OIDC-Client-Secret) + `.credentials.yaml` bleiben sops-Templates; die dienen jetzt dem `dsh`-User.
- **Dedizierter User:** `users.users.dsh` (isSystemUser, home `/var/lib/dsh`, group `dsh`).
- **Sicherheit:** Die Migration läuft **inkrementell/verifiziert**; der funktionierende `User=philipp`-Pfad bleibt bis zum erfolgreichen Umschalten aktiv (Blue/Green-artig), damit `ai.rls.ancoris.ovh` nie ausfällt.

---

## 3. Phasen (& Verifikations-Gate je Phase)

| Phase | Inhalt | Gate |
|---|---|---|
| **P1 Config-Doc-Hoist** | `settingsDoc`/`homePatch`/`pluginConfigs`/`renderedProfiles`/`activePluginDrvs`/`allConfiguredFacts` von der Home-Manager-`let` in eine **top-level Funktion** `mkDshRuntime { systemCfg; osConfig; userCfg; }` heben; HM + NixOS nutzen dieselbe Funktion (keine Duplikation). | `nix flake check` grün; HM-Output unverändert (regression-frei) |
| **P2 `dsh`-User + `/var/lib/dsh`** | `users.users.dsh` (home `/var/lib/dsh`), `users.groups.dsh`, `systemd.tmpfiles` für `/var/lib/dsh/tenants/<u>/`. | rollins eval: `users.users.dsh.home=/var/lib/dsh` |
| **P3 Config nach `/var/lib/dsh`** | NixOS rendert `settings.yaml`/`cordis.patch.yml`/`.credentials.yaml`/`profiles/`/`node_modules/` nach `/var/lib/dsh` (via `systemd.tmpfiles` + Generierung), **Home-Manager-`~/.dsh`-Materialisierung für den System-Modus deaktiviert**. | rollins: `/var/lib/dsh/settings.yaml` vorhanden & von `dsh`-User lesbar |
| **P4 Service-Umschalten** | `systemd.services.dsh-web` → `User=dsh`, `DSH_HOME=/var/lib/dsh`, OIDC-`EnvironmentFile`. | rollins eval: `User=dsh`, `DSH_HOME=/var/lib/dsh` |
| **P5 Memory/Secrets** | Memory-`dbPath`/Tenant-Pfade, `auth/presence.db` unter `/var/lib/dsh`; sops-Secrets Owner → `dsh`. | Pfade unter `/var/lib/dsh`, Owner `dsh` |
| **P6 Verifikation** | `nix flake check` + rollins-Home-Build + Service-Eval; **Rollback-Punkt** = `User=philipp`-Pfad bleibt als drv im Store. | build grün; `ai.rls.ancoris.ovh` nach Redeploy → 200 + OIDC-Login |

---

## 4. Sicherheits- & Rollback-Garantien

- **Kein Ausfallzeitpunkt:** Solange P4 nicht abgeschlossen ist, läuft `User=philipp`/`~/.dsh` weiter. Erst wenn die `/var/lib/dsh`-Config in P3 vorhanden UND im P4-Build bestätigt ist, wird umgeschaltet.
- **Verifikation vor Umschalten:** Der neue Generations-Toplevel wird `nix build`t und das gerenderte `/var/lib/dsh/settings.yaml` geprüft, **bevor** der Rollout den alten Pfad entfernt.
- **Rollback:** Die alte Generation (philipp/`~/.dsh`) bleibt im Store; ein `nixos-rebuild switch` zurück ist einzeilig.

---

## 5. Offene Punkte / Risiken

1. **Home-Manager `config`-Zugriff:** `userCfg`-Anteile (philipp-personal `userFacts`/`userPeers`/`instructions`) sind für eine Multi-Tenant-Instanz fraglich — sollen sie in `/var/lib/dsh` eingehen (scope-gated) oder dem Operator zugeordnet werden? → Entscheidung.
2. **`currentUser`/`defaultUser`:** dsh-auth `loopback`/Facts nutzen `currentUser` (philipp) — für den System-`dsh`-User müssen diese als Operator gesetzt werden.
3. **Credentials lesbar:** Das `dsh`-User muss `.credentials.yaml`/`dsh-oidc.env` lesen (Owner/Group), sonst `EACCES` beim Start.
4. **Migration der bestehenden Memory-/Presence-Daten** von `~/.dsh` → `/var/lib/dsh` (falls bereits Daten existieren) — sonst Neustart mit leerem Gedächtnis.

---

## 6. Nächste Schritte

1. **P1** umsetzen (Config-Doc-Hoist) — unabhängig, verifizierbar, ohne Funktionalität zu ändern.
2. P2–P4 in aufeinanderfolgenden, verifizierten Commits.
3. Vor dem Live-Umschalten: `nix flake check` + rollins-Build + `/var/lib/dsh`-Inhalt prüfen.
4. Rollout (rollins) mit Rollback-Punkt dokumentiert.

---
*Migrationsplan für die dsh-Multi-Tenant-System-Service-/`/var/lib/dsh`-Migration. Grundlage: `multi-tenancy.md §3`, aktuelle System-Service-Implementierung (`systemd.services.dsh-web`).*
