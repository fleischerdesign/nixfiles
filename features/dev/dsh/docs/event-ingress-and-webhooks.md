# Event Ingress, Webhooks & Reactive Trigger Mesh

Diese Spezifikation beschreibt die Architektur des **Event Ingress Layers** in `dsh`. Sie erweitert traditionelle Push-Webhooks zu einem robusten, ausfallsicheren und entkoppelten System, das HTTP-Webhooks, Prometheus/Grafana-Alerts und lokale Systemd-Events vereint.

---

## 1. Problemstellung & Motivation

Autonome Agenten agieren meist synchron (Prompt $\to$ Response). In modernen Infrastrukturen müssen Agenten jedoch **reaktiv auf Ereignisse** reagieren:
- Git-Pushes auf Forgejo/GitHub (CI/CD Automatisierung).
- Prometheus Alertmanager Meldungen (Out-of-Memory, Disk Full, Cert Expiry).
- Lokale Systemd-Unit Failures (`caddy.service` abgestürzt).

Ein naiver Webhook-Ansatz leidet unter drei fundamentalen Mängeln:
1. **Alert Storms & Denial of Service:** Wenn ein Switch ausfällt und 50 Alerts innerhalb von 2 Sekunden eintreffen, darf der Agent nicht 50 parallele LLM-Sessions starten, die API-Quotas sprengen und Git-Locks blockieren.
2. **Replay-Attacks & Spoofing:** Ohne kryptographische Signatur- und Frischeprüfung können gefälschte Payloads unerwünschte Aktionen auslösen.
3. **Transport-Inhomogenität:** Lokale Kernel-/Systemd-Events besitzen keine HTTP-Webhooks.

---

## 2. Der Dreistufige Ingress-Stack

```
+------------------------+  +--------------------------+  +--------------------------+
| HTTP Webhooks (Caddy)  |  | Prometheus Alertmanager  |  | Local Journal Watcher    |
| (GitHub, Forgejo, etc.)|  | (Metrics, SLO Violations)|  | (Systemd Unit Failures)  |
+------------------------+  +--------------------------+  +--------------------------+
            |                             |                             |
            \                             |                             /
             v                            v                            v
+------------------------------------------------------------------------------------+
|                         dsh Event Ingress Gateway (Daemon)                         |
|  - Cryptographic Verification (HMAC-SHA256, Nonce, Timestamp drift <= 300s)       |
|  - Payload Normalization into CloudEvents v1.0 Envelope                            |
+------------------------------------------------------------------------------------+
                                          |
                                          v
+------------------------------------------------------------------------------------+
|                  Deduplication, Debouncing & Rate-Limiting Engine                  |
|  - Sliding-Window Debounce (tau_debounce = 15s)                                    |
|  - Leaky Bucket Token Pool per Tenant / Event Type                                 |
+------------------------------------------------------------------------------------+
                                          |
                                          v
+------------------------------------------------------------------------------------+
|               Persistent Priority Task Queue (SQLite WAL / Redis)                  |
|  - Priority: P0 (System Outage) > P1 (CI/Push) > P2 (Scheduled / Maintenance)      |
+------------------------------------------------------------------------------------+
                                          |
                                          v
+------------------------------------------------------------------------------------+
|                     dsh Task Worker (Isolated Worktree Execution)                  |
+------------------------------------------------------------------------------------+
```

---

## 3. Formales Event-Modell (CloudEvents v1.0 Konformität)

Jedes eingehende Ereignis $E$ wird in ein standardisiertes 6-Tupel normalisiert:

$$E = \langle \text{id}, \text{source}, \text{type}, \text{time}, \text{tenant}, \text{data}, \sigma \rangle$$

- **id ($\text{UUIDv4}$):** Eindeutige Idempotenz-ID.
- **source ($\text{URI}$):** Quelle des Ereignisses (z. B. `urn:nixos:host:mackaye:systemd`, `urn:git:forgejo:org/repo`).
- **type ($\text{String}$):** Typisierte Kategorie (z. B. `infra.alert.firing`, `vcs.push.completed`).
- **time ($t_{\text{event}}$):** ISO-8601 Zeitstempel der Erzeugung.
- **tenant ($\text{TenantID}$):** Ziel-Tenant (z. B. `philipp` oder `system`).
- **data ($\text{JSON}$):** Payload mit Details (Labels, Commit-Hash, Exit-Code).
- **$\sigma$ (Signature):** HMAC-SHA256 Signatur zur Integritätsprüfung:
  $$\sigma = \text{HMAC-SHA256}(K_{\text{webhook}}, \text{timestamp} \mathbin{\Vert} \text{payload})$$

### Sicherheitsregeln:
- **Timestamp Drift Protection:** $|t_{\text{now}} - t_{\text{event}}| \le 300\text{s}$. Veraltete Events werden sofort verworfen.
- **Nonce/ID Dedup:** Bereits in den letzten 24 Stunden verarbeitete IDs werden mit HTTP 200 (No-Op) quittiert.

---

## 4. Debouncing & Alert Storm Suppression

Wenn Prometheus 50 Warnungen für denselben Fehler schickt, wendet `dsh` eine **Sliding-Window Aggregation** an:

$$\Delta t_{\text{debounce}} = 15\text{s}$$

1. Trifft ein Ereignis $E_1$ mit Fingerprint $H(E_1) = \text{Hash}(\text{type} \mathbin{\Vert} \text{source} \mathbin{\Vert} \text{labels})$ ein, wird ein Timer gestartet.
2. Treffen innerhalb von $\Delta t_{\text{debounce}}$ weitere identische Events $E_2, \dots, E_k$ ein, werden sie aggregiert:
   $$E_{\text{aggregated}}.\text{data.occurrences} \leftarrow k$$
3. Erst nach Ablauf des Fensters wird **ein einziger** konsolidierter Agenten-Task in die Queue gestellt.

---

## 5. Lokaler Systemd-Journal Ingress

Um Server-Probleme (z. B. auf `mackaye` oder `strummer`) ohne HTTP-Roundtrips zu erfassen, läuft ein leichtgewichtiger Journal-Tailer als Subservice (`features/dev/dsh/journal-watcher`):

```bash
# Formale Filter-Invariante für systemd-journal
journalctl -f -o json --priority=err..emerg
```

Tritt eine Meldung auf, die auf eine überwachte Unit (`caddy.service`, `forgejo.service`, `postgresql.service`) zutrifft, transformiert der Watcher diese via IPC-Socket (`/run/dsh/ingress.sock`) in ein $E$-Tupel.

---

## 6. Autonomer Reparatur-Workflow (Beispiel)

1. **Alert:** Prometheus meldet: `DiskSpaceFillingUp (Host: strummer, Filesystem: /nix)`.
2. **Ingress:** Gate verifiziert und bündelt die Meldung $\to$ erzeugt Task in Queue mit Priorität $P_0$.
3. **Dispatch:** `dsh` startet Task mit strikter Capability:
   - Read: `journalctl`, `df -h`, `nix-store --gc --print-dead`.
   - Action: Agent führt `nix-collect-garbage --delete-older-than 7d` aus.
4. **Verifikation:** Agent prüft `df -h`. Ist wieder $> 15\%$ Speicher frei, gilt der Task als erfolgreich.
5. **Notification:** Agent sendet kurze Benachrichtigung via Ntfy/Telegram an den Admin:
   *"[Auto-Healing] Disk-Space auf strummer bereinigt. 42 GB freigegeben."*
