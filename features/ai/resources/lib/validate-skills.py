#!/usr/bin/env python3
"""Validate an AgentSkills tree and copy it unchanged to its output path.

The frontmatter is parsed with PyYAML rather than a hand-written subset: standard YAML and
vendor-specific metadata keys are accepted, and only the fields the portable AgentSkills format
defines are checked. Unknown keys are preserved and never inspected.

Usage: validate-skills.py <source-tree> <output-tree>
"""

import os
import re
import shutil
import sys

import yaml

NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
NAME_MAX = 64
DESCRIPTION_MAX = 1024
SKIP_DIRS = {"node_modules"}
MAX_DEPTH = 6


def is_regular(entry):
    return entry.is_file(follow_symlinks=False)


def validate_skill(root, skill_path, leaf, errors):
    rel = os.path.relpath(skill_path, root)
    try:
        with open(skill_path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, UnicodeError) as error:
        errors.append(f"{rel}: cannot read SKILL.md: {error}")
        return

    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        errors.append(f"{rel}: SKILL.md must start with a `---` frontmatter block")
        return

    try:
        closing = next(index for index in range(1, len(lines)) if lines[index].strip() == "---")
    except StopIteration:
        errors.append(f"{rel}: frontmatter is not closed by `---`")
        return

    try:
        metadata = yaml.safe_load("\n".join(lines[1:closing]))
    except yaml.YAMLError as error:
        errors.append(f"{rel}: frontmatter is not valid YAML: {error}")
        return

    if not isinstance(metadata, dict):
        errors.append(f"{rel}: frontmatter must be a YAML mapping")
        return

    name = metadata.get("name")
    if not isinstance(name, str) or not name:
        errors.append(f"{rel}: frontmatter `name` is required and must be a string")
    else:
        if len(name) > NAME_MAX:
            errors.append(f"{rel}: frontmatter `name` must be at most {NAME_MAX} characters")
        if not NAME_PATTERN.fullmatch(name):
            errors.append(
                f"{rel}: frontmatter `name` must be lower-case kebab-case "
                f"(lowercase letters, digits and single hyphens)"
            )
        if name != leaf:
            errors.append(
                f"{rel}: frontmatter `name` '{name}' must equal the directory ID '{leaf}'"
            )

    description = metadata.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append(f"{rel}: frontmatter `description` is required and must not be empty")
    elif len(description) > DESCRIPTION_MAX:
        errors.append(
            f"{rel}: frontmatter `description` must be at most {DESCRIPTION_MAX} characters"
        )


def walk_skills(root, directory, depth, errors):
    try:
        entries = sorted(os.scandir(directory), key=lambda entry: entry.name)
    except OSError as error:
        errors.append(f"cannot read {directory}: {error}")
        return

    skill_entry = next((entry for entry in entries if entry.name == "SKILL.md"), None)
    if depth == 0 and skill_entry is not None and is_regular(skill_entry):
        errors.append(
            f"{os.path.relpath(root, root)}: the skill root must not contain SKILL.md; "
            "put it in a child directory whose name is the skill ID"
        )
        return
    if depth > MAX_DEPTH:
        errors.append(
            f"{os.path.relpath(directory, root)}: skill is deeper than {MAX_DEPTH} directories"
        )
        return
    if skill_entry is not None and is_regular(skill_entry):
        leaf = os.path.basename(directory)
        validate_skill(root, skill_entry.path, leaf, errors)
        return

    for entry in entries:
        if entry.name.startswith(".") or entry.name in SKIP_DIRS:
            continue
        if entry.is_dir(follow_symlinks=False):
            walk_skills(root, entry.path, depth + 1, errors)


def main():
    if len(sys.argv) != 3:
        print("usage: validate-skills.py <source-tree> <output-tree>", file=sys.stderr)
        return 2

    source, output = sys.argv[1:3]
    if not os.path.isdir(source):
        print(f"ai-resources: source tree {source} is not a directory", file=sys.stderr)
        return 1

    # The output is the tree the consumer receives, so validate the copied artifact rather than a
    # separate reading of the source.
    try:
        shutil.copytree(source, output, symlinks=True, dirs_exist_ok=True)
    except OSError as error:
        print(f"ai-resources: cannot copy skill tree: {error}", file=sys.stderr)
        return 1

    errors = []
    walk_skills(output, output, 0, errors)
    if errors:
        for error in errors:
            print(f"ai-resources: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
