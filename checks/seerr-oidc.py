"""Measure targeted native API updates, preservation, idempotence, and credential failure."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from urllib.parse import unquote

spec = importlib.util.spec_from_file_location("configure_oidc", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
desired = json.loads(Path(sys.argv[2]).read_text())
assert desired["provider"]["issuerUrl"] == sys.argv[3]
assert desired["provider"]["slug"] == "authentik"
assert desired["provider"]["clientId"] == "seerr"

state = {"providers": [
    {"slug": desired["provider"]["slug"], "issuerUrl": "https://obsolete.invalid/",
     "newUserLogin": True, "requiredClaims": "ui-owned-claim", "logo": "ui-owned-logo"},
    {"slug": "other", "clientSecret": "synthetic-other", "name": "UI-owned provider"},
]}
original = deepcopy(state)
main = {"apiKey": "synthetic-api", **desired["main"], "applicationTitle": "UI-owned title"}
writes = []


def request(method, path, body=None):
    if method == "GET":
        return deepcopy(state)
    writes.append((method, path, deepcopy(body)))
    if method == "PUT":
        assert "slug" not in body, "Expected the native OpenAPI read-only field to stay out of PUT"
        slug = unquote(path.rsplit("/", 1)[1])
        provider = next((p for p in state["providers"] if p["slug"] == slug), None)
        if provider is None:
            provider = {"slug": slug}
            state["providers"].append(provider)
        provider.update(body)
        return deepcopy(provider)
    assert method == "POST" and path == "/api/v1/settings/main"
    assert body == desired["main"]
    main.update(body)
    return deepcopy(main)


with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / "settings.json"
    path.write_text(json.dumps({"main": main}))
    module.configure("http://localhost", path, desired, "synthetic-secret", request)
    assert len(writes) == 1 and writes[0][0] == "PUT"
    assert state["providers"][1] == original["providers"][1]
    for key in ["newUserLogin", "requiredClaims", "logo"]:
        assert state["providers"][0][key] == original["providers"][0][key]
    writes.clear()
    module.configure("http://localhost", path, desired, "synthetic-secret", request)
    assert writes == [], "Expected an idempotent native configuration apply"
    try:
        module.configure("http://localhost", path, desired, "", request)
        raise AssertionError("Expected missing credential to fail")
    except ValueError:
        pass
    assert writes == []
    state["providers"] = []
    main["oidcLogin"] = False
    main["applicationUrl"] = "https://obsolete.invalid"
    path.write_text(json.dumps({"main": main}))
    module.configure("http://localhost", path, desired, "synthetic-secret", request)
    assert state["providers"][0]["newUserLogin"] is False
    assert main["oidcLogin"] is True and main["applicationTitle"] == "UI-owned title"
    assert main["applicationUrl"] == desired["main"]["applicationUrl"]
print("Expected native OIDC configuration, UI preservation, idempotence and missing-secret failure: verified")
