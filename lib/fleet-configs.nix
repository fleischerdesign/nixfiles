# Fleet configurations for contract consumers, owned by the composition root.
#
# Every consumer that projects across hosts needs the same thing: all hosts' evaluated
# configurations, each carrying `.config` like flake.nixosConfigurations. That mapping lives
# here once, instead of once per consumer. Standalone evaluation (no flake) is explicitly
# unsupported: a fallback that silently projects one host - or nothing - is exactly the
# failure this helper exists to make impossible, so absence fails loudly with a domain
# message instead of a null dereference.
{ lib }:
{
  systems =
    config:
    let
      flake = config._module.specialArgs.flake or null;
    in
    if flake == null then
      throw "fleet configs: standalone evaluation is unsupported; build through the flake (lib/mk-system.nix injects flake = self)"
    else
      flake.nixosConfigurations
        or (throw "fleet configs: the flake provides no nixosConfigurations to project from");

  providesOf = hostConfig: hostConfig.config.my.contracts.provides or { };

  # The single host matching a provider predicate. Placement is a fact, not a search: zero
  # candidates means nothing provides the role, several means the fleet never decided which one
  # does - both fail loudly naming the role instead of picking loopback or list order.
  uniqueHost =
    {
      systems,
      matches,
      role,
    }:
    let
      candidates = lib.attrNames (lib.filterAttrs (_: hostCfg: matches hostCfg.config) systems);
    in
    if candidates == [ ] then
      throw "fleet configs: no host provides ${role}"
    else if builtins.length candidates > 1 then
      throw "fleet configs: ambiguous ${role}: ${lib.concatStringsSep ", " candidates}; assign exactly one provider"
    else
      builtins.head candidates;
}
