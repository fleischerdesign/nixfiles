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
        numbers = map (
          part:
          if builtins.stringLength part > 3 || builtins.match "[0-9]+" part == null then
            null
          else
            lib.toInt part
        ) parts;
      in
      if builtins.elem null numbers || !lib.all (n: n >= 0 && n <= 255) numbers then null else numbers;

  intOf = octets: builtins.foldl' (acc: n: acc * 256 + n) 0 octets;

  validV6 =
    address:
    let
      addressParts = lib.splitString ":" address;
      hasIpv4Tail = lib.hasInfix "." address;
      ipv4Tail =
        if hasIpv4Tail then builtins.elemAt addressParts (builtins.length addressParts - 1) else null;
      expandedAddress = if hasIpv4Tail then (lib.removeSuffix ipv4Tail address) + "0:0" else address;
      halves = lib.splitString "::" expandedAddress;
      usesCompression = lib.hasInfix "::" expandedAddress;
      compressed = usesCompression && builtins.length halves == 2;
      groups =
        if compressed then
          (if builtins.head halves == "" then [ ] else lib.splitString ":" (builtins.head halves))
          ++ (if builtins.elemAt halves 1 == "" then [ ] else lib.splitString ":" (builtins.elemAt halves 1))
        else
          lib.splitString ":" expandedAddress;
      validGroup = part: builtins.stringLength part <= 4 && builtins.match "[0-9a-fA-F]+" part != null;
    in
    address != ""
    && (!hasIpv4Tail || octetsOf ipv4Tail != null)
    && (!usesCompression || builtins.length halves == 2)
    && lib.all validGroup groups
    && (if compressed then builtins.length groups < 8 else builtins.length groups == 8);
