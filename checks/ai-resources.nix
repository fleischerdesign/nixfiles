# A policy fragment or skill whose identity collides is silently resolved by the consumer's
# precedence instead of failing; a skill whose frontmatter is invalid or disagrees with its
# directory ID would be loaded under one name and addressed under another; and a skill that is
# added or removed must appear in the rendered paths without a manifest edit. The fixture feeds
# duplicate identities, namespaced same-name fragments, invalid frontmatter and a changed skill
# tree through the discovery and the validator the module uses.
{
  pkgs,
  lib,
  ...
}:

let
  resources = import ../features/ai/resources/lib { inherit lib pkgs; };
  fixtures = ./fixtures/ai-resources;

  policies = resources.discoverPolicies (fixtures + "/policies");
  policyIds = map (policy: policy.id) policies;

  skills = resources.discoverSkills (fixtures + "/skills");
  skillIds = map (skill: skill.id) skills;

  removed = resources.discoverSkills (fixtures + "/skills-removed");
  added = resources.discoverSkills (fixtures + "/skills-added");

  # Discovery is path-derived and does not read metadata, so an invalid skill is still listed here;
  # the build validation below is the layer that rejects it instead of silently dropping it.
  mismatched = resources.discoverSkills (fixtures + "/skill-name-mismatch");

  # The rendered consumer path is the validated copy, not the source tree, so the check proves the
  # build dependency exists as well as the frontmatter rules.
  validated = resources.validateSkillsTree { root = fixtures + "/skills"; };

  rendered = resources.render {
    namespaces = [
      "common"
      "opencode"
    ];
    inherit policies;
    skillsRoot = validated;
  };

  duplicatePolicy = builtins.tryEval (
    builtins.deepSeq (resources.discoverPolicies (fixtures + "/policy-collision")) true
  );
  duplicateSkill = builtins.tryEval (
    builtins.deepSeq (resources.discoverSkills (fixtures + "/skill-collision")) true
  );
in
assert
  policyIds == [
    "common/00-scope"
    "common/10-delegation"
    "opencode/00-scope"
    "other/00-scope"
  ];
assert
  skillIds == [
    "nf-delegation"
    "nf-review"
  ];
assert map (skill: skill.id) removed == [ "nf-review" ];
assert
  map (skill: skill.id) added == [
    "nf-review"
    "triage"
  ];
assert map (skill: skill.id) mismatched == [ "foo" ];
assert
  rendered.instructions == [
    "${toString fixtures}/policies/common/00-scope.md"
    "${toString fixtures}/policies/common/10-delegation.md"
    "${toString fixtures}/policies/opencode/00-scope.md"
  ];
assert rendered.skills == [ (toString validated) ];
assert !duplicatePolicy.success;
assert !duplicateSkill.success;
pkgs.runCommandLocal "ai-resources-check" { } ''
  set -eu

  # Validation copies the whole tree; supporting files are not dropped with the metadata check.
  test -f ${validated}/nf-delegation/SKILL.md
  test -f ${validated}/nf-delegation/references/example.md
  test -f ${validated}/nf-review/SKILL.md
  test "$(find ${validated} -name SKILL.md | wc -l)" -eq 2

  tmp=$(mktemp -d)

  # A name that disagrees with the leaf directory is rejected at build time, with the reason.
  if ${resources.python}/bin/python ${resources.validator} ${fixtures}/skill-name-mismatch "$tmp/mismatch" 2> "$tmp/mismatch.err"; then
    echo "validator accepted a frontmatter name that disagrees with its directory" >&2
    exit 1
  fi
  grep -q "must equal the directory ID 'foo'" "$tmp/mismatch.err"

  # Discovery accepts the segment pattern, but AgentSkills does not accept a double hyphen.
  if ${resources.python}/bin/python ${resources.validator} ${fixtures}/skill-name-invalid "$tmp/name" 2> "$tmp/name.err"; then
    echo "validator accepted a non-portable AgentSkills name" >&2
    exit 1
  fi
  grep -q "lower-case kebab-case" "$tmp/name.err"

  if ${resources.python}/bin/python ${resources.validator} ${fixtures}/skill-missing-description "$tmp/description" 2> "$tmp/description.err"; then
    echo "validator accepted a skill without a description" >&2
    exit 1
  fi
  grep -q "description.*required" "$tmp/description.err"

  if ${resources.python}/bin/python ${resources.validator} ${fixtures}/skill-missing-name "$tmp/name-field" 2> "$tmp/name-field.err"; then
    echo "validator accepted a skill without a name" >&2
    exit 1
  fi
  grep -q "name.*required" "$tmp/name-field.err"

  echo "ok: policy and skill resources have stable IDs and a validated native skill tree" > "$out"
''
