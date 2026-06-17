#!/usr/bin/env python3
"""
ILIAS eCampus Client for WBS Training
Read-only by default — safety guard can be configured for future write operations.

Cookie sources (auto-detected in order):
  1. ILIAS_SESSION env var — PHPSESSID from browser DevTools
  2. ~/.ilias_cookies.txt — Netscape-format cookie file (export via browser extension)
  3. Camofox/Firefox cookies.sqlite — auto-discovered from browser profiles
  4. Camofox REST API — imports cookies via POST /sessions/{userId}/cookies
     (requires CAMOFOX_API_KEY; userId from ILIAS_USER_ID env var)

Cache: Results cached to ~/.cache/ilias_client.json (TTL 5 min).
       Use --no-cache to force fresh fetch.

Usage:
  python ilias_client.py dashboard    # Courses + groups overview
  python ilias_client.py browse <id>  # List children of a ref_id
  python ilias_client.py exams        # All exams with dates
  python ilias_client.py reports      # Berichtsheft entries
  python ilias_client.py calendar     # Upcoming events
  python ilias_client.py search <q>   # Global ILIAS search
  python ilias_client.py summary      # Everything at a glance
  python ilias_client.py edit-report <request_id>  # Show Berichtsheft form
  python ilias_client.py save-day <req_id> <YYYY-MM-DD> <hours> <text1> [text2] [text3] [text4]
  python ilias_client.py --json ...   # JSON output mode
  python ilias_client.py --no-cache   # Skip cache, force fresh fetch
"""

import os
import sys
import re
import json
import time
import hashlib
from datetime import datetime
from dataclasses import dataclass, field, asdict
from html import unescape
from pathlib import Path
from typing import Optional
from urllib.parse import urljoin

import requests

# ─── Constants ────────────────────────────────────────────────────

BASE_URL = "https://ecampus.wbstraining.de"
CLIENT_ID = "wbs50"
CACHE_DIR = Path(os.path.expanduser("~/.cache"))
CACHE_FILE = CACHE_DIR / "ilias_client.json"
CACHE_TTL = 300  # 5 minutes

# ⛔ URL patterns that MAY be blocked depending on safety_mode
# These are checked before any request is made.
# "cmd=post" is allowed ONLY for search (ilSearchController) and save (reportsstudent.save).
WRITE_PATTERNS = [
    r"cmd=(delete|revoke|update|create|add|remove|withdraw|edit)",
    r"cmdClass=ilmail",
    r"action=delete",
    r"method=post",
]

# 🚫 Commands that must NEVER be sent — even via POST
# These are PERMANENTLY blocked regardless of safety_mode.
BLOCKED_COMMANDS = [
    "reportsstudent.savesub",    # Einreichen — irreversible!
    "reportsstudent.submit",     # Alternative submit path
    "reportsstudent.finalize",   # Final submission
]

# ─── Dataclasses ──────────────────────────────────────────────────


@dataclass
class IliasItem:
    """A generic ILIAS object (course, group, folder, file, test, etc.)."""

    ref_id: int
    title: str
    item_type: str  # "course", "group", "folder", "file", "test", "weblink", "learningmodule", "exercise"
    description: str = ""


@dataclass
class ReportEntry:
    """A Berichtsheft weekly report entry."""

    week_start: str  # "04. Aug 2025"
    week_end: str  # "10. Aug 2025"
    submitted: str  # "09. Sep 2025"
    status: str  # "Angenommen", "Neu", "Abgelehnt"
    request_id: int
    user_id: int


@dataclass
class ExamEntry:
    """An exam with module code and date."""

    ref_id: int
    title: str
    module_code: str  # "TF_US_PPP"
    exam_date: str  # "16.01.2026"
    is_retry: bool  # "Nachprüfung" in title


@dataclass
class CalendarEvent:
    """A calendar event."""

    date: str
    title: str
    ref_id: Optional[int] = None


# ─── Exceptions ───────────────────────────────────────────────────


class IliasError(Exception):
    """Base error for ILIAS client."""

    pass


class AuthError(IliasError):
    """Authentication failed or session expired."""

    pass


class SafetyError(IliasError):
    """Request blocked by safety guard."""

    pass


# ─── Client ───────────────────────────────────────────────────────


