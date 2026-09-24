# lib/checks/vyrx-portal.nix
# The portal is built, not fetched, and its catalogue is a build input: one page per service is a
# prerendered file, so a build handed no catalogue renders the honest "no catalogue" state and produces no
# service page at all - which is exactly what shipped once, with nothing failing.
#
# The claim is about files, so this check reads files. The artifact the portal host runs must serve the
# catalogue it was rendered from, byte for byte, and carry a page for every service that catalogue names,
# in every services tree the build produced. Which trees exist is the portal's business; that each of them
# is complete is the part this refuses to take on trust.
#
# A host that was skipped and a host that passed must not read the same, so the exit code is derived from
# the checks rather than from the last statement.
{
  pkgs,
  lib,
  self,
  hostNames,
}:
let
  portalHosts = lib.filter (
    name: self.nixosConfigurations.${name}.config.my.features.services.vyrx-landing.enable
  ) hostNames;

  inspect =
    name:
    let
      portal = self.nixosConfigurations.${name}.config.my.features.services.vyrx-landing;
    in
    ''
      # ${name}
      pkg=${portal.package}
      catalogue=${portal.catalogue}

      if ! test -f "$pkg/client/portal.json"; then
        echo "vyrx portal ${name}: the artifact serves no client/portal.json" >&2
        fail=1
      elif ! cmp -s "$pkg/client/portal.json" "$catalogue"; then
        echo "vyrx portal ${name}: the served catalogue is not the one the build was given" >&2
        fail=1
      fi

      services=$(jq -r '.services[].id' "$catalogue" 2>/dev/null || true)
      wanted=$(printf '%s\n' "$services" | grep -c . || true)
      if [ "$wanted" -eq 0 ]; then
        echo "vyrx portal ${name}: the catalogue names no service, so no page is proved" >&2
        fail=1
      fi

      trees=$(cd "$pkg/client" && ls -d services */services 2>/dev/null || true)
      if [ -z "$trees" ]; then
        echo "vyrx portal ${name}: the artifact has no services tree" >&2
        fail=1
      fi
      for tree in $trees; do
        for id in $services; do
          if ! test -f "$pkg/client/$tree/$id/index.html"; then
            echo "vyrx portal ${name}: no page for service '$id' in client/$tree" >&2
            fail=1
          fi
        done
      done
      echo "  ${name}: $wanted service(s), $(printf '%s\n' $trees | grep -c . || true) services tree(s)"
      checked=$((checked + 1))
    '';
in
pkgs.runCommandLocal "vyrx-portal"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    fail=0
    checked=0
    ${lib.concatMapStringsSep "\n" inspect portalHosts}

    if [ "$checked" -eq 0 ]; then
      echo "vyrx portal: no host in this flake runs the portal, so nothing was measured" >&2
      exit 1
    fi
    if [ "$fail" -ne 0 ]; then
      echo "vyrx portal: $checked portal artifact(s) inspected, at least one claim is false" >&2
      exit 1
    fi
    echo "ok: $checked portal artifact(s) carry the catalogue they were built from and a page for every service it names" > $out
  ''
