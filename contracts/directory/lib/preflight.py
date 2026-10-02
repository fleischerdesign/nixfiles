"""Read-only directory planning; provider adapters supply observations, not policy."""


def directory_preflight(directory, lookup_users, lookup_groups):
    """Separate invalid references, pending creation and UI-owned suspension.

    Lookups return zero, one, or at least two observations for ambiguity. User observations contain ``human``
    and ``active`` booleans; group observations only need to establish cardinality.
    No callback creates, updates or deletes objects.
    """
    result = {"failures": [], "pending": [], "inactive": []}
    for username, declaration in sorted(directory["users"].items()):
        matches = list(lookup_users(username))
        if len(matches) > 1:
            result["failures"].append(f"user {username}: ambiguous login (at least {len(matches)} matches)")
        elif not matches:
            category = "pending" if declaration["initialProfile"] is not None else "failures"
            reason = "seed will create an account" if category == "pending" else "referenced UI account does not exist"
            result[category].append(f"user {username}: {reason}")
        elif not matches[0]["human"]:
            result["failures"].append(f"user {username}: login belongs to a service account, not a human")
        elif not matches[0]["active"]:
            result["inactive"].append(f"user {username}: account is suspended; apply must not reactivate it")

    for name, declaration in sorted(directory["groups"].items()):
        matches = list(lookup_groups(name))
        if len(matches) > 1:
            result["failures"].append(f"group {name}: ambiguous name (at least {len(matches)} matches)")
        elif not matches and declaration["state"] == "present":
            result["pending"].append(f"group {name}: definition will create a group")
    return result