class IliasClient:
    """
    ILIAS eCampus read-only client.

    Parameters:
        session_cookie: PHPSESSID value from browser
        safety_mode: 'strict' (default, blocks all writes),
                     'ask' (prompts before write — future),
                     'allow' (allows writes — future)
    """

    def __init__(
        self,
        session_cookie: Optional[str] = None,
        safety_mode: str = "strict",
        use_cache: bool = True,
    ):
        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": (
                    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
            }
        )
        self.safety_mode = safety_mode
        self.use_cache = use_cache
        self._cache: dict = {}
        self._load_cache()

        cookie = session_cookie or os.environ.get("ILIAS_SESSION")
        cookie_source = "env var"

        if not cookie:
            cookie = self._discover_cookie()
            cookie_source = "auto-discovered"

        if not cookie:
            cookie = self._try_camofox_import()
            cookie_source = "camofox-import"

        if cookie:
            self.session.cookies.set(
                "PHPSESSID", cookie, domain="ecampus.wbstraining.de"
            )
            self.session.cookies.set(
                "ilClientId", CLIENT_ID, domain="ecampus.wbstraining.de"
            )
            print(f"🔑 Cookie geladen ({cookie_source})")

    # ─── Safety ────────────────────────────────────────────────

    def _check_safety(self, url: str, method: str = "GET", data: dict = None):
        """Block write URLs in strict mode. Allows cmd=post only for search and save."""
        if self.safety_mode == "allow":
            return
        if self.safety_mode == "ask":
            pass  # Future: prompt user

        # 🚫 PERMANENTLY blocked commands (savesub = Einreichen)
        data_str = json.dumps(data) if data else ""
        for blocked in BLOCKED_COMMANDS:
            if blocked in url or blocked in data_str:
                raise SafetyError(
                    f"🚫 PERMANENTLY BLOCKED: '{blocked}'\n"
                    f"   This action is IRREVERSIBLE and will never be executed.\n"
                    f"   Only 'reportsstudent.save' (draft save) is allowed."
                )

        # Allow search POSTs
        if method == "POST" and "ilSearchController" in url and "cmd=post" in url:
            return

        # Allow report save POSTs (but NEVER savesub — already blocked above)
        if method == "POST" and ("reportsstudent.save" in url or "reportsstudent.save" in data_str):
            return

        # Block cmd=post outside allowed contexts
        if "cmd=post" in url and "ilSearchController" not in url and "reportsstudent.save" not in url and "reportsstudent.save" not in data_str:
            raise SafetyError(
                f"⛔ BLOCKED by safety guard (mode={self.safety_mode})\n"
                f"   POST requests are only allowed for search and report save.\n"
                f"   URL: {url[:120]}"
            )

        for pattern in WRITE_PATTERNS:
            if re.search(pattern, url, re.IGNORECASE):
                raise SafetyError(
                    f"⛔ BLOCKED by safety guard (mode={self.safety_mode})\n"
                    f"   Pattern: {pattern}\n"
                    f"   URL: {url[:120]}\n"
                    f"   Tip: Set safety_mode='allow' to enable writes (future)."
                )

    def _post(self, path: str, data: dict = None, params: dict = None) -> requests.Response:
        """Safe POST request. Only allows ilSearchController search and reportsstudent.save."""
        url = path if path.startswith("http") else urljoin(BASE_URL, path.lstrip("/"))
        from urllib.parse import urlencode
        full_url = f"{url}?{urlencode(params)}" if params else url
        self._check_safety(full_url, method="POST", data=data)
        return self.session.post(url, data=data, params=params, allow_redirects=True)

    # ─── HTTP ──────────────────────────────────────────────────

    def _get(self, path: str, params: dict = None) -> requests.Response:
        """Safe GET request with auto session refresh."""
        url = path if path.startswith("http") else urljoin(BASE_URL, path.lstrip("/"))
        full_url = url
        if params:
            from urllib.parse import urlencode
            full_url = f"{url}?{urlencode(params)}"
        self._check_safety(full_url)

        resp = self.session.get(url, params=params, allow_redirects=True)

        # Auth failure? Try SSO refresh once, then retry
        needs_refresh = (
            resp.status_code == 401
            or ("login.php" in resp.url and "ilias.php" not in (resp.request.url or ""))
        )
        if needs_refresh:
            if self._refresh_session():
                resp = self.session.get(url, params=params, allow_redirects=True)

        if resp.status_code == 401:
            raise AuthError(
                "Session expired. Refresh failed. Get a fresh PHPSESSID:\n"
                "  1. ecampus.wbstraining.de → F5 in Browser\n"
                "  2. F12 → Cookies → PHPSESSID → ~/.ilias_cookies.txt"
            )
        resp.raise_for_status()
        return resp

    def _ensure_auth(self):
        """Verify authenticated session."""
        # Use goto.php root as auth check (avoids ILIAS routing errors)
        resp = self._get("goto.php", {"target": "root_1", "client_id": CLIENT_ID})

    # ─── Cookie Discovery ──────────────────────────────────────

    def _discover_cookie(self) -> Optional[str]:
        """Try to find PHPSESSID from local browser storage."""
        # 1. Try ~/.ilias_cookies.txt first (easiest user workflow)
        cookie = self._discover_file_cookie()
        if cookie:
            return cookie

        # 2. Check Firefox / Camofox cookies.sqlite
        firefox_profiles = [
            os.path.expanduser("~/.mozilla/firefox"),
            os.path.expanduser("~/.camofox"),
            os.path.expanduser("~/snap/firefox/common/.mozilla/firefox"),
            # Camofox Docker volume mount point
            "/var/lib/camofox",
            # Camofox service data dir
            "/data/camofox",
            "/data/profiles",
        ]
        for profile_dir in firefox_profiles:
            if not os.path.isdir(profile_dir):
                continue
            try:
                for root, _, files in os.walk(profile_dir):
                    if "cookies.sqlite" in files:
                        return self._read_firefox_cookie(
                            os.path.join(root, "cookies.sqlite")
                        )
            except PermissionError:
                continue

        # Check Chromium Cookies
        chromiums = [
            os.path.expanduser("~/.config/chromium/Default/Cookies"),
            os.path.expanduser("~/.config/google-chrome/Default/Cookies"),
            os.path.expanduser("~/.var/app/org.chromium.Chromium/config/chromium/Default/Cookies"),
        ]
        for path in chromiums:
            if os.path.isfile(path):
                try:
                    return self._read_chromium_cookie(path)
                except Exception:
                    continue
        return None

    def _read_firefox_cookie(self, db_path: str) -> Optional[str]:
        """Read PHPSESSID from Firefox cookies.sqlite."""
        try:
            import sqlite3

            conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
            cur = conn.execute(
                "SELECT value FROM moz_cookies "
                "WHERE host LIKE '%ecampus.wbstraining.de%' AND name='PHPSESSID' "
                "ORDER BY lastAccessed DESC LIMIT 1"
            )
            row = cur.fetchone()
            conn.close()
            if row:
                return row[0]
        except Exception:
            pass
        return None

    def _read_chromium_cookie(self, db_path: str) -> Optional[str]:
        """Read PHPSESSID from Chromium Cookies."""
        try:
            import sqlite3

            conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
            cur = conn.execute(
                "SELECT value FROM cookies "
                "WHERE host_key LIKE '%ecampus.wbstraining.de%' AND name='PHPSESSID' "
                "ORDER BY last_access_utc DESC LIMIT 1"
            )
            row = cur.fetchone()
            conn.close()
            if row:
                return row[0]
        except Exception:
            pass
        return None

    def _discover_file_cookie(self) -> Optional[str]:
        """Read cookies from ~/.ilias_cookies.txt (Netscape format)."""
        paths = [
            Path(os.path.expanduser("~/.ilias_cookies.txt")),
            Path(os.path.expanduser("~/.config/ilias_cookies.txt")),
        ]
        phpsessid = None
        for p in paths:
            if not p.is_file():
                continue
            try:
                for line in p.read_text().splitlines():
                    line = line.strip()
                    if line.startswith("#") or not line:
                        continue
                    parts = line.split("\t")
                    if len(parts) >= 7:
                        domain = parts[0]
                        name = parts[5]
                        value = parts[6]
                        if "ecampus.wbstraining.de" in domain:
                            self.session.cookies.set(name, value, domain="ecampus.wbstraining.de")
                            if name == "PHPSESSID":
                                phpsessid = value
            except Exception:
                continue
        return phpsessid

    def _refresh_session(self) -> bool:
        """Attempt SSO session refresh via SAML. Returns True on success."""
        try:
            resp = self.session.get(
                urljoin(BASE_URL, "/saml.php"),
                params={
                    "lang": "de",
                    "saml_idp_id": "2",
                    "cmd": "doSamlAuthentication",
                    "cmdClass": "ilstartupgui",
                    "cmdNode": "10f",
                    "baseClass": "ilStartUpGUI",
                },
                allow_redirects=True,
                timeout=30,
            )
            # Check if we got a new PHPSESSID
            new_cookie = self.session.cookies.get("PHPSESSID", domain="ecampus.wbstraining.de")
            if new_cookie and "login.php" not in resp.url:
                # Update cookie file
                self._update_cookie_file(new_cookie)
                return True
        except Exception:
            pass
        return False

    def _update_cookie_file(self, phpsessid: str):
        """Update PHPSESSID in ~/.ilias_cookies.txt."""
        cookie_file = Path(os.path.expanduser("~/.ilias_cookies.txt"))
        if not cookie_file.is_file():
            return
        try:
            lines = cookie_file.read_text().splitlines()
            new_lines = []
            for line in lines:
                if "\tPHPSESSID\t" in line:
                    parts = line.split("\t")
                    parts[6] = phpsessid
                    new_lines.append("\t".join(parts))
                else:
                    new_lines.append(line)
            cookie_file.write_text("\n".join(new_lines) + "\n")
        except Exception:
            pass
    def _try_camofox_import(self) -> Optional[str]:
        """Try to import cookies from Camofox via REST API."""
        api_key = os.environ.get("CAMOFOX_API_KEY")
        user_id = os.environ.get("ILIAS_USER_ID")
        if not api_key or not user_id:
            return None
        return self._discover_file_cookie()

    # ─── Cache ──────────────────────────────────────────────────

    def _load_cache(self):
        """Load cached results from disk."""
        if not self.use_cache:
            return
        try:
            if CACHE_FILE.is_file():
                data = json.loads(CACHE_FILE.read_text())
                if time.time() - data.get("_ts", 0) < CACHE_TTL:
                    self._cache = data
        except Exception:
            self._cache = {}

    def _save_cache(self):
        """Save results to disk cache."""
        if not self.use_cache or not self._cache:
            return
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        self._cache["_ts"] = time.time()
        CACHE_FILE.write_text(json.dumps(self._cache, default=str))

    # ─── Generic Item Parser ───────────────────────────────────

    def _parse_items(
        self, html: str, exclude_ref_ids: Optional[set] = None
    ) -> list[IliasItem]:
        """
        Extract ILIAS items from repository/dashboard HTML.
        Matches the standard ILIAS item list pattern.
        """
        exclude = exclude_ref_ids or set()
        items = []

        # Pattern: link with ref_id inside il-item-title
        pattern = (
            r'<a\s+(?:[^>]*\s)?href="ilias\.php\?[^"]*ref_id=(\d+)[^"]*"'
            r'\s*(?:[^>]*\s)?(?:class="[^"]*"[^>]*)?>'
            r'(.*?)</a>'
        )
        for m in re.finditer(pattern, html, re.DOTALL):
            ref_id = int(m.group(1))
            if ref_id in exclude:
                continue
            title = unescape(re.sub(r"<[^>]+>", "", m.group(2)).strip())
            if not title or len(title) < 3:
                continue

            # Detect type from surrounding context
            ctx_start = max(0, m.start() - 400)
            ctx = html[ctx_start : m.start()]
            item_type = self._detect_type(ctx)
            description = self._extract_description(html, m.end())

            items.append(
                IliasItem(
                    ref_id=ref_id,
                    title=title,
                    item_type=item_type,
                    description=description,
                )
            )

        return items

    def _detect_type(self, ctx: str) -> str:
        """Detect ILIAS object type from icon/class markers in context."""
        markers = {
            "Symbol Kurs": "course",
            "il_crs_": "course",
            "Symbol Gruppe": "group",
            "il_grp_": "group",
            "Symbol Ordner": "folder",
            "il_fold_": "folder",
            "Symbol Kategorie": "category",
            "il_cat_": "category",
            "Symbol Datei": "file",
            "il_file_": "file",
            "Symbol Test": "test",
            "il_tst_": "test",
            "Symbol Weblink": "weblink",
            "il_webr_": "weblink",
            "Symbol Lernmodul": "learningmodule",
            "il_lm_": "learningmodule",
            "Symbol Übung": "exercise",
            "il_exc_": "exercise",
        }
        for marker, t in markers.items():
            if marker in ctx:
                return t
        return "unknown"

    def _extract_description(self, html: str, start_pos: int) -> str:
        """Extract item description following the title (searches up to 3000 chars)."""
        desc_match = re.search(
            r'<div[^>]*class="[^"]*il_Description[^"]*"[^>]*>(.*?)</div>',
            html[start_pos : start_pos + 3000],
            re.DOTALL,
        )
        if desc_match:
            return unescape(re.sub(r"<[^>]+>", "", desc_match.group(1)).strip())
        return ""

    # ─── High-Level API ────────────────────────────────────────

    def get_dashboard(self) -> list[IliasItem]:
        """Get all courses, groups, and items from the dashboard."""
        self._ensure_auth()
        resp = self._get("ilias.php", {
            "baseClass": "ilDashboardGUI",
            "cmd": "jumpToMemberships",
        })
        return self._parse_items(resp.text)

    def get_children(self, ref_id: int) -> list[IliasItem]:
        """List contents of any folder/course/group.
        
        Handles both standard repository listings (ref_id= links) and 
        content-folders with goto.php?target= links.
        """
        self._ensure_auth()
        resp = self._get("ilias.php", {
            "ref_id": ref_id,
            "cmd": "view",
            "cmdClass": "ilrepositorygui",
            "cmdNode": "xe",
            "baseClass": "ilrepositorygui",
        })
        html = resp.text

        # Strategy 1: Standard repository items (ref_id= links)
        # Exclude navigation-path ref_ids (the parent hierarchy)
        known_path_refs = {1, 67, 89, 875, 16353, 7655824, 7750392, 
                          7763567, 8326976, 8326979}
        items = self._parse_items(html, exclude_ref_ids=known_path_refs | {ref_id})
        
        # If we got actual content items, return them
        content_items = [i for i in items if i.title not in (
            'Inhalt', 'Info', 'Zu Favoriten hinzufügen', '')
            and i.item_type != 'unknown']
        if content_items:
            return items

        # Strategy 2: Content-folder with goto.php?target= links
        # These are deeper folders where items use goto.php instead of ilias.php?ref_id=
        for m in re.finditer(
            r'goto\.php\?target=(\w+)_(\d+)',
            html
        ):
            ttype = m.group(1)
            item_id = int(m.group(2))
            # Skip navigation targets
            if ttype in ('root', 'impr', 'copa'):
                continue
            # Get the link text
            ctx_end = min(len(html), m.end() + 300)
            ctx = html[m.start():ctx_end]
            text_match = re.search(r'>([^<]+)<', ctx)
            title = text_match.group(1).strip() if text_match else "???"
            title = re.sub(r'<[^>]+>', '', title)
            
            if title and title not in ('Inhalt', 'Info', 'Zu Favoriten hinzufügen', ''):
                items.append(IliasItem(
                    ref_id=item_id,
                    title=unescape(title),
                    item_type=ttype,
                ))

        return items

    def get_reports(self) -> list[ReportEntry]:
        """Get all Berichtsheft (weekly report) entries."""
        self._ensure_auth()
        resp = self._get("ilias.php", {
            "cmd": "reportsstudent.list",
            "cmdClass": "ildigitalreportsgui",
            "cmdNode": "163:ad",
            "baseClass": "iluipluginroutergui",
        })
        return self._parse_reports(resp.text)

    def _parse_reports(self, html: str) -> list[ReportEntry]:
        """Parse the Berichtsheft table rows. Handles all status types (Neu, Angenommen, etc.)."""
        reports = []
        # Match each data row (<tr class="tblrow\d">)
        for row_match in re.finditer(r'<tr class="tblrow\d">(.*?)</tr>', html, re.DOTALL):
            row = row_match.group(1)

            # Extract date range: "DD. Mon YYYY - DD. Mon YYYY"
            date_match = re.search(
                r"(\d{1,2}\.\s\w{3}\s\d{4})\s*-\s*(\d{1,2}\.\s\w{3}\s\d{4})", row
            )
            if not date_match:
                continue

            # Extract due date (second date in a <td>)
            due_match = re.search(
                r"(\d{1,2}\.\s\w{3}\s\d{4})", row[date_match.end():]
            )
            if not due_match:
                continue

            # Extract status
            status_match = re.search(
                r"(Angenommen|Neu|Abgelehnt|Abgewiesen|In\sBearbeitung)", row
            )
            if not status_match:
                continue

            # Extract request_id and user_id from Aktionen links
            req_match = re.search(r"request_id=(\d+)", row)
            user_match = re.search(r"user_id=(\d+)", row)
            if not req_match or not user_match:
                continue

            reports.append(
                ReportEntry(
                    week_start=date_match.group(1),
                    week_end=date_match.group(2),
                    submitted=due_match.group(1),
                    status=status_match.group(1).replace("\n", " ").strip(),
                    request_id=int(req_match.group(1)),
                    user_id=int(user_match.group(1)),
                )
            )

        return reports

    # ─── Report Editing (SAVE-ONLY, NEVER submit) ──────────────

    def _get_module_material_ref(self, module_code: str) -> int | None:
        """Find the Unterrichtsmaterial ref_id for a module code.

        Searches both material locations (7750398 and 8326979) and caches results.
        """
        # Check cache
        cache_key = f"module_ref_{module_code}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        # Search both material parent folders
        for parent_ref in (7750398, 8326979):
            try:
                children = self.get_children(parent_ref)
                for c in children:
                    if c.title.lower().startswith(module_code.lower()):
                        self._cache[cache_key] = c.ref_id
                        self._save_cache()
                        return c.ref_id
            except Exception:
                continue
        return None

    def get_day_topics(self, date: str, module_code: str = "") -> list[str]:
        """Get topic titles for a given date from the module's material folder.

        Searches the module's Tag-Ordner for the given date and extracts
        file/folder titles as topic names. Falls back to scanning the module
        root if no daily structure is found.

        Returns list of topic strings, e.g.:
          ["Datenbank-SQL Wiederholung", "MySQL Connector für Java"]
        """
        from datetime import datetime as dt

        d = dt.strptime(date, "%Y-%m-%d")
        if d.weekday() >= 5:
            return []  # Weekend

        # Determine module if not provided
        if not module_code:
            meta = self._get_report_meta(date)
            module_code = meta.get("module_code", "")

        if not module_code:
            return []

        # Find the module's material folder
        module_ref = self._get_module_material_ref(module_code)
        if not module_ref:
            # Fallback: try known refs
            return []

        # Strategy 1: Look for "Tag NN - YYYY-MM-DD" folder
        date_str_de = d.strftime("%d.%m.%Y")  # German date format
        children = self.get_children(module_ref)

        day_folder_ref = None
        for c in children:
            if date_str_de in c.title:
                day_folder_ref = c.ref_id
                break

        if not day_folder_ref:
            # Strategy 2: "Tageszusammenfassung" → find matching subfolder
            for c in children:
                if 'tageszusammen' in c.title.lower():
                    tz_children = self.get_children(c.ref_id)
                    for tzc in tz_children:
                        if date_str_de in tzc.title:
                            day_folder_ref = tzc.ref_id
                            break
                    break

        if not day_folder_ref:
            # Strategy 3: Scan all module contents for date references
            return []

        # Extract topic names from the day folder
        topics = []
        
        # First: get the day folder's own description (subtitle like "Wiederholung ERM, RM, SQL")
        for c in children:
            if date_str_de in c.title and c.description:
                # Split subtitle on commas/semicolons into individual topics
                for part in re.split(r'[,;]\s*', c.description):
                    part = part.strip()
                    if part:
                        topics.append(part)
                break
        
        # Then: add file/folder names from inside the day folder
        day_contents = self.get_children(day_folder_ref)
        for item in day_contents:
            title = item.title.strip()
            # Skip non-content items and module folder links
            if not title or title in ('Inhalt', 'Info', 'Zu Favoriten hinzufügen'):
                continue
            if title.upper().startswith('TF_') or title.upper().startswith('IE'):
                continue  # Module folder navigation links
            # Clean up numeric prefixes: "10_dbsql_wiederholung" → "dbsql_wiederholung"
            cleaned = re.sub(r'^\d+[_\s-]+', '', title)
            if cleaned and len(cleaned) > 3:
                topics.append(cleaned)

        return topics

    # _get_report_meta body follows
    def _get_report_meta(self, date: str, reports: list = None) -> dict:
        from datetime import datetime as dt

        # ── Report number: derived from total count ──
        if reports is None:
            reports = self.get_reports()
        number = f"{len(reports):04d}"

        # ── Module lookup from Kursablaufplan ──
        d = dt.strptime(date, "%Y-%m-%d")

        # Kursablaufplan: (von, bis, code, name)
        plan = [
            ("2025-08-04", "2025-08-21", "TF_US_HWEG", "IT-Hardware, Energie, Grundlagen"),
            ("2025-08-25", "2025-09-11", "TF_US_VBS", "Betriebssysteme und Systemsteuerung"),
            ("2025-09-14", "2025-10-01", "TF_US_NEINT1", "Netzwerke & Internet (Teil 1)"),
            ("2025-10-02", "2025-10-09", "TF_US_SSQ", "Service, Support, Qualität"),
            ("2025-10-12", "2025-10-23", "TF_US_ISDS", "Informationssicherheit & Datenschutz"),
            ("2025-10-26", "2025-11-20", "TF_US_PSS", "Programmierung und Strukturierte Softwareentwicklung"),
            ("2025-11-23", "2025-12-11", "TF_US_DBS1", "Datenbanken mit SQL"),
            ("2025-12-14", "2026-01-15", "TF_US_WG1", "Webentwicklung-Grundlagen"),
            ("2026-01-18", "2026-01-29", "TF_US_WG2", "PHP"),
            ("2026-02-01", "2026-02-15", "TF_US_PPP", "Programmiersprache Java und prozedurale Programmierung"),
            ("2026-02-16", "2026-02-22", "—", "WBS Zwischenprüfung"),
            ("2026-02-24", "2026-03-20", "TF_US_NEINT2", "Netzwerke & Internet (Teil 2)"),
            ("2026-03-23", "2026-04-23", "TF_US_OOP1", "Objektorientierte Programmierung mit Java (Teil 1)"),
            ("2026-04-26", "2026-05-21", "TF_US_OOP2", "OOP/GUI-Programmierung mit Java (Teil 2)"),
            ("2026-05-24", "2026-06-12", "TF_US_CPS1", "Cyberphysische Systeme (Teil 1)"),
            ("2026-06-15", "2026-06-26", "TF_US_OP3", "Datenverarbeitung mit Datenbanken in Java"),
            ("2026-06-29", "2026-07-10", "TF_US_OP4", "Datenverarbeitung mit Dateien und Streams in Java"),
            ("2026-07-13", "2026-07-24", "TF_US_DB2", "Datenbanken und SQL 2"),
        ]

        section = ""
        module_code = ""
        for von, bis, code, name in plan:
            von_d = dt.strptime(von, "%Y-%m-%d")
            bis_d = dt.strptime(bis, "%Y-%m-%d")
            if von_d <= d <= bis_d:
                section = f"{code}: {name}"
                module_code = code
                break

        # ── External checkbox: only during Praktikum ──
        # Currently no Praktikum phases in the plan; all are Unterricht
        external = False

        return {
            "number": number,
            "section": section,
            "external": external,
            "module_code": module_code,
        }

    def get_report_form(self, request_id: int, user_id: int = 8042150) -> dict:
        """Fetch the edit form for a Berichtsheft and return its structure.

        Returns a dict with:
          - request_id: int
          - user_id: int
          - rtoken: str (CSRF token)
          - week_dates: list[str] (7 ISO dates, Mon-Sun)
          - fields: dict[str, str] (all current field values)
          - has_content: bool (whether any day has text filled in)
          - number: str (current report number, e.g. "0046")
          - section: str (current Abschnitt/module)
          - external: bool (extern prüfen / Praktikumsbericht)
        """
        self._ensure_auth()
        resp = self._get("ilias.php", {
            "user_id": str(user_id),
            "request_id": str(request_id),
            "cmd": "reportsstudent.editreport",
            "cmdClass": "ildigitalreportsgui",
            "cmdNode": "163:ad",
            "baseClass": "iluipluginroutergui",
        })
        html = resp.text

        # Extract rtoken
        rtoken_match = re.search(
            r'action="[^"]*rtoken=([a-f0-9]{32})',
            html,
        )
        rtoken = rtoken_match.group(1) if rtoken_match else ""

        # Extract hidden fields
        hidden = {}
        for m in re.finditer(
            r'<input[^>]*type="hidden"[^>]*name="([^"]*)"[^>]*value="([^"]*)"',
            html,
        ):
            hidden[m.group(1)] = m.group(2)

        # Extract all input fields (text, hours)
        fields = {}
        for m in re.finditer(
            r'<input[^>]*name="([^"]*)"[^>]*value="([^"]*)"',
            html,
        ):
            name = m.group(1)
            val = m.group(2)
            if name not in ("cmd[reportsstudent.save]", "cmd[reportsstudent.savesub]",
                           "cmd[reportsstudent.cancel]", "queryString", "root_id"):
                fields[name] = val

        # Extract textarea
        ta_match = re.search(
            r'<textarea[^>]*name="([^"]*)"[^>]*>(.*?)</textarea>',
            html,
            re.DOTALL,
        )
        if ta_match:
            fields[ta_match.group(1)] = ta_match.group(2).strip()

        # Extract week dates from field names
        week_dates = sorted(set(
            m.group(1) for m in re.finditer(r'(20\d{2}-\d{2}-\d{2})_', ' '.join(fields.keys()))
        ))

        # Check if any day has content
        has_content = any(
            v.strip()
            for k, v in fields.items()
            if '_text' in k and v.strip()
        )

        # Check if external checkbox is actually checked
        external_checked = bool(re.search(
            r'<input[^>]*type="checkbox"[^>]*name="external"[^>]*checked',
            html,
        ))

        return {
            "request_id": request_id,
            "user_id": user_id,
            "rtoken": rtoken,
            "week_dates": week_dates,
            "fields": fields,
            "hidden": hidden,
            "has_content": has_content,
            "number": fields.get("number", ""),
            "section": fields.get("section", ""),
            "external": external_checked,
        }

    def save_report_day(
        self,
        request_id: int,
        date: str,  # "YYYY-MM-DD"
        texts: list[str],  # up to 4 text lines
        hours: int = 10,  # default: full school day
        user_id: int = 8042150,
        report_number: str = "",  # e.g. "0046" — set once per week
        section: str = "",        # e.g. "TF_US_OP3: Datenverarbeitung mit Datenbanken in Java"
        external: bool = False,   # Extern prüfen / Praktikumsbericht
    ) -> bool:
        """Save one day of a Berichtsheft (NEVER submits/einreichen).

        This is SAFE: it only sends cmd[reportsstudent.save].
        The BLOCKED_COMMANDS list permanently prevents savesub/submit.

        Args:
            request_id: The report's request_id (from get_reports)
            date: ISO date string "YYYY-MM-DD" (must be Mon-Fri)
            texts: List of 1-4 activity descriptions
            hours: Hours for this day (default 10 = full school day)
            report_number: Report sequence number (e.g. "0046"), set once
            section: Current module/section, e.g. "TF_US_OP3: ..."
            external: True if Praktikum, False otherwise

        Returns True if save succeeded (no error page).
        """
        # 🚫 Never on weekends
        from datetime import datetime as dt
        d = dt.strptime(date, "%Y-%m-%d")
        if d.weekday() >= 5:  # Saturday=5, Sunday=6
            raise SafetyError(
                f"🚫 Weekend days cannot be filled: {date} is a {'Saturday' if d.weekday() == 5 else 'Sunday'}.\n"
                f"   Berichtsheft only covers Mon-Fri."
            )

        # First get the form to extract rtoken and baseline fields
        form = self.get_report_form(request_id, user_id)

        if not form["rtoken"]:
            raise IliasError(f"Could not find rtoken for report {request_id}")

        # Build save data: start with hidden fields + all current values
        data = {}
        data.update(form["hidden"])
        data.update(form["fields"])

        # Set header fields (report number, section, external)
        if report_number:
            data["number"] = report_number
        if section:
            data["section"] = section
        data["external"] = "1" if external else ""

        # Override with the day's new values
        for i in range(1, 5):
            key = f"{date}_text{i}"
            if i <= len(texts):
                data[key] = texts[i - 1]
            elif key in data:
                data[key] = data.get(key, "")

        hours_key = f"{date}_hours"
        data[hours_key] = str(hours)

        # CRITICAL: Only ever send cmd[reportsstudent.save]
        # BLOCKED_COMMANDS will catch savesub/submit if somehow present
        data["cmd[reportsstudent.save]"] = "Speichern"

        # Remove dangerous commands that might have leaked from form
        for bad in ["cmd[reportsstudent.savesub]", "cmd[reportsstudent.cancel]",
                     "cmd[reportsstudent.submit]"]:
            data.pop(bad, None)

        # POST the save
        params = {
            "cmd": "post",
            "cmdClass": "ildigitalreportsgui",
            "cmdNode": "163:ad",
            "baseClass": "iluipluginroutergui",
            "fallbackCmd": "reportsstudent.list",
            "rtoken": form["rtoken"],
        }

        resp = self._post("ilias.php", data=data, params=params)

        # Success check: no error.php redirect and not a login page
        success = "error.php" not in resp.url and "login.php" not in resp.url

        # Invalidate cache after save
        if success:
            self._cache = {}
            self._save_cache()

        return success

    def get_exams(self, ref_id: int = 7750468) -> list[ExamEntry]:
        """Get all exams from the Prüfungen folder."""
        children = self.get_children(ref_id)
        exams = []
        for item in children:
            if "Prüfung" not in item.title and "prüfung" not in item.title.lower():
                continue
            exams.append(self._parse_exam_title(item))
        return exams

    def _parse_exam_title(self, item: IliasItem) -> ExamEntry:
        """Extract module code and date from exam title."""
        title = item.title
        # Pattern: "TF_US_PPP - Prüfung 16.01.2026 - ..."
        code_match = re.match(r"([A-Z]{2,3}_[A-Z0-9]+?)(_Prüfung|_Pr fung| -)", title)
        module_code = code_match.group(1) if code_match else "?"
        # Clean up trailing underscore
        module_code = module_code.rstrip("_")

        date_match = re.search(r"(\d{1,2}\.\d{1,2}\.\d{4})", title)
        exam_date = date_match.group(1) if date_match else "?"

        is_retry = "nachprüfung" in title.lower()

        return ExamEntry(
            ref_id=item.ref_id,
            title=title,
            module_code=module_code,
            exam_date=exam_date,
            is_retry=is_retry,
        )

    def get_calendar(self) -> list[CalendarEvent]:
        """Get upcoming calendar events from dashboard sidebar."""
        self._ensure_auth()
        resp = self._get("ilias.php", {
            "baseClass": "ilDashboardGUI",
            "cmd": "jumpToMemberships",
        })
        return self._parse_calendar(resp.text)

    def _parse_calendar(self, html: str) -> list[CalendarEvent]:
        """Parse calendar widget from dashboard."""
        events = []
        # Look for calendar day links with data
        cal_pattern = r'data-date="(\d{4}-\d{2}-\d{2})"[^>]*>.*?</a>'
        for m in re.finditer(cal_pattern, html):
            date_str = m.group(1)
            # Look for event text near this date
            ctx_start = m.start()
            ctx_end = min(len(html), m.end() + 500)
            ctx = html[ctx_start:ctx_end]
            event_match = re.search(r'class="[^"]*calevent[^"]*"[^>]*>(.*?)<', ctx, re.DOTALL)
            if event_match:
                title = unescape(re.sub(r"<[^>]+>", "", event_match.group(1)).strip())
                if title:
                    events.append(CalendarEvent(date=date_str, title=title))
        return events

    def search(self, query: str) -> list[IliasItem]:
        """Search ILIAS via embedded search form (rtoken-based POST)."""
        self._ensure_auth()

        # Step 1: Get rtoken from the dashboard search form
        resp = self._get("ilias.php", {
            "baseClass": "ilDashboardGUI",
            "cmd": "jumpToMemberships",
        })
        rtoken_match = re.search(
            r'baseClass=ilSearchController&cmd=post&rtoken=([a-f0-9]{32})',
            resp.text,
        )
        if not rtoken_match:
            # Fallback: dashboard substring search
            dashboard = self.get_dashboard()
            results = []
            q = query.lower()
            for item in dashboard:
                if q in item.title.lower() or (item.description and q in item.description.lower()):
                    results.append(item)
            return results

        rtoken = rtoken_match.group(1)

        # Step 2: POST the search
        search_resp = self._post(
            "ilias.php",
            data={"queryString": query},
            params={
                "baseClass": "ilSearchController",
                "cmd": "post",
                "rtoken": rtoken,
                "fallbackCmd": "remoteSearch",
            },
        )

        # Step 3: Parse results
        if "error.php" in search_resp.url:
            return []
        return self._parse_search_results(search_resp.text)

    def _parse_search_results(self, html: str) -> list[IliasItem]:
        """Parse ILIAS global search results page."""
        items = []
        # Each result is in: <div class="ilContainerListItemOuter" data-list-item-id="lg_div_REFID_pref_N" ...>
        for block_match in re.finditer(
            r'<div[^>]*class="[^"]*ilContainerListItemOuter[^"]*"[^>]*data-list-item-id="lg_div_(\d+)_pref_\d+"[^>]*>(.*?)</div>\s*</div>\s*</div>',
            html,
            re.DOTALL,
        ):
            ref_id = int(block_match.group(1))
            block = block_match.group(2)

            # Extract title from <a class="il_ContainerItemTitle">
            title_match = re.search(
                r'<a[^>]*class="[^"]*il_ContainerItemTitle[^"]*"[^>]*>(.*?)</a>',
                block,
                re.DOTALL,
            )
            title = title_match.group(1).strip() if title_match else "???"
            title = re.sub(r"<[^>]+>", "", title).strip()

            # Extract type from goto.php target
            type_match = re.search(r"target=(\w+)_" + str(ref_id), block)
            item_type = type_match.group(1) if type_match else "unknown"

            # Extract description (if any)
            desc_match = re.search(
                r'<div[^>]*class="[^"]*il_Description[^"]*"[^>]*>(.*?)</div>',
                block,
                re.DOTALL,
            )
            description = ""
            if desc_match:
                description = re.sub(r"<[^>]+>", "", desc_match.group(1)).strip()

            items.append(IliasItem(
                ref_id=ref_id,
                title=unescape(title),
                item_type=item_type,
                description=description,
            ))

        return items

    def get_summary(self) -> dict:
        """Get a complete overview of everything."""
        self._ensure_auth()

        dashboard = self.get_dashboard()
        reports = self.get_reports()
        exams = self.get_exams()

        # Count by type
        courses = [i for i in dashboard if i.item_type == "course"]
        groups = [i for i in dashboard if i.item_type == "group"]
        accepted = [r for r in reports if r.status == "Angenommen"]
        pending = [r for r in reports if r.status in ("Neu", "In Bearbeitung")]
        retries = [e for e in exams if e.is_retry]
        regular = [e for e in exams if not e.is_retry]

        return {
            "courses": len(courses),
            "groups": len(groups),
            "dashboard_items": len(dashboard),
            "reports_total": len(reports),
            "reports_accepted": len(accepted),
            "reports_pending": len(pending),
            "exams_total": len(exams),
            "exams_regular": len(regular),
            "exams_retries": len(retries),
            "latest_report": reports[0] if reports else None,  # First = newest
        }


