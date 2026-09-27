# IPv4 CIDR arithmetic in pure Nix, plus family-neutral prefix extraction. Integers are
# 64-bit signed, so an IPv4 address fits exactly and every operation below is exact - no
# floats, no bit builtins, no external tool. Containment math is IPv4-only: 128-bit
# arithmetic does not fit, and the only IPv6 facts in the inventory (overlay addresses) are
# matched exactly, never by containment. Prefix lengths are extracted for both families.
{ lib }:
let
  octetsOf =
    ip:
    let
      parts = lib.splitString "." ip;
    in
    if builtins.length parts != 4 then
      null
    else
      let
        numbers = map (part: if builtins.match "[0-9]+" part == null then null else lib.toInt part) parts;
      in
      if builtins.elem null numbers || !lib.all (n: n >= 0 && n <= 255) numbers then null else numbers;

  intOf = octets: builtins.foldl' (acc: n: acc * 256 + n) 0 octets;
in
rec {
  # Dotted quad with four octets in range, nothing more. CIDR suffixes are rejected here;
  # use prefixLength for those.
  validV4 = ip: octetsOf ip != null;

  # The number after the slash, validated against the address family: 0-32 with a valid IPv4
  # address, 0-128 with a plausible IPv6 one. Null means malformed, for either family.
  prefixLength =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      address = if builtins.length parts == 2 then builtins.head parts else "";
      suffix = if builtins.length parts == 2 then builtins.elemAt parts 1 else "";
      length = if builtins.match "[0-9]+" suffix == null then -1 else lib.toInt suffix;
    in
    if lib.hasInfix ":" address then
      if builtins.match "[0-9a-fA-F:]+" address != null && length >= 0 && length <= 128 then
        length
      else
        null
    else if octetsOf address != null && length >= 0 && length <= 32 then
      length
    else
      null;

  # Containment of an address in a CIDR block, by prefix arithmetic: two addresses share the
  # first `length` bits exactly when their integers agree after shifting the host bits out.
  containsV4 =
    cidr: ip:
    let
      length = prefixLength cidr;
      octets = octetsOf ip;
    in
    if length == null || octets == null then
      false
    else
      let
        shift = lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - length));
        net = intOf (octetsOf (builtins.head (lib.splitString "/" cidr)));
      in
      (intOf octets) / shift == net / shift;
}
