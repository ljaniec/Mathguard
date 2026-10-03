"""Regression tests for source provenance and lexical boundary handling."""
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import audit_sources
from lean_source import definitions, proof_scan, statements, tokens


class ExtractorTests(unittest.TestCase):
    def test_attributes_modifiers_comments_and_term_bodies(self):
        a = "theorem check {n : Nat} (x : Nat := 1) : x = x := by rfl"
        b = "@[simp] public theorem check (x : Nat := 1) : x /- nested /- x -/ -/ = x := Eq.refl x"
        self.assertEqual(statements(a), statements(b))

    def test_literal_whitespace_and_comment_markers_are_preserved(self):
        a = 'def message : String := "a /- -- b"\ndef number := 1'
        b = 'public def message : String := "a /- -- b"\ndef number := 1'
        self.assertEqual(definitions(a), definitions(b))
        self.assertNotEqual(definitions(a), definitions(a.replace('a /-', 'a  /-')))

    def test_comments_do_not_merge_identifiers(self):
        self.assertEqual([t.value for t in tokens("Nat/- comment -/Nat")], ["Nat", "Nat"])

    def test_next_declaration_attributes_do_not_change_previous_definition(self):
        a = "def a := 1\ndef b := 2"
        b = "def a := 1\n@[simp]\npublic def b := 2"
        self.assertEqual(definitions(a), definitions(b))

    def test_proof_scan_literals_and_interpolation(self):
        self.assertNotIn("sorry", proof_scan('def text := "sorry /- --"'))
        self.assertIn("sorry", proof_scan('def text := s!"{(by sorry : String)}"'))
        self.assertIn("sorry", proof_scan('theorem t : True := by sorry'))

    def test_raw_strings_quoted_names_and_characters(self):
        source = 'def «example name» := r#"/- -- sorry"#\ndef char := \'"\''
        self.assertIn("«example name»", definitions(source))
        self.assertNotIn("sorry", proof_scan(source))

    def test_malformed_and_duplicate_declarations_fail(self):
        for text in ['/- never closed', 'def s := "never closed']:
            with self.assertRaises(ValueError): tokens(text)
        with self.assertRaises(ValueError):
            statements('theorem a : True := by trivial\ntheorem a : True := by trivial')


class AuditMutationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for folder in ("Mathguard", "aristotle", "docs/verification"):
            shutil.copytree(audit_sources.ROOT / folder, self.root / folder)
        for name in ("Mathguard.lean", "Main.lean", "Bench.lean", "Tests.lean"):
            shutil.copyfile(audit_sources.ROOT / name, self.root / name)
        self.root_patch = patch.object(audit_sources, "ROOT", self.root)
        self.root_patch.start()
        self.report = self.root / "docs/verification/axioms.txt"

    def tearDown(self):
        self.root_patch.stop()
        self.tmp.cleanup()

    def rewrite(self, path, before, after):
        file = self.root / path
        content = file.read_text()
        self.assertIn(before, content)
        file.write_text(content.replace(before, after, 1))

    def test_baseline(self):
        self.assertEqual(audit_sources.audit(self.report)["total"], 55)

    def test_guard_change_rejected(self):
        self.rewrite("Mathguard/Spec.lean", "q.amount ≤ s.balances q.source ∧", "True ∧")
        with self.assertRaisesRegex(ValueError, "Model definition changes"):
            audit_sources.audit(self.report)

    def test_signature_change_rejected(self):
        self.rewrite("Mathguard/Ledger.lean",
                     "q.expectedRevision = s.revision ∧ q.policyEpoch = p.epoch",
                     "True ∧ q.policyEpoch = p.epoch")
        with self.assertRaisesRegex(ValueError, "Changed or missing target"):
            audit_sources.audit(self.report)

    def test_production_hole_rejected(self):
        file = self.root / "Mathguard/Runtime.lean"
        file.write_text(file.read_text() + "\ntheorem injected : True := by sorry\n")
        with self.assertRaisesRegex(ValueError, "Forbidden proof"):
            audit_sources.audit(self.report)

    def test_nested_production_hole_rejected(self):
        folder = self.root / "Mathguard/Adapters"
        folder.mkdir()
        (folder / "Example.lean").write_text("theorem injected : True := by sorry\n")
        with self.assertRaisesRegex(ValueError, "Forbidden proof"):
            audit_sources.audit(self.report)

    def test_missing_and_unapproved_axiom_records_rejected(self):
        original = self.report.read_text()
        self.report.write_text("\n".join(original.splitlines()[1:]))
        with self.assertRaisesRegex(ValueError, "Missing axiom records"):
            audit_sources.audit(self.report)
        self.report.write_text(original.replace("propext", "sorryAx", 1))
        with self.assertRaisesRegex(ValueError, "Unapproved axioms"):
            audit_sources.audit(self.report)

    def test_fresh_gate_requires_refinement_records(self):
        # The supplied baseline report cannot establish new refinement evidence.
        original = self.report.read_text()
        baseline = "\n".join(line for line in original.splitlines()
                             if not any(f"Mathguard.{n}'" in line for n in audit_sources.EXTRA_TARGETS))
        self.report.write_text(baseline)
        with self.assertRaisesRegex(ValueError, "Missing axiom records"):
            audit_sources.audit(self.report, require_extra=True)


if __name__ == "__main__":
    unittest.main()