# ─── CLI ──────────────────────────────────────────────────────────


def _fmt_table(headers: list[str], rows: list[list[str]], align: Optional[list[str]] = None) -> str:
    """Format a Markdown table."""
    if not rows:
        return "_No data_"
    out = "| " + " | ".join(headers) + " |\n"
    if align:
        sep = []
        for a in align:
            if a == "r":
                sep.append("---:")
            elif a == "l":
                sep.append(":---")
            else:
                sep.append(":---:")
        out += "| " + " | ".join(sep) + " |\n"
    else:
        out += "| " + " | ".join(["---"] * len(headers)) + " |\n"
    for row in rows:
        out += "| " + " | ".join(str(c) for c in row) + " |\n"
    return out


ICONS = {
    "course": "📖",
    "group": "👥",
    "folder": "📁",
    "file": "📄",
    "test": "📝",
    "weblink": "🔗",
    "learningmodule": "📖",
    "category": "📂",
    "exercise": "✏️",
    "unknown": "  ",
}


def cmd_dashboard(client: IliasClient, json_mode: bool = False):
    items = client.get_dashboard()
    if json_mode:
        print(json.dumps([asdict(i) for i in items], indent=2, ensure_ascii=False))
        return

    print("📊 **Dashboard**\n")
    rows = []
    for item in items:
        icon = ICONS.get(item.item_type, "  ")
        rows.append([str(item.ref_id), f"{icon} {item.item_type}", item.title])
    print(_fmt_table(["Ref-ID", "Typ", "Titel"], rows, align=["r", "l", "l"]))


