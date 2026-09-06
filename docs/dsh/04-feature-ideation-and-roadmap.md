# Feature Ideation, Ergonomie-Innovationen und Future Roadmap

Dieses Dokument dient als kuratierte Sammelstelle für geprüfte, akademisch saubere und systemagnostische Erweiterungen im DeepSeek Harness (`dsh`).

---

## 1. Bereinigte & validierte Feature-Kandidaten

### 1.1 Semantic AST & Tree-sitter Code Intelligence (`dsh-ast-nav`)
- **Status:** Hohe Priorität, essenzieller Code-Intelligence-Baustein.
- **Problemstellung:**
  - Vektor-Embeddings und Volltextsuche (`grep`, `ripgrep`) sind blind für Syntaxstrukturen.
  - LLMs übersehen bei Refactorings oft Methodenüberladungen, Vererbungshierarchien oder importierte Typen.
- **Architektur & Funktionsweise:**
  - Headless Tree-sitter Daemon / Parser im Node-Prozess oder via WASM-Grammatiken für alle relevanten Sprachen (Nix, TypeScript, Rust, Python, Go, Bash, C).
  - Stellt dem Agenten exakte syntaktische Abfrage-Tools bereit:
    - `ast_find_symbols(pattern, kind: "function" | "class" | "type" | "nix_option")`
    - `ast_get_call_hierarchy(symbol, direction: "incoming" | "outgoing")`
    - `ast_get_scope_definitions(filePath, line, col)`
  - Ermöglicht dem Modell ein strukturelles Verständnis des Repositories, bevor Code editiert wird.

---

### 1.2 Time-Travel Session Branching & Conversation DAG (`dsh-branching`)
- **Status:** Hohe Priorität, direkte Ergonomie- und UX-Verbesserung.
- **Problemstellung:**
  - Lineare Chats zwingen Entwickler in eine Sackgasse, wenn ein Prompt-Turn in die falsche Richtung abbiegt.
  - Das Löschen von Nachrichten führt zu Kontextverlust; das Weiterschreiben mit "Vergiss das vorherige" verwirrt das LLM.
