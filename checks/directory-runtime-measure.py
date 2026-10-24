"""Measure the directory with the real importer, the real provider binary and the ORM."""

import ast
from contextlib import contextmanager, redirect_stdout
import http.server
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import urllib.parse

from authentik.root.setup import setup

setup()
import django

django.setup()

from authentik.blueprints.v1.importer import Importer
from authentik.core.api.users import UserSerializer
from authentik.core.models import Application, Group, User, UserTypes
from authentik.policies.models import PolicyBinding
from authentik.stages.authenticator_webauthn.models import WebAuthnDevice

root, verifier, expectations_path, snapshot_path = map(Path, sys.argv[1:5])
expectations = json.loads(expectations_path.read_text())
directory = expectations["directory"]
superuser_groups = expectations["superuserGroups"]
# The directory has no blueprint: the provider is its only writer.

# Execute the exact verification functions embedded in the shipped apply script, not a test reimplementation.
tree = ast.parse(verifier.read_text())
functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
             and node.name in {"relation_diffs", "directory_preflight", "directory_observations"}]
assert len(functions) == 3, "Expected the production relation verifier and directory preflight"
namespace = {"root": root, "Importer": Importer, "json": json}
exec(compile(ast.Module(body=functions, type_ignores=[]), str(verifier), "exec"), namespace)
preflight = namespace["directory_observations"]

# The provider is the only writer for groups. This adapter translates the three endpoints it speaks into
# the ORM calls the API would make; the binary under test is the shipped one, not a reimplementation.
TOKEN = "fixture-token"
PAGE_SIZE = 2

def group_payload(group):
    return {
        "pk": str(group.pk),
        "name": group.name,
        "is_superuser": group.is_superuser,
        "attributes": group.attributes or {},
        "users": list(group.users.values_list("pk", flat=True)),
        "users_obj": [
            {"pk": user.pk, "username": user.username}
            for user in group.users.order_by("username")
        ],
    }

def user_payload(user):
    return {
        "pk": user.pk,
        "username": user.username,
        "name": user.name,
        "email": user.email,
        "attributes": user.attributes or {},
        "is_active": user.is_active,
    }

def application_payload(app):
    return {
        "slug": app.slug,
        "name": app.name,
        "provider_obj": (
            {"pk": app.provider.pk, "name": app.provider.name}
            if app.provider
            else None
        ),
        "open_in_new_tab": app.open_in_new_tab,
        "meta_launch_url": app.meta_launch_url,
        "meta_description": app.meta_description,
        "meta_publisher": app.meta_publisher,
        "policy_engine_mode": app.policy_engine_mode,
        "group": app.group,
        "meta_hide": app.meta_hide,
    }

def binding_payload(binding):
    return {
        "pk": str(binding.pk),
        "target": str(binding.target_id),
        "group": str(binding.group_id) if binding.group_id else None,
        "user": binding.user_id,
        "policy": str(binding.policy_id) if binding.policy_id else None,
        "enabled": binding.enabled,
    }