def cmd_browse(client: IliasClient, ref_id: int, json_mode: bool = False):
    children = client.get_children(ref_id)
    if json_mode:
        print(json.dumps([asdict(c) for c in children], indent=2, ensure_ascii=False))
        return

    print(f"📂 **Inhalt von ref_id={ref_id}**\n")
    if not children:
        print("_Keine Einträge gefunden_")
        return
    rows = []
    for item in children:
        icon = ICONS.get(item.item_type, "  ")
        desc = f" — {item.description[:60]}" if item.description else ""
        rows.append([str(item.ref_id), f"{icon} {item.item_type}", item.title + desc])
    print(_fmt_table(["Ref-ID", "Typ", "Titel"], rows, align=["r", "l", "l"]))


def cmd_exams(client: IliasClient, json_mode: bool = False):
    exams = client.get_exams()
    if json_mode:
        print(json.dumps([asdict(e) for e in exams], indent=2, ensure_ascii=False))
        return

    print("📝 **Prüfungen**\n")
    rows = []
    for e in exams:
        flag = "🔄" if e.is_retry else ""
        rows.append([e.module_code, e.exam_date, flag, e.title[:80]])
    print(_fmt_table(["Modul", "Datum", "↺", "Titel"], rows, align=["l", "l", "c", "l"]))


