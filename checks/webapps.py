"""Exercise Firefox's native webapp CLI in a disposable profile, without external network."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.support.ui import WebDriverWait


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"<!doctype html><title>Native webapp acceptance</title><p>Fixture</p>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def check_launchers(manifest):
    with tempfile.TemporaryDirectory() as temporary:
        log = Path(temporary) / "argv.json"
        for status in [0, 17]:
            result = subprocess.run(
                [manifest["fixture"]],
                env=os.environ | {"CALL_LOG": str(log), "BROWSER_EXIT": str(status)},
                capture_output=True,
                text=True,
            )
            assert result.returncode == status, result.stderr
            assert json.loads(log.read_text()) == manifest["expected"]
    for host, configuration in manifest["hosts"].items():
        assert configuration["enabled"] == {"Value": True, "Status": "locked"}, host
        for mime in ["text/html", "x-scheme-handler/http", "x-scheme-handler/https"]:
            assert configuration["mime"][mime] == ["firefox.desktop"], (host, mime)
        assert len(configuration["packages"]) == len(configuration["apps"]), host
        for package in configuration["packages"]:
            path = Path(package)
            (desktop,) = (path / "share/applications").glob("*.desktop")
            entries = dict(
                line.split("=", 1)
                for line in desktop.read_text().splitlines()
                if "=" in line
            )
            executable = shlex.split(entries["Exec"])
            assert len(executable) == 1, entries
            script = Path(executable[0]).read_text()
            assert "-taskbar-tab" in script and "nix-webapp-bootstrap" in script, script
            assert "google-chrome" not in script, script
            assert configuration["firefox"] in script, "launcher bypassed the policy-wrapped Firefox"
        print(
            f"{host}: {len(configuration['packages'])} native Firefox launchers and MIME defaults checked",
            flush=True,
        )


def exercise(firefox, geckodriver, manifest):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        profile = root / "profile"
        profile.mkdir()
        server = ThreadingHTTPServer(("127.0.0.1", 0), Page)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://webapp.example.test:{server.server_port}"
        original_id = None
        try:
            for launch in range(2):
                options = Options()
                options.binary_location = firefox
                arguments = [
                    url if arg == "http://webapp.example.test" else arg
                    for arg in manifest["arguments"]
                ]
                for argument in ["-headless", "-profile", str(profile), *arguments]:
                    options.add_argument(argument)
                options.set_preference("network.dns.localDomains", "webapp.example.test")
                options.set_preference("network.proxy.type", 0)
                options.set_preference("browser.shell.checkDefaultBrowser", False)
                options.set_preference("browser.startup.homepage_override.mstone", "ignore")
                options.set_preference("datareporting.policy.dataSubmissionEnabled", False)
                options.accept_insecure_certs = False
                service = Service(
                    executable_path=geckodriver,
                    service_args=["--allow-system-access"],
                    log_output=str(root / "geckodriver.log"),
                )
                driver = webdriver.Firefox(options=options, service=service)
                try:
                    driver.set_context("chrome")
                    policy = driver.execute_script(
                        """
                        return [Services.prefs.getBoolPref('browser.taskbarTabs.enabled'),
                          Services.prefs.prefIsLocked('browser.taskbarTabs.enabled')];
                        """
                    )
                    assert policy == [True, True], "configured Firefox must enable and lock native webapps"
                    state = WebDriverWait(driver, 30).until(
                        lambda browser: browser.execute_script(
                            """
                        const {TaskbarTabsUtils} = ChromeUtils.importESModule(
                          'resource:///modules/taskbartabs/TaskbarTabsUtils.sys.mjs');
                        const windows = Array.from(Services.wm.getEnumerator('navigator:browser'));
                        const win = windows.find(w => TaskbarTabsUtils.getTaskbarTabIdFromWindow(w));
                        if (!win?.gBrowser?.selectedBrowser) return null;
                        const browser = win.gBrowser.selectedBrowser;
                        if (!browser.currentURI.spec.startsWith(arguments[0])) return null;
                        return {id: TaskbarTabsUtils.getTaskbarTabIdFromWindow(win),
                          mode: browser.browsingContext.displayMode,
                          container: win.gBrowser.selectedTab.userContextId,
                          profile: Services.dirsvc.get('ProfD', Ci.nsIFile).path};
                            """,
                            url,
                        )
                    )
                    assert state["mode"] == "minimal-ui", state
                    assert state["container"] == 0, state
                    assert Path(state["profile"]) == profile, state
                    assert state["id"] != "nix-webapp-bootstrap", state
                    if original_id is not None:
                        assert state["id"] == original_id, "repeated launch created a different app"
                    original_id = state["id"]
                    driver.set_context("content")
                    WebDriverWait(driver, 30).until(
                        lambda browser: browser.title == "Native webapp acceptance"
                    )
                    if launch == 0:
                        driver.add_cookie({
                            "name": "session-fixture",
                            "value": "shared-profile",
                            "expiry": int(time.time()) + 3600,
                        })
                    else:
                        assert driver.get_cookie("session-fixture")["value"] == "shared-profile"
                    print(
                        f"Native launch {launch + 1}: app window, shared profile, ID {original_id}",
                        flush=True,
                    )
                finally:
                    driver.quit()
                registry = json.loads((profile / "taskbartabs/taskbartabs.json").read_text())
                assert registry["version"] == 1, registry
                assert len(registry["taskbarTabs"]) == 1, registry
                assert registry["taskbarTabs"][0]["id"] == original_id, registry
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            log = root / "geckodriver.log"
            if log.exists():
                print(log.read_text(), file=sys.stderr)


if __name__ == "__main__":
    firefox, geckodriver, manifest_path = sys.argv[1:]
    manifest = json.loads(Path(manifest_path).read_text())
    check_launchers(manifest)
    exercise(firefox, geckodriver, manifest)
