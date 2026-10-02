"""Measure profile ownership, UI users and exact membership with the real importer and ORM."""

import ast
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys

from authentik.root.setup import setup

setup()
import django

django.setup()

from authentik.blueprints.v1.importer import Importer
from authentik.core.api.users import UserSerializer
from authentik.core.models import Group, User, UserTypes
from authentik.stages.authenticator_webauthn.models import WebAuthnDevice
import yaml

root, verifier, expectations_path, snapshot_path = map(Path, sys.argv[1:5])
expectations = json.loads(expectations_path.read_text())
directory = expectations["directory"]
path = "01-rbac/users-and-groups.yaml"
source = (root / path).read_text()

def apply(content=source):
    assert Importer.from_string(content, {}).apply(), "Native directory blueprint apply failed"

def change_group(name, attrs=None, state="present"):
    entry = {"model": "authentik_core.group", "identifiers": {"name": name}, "state": state}
    if attrs is not None:
        entry["attrs"] = attrs
    apply(yaml.safe_dump({"version": 1, "metadata": {"name": "fixture"}, "entries": [entry]}))

# Execute the exact verification functions embedded in the shipped apply script, not a test reimplementation.
tree = ast.parse(verifier.read_text())
functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
             and node.name in {"group_membership_diffs", "relation_diffs", "directory_preflight", "directory_observations"}]
assert len(functions) == 4, "Expected the production membership verifier and directory preflight"
namespace = {"root": root, "Importer": Importer, "json": json}
exec(compile(ast.Module(body=functions, type_ignores=[]), str(verifier), "exec"), namespace)
verify = lambda: namespace["relation_diffs"]([path])
preflight = namespace["directory_observations"]

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
    apply()
    assert verify() == [], verify()
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
blueprint = Importer.from_string(source, {}).blueprint
assert not any(entry.get_model(blueprint) == "authentik_core.user"
               and entry.identifiers.get("username") == reference_user
               for entry in blueprint.iter_entries())
apply()
assert verify() == [], verify()
assert preflight() == {"failures": [], "pending": [], "inactive": []}, preflight()
diagnose(preflight())
seeded = expectations["subjects"]["user"]
managed = expectations["subjects"]["managed"]
ordinary = expectations["subjects"]["ordinary"]
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
apply()
apply()
user.refresh_from_db()
assert (user.name, user.email, user.attributes) == (
    "Personal changed name", "personal-change@example.test", {"personal_preference": "keep"})
assert user.check_password("disposable-personal-password")
assert WebAuthnDevice.objects.filter(pk=credential.pk, user=user).exists()
assert set(group.users.values_list("username", flat=True)) == {seeded, invited.username}
assert User.objects.filter(pk=invited.pk).exists()
assert verify() == [], verify()
assert User.objects.get(username=reference_user).email == "existing-ui@example.test"
print("Expected personal email/name/password/passkey record and UI memberships to survive repeat apply: preserved")

user.is_active = False
user.save(update_fields=["is_active"])
observation = preflight()
assert observation["failures"] == [] and any(seeded in value for value in observation["inactive"]), observation
diagnose(observation)
apply()
user.refresh_from_db()
assert user.is_active is False, "Apply reactivated a UI-suspended account"
assert user.check_password("disposable-personal-password")
assert WebAuthnDevice.objects.filter(pk=credential.pk, user=user).exists()
user.is_active = True
user.save(update_fields=["is_active"])
print("Expected UI suspension to remain effective after apply without destroying credentials: verified")

target = Group.objects.get(name=managed)
target.users.remove(user)
target.users.add(invited)
diffs = verify()
assert any("missing members" in diff and seeded in diff and invited.username in diff for diff in diffs), diffs
apply()
assert verify() == [], verify()
print("Expected both missing and extra managed members to be detected, then exact membership restored: verified")

apply(f"""version: 1
metadata:
  name: fixture-ui-reference
entries:
  - model: authentik_core.group
    identifiers:
      name: {managed}
    attrs:
      users:
        - !Find [authentik_core.user, [username, {invited.username}]]
""")
invited.refresh_from_db()
assert set(target.users.values_list("username", flat=True)) == {invited.username}
assert (invited.name, invited.email) == ("UI user", "ui@example.test")
apply()
assert verify() == [], verify()
print("Expected an existing UI-created identity to resolve without reseeding its profile: verified")

change_group(managed, {"users": []})
assert not target.users.exists()
assert verify(), "Expected emptying a managed group to fail the original declaration"
apply()
assert verify() == [], verify()
assert set(group.users.values_list("username", flat=True)) == {seeded, invited.username}
print("Expected explicit empty membership to remove only that group's memberships: verified")

target.delete()
assert any("declared membership has no group" in diff for diff in verify()), verify()
apply()
assert verify() == [], verify()
print("Expected a missing managed group to fail verification, then be recreated: verified")

Group.objects.create(name="retired-fixture")
change_group("retired-fixture", state="absent")
assert not Group.objects.filter(name="retired-fixture").exists()
print("Expected explicit group tombstone to remove the group: verified")
snapshot_path.write_text(json.dumps(personal_state(), default=str))