def cmd_reports(client: IliasClient, json_mode: bool = False):
    reports = client.get_reports()
    if json_mode:
        print(json.dumps([asdict(r) for r in reports], indent=2, ensure_ascii=False))
        return

    print("📋 **Berichtsheft**\n")
    status_icon = {"Angenommen": "✅", "Neu": "🆕", "Abgelehnt": "❌", "Abgewiesen": "❌", "In Bearbeitung": "⏳"}
    rows = []
    for r in reports[:10]:  # First 10 = newest (HTML table order)
        icon = status_icon.get(r.status, "❓")
        rows.append([r.week_start, r.week_end, r.submitted, f"{icon} {r.status}", str(r.request_id)])
    if len(reports) > 10:
        print(f"_(Letzte 10 von {len(reports)} Einträgen)_\n")
    print(_fmt_table(["Von", "Bis", "Eingereicht", "Status", "Req-ID"], rows, align=["l", "l", "l", "l", "r"]))


def cmd_calendar(client: IliasClient, json_mode: bool = False):
    events = client.get_calendar()
    if json_mode:
        print(json.dumps([asdict(e) for e in events], indent=2, ensure_ascii=False))
        return

    print("📅 **Kalender**\n")
    if not events:
        print("_Keine Termine gefunden_")
        return
    rows = [[e.date, e.title, str(e.ref_id) if e.ref_id else "-"] for e in events]
    print(_fmt_table(["Datum", "Ereignis", "Ref-ID"], rows, align=["l", "l", "r"]))


