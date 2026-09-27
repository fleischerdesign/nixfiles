# features/system/networking/lib/nftables-render.nix - how this fleet spells an nftables rule.
#
# Network-owned and backend-specific by name: it renders text, it does not decide policy. The
# declarations the rules are built from (endpoints, devices, trust levels) are read by the adapters in
# `features/system/networking`, never here.
#
# Nothing here is a command: these functions build *matches*, and the adapters hand them to
# `networking.firewall.extraInputRules` / `extraForwardRules`, which is where they belong.
{ lib }:
rec {
  # Several addresses go into an nftables set; a single one is spelled bare, because `{ 10.0.0.1 }` is a
  # set of one and reads like a list that was truncated.
  addressSet =
    addresses:
    if lib.length addresses == 1 then
      builtins.head addresses
    else
      "{ ${lib.concatStringsSep ", " addresses} }";

  portSet =
    ports:
    if lib.length ports == 1 then
      toString (builtins.head ports)
    else
      "{ ${lib.concatStringsSep ", " (map toString ports)} }";

  # Composable parts, in the order nftables reads them: match, then verdict.
  rule = parts: lib.concatStringsSep " " (lib.filter (part: part != "") parts);
}
