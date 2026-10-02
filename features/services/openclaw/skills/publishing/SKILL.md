---
name: publishing
description: Publish an application on the dedicated public app namespace using a private Unix socket.
---

# Application publishing

`OPENCLAW_SOCKET_DIR` is the private socket directory. `OPENCLAW_PUB_DOMAIN` is
the public namespace. An application named `demo` listens on
`$OPENCLAW_SOCKET_DIR/demo.sock` and is served at
`https://demo.$OPENCLAW_PUB_DOMAIN`.

Names must be lowercase ASCII letters, digits, or hyphens, start with a letter
or digit, and contain at most 63 characters. The router proxies HTTP and
WebSockets; it does not launch applications or persist application processes.

**Every published application is public.** Obtain the operator's permission
before publishing. Never publish the personal gateway, authenticated browser
profiles, OAuth callbacks, shell consoles, private notes, or credentials. If the
application needs private access, declare a normal authenticated service contract
instead of this public namespace.

Prefer an application server with native Unix sockets. For a loopback-only TCP
server, `socat UNIX-LISTEN:"$OPENCLAW_SOCKET_DIR/demo.sock",fork,mode=0600
TCP:127.0.0.1:<port>` bridges it without opening another network listener.
For a persistent application, declare its service in Nix; an OpenClaw background
process is useful for a demonstration, not a promise of reboot persistence.

Verify the actual public HTTPS response and WebSocket behavior when applicable.
Do not claim success from a process ID or an existing socket alone. Stop the
application and its bridge when withdrawing it; remove only its own stale socket.
