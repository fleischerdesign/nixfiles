# One rule for the name of an endpoint across the fleet.
#
# The same string is the blueprint's application slug, the Prometheus `service` label and the portal
# tile id. Three consumers that must agree on it are three reasons to state it once: a rename that
# changed one of them would leave the others pointing at a series or an object that no longer exists -
# silently, because each of them still evaluates.
_:
let
  # Reserved for the audiences this repository derives itself. A hand-written audience may not use it,
  # so the two origins of a group name cannot collide and the compiler knows by the name alone whether
  # it is the author - which is what lets it declare the group instead of looking it up.
  audienceGroupPrefix = "svc-";
in
{
  endpointName =
    svcName: epName: if epName == "default" || epName == "web" then svcName else "${svcName}-${epName}";

  # The audience of an endpoint that has no role to share: its own. Derived from the endpoint's name,
  # so a personal resource names no person - the repository declares the group and the interface
  # decides who is in it, exactly as it does for a role group. `endpointName` derives the identity, this
  # derives the audience of that identity; both are stated once because both are consumed more than once
  # (the ingress binding, the portal tile).
  inherit audienceGroupPrefix;
  audienceGroup = endpointName: "${audienceGroupPrefix}${endpointName}";
  isAudienceGroup =
    name: builtins.substring 0 (builtins.stringLength audienceGroupPrefix) name == audienceGroupPrefix;
}
