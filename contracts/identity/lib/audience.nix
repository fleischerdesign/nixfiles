# Naming and recognition of personal audience groups, owned by the identity contract.
let
  # A hand-written group may not use this reserved prefix: the compiler declares these groups.
  audienceGroupPrefix = "svc-";
in
{
  inherit audienceGroupPrefix;
  audienceGroup = username: "${audienceGroupPrefix}${username}";
  isAudienceGroup =
    name: builtins.substring 0 (builtins.stringLength audienceGroupPrefix) name == audienceGroupPrefix;
}