def cmd_search(client: IliasClient, query: str, json_mode: bool = False):
    results = client.search(query)
    if json_mode:
        print(json.dumps([asdict(r) for r in results], indent=2, ensure_ascii=False))
        return

    print(f"🔍 **Suche: \"{query}\"**\n")
    if not results:
        print("_Keine Ergebnisse_")
        return
    rows = [[str(r.ref_id), f"{ICONS.get(r.item_type, ' ')} {r.item_type}", r.title] for r in results]
    print(_fmt_table(["Ref-ID", "Typ", "Titel"], rows, align=["r", "l", "l"]))


def cmd_summary(client: IliasClient, json_mode: bool = False):
    s = client.get_summary()
    if json_mode:
        print(json.dumps(s, indent=2, ensure_ascii=False, default=str))
        return

    latest = s["latest_report"]
    print("## 📊 ILIAS eCampus — Zusammenfassung\n")
    print(f"**Kurse:** {s['courses']} | **Gruppen:** {s['groups']}")
    print(f"**Prüfungen:** {s['exams_total']} ({s['exams_regular']} regulär, {s['exams_retries']} Nachprüfungen)")
    print(f"**Berichtshefte:** {s['reports_total']} ({s['reports_accepted']} angenommen, {s['reports_pending']} ausstehend)")
    if latest:
        print(
            f"**Letzter Eintrag:** {latest.week_start} – {latest.week_end} "
            f"({latest.submitted}, Status: {latest.status})"
        )


