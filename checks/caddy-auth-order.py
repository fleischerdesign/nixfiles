"""Prove that identity headers are stripped before forward-auth copies them.

Caddy orders `forward_auth` before `request_header`. A generated block that
strips client-supplied identity headers *after* the auth step therefore deletes
the trusted headers the auth step just copied, and a downstream trusted-proxy
consumer sees none. The order is invisible in the Caddyfile source (Caddy
reorders it), so the only honest measurement is Caddy's own adapted output: for
every block that performs forward-auth, the strip must appear earlier in the
same ordered handler list.
"""

import json
import sys

data = json.load(open(sys.argv[1]))

failures = []


def check_block(routes):
    strip = None
    forward = None
    for index, route in enumerate(routes):
        if not isinstance(route, dict):
            continue
        if route.get("handler") == "headers":
            request = route.get("request")
            if isinstance(request, dict) and "X-Authentik-*" in (request.get("delete") or []):
                strip = index if strip is None else strip
        if route.get("handler") == "reverse_proxy" and route.get("handle_response"):
            forward = index if forward is None else forward
    if forward is not None:
        if strip is None:
            failures.append("a forward-auth block does not strip X-Authentik-* in the same block")
        elif strip > forward:
            failures.append(
                f"identity-header strip at index {strip} runs after forward-auth at index {forward}"
            )


def walk(node):
    if isinstance(node, list):
        check_block(node)
        for value in node:
            walk(value)
    elif isinstance(node, dict):
        for value in node.values():
            walk(value)


walk(data)
assert not failures, "; ".join(sorted(set(failures)))
print("Expected every forward-auth block to strip identity headers before authenticating: verified")
