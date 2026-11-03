# A policy fragment or skill whose identity collides is silently resolved by the consumer's
# precedence instead of failing, and a skill that is added or removed must appear in the rendered
# paths without a manifest edit. The fixture feeds duplicate identities, namespaced same-name
# fragments and a changed skill tree through the discovery the module uses.
{
  pkgs,
  lib,
  ...
}:

let
  resources = import ../features/ai/resources/lib { inherit lib; };
  fixtures = ./fixtures/ai-resources;

  policies = resources.discoverPolicies (fixtures + "/policies");
  policyIds = map (policy: policy.id) policies;

  skills = resources.discoverSkills (fixtures + "/skills");
  skillIds = map (skill: skill.id) skills;

  removed = resources.discoverSkills (fixtures + "/skills-removed");
  added = resources.discoverSkills (fixtures + "/skills-added");

  rendered = resources.render {
    namespaces = [
      "common"
      "opencode"
    ];
    inherit policies;
    skillsRoot = fixtures + "/skills";
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
    "delegation"
    "review"
  ];
assert map (skill: skill.id) removed == [ "review" ];
assert
  map (skill: skill.id) added == [
    "review"
    "triage"
  ];
assert
  rendered.instructions == [
    "${toString fixtures}/policies/common/00-scope.md"
    "${toString fixtures}/policies/common/10-delegation.md"
    "${toString fixtures}/policies/opencode/00-scope.md"
  ];
assert rendered.skills == [ "${toString fixtures}/skills" ];
assert !duplicatePolicy.success;
assert !duplicateSkill.success;
pkgs.runCommandLocal "ai-resources-check" { } ''
  echo "ok: policy and skill resources have stable, namespaced, duplicate-free IDs" > "$out"
''