def main():
    json_mode = "--json" in sys.argv
    no_cache = "--no-cache" in sys.argv
    args = [a for a in sys.argv[1:] if a not in ("--json", "--no-cache")]

    if not args:
        print(__doc__)
        return

    cmd = args[0]
    client = IliasClient(use_cache=not no_cache)

    try:
        if cmd == "dashboard":
            cmd_dashboard(client, json_mode)
        elif cmd == "browse":
            if len(args) < 2:
                print("Usage: ilias_client.py browse <ref_id>")
                return
            cmd_browse(client, int(args[1]), json_mode)
        elif cmd == "exams":
            ref_id = int(args[1]) if len(args) > 1 else 7750468
            cmd_exams(client, json_mode)
        elif cmd in ("reports", "berichtsheft"):
            cmd_reports(client, json_mode)
        elif cmd == "calendar":
            cmd_calendar(client, json_mode)
        elif cmd == "search":
            if len(args) < 2:
                print("Usage: ilias_client.py search <query>")
                return
            cmd_search(client, args[1], json_mode)
        elif cmd == "summary":
            cmd_summary(client, json_mode)
        elif cmd == "test":
            client._ensure_auth()
            print("✅ Session cookie works!")
        elif cmd == "topics":
            # Usage: ilias_client.py topics <YYYY-MM-DD> [module_code]
            if len(args) < 2:
                print("Usage: ilias_client.py topics <YYYY-MM-DD> [module_code]")
                return
            date = args[1]
            module = args[2] if len(args) > 2 else ""
            topics = client.get_day_topics(date, module)
            if topics:
                print(f"📚 **Themen für {date}**\n")
                for i, t in enumerate(topics, 1):
                    print(f"  {i}. {t}")
            else:
                print(f"📚 **{date}**: Keine Materialien gefunden (noch nicht hochgeladen oder kein Unterricht)")
        elif cmd == "edit-report":
            if len(args) < 2:
                print("Usage: ilias_client.py edit-report <request_id>")
                return
            form = client.get_report_form(int(args[1]))
            if json_mode:
                print(json.dumps(form, indent=2, ensure_ascii=False))
            else:
                print(f"📋 **Berichtsheft #{form['request_id']}**\n")
                print(f"Woche: {form['week_dates'][0]} – {form['week_dates'][-1]}")
                print(f"Nummer: {form['number'] or '(nicht gesetzt)'}")
                print(f"Abschnitt: {form['section'] or '(nicht gesetzt)'}")
                print(f"Extern/Praktikum: {'✅ Ja' if form['external'] else '❌ Nein'}")
                print(f"Bereits ausgefüllt: {'Ja' if form['has_content'] else 'Nein'}\n")
                # Show current content per day
                for date in form['week_dates']:
                    texts = []
                    for i in range(1, 5):
                        t = form['fields'].get(f"{date}_text{i}", "").strip()
                        if t:
                            texts.append(t)
                    h = form['fields'].get(f"{date}_hours", "0")
                    status = "✅" if texts else "⬜"
                    line = f"  {status} {date}: {h}h"
                    if texts:
                        line += f" — {' | '.join(texts[:2])}"
                        if len(texts) > 2:
                            line += f" (+{len(texts)-2} more)"
                    print(line)
        elif cmd == "save-day":
            # Usage: ilias_client.py save-day <request_id> <date> [hours] <text1> [text2] [text3] [text4] [--num nnnn] [--section "..."]
            if len(args) < 3:
                print("Usage: ilias_client.py save-day <request_id> <YYYY-MM-DD> [hours] <text1> [text2] [text3] [text4] [--num N] [--section '...'] [--external]")
                return
            req_id = int(args[1])
            date = args[2]

            # Parse optional named args
            named = {}
            texts_list = []
            i = 3
            while i < len(args):
                if args[i] == "--num" and i + 1 < len(args):
                    named["number"] = args[i + 1]; i += 2
                elif args[i] == "--section" and i + 1 < len(args):
                    named["section"] = args[i + 1]; i += 2
                elif args[i] == "--external":
                    named["external"] = True; i += 1
                else:
                    texts_list.append(args[i]); i += 1

            # First text-like arg might be hours if numeric
            hours = 10  # default
            texts = []
            if texts_list:
                try:
                    hours = int(texts_list[0])
                    texts = texts_list[1:]
                except ValueError:
                    texts = texts_list

            # Auto-derive number, section, external
            meta = client._get_report_meta(date)
            number = named.get("number", meta["number"])
            section = named.get("section", meta["section"])
            external = named.get("external", meta["external"])

            print(f"💾 Speichere {date} ({hours}h) für Bericht #{req_id}")
            print(f"   Nummer: {number} | Abschnitt: {section[:60]} | Extern: {'Ja' if external else 'Nein'}")
            success = client.save_report_day(req_id, date, texts, hours,
                                              report_number=number,
                                              section=section,
                                              external=external)
            if success:
                print(f"✅ Gespeichert! {date}: {hours}h — {' | '.join(texts[:2])}")
            else:
                print(f"❌ Speichern fehlgeschlagen.")
        else:
            print(f"Unknown command: {cmd}")
            print(__doc__)
    except AuthError as e:
        print(f"❌ Auth-Fehler: {e}")
        sys.exit(1)
    except SafetyError as e:
        print(f"🛡️  Safety: {e}")
        sys.exit(1)
    except requests.RequestException as e:
        print(f"🌐 Netzwerkfehler: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
