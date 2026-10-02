"""Exact membership verification for repository-owned groups, independent of ORM details."""


def group_membership_diffs(declarations, lookup_members, resolve_username):
    """Omitted membership is not owned; an explicit empty membership is owned."""
    diffs = []
    seen = set()
    for name, references in declarations:
        if name in seen:
            diffs.append(f"group {name}: multiple membership declarations")
            continue
        seen.add(name)
        expected = set()
        for reference in references:
            username = resolve_username(reference)
            if username is None:
                diffs.append(f"group {name}: unresolved member {reference!r}")
            elif username in expected:
                diffs.append(f"group {name}: duplicate member {username}")
            else:
                expected.add(username)
        actual = lookup_members(name)
        if actual is None:
            diffs.append(f"group {name}: declared membership has no group")
            continue
        actual = set(actual)
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        if missing or extra:
            diffs.append(f"group {name}: missing members {missing}, extra members {extra}")
    return diffs