- **Architektur & Funktionsweise:**
  - Der Session-Speicher modelliert die Konversation nicht als flache Liste, sondern als gerichteten azyklischen Graphen (DAG) von Turns.
  - An jedem Turn existiert ein `[Fork / Branch]’-Aktionspunkt.
  - **UI/UX:**
    - Ein interaktiver History-Navigator (Git-Tree-Style / U-Bahn-Netzplan) im Header oder in der Seitenleiste.
    - Nahtloses Umschalten zwischen parallelen Experimentier-Zweigen innerhalb derselben Session (`Branch A: Redis Sentinel` vs. `Branch B: Redis Cluster`).
    - Paralleles Erhalten von Zwischenergebnissen und Artefakten.

---

### 1.3 Voice-to-Intent & Push-to-Talk (`dsh-voice`)
- **Status:** Mittlere Priorität, starker Ergonomie-Gewinn beim Pair-Programming.
- **Problemstellung:**
  - Längere Gedanken, architektonische Zusammenhänge oder komplexe Refactoring-Absichten im Code lassen sich oft viel schneller sprechen als tippen.
  - Cloud-basierte Spracherkennung verletzt lokale Datenschutzprinzipien.
- **Architektur & Funktionsweise:**
  - Lokale Whisper-Integration (z. B. via `whisper.cpp` Daemon auf `jello` oder als lokaler Stream-Endpunkt).
  - Push-to-Talk Button (oder Shortcut `Leertaste` halten / `Alt+V`) direkt im DSH-Composer.
  - **Streaming-Transkription:** Sprache fließt live als Text in das Eingabefeld.
  - **Code-Token Heuristik:** Erkennung technischer Begriffe (CamelCase, Snake_case, Pfade, Symbole), damit gesprochenes "nix flake check" nicht als "Nix Flake Check" oder "nix like check" landet.

---

### 1.4 Universeller Projekt-Contract / Manifest-gesteuerte Verifikation (`dsh-verify-contract`)
- **Status:** Neu konzipiert (agnostische Weiterentwicklung der Test-Loop).
- **Problemstellung:**
  - Jedes Projekt nutzt andere Build-Tools (`cargo`, `nix`, `npm`, `pnpm`, `make`, `pytest`, `go test`, `gradle`).
  - Ein hartcodierter Mechanismus ist unbrauchbar und verletzt das Agnostizitäts-Prinzip von `/etc/nixos/AGENTS.md`.
- **Architektur & Lösungsansatz:**
  - **Projekt-Agnostischer Kontrakt (`.dsh/contract.yml` oder Auto-Discovery):**
    - Statt feste Befehle vorzuschreiben, definiert das Projekt oder das Repository einen standardisierten Verifikations-Kontrakt:
      ```yaml
      # .dsh/contract.yml (optional im Repo-Root oder via DSH-Settings)
      verify:
        lint: "nixfmt --check && statix check"
        build: "nix build .#nixosConfigurations.jello.config.system.build.toplevel"
        test: "nix flake check"
      ```
    - **Zero-Config Fallback:** Erkennt automatisch vorhandene Standarddateien:
      - `flake.nix` -> `nix flake check`
      - `Cargo.toml` -> `cargo check && cargo test`
      - `package.json` -> `npm test` (falls Script vorhanden)
      - `Makefile` -> `make check` oder `make test`
  - **Autonomer Feedback-Loop:**
    - Wenn aktiviert, führt DSH nach dem Anwenden von Diffs den definierten Verify-Befehl im Projektverzeichnis aus.
    - Schlägt der Kontrakt fehl, analysiert der Agent die Exit-Codes und Stderr-Ausgaben selbstständig in einem internen Sub-Turn.

---

## 2. Aussortierte / Verworfene Ideen

| Feature-Idee | Entscheidung | Begründung |
|---|---|---|
| **Hardcodierte Test & Fix Loop** | **Verworfen** | Zu unflexibel. Ersetzt durch das universelle, manifest-gesteuerte Modell (`dsh-verify-contract`). |
| **Ephemeral MicroVM Sandboxes** | **Zurückgestellt** | Aktuell kein Bedarf; Overhead und Komplexität stehen in keinem Verhältnis zum unmittelbaren Mehrwert. |
| **Forgejo / CI Webhook Bot** | **Verworfen** | Redundant. Das Webhook-Ingress-System (`dsh-ingress`) existiert bereits und deckt Event-getriebene Anwendungsfälle vollständig ab. |

---

## 3. Neue Ideensammlung: Weitere High-Value Konzepte

Welche zusätzlichen Konzepte bieten echten praktischen Mehrwert?

1. **Terminal Stream Replay & Session Recording (`dsh-terminal-cast`)**:
   - Strukturierte Erfassung aller Terminal-Outputs inklusive ANSI-Colors.
   - Der Benutzer kann interaktiv durch Terminal-Historien scrollen, Fehlerzeilen anklicken und mit einem Klick *"Erkläre diesen Stacktrace"* an den Agenten senden.
2. **Context Compression & Selective Sliding Window (`dsh-context-prune`)**:
   - Wenn Konversationen sehr lang werden (> 60k Tokens), fasst das System alte Turns nicht plump zusammen, sondern behält exakt die aufgerufenen Tool-Signaturen und Dateipfade im Fokus, während repetitive Ausgaben komprimiert werden.
3. **Workspace File-Tree HUD mit Live Agent Attention Tracker**:
   - Eine dezente Datei-Explorer-Leiste, die visuell anzeigt, welche Dateien der Agent gerade im aktuellen Turn gelesen, analysiert oder modifiziert hat (Heatmap der Agent-Aufmerksamkeit).
