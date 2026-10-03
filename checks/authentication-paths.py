"""Compare declared forward-auth dependencies with Caddy's actual adapted consumers."""
import json
from pathlib import Path
import sys


def targets(value):
    if isinstance(value, dict):
        if value.get("handler") == "reverse_proxy" and value.get("rewrite", {}).get("uri") == "/outpost.goauthentik.io/auth/caddy":
            yield from (u["dial"] for u in value["upstreams"])
        for child in value.values():
            yield from targets(child)
    elif isinstance(value, list):
        for child in value:
            yield from targets(child)


for name, expected in json.loads(Path(sys.argv[1]).read_text()).items():
    observed = set(targets(json.loads(Path(f"{name}.json").read_text())))
    assert bool(observed) == expected["required"], (name, expected, observed)
    assert observed <= {expected["address"]}, (name, expected, observed)
print("Expected declared forward-auth dependencies to match Caddy's executed configuration: verified")