class StubAuthentik(http.server.BaseHTTPRequestHandler):
    """The Authentik group, user and application endpoints, backed by the real ORM."""

    def log_message(self, *args):
        pass

    def _authorised(self):
        if self.headers.get("Authorization") == f"Bearer {TOKEN}":
            return True
        self._send(401, {"detail": "unauthorised"})
        return False

    def _send(self, status, payload=None):
        body = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def _page(self, rows, render):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        page = int(query.get("page", ["1"])[0])
        size = int(query.get("page_size", [str(PAGE_SIZE)])[0])
        window = rows[(page - 1) * size:page * size]
        following = page + 1 if page * size < len(rows) else None
        self._send(200, {
            "pagination": {"next": following, "count": len(rows)},
            "results": [render(row) for row in window],
        })

    def do_GET(self):
        try:
            if not self._authorised():
                return
            route = urllib.parse.urlparse(self.path).path
            if route == "/api/v3/core/groups/":
                self._page(list(Group.objects.order_by("name")), group_payload)
            elif route == "/api/v3/core/users/":
                self._page(list(User.objects.order_by("username")), user_payload)
            elif route == "/api/v3/core/applications/":
                self._page(list(Application.objects.order_by("slug")), application_payload)
            elif route == "/api/v3/policies/bindings/":
                self._page(list(PolicyBinding.objects.all()), binding_payload)
            elif route == "/api/v3/providers/proxy/":
                self._page([], lambda provider: provider)
            elif route == "/api/v3/flows/instances/":
                self._page([], lambda flow: flow)
            elif route == "/api/v3/providers/all/":
                self._page([], lambda provider: provider)
            elif route == "/api/v3/outposts/instances/":
                self._page([], lambda outpost: outpost)
            else:
                self._send(404, {"detail": "not found"})
        finally:
            django.db.connections.close_all()

    def do_POST(self):
        try:
            if not self._authorised():
                return
            route = urllib.parse.urlparse(self.path).path
            body = self._body()
            if route == "/api/v3/core/users/":
                user = User.objects.create(
                    username=body["username"],
                    name=body.get("name", ""),
                    email=body.get("email", ""),
                    attributes=body.get("attributes") or {},
                    is_active=body.get("is_active", True),
                )
                self._send(201, user_payload(user))
                return
            group = Group.objects.create(
                name=body["name"],
                is_superuser=body.get("is_superuser", False),
                attributes=body.get("attributes") or {},
            )
            if "users" in body:
                group.users.set(User.objects.filter(pk__in=body["users"]))
            self._send(201, group_payload(group))
        finally:
            django.db.connections.close_all()

    def _group(self):
        route = urllib.parse.urlparse(self.path).path.rstrip("/")
        try:
            pk = route.rsplit("/", 1)[1]
            return Group.objects.get(pk=pk)
        except (IndexError, Group.DoesNotExist):
            self._send(404, {"detail": "not found"})
            return None

    def do_PATCH(self):
        try:
            if not self._authorised():
                return
            route = urllib.parse.urlparse(self.path).path
            body = self._body()
            if route.startswith("/api/v3/core/users/"):
                try:
                    user = User.objects.get(pk=route.rstrip("/").rsplit("/", 1)[1])
                except (IndexError, User.DoesNotExist):
                    self._send(404, {"detail": "not found"})
                    return
                if "attributes" in body:
                    user.attributes = body["attributes"] or {}
                user.save()
                self._send(200, user_payload(user))
                return
            group = self._group()
            if group is None:
                return
            if "is_superuser" in body:
                group.is_superuser = body["is_superuser"]
            if "attributes" in body:
                group.attributes = body["attributes"] or {}
            group.save()
            if "users" in body:
                group.users.set(User.objects.filter(pk__in=body["users"]))
            self._send(200, group_payload(group))
        finally:
            django.db.connections.close_all()

    def do_DELETE(self):
        try:
            if not self._authorised():
                return
            group = self._group()
            if group is None:
                return
            group.delete()
            self._send(204)
        finally:
            django.db.connections.close_all()

@contextmanager
def provider_settings():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), StubAuthentik)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield {
            "url": f"http://127.0.0.1:{server.server_address[1]}",
            "token_env": "AUTHENTIK_TOKEN",
            "marker_key": "vyrx",
            "marker_value": "owned",
            "page_size": PAGE_SIZE,
        }
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

def provider(requests):
    completed = subprocess.run(
        [expectations["provider"]],
        input="".join(json.dumps(request) + "\n" for request in requests),
        text=True, capture_output=True, check=True,
        env={**os.environ, "AUTHENTIK_TOKEN": TOKEN},
    )
    assert completed.stderr == "", completed.stderr
    return [json.loads(line) for line in completed.stdout.splitlines()]

