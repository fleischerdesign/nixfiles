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


def descendants(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from descendants(value)
    elif isinstance(node, list):
        for value in node:
            yield from descendants(value)


for exemption in json.load(open(sys.argv[2])):
    domain, paths = exemption["domain"], exemption["paths"]
    vhosts = [node for node in descendants(data)
              if isinstance(node.get("match"), list)
              and any(domain in match.get("host", []) for match in node["match"])]
    assert vhosts, f"Expected Caddy vHost for {domain}"
    routes = [node for vhost in vhosts for node in descendants(vhost)
              if isinstance(node.get("match"), list)
              and any(set(match.get("path", [])) == set(paths)
                      for match in node["match"])]
    assert routes, f"Expected self-authenticating route exceptions {paths} on {domain}"
    for route in routes:
        handlers = list(descendants(route.get("handle", [])))
        assert not any(node.get("handle_response") for node in handlers), (
            f"Expected no forward-auth on self-authenticating routes of {domain}"
        )
        assert any(node.get("handler") == "headers"
                   and "X-Authentik-*" in node.get("request", {}).get("delete", [])
                   for node in handlers), f"Expected forged identity headers stripped on {domain}"
        assert any(node.get("handler") == "reverse_proxy" for node in handlers), (
            f"Expected self-authenticating routes forwarded on {domain}"
        )
    assert any(node.get("handle_response") for vhost in vhosts for node in descendants(vhost)), (
        f"Expected ordinary routes to retain forward-auth on {domain}"
    )
assert not failures, "; ".join(sorted(set(failures)))
print("Expected every forward-auth block to strip identity headers before authenticating: verified")