in
rec {
  # Dotted quad with four octets in range, nothing more. CIDR suffixes are rejected here;
  # use prefixLength for those.
  validV4 = ip: octetsOf ip != null;
  inherit validV6;

  # The number after the slash, validated against address syntax: 0-32 for IPv4 and 0-128 for
  # IPv6 (including an IPv4-mapped tail). Null means malformed, for either family.
  prefixLength =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      address = if builtins.length parts == 2 then builtins.head parts else "";
      suffix = if builtins.length parts == 2 then builtins.elemAt parts 1 else "";
      length =
        if builtins.stringLength suffix > 3 || builtins.match "[0-9]+" suffix == null then
          -1
        else
          lib.toInt suffix;
    in
    if lib.hasInfix ":" address then
      if validV6 address && length >= 0 && length <= 128 then length else null
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
    if
      length == null || octets == null || lib.hasInfix ":" (builtins.head (lib.splitString "/" cidr))
    then
      false
    else
      let
        shift = lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - length));
        net = intOf (octetsOf (builtins.head (lib.splitString "/" cidr)));
      in
      (intOf octets) / shift == net / shift;

  canonicalV6 =
    address:
    if !validV6 address then
      null
    else
      let
        addressParts = lib.splitString ":" address;
        hasIpv4Tail = lib.hasInfix "." address;
        ipv4Tail =
          if hasIpv4Tail then builtins.elemAt addressParts (builtins.length addressParts - 1) else null;
        octets = if hasIpv4Tail then octetsOf ipv4Tail else [ ];
        hexDigits = lib.stringToCharacters "0123456789abcdef";
        hexByte =
          value:
          "${builtins.elemAt hexDigits (builtins.div value 16)}${builtins.elemAt hexDigits (lib.mod value 16)}";
        ipv4Groups =
          if !hasIpv4Tail then
            [ ]
          else
            [
              "${hexByte (builtins.elemAt octets 0)}${hexByte (builtins.elemAt octets 1)}"
              "${hexByte (builtins.elemAt octets 2)}${hexByte (builtins.elemAt octets 3)}"
            ];
        expandedAddress =
          if hasIpv4Tail then
            (lib.removeSuffix ipv4Tail address) + lib.concatStringsSep ":" ipv4Groups
          else
            address;
        halves = lib.splitString "::" expandedAddress;
        compressed = lib.hasInfix "::" expandedAddress;
        groups =
          if compressed then
            let
              left = if builtins.head halves == "" then [ ] else lib.splitString ":" (builtins.head halves);
              right =
                if builtins.elemAt halves 1 == "" then [ ] else lib.splitString ":" (builtins.elemAt halves 1);
            in
            left ++ lib.replicate (8 - builtins.length left - builtins.length right) "0" ++ right
          else
            lib.splitString ":" expandedAddress;
      in
      lib.concatStringsSep ":" (map (group: lib.fixedWidthString 4 "0" (lib.toLower group)) groups);

  overlapsV4 =
    left: right:
    let
      leftParts = lib.splitString "/" left;
      rightParts = lib.splitString "/" right;
      leftPrefix = prefixLength left;
      rightPrefix = prefixLength right;
      sharedPrefix =
        if leftPrefix == null || rightPrefix == null then null else lib.min leftPrefix rightPrefix;
      leftAddress = if builtins.length leftParts == 2 then octetsOf (builtins.head leftParts) else null;
      rightAddress =
        if builtins.length rightParts == 2 then octetsOf (builtins.head rightParts) else null;
    in
    if leftAddress == null || rightAddress == null || sharedPrefix == null || sharedPrefix == 0 then
      leftAddress != null && rightAddress != null && sharedPrefix == 0
    else
      let
        shift = lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - sharedPrefix));
      in
      intOf leftAddress / shift == intOf rightAddress / shift;

  ipv6Bits =
    address:
    let
      canonical = canonicalV6 address;
      hexValue =
        char:
        {
          "0" = 0;
          "1" = 1;
          "2" = 2;
          "3" = 3;
          "4" = 4;
          "5" = 5;
          "6" = 6;
          "7" = 7;
          "8" = 8;
          "9" = 9;
          a = 10;
          b = 11;
          c = 12;
          d = 13;
          e = 14;
          f = 15;
        }
        .${char};
      bitsFor =
        char:
        builtins.genList (
          index:
          let
            value = builtins.div (hexValue char) (builtins.elemAt [ 8 4 2 1 ] index);
            remainder = value - (builtins.div value 2) * 2;
          in
          if remainder == 1 then "1" else "0"
        ) 4;
    in
    if canonical == null then
      null
    else
      lib.concatStrings (
        lib.concatMap bitsFor (lib.stringToCharacters (builtins.replaceStrings [ ":" ] [ "" ] canonical))
      );

  containsV6 =
    cidr: address:
    let
      prefix = prefixLength cidr;
      networkAddress = builtins.head (lib.splitString "/" cidr);
      networkBits = ipv6Bits networkAddress;
      addressBits = ipv6Bits address;
    in
    prefix != null
    && lib.hasInfix ":" networkAddress
    && networkBits != null
    && addressBits != null
    && lib.substring 0 prefix networkBits == lib.substring 0 prefix addressBits;

  overlapsV6 =
    left: right:
    let
      leftParts = lib.splitString "/" left;
      rightParts = lib.splitString "/" right;
      leftPrefix = prefixLength left;
      rightPrefix = prefixLength right;
      sharedPrefix =
        if leftPrefix == null || rightPrefix == null then null else lib.min leftPrefix rightPrefix;
      leftAddress = if builtins.length leftParts == 2 then ipv6Bits (builtins.head leftParts) else null;
      rightAddress =
        if builtins.length rightParts == 2 then ipv6Bits (builtins.head rightParts) else null;
    in
    if leftAddress == null || rightAddress == null || sharedPrefix == null then
      false
    else
      lib.substring 0 sharedPrefix leftAddress == lib.substring 0 sharedPrefix rightAddress;

  overlaps =
    left: right:
    let
      leftAddress = builtins.head (lib.splitString "/" left);
      rightAddress = builtins.head (lib.splitString "/" right);
      leftV6 = lib.hasInfix ":" leftAddress;
      rightV6 = lib.hasInfix ":" rightAddress;
    in
    if leftV6 != rightV6 then
      false
    else if leftV6 then
      overlapsV6 left right
    else
      overlapsV4 left right;
}