desired_state = json.loads(Path(expectations["desiredState"]).read_text())
# This check measures the directory: groups and the users they contain. Applications are the provider's
# own kind, covered by its tests and the live fleet; the sandbox has no application create path, and adding
# one would test a stub, not the directory.
desired = [
    entry
    for entry in desired_state["resources"]
    if entry["kind"] in {"authentik.group", "authentik.user"}
]
absent = [entry["id"] for entry in desired_state.get("absent", [])]
assert expectations["subjects"]["retired"] in absent, (
    "a retired group must be an authorized deletion, not an implicit one",
    absent,
)

def observe(settings):
    return provider([{"op": "observe", "config": settings}])[0]["resources"]

def plan(settings, observed):
    return provider([{"op": "plan", "desired": desired, "observed": observed}])[0]["changes"]

def reconcile(settings, changes):
    result = provider([{"op": "apply", "config": settings, "changes": changes}])[0]
    assert all(item["ok"] for item in result["applied"]), result
    return result

def provider_apply(settings):
    """Converge the provider and return what it planned; an empty plan is converged."""
    changes = plan(settings, observe(settings))
    if changes:
        reconcile(settings, changes)
    return changes

def personal_state():
    usernames = list(directory["users"]) + ["ui-created-fixture"]
    return {
        "users": list(User.objects.filter(username__in=usernames).order_by("username").values(
            "pk", "username", "name", "email", "password", "attributes", "type", "is_active")),
        "credentials": list(WebAuthnDevice.objects.filter(credential_id="fixture-credential").values(
            "pk", "user_id", "name", "credential_id", "public_key", "rp_id", "sign_count")),
        "groups": {group.name: sorted(group.users.values_list("username", flat=True))
                   for group in Group.objects.order_by("name")},
    }

def diagnose(expected):
    before = personal_state()
    output = io.StringIO()
    with redirect_stdout(output):
        try:
            exec(compile(Path(expectations["reportScript"]).read_text(), "directory-report", "exec"), {})
        except SystemExit as result:
            assert result.code == (1 if any(expected.values()) else 0), result.code
        else:
            raise AssertionError("The production directory report must return an explicit verdict")
    assert json.loads(output.getvalue()) == expected, output.getvalue()
    assert personal_state() == before, "Read-only directory report modified personal state"

if sys.argv[5:] == ["--restore"]:
    expected = json.loads(snapshot_path.read_text())
    assert json.loads(json.dumps(personal_state(), default=str)) == expected, "Database restore changed personal state"
    with provider_settings() as settings:
        assert provider_apply(settings) == [], "a restored database is already converged"
    assert preflight() == {"failures": [], "pending": [], "inactive": []}, preflight()
    diagnose(preflight())
    assert json.loads(json.dumps(personal_state(), default=str)) == expected, "Apply after restore changed personal state"
    assert User.objects.get(username=expectations["subjects"]["user"]).check_password("disposable-personal-password")
    print("Expected logical database restore and subsequent apply to preserve identities, credentials and memberships: verified")
    sys.exit(0)

initial = preflight()
assert initial["failures"] and initial["pending"], initial
diagnose(initial)
assert not User.objects.filter(username=expectations["subjects"]["user"]).exists()
assert not Group.objects.filter(name=expectations["subjects"]["managed"]).exists()
print("Expected missing UI references to fail preflight while missing seeds remain pending, without writes: verified")

for username, declaration in directory["users"].items():
    if declaration["initialProfile"] is None:
        serializer = UserSerializer(data={"username": username, "name": "Existing UI profile",
                                          "email": "existing-ui@example.test"})
        serializer.is_valid(raise_exception=True)
        serializer.save()
reference_user = expectations["subjects"]["referenceUser"]
referenced = User.objects.get(username=reference_user)
referenced.type = UserTypes.SERVICE_ACCOUNT
referenced.save(update_fields=["type"])
assert any(reference_user in failure and "service account" in failure for failure in preflight()["failures"])
diagnose(preflight())
referenced.type = UserTypes.INTERNAL
referenced.save(update_fields=["type"])
assert preflight()["failures"] == [], preflight()
print("Expected service-account collisions to fail before explicit apply: verified")
# The directory is provider-owned: no blueprint file may exist for it.
assert not (root / "01-rbac/users.yaml").exists(), "the directory blueprint must be gone"

