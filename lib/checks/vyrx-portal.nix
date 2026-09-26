# lib/checks/vyrx-portal.nix
# The portal reads its fleet at runtime, so the projection is a file next to the artifact and not a
# build input. The claim is about files again: the entry point, the prerendered public pages and the
# two projections, measured on the artifact the portal host actually runs.
#
# The projection names services, not hosts, and no person anywhere. This check says so explicitly, so
# the old public catalogue cannot come back unnoticed. A host that was skipped and a host that passed
# must not read the same, so the exit code is derived from the checks rather than from the last
# statement.
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

  # The public pages a visitor gets without a session. `/` and `/en` are server-rendered - they read
  # the identity headers - so they are not files; project and help are prerendered for both languages.
  prerenderedPages = [
    "project/index.html"
    "help/index.html"
    "en/project/index.html"
    "en/help/index.html"
  ];

  inspect =
    name:
    let
      portal = self.nixosConfigurations.${name}.config.my.features.services.vyrx-landing;
    in
    ''
      # ${name}
      pkg=${portal.package}
      projection=${portal.projection}
      adapters=${portal.adapters}

      if ! test -f "$pkg/server/entry.mjs"; then
        echo "vyrx portal ${name}: the artifact has no server/entry.mjs" >&2
        fail=1
      fi

      for page in ${lib.concatStringsSep " " prerenderedPages}; do
        if ! test -f "$pkg/client/$page"; then
          echo "vyrx portal ${name}: no prerendered page client/$page" >&2
          fail=1
        fi
      done

      # The public catalogue is gone; a stray copy would be a leak that nobody noticed.
      if [ -n "$(find -L "$pkg" -name portal.json -print -quit)" ]; then
        echo "vyrx portal ${name}: the artifact still carries a portal.json" >&2
        fail=1
      fi

      # The artifact carries exactly the projections the host declares.
      if ! cmp -s "$pkg/fleet.json" "$projection"; then
        echo "vyrx portal ${name}: the artifact's fleet.json is not the declared projection" >&2
        fail=1
      fi
      if ! cmp -s "$pkg/adapters.json" "$adapters"; then
        echo "vyrx portal ${name}: the artifact's adapters.json is not the declared adapter file" >&2
        fail=1
      fi

      if ! jq -e . "$projection" >/dev/null 2>&1; then
        echo "vyrx portal ${name}: the projection does not parse as JSON" >&2
        fail=1
      else
        if ! jq -e '.schema == 1' "$projection" >/dev/null 2>&1; then
          echo "vyrx portal ${name}: the projection does not declare schema 1" >&2
          fail=1
        fi
        if ! jq -e 'all(.services[].id; test("^[a-z0-9][a-z0-9-]*$"))' "$projection" >/dev/null 2>&1; then
          echo "vyrx portal ${name}: the projection names a service that is not a lowercase slug" >&2
          fail=1
        fi
        if ! jq -e '([.categories[].id] | unique) as $cats | [.services[].categoryId | . as $id | ($cats | index($id)) != null] | all' "$projection" >/dev/null 2>&1; then
          echo "vyrx portal ${name}: the projection names a category that is not declared" >&2
          fail=1
        fi
        forbidden=$(jq '[.. | objects | keys[] | select(. == "owners" or . == "users" or . == "members" or . == "hosts")] | length' "$projection")
        if [ "$forbidden" -ne 0 ]; then
          echo "vyrx portal ${name}: the projection names people or topology ($forbidden forbidden field(s))" >&2
          fail=1
        fi
        services=$(jq '.services | length' "$projection")
        if [ "$services" -eq 0 ]; then
          echo "vyrx portal ${name}: the projection names no service, so no service claim is proved" >&2
          fail=1
        fi
      fi

      if ! jq -e . "$adapters" >/dev/null 2>&1; then
        echo "vyrx portal ${name}: the adapter file does not parse as JSON" >&2
        fail=1
      else
        if ! jq -e '.schema == 1' "$adapters" >/dev/null 2>&1; then
          echo "vyrx portal ${name}: the adapter file does not declare schema 1" >&2
          fail=1
        fi
        if ! jq -e --slurpfile project "$projection" '
              ([$project[0].services[].id] | unique) as $known
              | [.services | keys[] | . as $id | ($known | index($id)) != null] | all
            ' "$adapters" >/dev/null 2>&1; then
          echo "vyrx portal ${name}: the adapter file names a service the projection does not" >&2
          fail=1
        fi
      fi

      echo "  ${name}: entry point, ${toString (builtins.length prerenderedPages)} prerendered page(s), projection and adapters measured"
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
    echo "ok: $checked portal artifact(s) ship the entry point, the prerendered public pages and both runtime projections, and no projection names a person" > $out
  ''
