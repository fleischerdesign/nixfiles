"""Negative and positive measurements of the verifier shared by apply and drift."""

import importlib.util
import json
import sys
import unittest
import yaml

spec = importlib.util.spec_from_file_location("membership", sys.argv.pop(1))
membership = importlib.util.module_from_spec(spec)
spec.loader.exec_module(membership)
renderer_spec = importlib.util.spec_from_file_location("renderer", sys.argv.pop(1))
renderer = importlib.util.module_from_spec(renderer_spec)
renderer_spec.loader.exec_module(renderer)
with open(sys.argv.pop(1), encoding="utf-8") as source:
    reference_examples = json.load(source)
preflight_spec = importlib.util.spec_from_file_location("preflight", sys.argv.pop(1))
preflight = importlib.util.module_from_spec(preflight_spec)
preflight_spec.loader.exec_module(preflight)


class PreflightTests(unittest.TestCase):
    def measure(self, users=None, groups=None, observed_users=None, observed_groups=None):
        return preflight.directory_preflight(
            {"users": users or {}, "groups": groups or {}},
            lambda name: (observed_users or {}).get(name, []),
            lambda name: (observed_groups or {}).get(name, []),
        )

    def test_missing_reference_fails_but_missing_seed_is_pending(self):
        result = self.measure(users={"reference": {"initialProfile": None},
                                     "seed": {"initialProfile": {}}})
        self.assertEqual(len(result["failures"]), 1)
        self.assertIn("reference", result["failures"][0])
        self.assertEqual(len(result["pending"]), 1)
        self.assertIn("seed", result["pending"][0])

    def test_account_collision_and_ambiguous_identity_fail(self):
        for observed in [[{"human": False, "active": True}],
                         [{"human": True, "active": True}] * 2]:
            self.assertTrue(self.measure(users={"person": {"initialProfile": {}}},
                                         observed_users={"person": observed})["failures"])

    def test_suspension_is_observed_not_a_deployment_error(self):
        result = self.measure(users={"person": {"initialProfile": {}}},
                              observed_users={"person": [{"human": True, "active": False}]})
        self.assertEqual(result["failures"], [])
        self.assertEqual(len(result["inactive"]), 1)

    def test_group_cardinality_and_tombstone(self):
        self.assertTrue(self.measure(groups={"role": {"state": "present"}},
                                     observed_groups={"role": [1, 2]})["failures"])
        self.assertTrue(self.measure(groups={"role": {"state": "present"}})["pending"])
        self.assertEqual(self.measure(groups={"role": {"state": "absent"}}),
                         {"failures": [], "pending": [], "inactive": []})

    def test_lookup_errors_are_not_reported_as_success(self):
        def unavailable(_):
            raise RuntimeError("backend unavailable")
        with self.assertRaises(RuntimeError):
            preflight.directory_preflight({"users": {"person": {"initialProfile": None}},
                                           "groups": {}}, unavailable, lambda _: [])


class RenderingTests(unittest.TestCase):
    def test_reference_values_remain_typed_and_literals_are_not_references(self):
        document = yaml.dump(reference_examples, Dumper=renderer.BlueprintDumper)
        nodes = {key.value: value for key, value in yaml.compose(document).value}
        for key, expected in [("numeric", "123"), ("boolean", "true"),
                              ("punctuation", 'comma, quote" bracket]')]:
            self.assertEqual(nodes[key].tag, "!Find")
            value = nodes[key].value[1].value[1]
            self.assertEqual(value.tag, "tag:yaml.org,2002:str")
            self.assertEqual(value.value, expected)
        self.assertEqual(nodes["literal"].tag, "tag:yaml.org,2002:str")
        self.assertEqual(nodes["file"].tag, "!File")
        self.assertEqual(nodes["file"].value, "/fixture/path with spaces")

    def test_unknown_reference_tags_fail(self):
        with self.assertRaises(ValueError):
            yaml.dump({"__authentikTag": "unknown", "value": "x"}, Dumper=renderer.BlueprintDumper)


class MembershipTests(unittest.TestCase):
    def measure(self, declarations, groups):
        return membership.group_membership_diffs(
            declarations, groups.get, lambda name: name if name in {"owner", "other"} else None
        )

    def test_exact_membership_and_unowned_groups(self):
        self.assertEqual(self.measure([("managed", ["owner"])], {
            "managed": ["owner"], "ordinary": ["other"]
        }), [])

    def test_missing_and_extra_members_are_both_reported(self):
        diffs = self.measure([("managed", ["owner"])], {"managed": ["other"]})
        self.assertIn("missing members ['owner'], extra members ['other']", diffs[0])

    def test_explicit_empty_group_is_enforced(self):
        self.assertEqual(self.measure([("empty", [])], {"empty": []}), [])
        self.assertTrue(self.measure([("empty", [])], {"empty": ["owner"]}))

    def test_missing_group_and_user_fail(self):
        self.assertTrue(self.measure([("missing", [])], {}))
        self.assertTrue(self.measure([("managed", ["missing"])], {"managed": []}))

    def test_duplicate_ownership_and_members_fail(self):
        self.assertTrue(self.measure([("managed", []), ("managed", [])], {"managed": []}))
        self.assertTrue(self.measure([("managed", ["owner", "owner"])], {"managed": ["owner"]}))


if __name__ == "__main__":
    unittest.main()
