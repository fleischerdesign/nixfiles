#!/usr/bin/env python3
"""Prove the VYRX authentik blueprints before they reach a host.

The apply on the server proves the same files, but a deploy is too late: the failures this check looks
for are the silent ones - a model name without a dot, a `!KeyOf` that points nowhere, a dependency on a
blueprint that is not in the directory, and a person who is declared instead of seeded. It reads the
exact directory the server ships, so it proves the same bytes the apply will consume.

Two rule sets are enforced, and neither is trusted to whoever writes the next file.

authentik's blueprint semantics (docs/practices.md §6.7-§6.9):

  - a model name is an ``app.model`` string; without the dot the importer raises;
  - ``!KeyOf`` resolves only within one file, ``!Find`` looks the object up in the database, and a
    cross-file dependency must be declared with ``authentik_blueprints.metaapplyblueprint``;
  - a tombstone (``state: absent``) needs identifiers, or it deletes nothing.

this repository's ownership model (docs/identity.md §11):

  - the shape of the system is declared and enforced - ``state: present`` or ``absent``;
  - the people are seeded exactly once and owned by the interface afterwards - ``state: created``.
    The two are mutually exclusive per entry, so a seed cannot be forgotten and a topology object
    cannot silently stop being enforced.

Success prints one line and exits 0; every violation is printed to stderr and the process exits 1, so
the check fails loudly instead of passing on a warning nobody reads.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

MODEL_META_APPLY = "authentik_blueprints.metaapplyblueprint"
MODEL_USER = "authentik_core.user"
USER_TYPE_FIELD = "type"
SERVICE_ACCOUNT_TYPE = "service_account"

DECLARED_STATES = {"present", "absent", "must_created"}
SEEDED_STATE = "created"
KNOWN_STATES = DECLARED_STATES | {SEEDED_STATE}

KNOWN_TAGS = {"Find", "KeyOf", "Env", "File", "Context"}


class Tag:
    """A YAML tag such as ``!Find`` or ``!KeyOf``, kept together with its resolved value."""

    __slots__ = ("name", "value")

    def __init__(self, name, value):
        self.name = name
        self.value = value

    def __repr__(self):
        return f"!{self.name} {self.value!r}"


class BlueprintLoader(yaml.SafeLoader):
    """SafeLoader that keeps unknown ``!`` tags instead of failing on them."""


def _construct_tag(loader, suffix, node):
    if isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node, deep=True)
    elif isinstance(node, yaml.MappingNode):
        value = loader.construct_mapping(node, deep=True)
    else:
        value = loader.construct_scalar(node)
    return Tag(suffix, value)


BlueprintLoader.add_multi_constructor("!", _construct_tag)


def walk(value):
    """Yield every :class:`Tag` inside a parsed structure, depth first."""
    if isinstance(value, Tag):
        yield value
        yield from walk(value.value)
    elif isinstance(value, dict):
        for inner in value.values():
            yield from walk(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from walk(inner)


def parse(path):
    try:
        return yaml.load(path.read_text(encoding="utf-8"), Loader=BlueprintLoader) or {}
    except yaml.YAMLError as exc:
        return {"__parse_error__": str(exc)}


def valid_model(value):
    return isinstance(value, str) and "." in value and not value.startswith(".")


def is_person(model, attrs):
    return model == MODEL_USER and attrs.get(USER_TYPE_FIELD) != SERVICE_ACCOUNT_TYPE


def check_owned(rel, raw, names, directory, problems):
    if "__parse_error__" in raw:
        problems.append(f"{rel}: not valid YAML: {raw['__parse_error__']}")
        return
    if raw.get("version") != 1:
        problems.append(f"{rel}: version is {raw.get('version')!r}, expected 1")

    metadata = raw.get("metadata") or {}
    name = metadata.get("name")
    if not isinstance(name, str) or not name:
        problems.append(f"{rel}: metadata.name is missing")
    if not isinstance(metadata.get("labels"), dict):
        problems.append(f"{rel}: metadata.labels is missing")

    entries = raw.get("entries")
    if not isinstance(entries, list) or not entries:
        problems.append(f"{rel}: entries is empty")
        return

    ids = {}
    for index, entry in enumerate(entries):
        where = f"{rel}[{index}]"
        if not isinstance(entry, dict):
            problems.append(f"{where}: entry is not a mapping")
            continue
        model = entry.get("model")
        if not valid_model(model):
            problems.append(f"{where}: model {model!r} is not an 'app.model' string")
            continue
        state = entry.get("state")
        if state is not None and state not in KNOWN_STATES:
            problems.append(f"{where}: state {state!r} is not one of {sorted(KNOWN_STATES)}")
        identifiers = entry.get("identifiers")
        identifiers = identifiers if isinstance(identifiers, dict) else {}
        attrs = entry.get("attrs")
        attrs = attrs if isinstance(attrs, dict) else {}
        if state == "absent" and not identifiers:
            problems.append(f"{where}: a tombstone needs identifiers")

        entry_id = entry.get("id")
        if entry_id is not None:
            if entry_id in ids:
                problems.append(f"{where}: duplicate id {entry_id!r}")
            ids[entry_id] = model

        check_references(where, entry, problems)
        check_ownership(where, model, state, attrs, problems)
        if model == MODEL_META_APPLY:
            check_meta_apply(where, attrs, names, directory, problems)

    check_key_of(rel, entries, ids, problems)


def check_references(where, entry, problems):
    for tag in walk({"identifiers": entry.get("identifiers"), "attrs": entry.get("attrs")}):
        if tag.name == "Find":
            value = tag.value
            if not isinstance(value, list) or len(value) != 2 or not valid_model(value[0]):
                problems.append(f"{where}: !Find {value!r} is not [app.model, [field, value]]")
        elif tag.name not in KNOWN_TAGS:
            problems.append(f"{where}: unknown YAML tag !{tag.name}")


def check_key_of(rel, entries, ids, problems):
    """Every ``!KeyOf`` must name an ``id`` declared in the same file; a cross-file one is skipped silently."""
    for index, entry in enumerate(entries):
        for tag in walk(entry):
            if tag.name == "KeyOf" and tag.value not in ids:
                problems.append(
                    f"{rel}[{index}]: !KeyOf {tag.value!r} names no id in this file "
                    f"(ids: {sorted(ids)})"
                )


def check_ownership(where, model, state, attrs, problems):
    """A person is seeded; everything else is declared. The two never mix (docs/identity.md §11)."""
    if is_person(model, attrs):
        if state != SEEDED_STATE:
            problems.append(
                f"{where}: a person must be seeded (state: {SEEDED_STATE}), found {state!r}"
            )
        if "groups" in attrs:
            problems.append(
                f"{where}: a person must not declare group membership - membership is the access "
                "decision and belongs to the interface"
            )
    elif state == SEEDED_STATE:
        problems.append(
            f"{where}: {model} is not a person and must not be seeded - a seed is never enforced, "
            "so topology declared with state: created would silently stay stale"
        )


def check_meta_apply(where, attrs, names, directory, problems):
    identifiers = attrs.get("identifiers")
    identifiers = identifiers if isinstance(identifiers, dict) else {}
    path = identifiers.get("path")
    name = identifiers.get("name")
    if path is None and name is None:
        problems.append(f"{where}: metaapply names neither a path nor an instance")
    if path is not None:
        if not isinstance(path, str) or not path.endswith(".yaml"):
            problems.append(f"{where}: metaapply path {path!r} is not a .yaml path")
        elif not (directory / path).is_file():
            problems.append(f"{where}: metaapply path {path!r} names no file in the directory")
    if name is not None and name not in names:
        problems.append(f"{where}: metaapply instance {name!r} names no blueprint in the directory")


def looks_owned(path, owner_name):
    """Whether a file claims ownership without a successful parse, so a syntax error is still caught."""
    try:
        return owner_name in path.read_text(encoding="utf-8")
    except OSError:
        return False


def check_cycles(owned, names, problems):
    """Cross-file dependencies are declared, so a cycle between two owned files can never settle."""
    edges = {rel: set() for rel in owned}
    for rel, raw in owned.items():
        for entry in raw.get("entries") or []:
            if not isinstance(entry, dict) or entry.get("model") != MODEL_META_APPLY:
                continue
            identifiers = (entry.get("attrs") or {}).get("identifiers")
            identifiers = identifiers if isinstance(identifiers, dict) else {}
            path = identifiers.get("path")
            if isinstance(path, str) and path in owned:
                edges[rel].add(path)
            name = identifiers.get("name")
            if name in names and names[name] in owned:
                edges[rel].add(names[name])

    visited = set()
    stack = []

    def visit(node):
        if node in stack:
            cycle = " -> ".join(stack[stack.index(node):] + [node])
            problems.append(f"metaapply dependency cycle: {cycle}")
            return
        if node in visited:
            return
        stack.append(node)
        for neighbour in sorted(edges[node]):
            visit(neighbour)
        stack.pop()
        visited.add(node)

    for node in sorted(edges):
        visit(node)


def check_directory(directory, owner_name, owner_value):
    root = Path(directory)
    problems = []
    owned = {}
    names = {}
    for path in sorted(root.rglob("*.yaml")):
        rel = str(path.relative_to(root))
        raw = parse(path)
        if not isinstance(raw, dict):
            continue
        if "__parse_error__" in raw:
            # Without a parse there is no label to read, so ownership is decided from the raw text.
            # Upstream files do not name the owner; our own do, and a broken one must still fail here
            # rather than at the blueprint migration on the host.
            if looks_owned(path, owner_name):
                problems.append(f"{rel}: not valid YAML: {raw['__parse_error__']}")
            continue
        metadata = raw.get("metadata") or {}
        labels = metadata.get("labels") or {}
        name = metadata.get("name")
        if isinstance(name, str) and name:
            if name in names and names[name] != rel:
                problems.append(f"{rel}: blueprint name {name!r} is also used by {names[name]}")
            names.setdefault(name, rel)
        if labels.get(owner_name) == owner_value:
            owned[rel] = raw

    if not owned:
        problems.append(f"{directory}: no blueprint carries {owner_name}={owner_value!r}")

    for rel, raw in owned.items():
        check_owned(rel, raw, names, root, problems)
    check_cycles(owned, names, problems)
    return owned, problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+", type=Path)
    parser.add_argument(
        "--owner-label",
        required=True,
        help="the ownership marker as NAME=VALUE; only labelled blueprints are checked",
    )
    args = parser.parse_args(argv)

    try:
        owner_name, owner_value = args.owner_label.split("=", 1)
    except ValueError:
        parser.error("--owner-label must be NAME=VALUE")

    problems = []
    total = 0
    for directory in args.directories:
        if not directory.is_dir():
            problems.append(f"{directory}: not a directory")
            continue
        owned, found = check_directory(directory, owner_name, owner_value)
        total += len(owned)
        problems.extend(f"{directory}: {problem}" for problem in found)

    if problems:
        for problem in problems:
            print(f"FAILED {problem}", file=sys.stderr)
        print(f"failed: {len(problems)} violation(s)", file=sys.stderr)
        return 1

    print(f"ok: {total} owned blueprint(s) parsed, referenced and owned correctly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
