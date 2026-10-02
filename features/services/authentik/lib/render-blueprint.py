"""Render structured blueprint data as YAML while preserving native Authentik tags."""

import json
import sys

import yaml


class BlueprintDumper(yaml.SafeDumper):
    pass


def represent_mapping(dumper, value):
    if set(value) == {"__authentikTag", "value"}:
        tag = value["__authentikTag"]
        if tag not in {"Find", "KeyOf", "Env", "File", "Context"}:
            raise ValueError(f"Invalid native blueprint reference: {value!r}")
        node = dumper.represent_data(value["value"])
        node.tag = f"!{tag}"
        return node
    return dumper.represent_dict(value)


BlueprintDumper.add_representer(dict, represent_mapping)

if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as source:
        blueprint = json.load(source)
    print("# yaml-language-server: $schema=https://goauthentik.io/blueprints/schema.json")
    yaml.dump(blueprint, sys.stdout, Dumper=BlueprintDumper, sort_keys=False, allow_unicode=True)
