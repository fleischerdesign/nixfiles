# ILIAS eCampus Client — Read-Only Integration Plan

> **For Hermes:** Implement via direct execution (no subagent needed — this is a single-file Python module).

**Goal:** A robust, read-only Python client for ILIAS eCampus (WBS Training) that exposes all student-relevant data: courses, modules, lessons, exams, Berichtsheft entries, calendar, and search — via session-cookie authentication.

**Architecture:** Single-file `ilias_client.py` with clean CLI + Python API. Session-cookie-based auth via `PHPSESSID`. Only HTTP GET requests — zero mutation risk. Structured output via dataclasses/JSON.

**Tech Stack:** Python 3.12+, `requests`, `html.parser`/regex, dataclasses, `json`.

**Safety Constraint:** **NEVER use POST/PUT/DELETE.** Validate all URLs before requesting. No form submissions, no button clicks, no state-changing operations. If a URL contains `cmd=post`, `cmd=delete`, `cmd=revoke`, `cmd=update`, `cmd=save`, `cmd=create`, `cmd=add` — **abort with error**.

**Base URL:** `https://ecampus.wbstraining.de` | **Client ID:** `wbs50` | **ILIAS Version:** 7.18

---

## Discovered Endpoints & Data Structures

### Authentication
- Cookie: `PHPSESSID=<value>` (from browser DevTools → Application → Cookies)
- All requests need `User-Agent: Mozilla/5.0`

### Dashboard (`ilDashboardGUI`)
- URL: `ilias.php?baseClass=ilDashboardGUI&cmd=jumpToMemberships`
- Extracts: courses (crs_*), groups (grp_*), recommended content, favorites

### Repository / Course Browser (`ilrepositorygui`)
- URL: `ilias.php?ref_id=<id>&cmd=view&cmdClass=ilrepositorygui&cmdNode=xe&baseClass=ilrepositorygui`
- Extracts: child items with ref_ids, titles, icons (folders, files, tests, learning modules)

### Berichtsheft (`ildigitalreportsgui`)
- URL: `ilias.php?cmd=reportsstudent.list&cmdClass=ildigitalreportsgui&cmdNode=163:ad&baseClass=iluipluginroutergui`
- Extracts: weekly reports with date range, submission date, status (Angenommen/Neu/Abgelehnt), request_id
- User ID discovered: `8042150`
- Actions observed (DO NOT USE): `reportsstudent.revokereport`, `reportsstudent.editreport`, `reportsstudent.printreport`

