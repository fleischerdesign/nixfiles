# Every rule this repository generates is an nftables match. The full parser cannot run here - it
# wants netlink, which a build sandbox does not have - so this is the part that can be proven at
# build time, and it is the part that would have caught the incident: a rule that names a command,
# or carries a shell flag, is not a rule. What remains is syntax, and that is safe to defer, because
# the firewall applies the whole ruleset in one nftables transaction: a malformed rule fails loudly
# and leaves the previous ruleset in place instead of half-applying a new one.
{
  pkgs,
  lib,
  self,
  hostNames,
  ...
}:
let
  rulesOf = name: self.nixosConfigurations.${name}.config;
  generated = lib.concatMapStringsSep "\n" (
    name:
    (rulesOf name).networking.firewall.extraInputRules
    + "\n"
    + (rulesOf name).networking.firewall.extraForwardRules
  ) hostNames;
in
pkgs.runCommandLocal "nftables-rules" { } ''
  cat > rules.txt <<'GENERATED'
  ${generated}
  GENERATED
  fail=0
  forbid() { if grep -qE -- "$1" rules.txt; then echo "violation: $2" >&2; fail=1; fi; }
  forbid '(^|[[:space:]])(iptables|ip6tables|nft)([[:space:]]|$)' "a rule names a command instead of a match"
  forbid '/bin/' "a rule contains a store path"
  forbid '(^|[[:space:]])-(A|I|D|F|X|N)([[:space:]]|$)' "a rule contains a shell flag"
  forbid -- '--comment' "a rule contains an iptables-only flag"
  forbid '(^|[[:space:]])-s[[:space:]]' "a rule uses -s instead of ip saddr"
  while read -r line; do
    [ -n "$line" ] || continue
    stripped=$(printf '%s' "$line" | sed 's/ comment .*$//')
    case "$stripped" in
      *accept|*drop|*reject|*return|*jump*) ;;
      *) echo "violation: rule without a verdict: $line" >&2; fail=1 ;;
    esac
  done < rules.txt
  [ "$fail" -eq 0 ] || exit 1
  echo 'ok: every generated rule is an nftables match with a verdict' > $out
''
