# Feature Ideation, Ergonomie-Innovationen und Future Roadmap

Dieses Dokument dokumentiert die abgestimmten, akademisch sauberen und praxisnahen Kern-Erweiterungen für das DeepSeek Harness (`dsh`) als grafische Desktop- und Web-Harness-Umgebung.

---

## 1. Abgestimmter Feature-Katalog (Prioritär)

### 1.1 Dual-Pane Interactive Canvas & Artifacts (`dsh-canvas`)
- **Status:** Vollständig ausdetailliert in `docs/dsh/01-dual-pane-canvas.md` und `docs/dsh/01-canvas-deep-dive-plan.md`.
- **Kern:** Entkopplung von Chat-Strom und Code-Artefakten im Split-Pane mit Monaco-Engine, gezieltem In-Place Refactoring (`Strg+K`), sandboxed Web-Previews und Revisions-Historie.

### 1.2 Active Context Chips & Git Diff Pinning (`dsh-context-chips`)
- **Status:** Spezifiziert in `docs/dsh/02-context-pinning-git-diff.md`.
- **Kern:** Interaktive Context-Pills (`@git:diff`, `@file`) im Composer mit visueller Token-Budget-Leiste und staleness-resistentem Session-Pinning.

### 1.3 Declarative LSP Code Intelligence (`dsh-lsp`)
- **Status:** Spezifiziert in `docs/dsh/03-declarative-lsp-intelligence.md`.
- **Kern:** Direkte NixOS-Anbindung von Store-Binaries (`nil`, `typescript-language-server`, `pyright`, `gopls`) für typ- und symbolgenaue Codegenerierung sowie Vorab-Prüfung.

### 1.4 Distributed Session Synchronization & Handoff Fabric (`dsh-mesh`)
- **Status:** Vollständig spezifiziert in `docs/dsh/04-distributed-session-sync-and-handoff.md`.
- **Kern:** P2P & VPS-Relay-gestützte Delta-Replikation von Zstandard-Event-Logs, Distributed Write Leases gegen Split-Brain und portable Workspace-Resolution für nahtloses Arbeiten über alle Geräte hinweg.

### 1.5 Semantic AST & Tree-sitter Code Intelligence (`dsh-ast-nav`)
- **Status:** In Ausarbeitung.
- **Kern:** Syntaxbaum-basierte Abfragen (Funktionshierarchien, Scope-Auflösung, Typ-Definitionen) für präzises Code-Verständnis jenseits von unscharfem Text-Grep.

### 1.5 Time-Travel Session Branching & Conversation DAG (`dsh-branching`)
- **Status:** In Ausarbeitung.
- **Kern:** Visueller U-Bahn-Netzplan der Konversation im UI, um an jedem Turn alternative Lösungswege parallel zu forken und zu vergleichen.

### 1.6 Voice-to-Intent & Push-to-Talk (`dsh-voice`)
- **Status:** In Ausarbeitung.
- **Kern:** Lokale Whisper-Integration mit Push-to-Talk im Composer und Code-Token-Erkennung für flüssiges Pair-Programming per Sprache.

### 1.7 Universal Contract-Driven Verification (`dsh-verify-contract`)
- **Status:** In Ausarbeitung.
- **Kern:** Projektagnostische Validierung via `.dsh/contract.yml` oder Auto-Discovery (`flake.nix`, `Cargo.toml`, etc.), damit der Agent Codeänderungen nach definierten Projektregeln eigenständig prüft.

---

## 2. Abgelehnte / Verworfene Ideen

- **Terminal Stream Replay**: Unnötig in einer vollwertigen Desktop-/Web-UI-Umgebung mit dedizierten Tool-Widgets.
- **Context Compression / Sliding Window Pruning**: Zu heuristisch und birgt Kontextverlust-Risiken; widerspricht der deterministischen Prompt-Transparenz.
- **Workspace Attention Heatmap**: Geringer Mehrwert bei hoher visueller Unruhe.
- **Ephemeral MicroVM Sandboxes**: Zu hoher Overhead für den aktuellen Einsatzzweck.
- **Forgejo CI Webhook Bot**: Durch existierendes `dsh-ingress` bereits vollständig abgedeckt.
