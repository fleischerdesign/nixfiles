# Resource discovery for the AI runtime resources.
#
# The two inputs are directories, not manifests:
#   policies/<namespace>/<name>.md  -> one instruction fragment with the ID `<namespace>/<name>`
#   skills/<name>/SKILL.md          -> one native skill with the ID `<name>`
#
# A consumer binds the rendered paths. This file decides which files are resources, keeps their
# order stable, refuses two resources that would resolve to the same ID, and builds the validated
# skill tree. It deliberately does not know any runtime's config shape; the module that binds a
# runtime selects the namespaces it needs.
{ lib, pkgs }:

let
  policyExtensions = [
    ".md"
    ".markdown"
  ];

  isRegular = type: type == "regular";
  isDirectory = type: type == "directory";
  isHidden = name: lib.hasPrefix "." name;
  isSkippedDirectory = name: isHidden name || name == "node_modules";

  # A portable ID segment: the numeric prefixes used for policy order are allowed, a leading digit is
  # not a special case. Discovery is the cheap path guard; the skill tree is validated against the
  # stricter AgentSkills rule when it is built.
  validSegment = segment: builtins.match "[a-z0-9][a-z0-9-]*" segment != null;

  duplicateIds =
    entries:
    let
      ids = map (entry: entry.id) entries;
      unique = lib.unique ids;
    in
    lib.filter (id: builtins.length (lib.filter (candidate: candidate == id) ids) > 1) unique;

  sortById = entries: lib.sort (a: b: a.id < b.id) entries;

  # Every regular Markdown file below a policy namespace. The relative path is kept so a fragment may
  # be grouped (`common/delegation/00-intent.md`) without losing its identity.
  policyFiles =
    root:
    let
      walk =
        relative: directory:
        let
          entries = builtins.readDir directory;
        in
        lib.concatMap (
          name:
          let
            type = entries.${name};
            path = directory + "/${name}";
          in
          if isDirectory type && !(isSkippedDirectory name) then
            walk (relative ++ [ name ]) path
          else if isRegular type && !(isHidden name) then
            let
              extension = lib.findFirst (candidate: lib.hasSuffix candidate name) null policyExtensions;
            in
            if extension == null then
              [ ]
            else
              [
                {
                  inherit path;
                  parts = relative ++ [ name ];
                  extension = extension;
                }
              ]
          else
            [ ]
        ) (builtins.attrNames entries);
    in
    walk [ ] root;

  policyId =
    namespace: file:
    let
      filename = lib.last file.parts;
      stem = lib.removeSuffix file.extension filename;
      segments = lib.init file.parts ++ [ stem ];
      invalid = lib.filter (segment: !(validSegment segment)) segments;
    in
    if invalid != [ ] then
      throw "ai-resources: policy '${toString file.path}' has non-portable path segments: ${lib.concatStringsSep ", " invalid}"
    else
      "${namespace}/${lib.concatStringsSep "/" segments}";

  # A directory containing SKILL.md is one skill and is not searched further, matching OpenCode's
  # native discovery. A skill is always a directory: the leaf directory name is the ID, so a
  # root-level `<name>.md` is not a skill. Supporting files stay in the tree; they are not resources
  # of their own.
  skillFiles =
    root:
    let
      walk =
        depth: directory:
        let
          entries = builtins.readDir directory;
          hasSkill = entries ? "SKILL.md" && isRegular entries."SKILL.md";
        in
        if depth == 0 && hasSkill then
          throw "ai-resources: ${toString root} is not a skill root; put SKILL.md in a child directory"
        else if depth > 6 then
          throw "ai-resources: skill below ${toString directory} is deeper than six directories"
        else if hasSkill then
          [
            {
              id = baseNameOf (toString directory);
              path = directory + "/SKILL.md";
              root = directory;
            }
          ]
        else
          lib.concatMap (
            name:
            let
              type = entries.${name};
              path = directory + "/${name}";
            in
            if isDirectory type && !(isSkippedDirectory name) then walk (depth + 1) path else [ ]
          ) (builtins.attrNames entries);
    in
    walk 0 root;

  validateSkills =
    skills:
    let
      invalid = lib.filter (skill: !(validSegment skill.id)) skills;
      duplicates = duplicateIds skills;
    in
    if invalid != [ ] then
      throw "ai-resources: skill IDs must match [a-z0-9][a-z0-9-]*: ${
        lib.concatStringsSep ", " (map (skill: skill.id) invalid)
      }"
    else if duplicates != [ ] then
      throw "ai-resources: duplicate skill IDs: ${lib.concatStringsSep ", " duplicates}"
    else
      skills;

  # PyYAML parses the frontmatter and the produced tree is validated as a whole. A hand-written
  # subset would reject standard YAML and vendor metadata; the maintained parser keeps the check
  # aligned with the AgentSkills format instead.
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  validator = pkgs.writeText "ai-resources-validate-skills.py" (
    builtins.readFile ./validate-skills.py
  );
in
{
  inherit python validator;

  # `policies` is sorted by ID and therefore stable across readDir order and machines. The ID keeps
  # the namespace, so `common/00-scope` and `opencode/00-scope` are distinct resources rather than a
  # collision to be forbidden.
  discoverPolicies =
    root:
    let
      namespaces = lib.filter (
        name: isDirectory (builtins.readDir root).${name} && !(isSkippedDirectory name)
      ) (builtins.attrNames (builtins.readDir root));
      policies = lib.concatMap (
        namespace:
        let
          invalid = if validSegment namespace then [ ] else [ namespace ];
        in
        if invalid != [ ] then
          throw "ai-resources: invalid policy namespace '${namespace}'"
        else
          map (file: {
            id = policyId namespace file;
            inherit (file) path;
            inherit namespace;
          }) (policyFiles (root + "/${namespace}"))
      ) (lib.sort (a: b: a < b) namespaces);
      duplicates = duplicateIds policies;
    in
    if duplicates != [ ] then
      throw "ai-resources: duplicate policy IDs: ${lib.concatStringsSep ", " duplicates}"
    else
      sortById policies;

  discoverSkills =
    root:
    if !(builtins.pathExists root) then
      throw "ai-resources: skills directory ${toString root} does not exist"
    else
      validateSkills (sortById (skillFiles root));

  # Copy the whole source tree to a content-addressed output and validate that produced tree. The
  # module renders this path, so an invalid skill fails the build of the consumer that receives it;
  # validation cannot be skipped while the unvalidated source path is still delivered.
  validateSkillsTree =
    {
      root,
      name ? "ai-resources-skills",
    }:
    pkgs.runCommandLocal name { } ''
      ${python}/bin/python ${validator} ${root} $out
    '';

  # Select the fragments one runtime consumes. `common` is the neutral policy every consumer gets;
  # an adapter adds its own namespace (for OpenCode, `opencode`).
  render =
    {
      namespaces,
      policies,
      skillsRoot,
    }:
    {
      instructions = map (policy: toString policy.path) (
        lib.filter (policy: builtins.elem policy.namespace namespaces) policies
      );
      skills = [ (toString skillsRoot) ];
    };
}