managed = expectations["subjects"]["managed"]
ordinary = expectations["subjects"]["ordinary"]
seeded = expectations["subjects"]["user"]

with provider_settings() as settings:
    observed = observe(settings)
    groups = [resource for resource in observed if resource["kind"] == "authentik.group"]
    assert groups == [], groups
    # The seed does not exist yet: the provider creates it in this run.
    assert not any(
        resource["kind"] == "authentik.user"
        and resource["id"] == expectations["subjects"]["user"]
        for resource in observed
    )
    changes = plan(settings, observed)
    assert changes and {change["kind"] for change in changes} == {"create"}, changes
    reconcile(settings, changes)

    seeded_user = User.objects.get(username=expectations["subjects"]["user"])
    assert seeded_user.attributes.get("vyrx") == "owned", seeded_user.attributes

    for name, declaration in sorted(directory["groups"].items()):
        if declaration["state"] != "present":
            continue
        group = Group.objects.get(name=name)
        assert group.attributes.get("vyrx") == "owned", (name, group.attributes)
        assert group.attributes.get("description") == declaration["description"], (name, group.attributes)
        assert group.is_superuser == (name in superuser_groups), name
        if declaration["members"] is not None:
            assert sorted(group.users.values_list("username", flat=True)) == sorted(declaration["members"]), name
    print("Expected the provider to create every declared group with marker, description and membership: verified")

    changes = plan(settings, observe(settings))
    assert changes == [], changes
    print("Expected a converged directory to plan nothing: verified")

    drifted = Group.objects.get(name=managed)
    drifted.attributes = {**drifted.attributes, "description": "drifted"}
    drifted.save(update_fields=["attributes"])
    changes = plan(settings, observe(settings))
    assert len(changes) == 1 and changes[0]["resource"]["id"] == managed and changes[0]["kind"] == "update", changes
    reconcile(settings, changes)
    drifted.refresh_from_db()
    assert drifted.attributes["description"] == directory["groups"][managed]["description"]
    print("Expected a drifted description to plan exactly one update and be restored: verified")

    target = Group.objects.get(name=managed)
    target.users.remove(User.objects.get(username=seeded))
    changes = plan(settings, observe(settings))
    assert len(changes) == 1 and changes[0]["kind"] == "update", changes
    reconcile(settings, changes)
    assert sorted(target.users.values_list("username", flat=True)) == sorted(directory["groups"][managed]["members"])
    print("Expected a missing managed member to be restored by the provider: verified")

    extra = User.objects.create(username="provider-extra-fixture", name="Extra", email="extra@example.test")
    target.users.add(extra)
    changes = plan(settings, observe(settings))
    assert len(changes) == 1 and changes[0]["kind"] == "update", changes
    reconcile(settings, changes)
    assert extra.username not in set(target.users.values_list("username", flat=True))
    print("Expected an extra member on a declared group to be removed by the provider: verified")

    foreign = Group.objects.create(name="unowned-fixture")
    changes = plan(settings, observe(settings))
    assert not any(change["resource"]["id"] == "unowned-fixture" for change in changes), changes
    refused = provider([{"op": "apply", "config": settings, "changes": [{
        "kind": "update", "owned": False, "destructive": False,
        "resource": {"kind": "authentik.group", "id": "unowned-fixture",
                     "attributes": {"is_superuser": True, "description": "x"}}}]}])[0]["applied"]
    assert refused[0]["ok"] is False and "unowned" in refused[0]["message"], refused
    foreign.refresh_from_db()
    assert foreign.is_superuser is False and foreign.attributes == {}
    print("Expected an unowned group to be left alone and a forced change to be refused: verified")

    Group.objects.create(name="retired-fixture", attributes={"vyrx": "owned"})
    changes = plan(settings, observe(settings))
    deletes = [change for change in changes if change["kind"] == "delete"]
    assert [change["resource"]["id"] for change in deletes] == ["retired-fixture"], changes
    reconcile(settings, deletes)
    assert not Group.objects.filter(name="retired-fixture").exists()
    print("Expected an owned group outside the declaration to be deleted: verified")

