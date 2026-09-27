# Fleet configurations for contract consumers, owned by the composition root.
#
# Every consumer that projects across hosts needs the same thing: all hosts' evaluated
# configurations, each carrying `.config` like flake.nixosConfigurations. That mapping lives
# here once, instead of once per consumer. Standalone evaluation (no flake) is explicitly
# unsupported: a fallback that silently projects one host - or nothing - is exactly the
# failure this helper exists to make impossible, so absence fails loudly with a domain
# message instead of a null dereference.
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
}
