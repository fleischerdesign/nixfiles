# DeepSeek Harness (DSH): Vollständiges Client-Slot-Inventar

Dieses Dokument listet alle im Upstream-Repository (`/tmp/deepseek-harness/packages/client/`) typisierten **SlotMap-Slots** auf, geordnet nach Domäne, Funktionsbereich und Quellmodul.

---

## 1. Conversation & Chat Surface

| Slot-Name | Kind | Scope | Quellpaket | Beschreibung / Verwendung |
|---|---|---|---|---|
| `conversation.view` | `list` | `session` | `ui-conversation` | **Hauptansichten-Registry.** Hier registrieren sich `chat`, `canvas`, `plan` etc. Erzeugt Tabs im Session-Header. |
| `conversation.session` | `single` | `session` | `ui-conversation` | Gesamter Session-Body unterhalb des Headers (beherbergt Scrollport und Composer). |
| `conversation.session.header` | `single` | `session` | `ui-conversation` | Header-Chrome der Session (Titel, Tab-Leiste). |
| `conversation.session.header.actions` | `list` | `session` | `ui-conversation` | Aktions-Buttons im Session-Header (rechts). |
| `conversation.session.header.utilities` | `list` | `session` | `ui-conversation` | Utility-Tools im Header (z. B. Canvas-Toggle, Stats). |
| `conversation.session.header.lineage` | `single` | `session` | `ui-conversation` | Anzeige von Fork- und Branching-Stammbäumen der Session. |
| `conversation.chat.node` | `keyed` | `session` | `ui-chat` | **Render-Slot für Chat-Nachrichten.** Keyed by `ChatNodeKind` (`assistant`, `tool`, `user`, etc.). |
| `conversation.chat.commandview` | `keyed` | `session` | `ui-chat` | Visualisierung von Slash-Befehlen im Chat. |
| `conversation.chat.assistant-actions` | `list` | `session` | `ui-chat` | Aktionsleiste unter einer Assistant-Nachricht (Copy, Retry, Fork). |
| `conversation.message.images` | `single` | `session` | `ui-chat` | Galerie-Renderer für Bild-Anhänge in Chat-Nachrichten. |
| `conversation.approval.detail` | `single` | `session` | `ui-approval` | Detail-Panel für Human-in-the-Loop Freigaben. |
| `conversation.details.tool` | `single` | `session` | `ui-chat` | Detail-Ansicht für Tool-Aufrufe (Rechte Schublade / Drawer). |
| `conversation.trajectory.images` | `single` | `session` | `ui-trajectory` | Bild-Visualisierung in Trajectory-Ansichten. |

---

## 2. Composer, Input & Eingabeleiste

| Slot-Name | Kind | Scope | Quellpaket | Beschreibung / Verwendung |
|---|---|---|---|---|
| `conversation.composer` | `chain` | `session` | `ui-conversation` | Vollständiger Ersatz / Wrapping des Eingabebereichs. |
| `conversation.composer.bar` | `single` | `session` | `ui-conversation` | Die eigentliche Composer-Eingabezeile. |
| `conversation.composer.dock` | `list` | `session` | `ui-conversation` | Dock über/unter dem Composer (z. B. Token-Budget, Statuszeile). |
| `conversation.input.dock` | `list` | `session` | `ui-conversation` | Zusätzliche Toolbars/Docks am Eingabefeld. |
| `conversation.input.left` | `list` | `session` | `ui-conversation` | Icons/Buttons links im Eingabefeld (z. B. Attachment, Mic). |
| `conversation.input.right` | `list` | `session` | `ui-conversation` | Buttons rechts im Eingabefeld (Send, Abort). |
| `conversation.input.attachments`| `list` | `session` | `ui-conversation` | Anzeige angehängter Dateien/Bilder im Composer. |
| `conversation.input.overlay` | `single` | `session` | `ui-conversation` | Dropdown-Overlays über dem Composer (z. B. `@mention`-Vorschläge). |
| `conversation.input.model` | `single` | `session` | `ui-conversation` | Modellauswahl-Dropdown im Composer. |
| `conversation.input.plan` | `single` | `session` | `ui-conversation` | Planungs-Badge/Trigger im Composer. |

---

## 3. Blank-Session Hero (Willkommensbildschirm)

| Slot-Name | Kind | Scope | Quellpaket | Beschreibung / Verwendung |
|---|---|---|---|---|
| `conversation.hero.workspace` | `single` | `root` | `ui-conversation` | Workspace-Picker im leeren Startbildschirm. |
| `conversation.hero.brand.mark` | `single` | `root` | `ui-conversation` | Logo/Markenzeichen im leeren Startbildschirm. |

---

## 4. Sidebar & Global Navigation

| Slot-Name | Kind | Scope | Quellpaket | Beschreibung / Verwendung |
|---|---|---|---|---|
| `sidebar.brand.mark` | `single` | `root` | `ui-sidebar` | App-Logo oben in der linken Seitenleiste. |
| `sidebar.brand.name` | `single` | `root` | `ui-sidebar` | Titel / Org-Name in der Seitenleiste (von `dsh-auth` genutzt). |
| `sidebar.workspaces` | `list` | `root` | `ui-sidebar` | Workspace- und Projekt-Navigation in der Seitenleiste. |
| `sidebar.footer.action` | `list` | `root` | `ui-sidebar` | Aktionen unten in der Seitenleiste (z. B. Share-Modal-Listener). |
| `sidebar.settings` | `single` | `root` | `ui-sidebar` | Settings-Trigger-Button ganz unten in der Seitenleiste. |

---

## 5. Settings, Plugins & Modals

| Slot-Name | Kind | Scope | Quellpaket | Beschreibung / Verwendung |
|---|---|---|---|---|
| `settings.section` | `list` | `root` | `ui-settings` | Kategorien im Settings-Dialog (Allgemein, Modelle, Plugins). |
| `settings.general.item` | `list` | `root` | `ui-settings` | Einstellungszeilen im Bereich „Allgemein“. |
| `settings.plugins.tab` | `list` | `root` | `ui-settings` | Tabs im Bereich „Plugins“. |
| `settings.plugin.item` | `keyed` | `root` | `ui-settings-plugins`| Konfigurationszeile für ein spezifisches Plugin. |
| `settings.models.provider-card`| `keyed`| `root` | `ui-settings-models` | Provider-Karte für LLM-Anbieter (DeepSeek, Ollama, etc.). |
| `settings.models.footer` | `list` | `root` | `ui-settings-models` | Footer-Optionen in den Modell-Einstellungen. |
| `settings.header` | `single` | `root` | `ui-settings` | Header des Einstellungsfensters. |
| `settings.close` | `single` | `root` | `ui-settings` | Schließen-Button der Einstellungen. |
| `settings.action` | `list` | `root` | `ui-settings` | Globale Aktionen innerhalb der Einstellungen. |
| `settings.trigger` | `single` | `root` | `ui-settings` | Trigger zum Öffnen der Einstellungen. |
| `settings.onboarding` | `single` | `root` | `ui-settings` | Onboarding-Dialog beim ersten Start. |

---

## 6. App Shell & Tool View

| Slot-Name | Kind | Scope | Quellpaket | Beschreibung / Verwendung |
|---|---|---|---|---|
| `shell.overlay` | `list` | `root` | `ui-layout` | Globales Overlay-Layer (für systemweite Dialoge und Modals). |
| `tool.call.toolview` | `keyed` | `session` | `ui-tool` | Angepasste Rendering-Karten für spezifische Tool-Aufrufe. |
| `tool.call.images` | `single` | `session` | `ui-tool` | Bildausgaben von Tools. |
