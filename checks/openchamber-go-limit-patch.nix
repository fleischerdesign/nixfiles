# The Go limit-failover patch must add `provider.go-limit` to exactly the two upstream boundaries and
# must fail closed when the pinned sources move or upstream already fixes one or both. The positive
# case against the real package is decided by the openchamber-core installPhase in the host build;
# this fixture proves the script's behaviour on two tiny files, not on a 103 MB source copy.
#
# Named failure: a future 2.6.x/2.7 source silently keeps an obsolete or half-applied patch, or the
# insertion lands in a moved LIMIT_ERROR_TYPES set without review.
{
  pkgs,
  ...
}:
let
  fixture = pkgs.runCommandLocal "openchamber-go-limit-fixture" { } ''
    mkdir -p $out/packages/web/server/lib/limit-failover
    cat > $out/package.json <<'EOF'
    {"name":"fixture","version":"2.6.0","type":"module"}
    EOF
    cat > $out/packages/web/server/lib/limit-failover/policy.js <<'EOF'
    export const classify = (error) => {
      const LIMIT_ERROR_TYPES = new Set([
      'provider.quota',
      'provider.free-limit',
      'provider.budget-limit',
      'provider.model-budget-limit',
      'provider.rate-limit',
    ]);
      return LIMIT_ERROR_TYPES.has(error.type);
    };
    EOF
    cat > $out/packages/web/server/lib/limit-failover/runtime.js <<'EOF'
    const PLUGIN_SOURCE = `const LIMIT_ERROR_TYPES = new Set(["provider.quota", "provider.free-limit", "provider.budget-limit", "provider.model-budget-limit", "provider.rate-limit"])
    export default { id: "fixture" };
    `;
    export const source = PLUGIN_SOURCE;
    EOF
  '';

  patch = ../packages/overlays/fix/openchamber/patch-go-limit.mjs;

  policy = "packages/web/server/lib/limit-failover/policy.js";
  runtime = "packages/web/server/lib/limit-failover/runtime.js";

  expect = ''
    # expect <description> <needle> <wanted-count> <file>
    expect() {
      got=$( { grep -o "$2" "$4" || true; } | wc -l )
      if [ "$got" -ne "$3" ]; then
        echo "$1: expected $3 occurrences of $2 in $4, found $got" >&2
        exit 1
      fi
    }
  '';
in
pkgs.runCommandLocal "openchamber-go-limit-patch-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    set -euo pipefail
    ${expect}

    # Positive: the pinned shape gains the type at both boundaries, once each.
    cp -r ${fixture} applied
    chmod -R u+w applied
    (
      cd applied
      node ${patch}
      expect "policy" "provider.go-limit" 1 ${policy}
      expect "runtime" "provider.go-limit" 1 ${runtime}
      node --check ${policy}
      node --check ${runtime}
      if ! grep -q "provider.model-budget-limit'," ${policy}; then
        echo "policy: the neighbouring model-budget entry was dropped" >&2
        exit 1
      fi
    )

    # Re-running the applied tree is the "upstream already fixed both" case: it must stop the build
    # and name the patch files to remove.
    status=0
    node ${patch} applied 2>already.err || status=$?
    if [ "$status" -ne 78 ]; then
      echo "already-fixed: expected exit 78, got $status" >&2
      exit 1
    fi
    if ! grep -q "already lists provider.go-limit" already.err || ! grep -q "remove patch-go-limit.mjs" already.err; then
      echo "already-fixed: the failure does not name the obsolete patch" >&2
      cat already.err >&2
      exit 1
    fi

    # Partial upstream fix: one boundary handles it, the other does not.
    cp -r ${fixture} partial
    chmod -R u+w partial
    sed -i "s/'provider.model-budget-limit',/'provider.model-budget-limit',\n  'provider.go-limit',/" partial/${policy}
    status=0
    node ${patch} partial 2>partial.err || status=$?
    if [ "$status" -ne 65 ]; then
      echo "partial: expected exit 65, got $status" >&2
      exit 1
    fi
    if ! grep -q "partial upstream fix" partial.err; then
      echo "partial: the failure does not name the partial fix" >&2
      cat partial.err >&2
      exit 1
    fi

    # Drifted set: neither boundary has the type, and the anchor no longer matches.
    cp -r ${fixture} drifted
    chmod -R u+w drifted
    sed -i "s/provider.model-budget-limit/provider.model-budget-limit-v2/" drifted/${policy}
    status=0
    node ${patch} drifted 2>drifted.err || status=$?
    if [ "$status" -ne 65 ]; then
      echo "drifted: expected exit 65, got $status" >&2
      exit 1
    fi
    if ! grep -q "source drift" drifted.err; then
      echo "drifted: the failure does not name the source drift" >&2
      cat drifted.err >&2
      exit 1
    fi

    # Version drift alone is refused even with a recognisable anchor.
    cp -r ${fixture} revised
    chmod -R u+w revised
    sed -i 's/"version":"2.6.0"/"version":"2.6.1"/' revised/package.json
    status=0
    node ${patch} revised 2>revised.err || status=$?
    if [ "$status" -ne 65 ]; then
      echo "version: expected exit 65, got $status" >&2
      exit 1
    fi
    if ! grep -q "differs from the pinned 2.6.0" revised.err; then
      echo "version: the failure does not name the version drift" >&2
      cat revised.err >&2
      exit 1
    fi

    # No tree may be left half-patched.
    expect "partial-untouched" "provider.go-limit" 1 partial/${policy}
    expect "drifted-untouched" "provider.go-limit" 0 drifted/${policy}
    expect "drifted-untouched" "provider.go-limit" 0 drifted/${runtime}

    touch $out
  ''