assert preflight() == {"failures": [], "pending": [], "inactive": []}, preflight()
diagnose(preflight())

user = User.objects.get(username=seeded)
user.name = "Personal changed name"
user.email = "personal-change@example.test"
user.attributes = {"personal_preference": "keep"}
user.set_password("disposable-personal-password")
user.save()
credential = WebAuthnDevice.objects.create(
    user=user, name="Persisted credential fixture", credential_id="fixture-credential",
    public_key="fixture-public-key", rp_id="example.test",
)
group = Group.objects.get(name=ordinary)
group.users.add(user)
serializer = UserSerializer(data={"username": "ui-created-fixture", "name": "UI user",
                                  "email": "ui@example.test", "groups": [group.pk]})
serializer.is_valid(raise_exception=True)
invited = serializer.save()
with provider_settings() as settings:
    assert provider_apply(settings) == [], "a converged directory plans nothing"
user.refresh_from_db()
assert (user.name, user.email, user.attributes) == (
    "Personal changed name", "personal-change@example.test", {"personal_preference": "keep"})
assert user.check_password("disposable-personal-password")
assert WebAuthnDevice.objects.filter(pk=credential.pk, user=user).exists()
assert User.objects.filter(pk=invited.pk).exists()
assert User.objects.get(username=reference_user).email == "existing-ui@example.test"
print("Expected personal email/name/password/passkey record and UI memberships to survive repeat apply: preserved")

# `ordinary` declares no membership: a UI-owned membership must survive a reconcile untouched.
with provider_settings() as settings:
    changes = plan(settings, observe(settings))
    assert changes == [], changes
    reconcile(settings, changes)
assert set(group.users.values_list("username", flat=True)) == {seeded, invited.username}
print("Expected an undeclared membership to stay UI-owned through a provider reconcile: verified")

user.is_active = False
user.save(update_fields=["is_active"])
observation = preflight()
assert observation["failures"] == [] and any(seeded in value for value in observation["inactive"]), observation
diagnose(observation)
with provider_settings() as settings:
    provider_apply(settings)
user.refresh_from_db()
assert user.is_active is False, "Apply reactivated a UI-suspended account"
assert user.check_password("disposable-personal-password")
assert WebAuthnDevice.objects.filter(pk=credential.pk, user=user).exists()
user.is_active = True
user.save(update_fields=["is_active"])
print("Expected UI suspension to remain effective after apply without destroying credentials: verified")

target = Group.objects.get(name=managed)
target.users.add(invited)
with provider_settings() as settings:
    changes = plan(settings, observe(settings))
    assert len(changes) == 1 and changes[0]["kind"] == "update", changes
    reconcile(settings, changes)
invited.refresh_from_db()
assert set(target.users.values_list("username", flat=True)) == {seeded, reference_user}
assert (invited.name, invited.email) == ("UI user", "ui@example.test")
print("Expected an existing UI-created identity to resolve without reseeding its profile: verified")

target.users.clear()
assert not target.users.exists()
with provider_settings() as settings:
    changes = plan(settings, observe(settings))
    assert len(changes) == 1 and changes[0]["kind"] == "update", changes
    reconcile(settings, changes)
assert set(target.users.values_list("username", flat=True)) == {seeded, reference_user}
print("Expected an emptied managed group to be restored to its exact declared membership: verified")

target.delete()
assert any("declared but not created yet" in value for value in preflight()["pending"]), preflight()
with provider_settings() as settings:
    changes = plan(settings, observe(settings))
    assert [change["kind"] for change in changes] == ["create"], changes
    reconcile(settings, changes)
assert Group.objects.filter(name=managed).exists()
assert preflight()["pending"] == [], preflight()
print("Expected a missing managed group to be planned, recreated and observed again: verified")

snapshot_path.write_text(json.dumps(personal_state(), default=str))
