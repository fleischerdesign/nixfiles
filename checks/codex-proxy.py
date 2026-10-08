"""Exercise Responses translation against a local, credential-checked provider."""

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

requests = []

installed_unit = Path.home() / ".config/systemd/user/opencodex-proxy.service"
if installed_unit.exists() or installed_unit.is_symlink():
    raise SystemExit(
        "Run this isolated fixture under a test account without an installed OpenCodex service. "
        "The live service's ownership guard correctly rejects a proxy using foreign test homes."
    )


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply({"object": "list", "data": [{"id": "fixture-model", "object": "model"}]})

    def do_POST(self):
        if self.headers.get("Authorization") != "Bearer fixture-secret":
            self.send_error(401)
            return
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        requests.append(body)
        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for delta, finish in [({"role": "assistant", "content": "fixture-content"}, None), ({}, "stop")]:
                chunk = {"id": "chatcmpl-followup", "object": "chat.completion.chunk", "created": 1,
                         "model": "fixture-model", "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return
        self.reply({
            "id": "chatcmpl-fixture", "object": "chat.completion", "created": 1,
            "model": "fixture-model",
            "choices": [{"index": 0, "finish_reason": "tool_calls", "message": {
                "role": "assistant", "content": None,
                "tool_calls": [{"id": "call-fixture", "type": "function", "function": {
                    "name": "read_fixture", "arguments": '{"path":"fixture.txt"}'
                }}],
            }}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        })


provider = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
threading.Thread(target=provider.serve_forever, daemon=True).start()
with socket.socket() as reservation:
    reservation.bind(("127.0.0.1", 0))
    port = reservation.getsockname()[1]

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    codex_home, proxy_home = root / "codex", root / "proxy"
    codex_home.mkdir()
    proxy_home.mkdir()
    (codex_home / "config.toml").write_text("")
    (proxy_home / "config.json").write_text(json.dumps({
        "hostname": "127.0.0.1", "port": port, "defaultProvider": "fixture",
        "providers": {"fixture": {
            "adapter": "openai-chat", "authMode": "key", "apiKey": "${FIXTURE_KEY}",
            "baseUrl": f"http://127.0.0.1:{provider.server_port}/v1",
            "allowPrivateNetwork": True, "models": ["fixture-model"],
        }},
        "claudeCode": {"enabled": False, "intercept": {"enabled": False}},
        "codexAutoStart": False, "codexShimAutoRestore": False,
    }))
    environment = os.environ | {
        "CODEX_HOME": str(codex_home), "OPENCODEX_HOME": str(proxy_home),
        "FIXTURE_KEY": "fixture-secret", "OCX_SERVICE": "1", "OCX_SERVICE_MANAGED": "1",
        "OCX_TEST_HOME_GUARD": "1", "OCX_OWNER_REGISTRY_DIR": str(root / "owners"),
    }
    with (root / "proxy.log").open("w+") as log:
        process = subprocess.Popen([sys.argv[1], "start", "--port", str(port)],
                                   env=environment, stdout=log, stderr=log)
        try:
            endpoint = f"http://127.0.0.1:{port}"
            deadline = time.monotonic() + 45
            while True:
                if process.poll() is not None:
                    raise RuntimeError(f"Proxy exited with {process.returncode}")
                try:
                    with urllib.request.urlopen(endpoint + "/readyz", timeout=2) as response:
                        if json.load(response)["status"] == "ready":
                            break
                except (OSError, urllib.error.HTTPError):
                    pass
                if time.monotonic() >= deadline:
                    raise RuntimeError("Expected proxy readiness within 45 seconds")
                time.sleep(0.1)

            with urllib.request.urlopen(endpoint + "/", timeout=5) as response:
                assert b"<html" in response.read(), "Expected the packaged dashboard"
            request = urllib.request.Request(endpoint + "/v1/responses", method="POST",
                headers={"Content-Type": "application/json"}, data=json.dumps({
                    "model": "fixture/fixture-model", "stream": False,
                    "input": [{"role": "user", "content": "Read fixture.txt"}],
                    "tools": [{"type": "function", "name": "read_fixture", "parameters": {
                        "type": "object", "properties": {"path": {"type": "string"}},
                        "required": ["path"],
                    }}],
                }).encode())
            with urllib.request.urlopen(request, timeout=15) as response:
                result = json.load(response)
            calls = [item for item in result["output"] if item["type"] == "function_call"]
            assert calls and calls[0]["name"] == "read_fixture", "Expected translated tool call"
            assert json.loads(calls[0]["arguments"])["path"] == "fixture.txt"
            assert requests[-1]["model"] == "fixture-model", "Expected the selected upstream model"
            assert requests[-1]["tools"][0]["function"]["name"] == "read_fixture"
            followup = urllib.request.Request(endpoint + "/v1/responses", method="POST",
                headers={"Content-Type": "application/json"}, data=json.dumps({
                    "model": "fixture/fixture-model", "stream": True,
                    "input": [
                        {"role": "user", "content": "Read fixture.txt"},
                        {"type": "function_call", "call_id": calls[0]["call_id"],
                         "name": calls[0]["name"], "arguments": calls[0]["arguments"]},
                        {"type": "function_call_output", "call_id": calls[0]["call_id"], "output": "fixture-content"},
                    ],
                }).encode())
            with urllib.request.urlopen(followup, timeout=15) as response:
                stream = response.read().decode()
            assert "response.completed" in stream and "fixture-content" in stream, "Expected a completed streamed follow-up"
            tool_results = [message for message in requests[-1]["messages"] if message["role"] == "tool"]
            assert tool_results and tool_results[0]["content"] == "fixture-content", "Expected the tool result at the provider"
            config = (codex_home / "config.toml").read_text()
            assert f"127.0.0.1:{port}/v1" in config, "Expected Codex routing through the proxy"
            assert (codex_home / "opencodex-catalog.json").is_file(), "Expected the shared catalog"
            print("Verified dashboard, readiness, credential reference, routing, tools and streamed follow-up")
        except BaseException:
            log.flush()
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
provider.shutdown()