### Known Reference IDs
| Ref-ID | Name | Type |
|--------|------|------|
| 16353 | US_IT Umschulung FIAE/SI (IHK) | Course |
| 7655824 | Sommerkurse 2025 | Folder |
| 7750392 | US_IT-80.3 (Philipp's group) | Group |
| 7750398 | Unterrichtsmaterial | Folder |
| 7750468 | Prüfungen | Folder |
| 7750396 | Berichtshefte | Folder |
| 7750410 | TF_US_PPP (Java) | Folder |
| 7750430 | TF_US_DBP (Datenbanken) | Folder |

---

## Implementation Tasks

### Task 1: Core Client Class with Safety Guard

**Objective:** Create `IliasClient` with session management and URL safety filter.

**File:** Modify `/data/workspace/ilias_client.py`

```python
import os
import re
import json
import requests
from dataclasses import dataclass, field, asdict
from datetime import datetime
from typing import Optional
from html import unescape

BASE_URL = "https://ecampus.wbstraining.de"
CLIENT_ID = "wbs50"

# ⛔ BLOCKED URL patterns — never request these
FORBIDDEN_PATTERNS = [
    r'cmd=(post|delete|revoke|update|save|create|add|remove|edit|withdraw)',
    r'cmdClass=ilmail',
    r'action=delete',
]

class IliasSafetyError(Exception):
    """Raised when a potentially mutating request is blocked."""
    pass

class IliasClient:
    """Read-only ILIAS eCampus client."""
    
    def __init__(self, session_cookie: str = None):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        })
        cookie = session_cookie or os.environ.get("ILIAS_SESSION")
        if cookie:
            self.session.cookies.set("PHPSESSID", cookie, domain="ecampus.wbstraining.de")
        self._base = BASE_URL
    
    def _check_safety(self, url: str):
        """Abort if URL contains forbidden patterns."""
        for pattern in FORBIDDEN_PATTERNS:
            if re.search(pattern, url, re.IGNORECASE):
                raise IliasSafetyError(
                    f"⛔ BLOCKED: URL contains potentially mutating action.\n"
                    f"   Pattern: {pattern}\n   URL: {url[:120]}"
                )
    
    def _get(self, path: str, params: dict = None) -> requests.Response:
        """Safe GET request with URL validation."""
        url = f"{self._base}/{path.lstrip('/')}" if not path.startswith('http') else path
        self._check_safety(url)
        resp = self.session.get(url, params=params)
        resp.raise_for_status()
        # Detect if redirected to login
        if "login.php" in resp.url:
            raise AuthError("Session expired. Get a fresh PHPSESSID cookie.")
        return resp
    
    def _ensure_auth(self):
        """Verify we're authenticated."""
        resp = self._get("/ilias.php", {"lang": "de", "client_id": CLIENT_ID})
        if "login.php" in resp.url:
            raise AuthError("Not authenticated. Set ILIAS_SESSION env var.")
```

**Verification:** `python3 -c "from ilias_client import IliasClient; c = IliasClient(); c._ensure_auth()"` → prints nothing (success) or AuthError

---

### Task 2: Dashboard — Courses & Groups

**Objective:** Parse dashboard for course/group list with ref_ids, titles, types.

**Add to `IliasClient`:**

```python
@dataclass
class CourseItem:
    ref_id: int
    title: str
    item_type: str  # "course", "group", "folder", "weblink", "category"

def get_dashboard(self) -> list[CourseItem]:
    """Get all courses and groups from dashboard."""
    resp = self._get("/ilias.php", {
        "baseClass": "ilDashboardGUI",
        "cmd": "jumpToMemberships",
    })
    return self._parse_items(resp.text)
```

Parsing: Extract `<a href="ilias.php?ref_id=XXX"...>Title</a>` from course/group sections. Detect type from surrounding icon markers (`Symbol Kurs`, `Symbol Gruppe`, etc.).

**Verification:** `python3 ilias_client.py dashboard` → prints table with ref_id, type, title

---

### Task 3: Repository Browser — List Child Items

**Objective:** Navigate any ref_id and list its children.

```python
def get_children(self, ref_id: int) -> list[CourseItem]:
    """List contents of a folder/course/group."""
    resp = self._get("/ilias.php", {
        "ref_id": ref_id,
        "cmd": "view",
        "cmdClass": "ilrepositorygui",
        "cmdNode": "xe",
        "baseClass": "ilrepositorygui",
    })
    return self._parse_items(resp.text)
```

Skip breadcrumb items (ref_ids 1, 67, 89, 875, and the current ref_id).

**Verification:** `python3 ilias_client.py browse 7750398` → lists all 32 modules

---

### Task 4: Berichtsheft Parser

**Objective:** Parse the digital report book for weekly entries.

```python
@dataclass
class ReportEntry:
    week_start: str       # "04. Aug 2025"
    week_end: str         # "10. Aug 2025" 
    submitted: str        # "09. Sep 2025"
    status: str           # "Angenommen", "Neu", "Abgelehnt"
    request_id: int       # 101946
    user_id: int          # 8042150

def get_reports(self) -> list[ReportEntry]:
    """Get all Berichtsheft entries."""
    resp = self._get("/ilias.php", {
        "cmd": "reportsstudent.list",
        "cmdClass": "ildigitalreportsgui",
        "cmdNode": "163:ad",
        "baseClass": "iluipluginroutergui",
    })
    return self._parse_reports(resp.text)
```

Parse each table row: extract date range, submission date, status, request_id, user_id.

**Verification:** `python3 ilias_client.py reports` → prints 45+ entries with status

---

### Task 5: Exams/Prüfungen Parser

**Objective:** List all exams with dates from the Prüfungen folder (ref_id=7750468).

```python
@dataclass  
class ExamEntry:
    ref_id: int
    title: str           # "TF_US_PPP - Prüfung 16.01.2026 - Programmiersprache Java"
    module_code: str     # "TF_US_PPP"
    date: str            # "16.01.2026"
    is_retry: bool       # "Nachprüfung" in title

def get_exams(self, ref_id: int = 7750468) -> list[ExamEntry]:
    """Get all exams from a folder."""
    children = self.get_children(ref_id)
    return [self._parse_exam_title(c) for c in children if "Prüfung" in c.title]
```

**Verification:** `python3 ilias_client.py exams` → prints 18 exams with module codes and dates

---

### Task 6: Calendar / Events

**Objective:** Extract ILIAS calendar data.

```python
@dataclass
class CalendarEvent:
    date: str
    title: str
    ref_id: Optional[int]

def get_calendar(self) -> list[CalendarEvent]:
    """Get upcoming calendar events from dashboard."""
    resp = self._get("/ilias.php", {
        "baseClass": "ilDashboardGUI",
        "cmd": "jumpToMemberships",
    })
    return self._parse_calendar(resp.text)
```

Parse the calendar widget from dashboard sidebar.

**Verification:** `python3 ilias_client.py calendar` → lists upcoming events

---

### Task 7: Search

**Objective:** Search ILIAS for content.

```python
def search(self, query: str) -> list[CourseItem]:
    """Search ILIAS for objects matching query."""
    resp = self._get("/ilias.php", {
        "baseClass": "ilSearchControllerGUI",
        "cmd": "remoteSearch",
        "query": query,
        "client_id": CLIENT_ID,
    })
    return self._parse_search_results(resp.text)
```

**Verification:** `python3 ilias_client.py search "Java"` → lists matching items

---

### Task 8: Progress / Lernfortschritt

**Objective:** Check learning progress status.

```python
def get_progress(self, ref_id: int) -> dict:
    """Get learning progress percentage for a ref_id."""
    resp = self._get("/ilias.php", {
        "ref_id": ref_id,
        "cmd": "view",
        "cmdClass": "ilrepositorygui",
        "cmdNode": "xe",
        "baseClass": "ilrepositorygui",
    })
    # Parse progress badge/percentage from the page
    return self._parse_progress(resp.text)
```

**Verification:** `python3 ilias_client.py progress 7750410` → shows PPP module completion %

---

### Task 9: Clean CLI Interface

**Objective:** Polished command-line interface with formatted output.

```python
# CLI commands:
#   ilias_client.py dashboard     — Courses + groups table
#   ilias_client.py browse <id>   — List children of ref_id
#   ilias_client.py exams         — All exams with dates
#   ilias_client.py reports       — Berichtsheft entries
#   ilias_client.py report <id>   — Single report details
#   ilias_client.py calendar      — Upcoming events
#   ilias_client.py search <q>    — Search ILIAS
#   ilias_client.py progress <id> — Learning progress
#   ilias_client.py summary       — Everything at a glance
```

Output format: Markdown tables (works in Telegram), JSON mode with `--json` flag.

**Verification:** Each command runs and produces clean, readable output.

---

### Task 10: Session Cookie Auto-Discovery

**Objective:** Try to read cookie from browser profile if available.

```python
def discover_cookie(self) -> Optional[str]:
    """Try to find PHPSESSID from local browser storage."""
    # Check env var first
    if os.environ.get("ILIAS_SESSION"):
        return os.environ["ILIAS_SESSION"]
    # Check Firefox/Camofox cookies.sqlite (NixOS path)
    # Check Chromium Cookies file
    # Return None if not found
```

**Verification:** On user's machine, `ilias_client.py dashboard` works without explicit cookie if browser is logged in.

---

## Files

| File | Action | Purpose |
|------|--------|---------|
| `/data/workspace/ilias_client.py` | Rewrite | Complete read-only client |
| `/data/.hermes/skills/custom/ilias-ecampus/SKILL.md` | Create | Skill with usage docs |

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Session expires | Clear error message, instructions to refresh |
| Accidental mutation | URL safety filter blocks all write operations |
| HTML structure changes | Graceful degradation, regex fallbacks |
| Rate limiting | Conservative request spacing |
| Cookie leaked in logs | Never log cookie value, mask in errors |

## Open Questions

- Calendar token needed for iCal feed? → Test `ical.php` endpoint
- Can we get individual report content (not just list)? → `reportsstudent.printreport` looks like a GET
- Learning progress percentage parsing → needs HTML inspection of a module with progress
