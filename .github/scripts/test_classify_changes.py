import unittest

from classify_changes import classify


class ClassifyChangesTests(unittest.TestCase):
    def test_file_selects_its_checks(self):
        cases = {
            "docs/model.md": {"instructions"},
            "MarfaMac/Model/AGENTS.md": {"instructions"},
            "MarfaMac/Localizable.xcstrings": set(),
            "MarfaMac/Assets.xcassets/AppIcon.appiconset/Contents.json": set(),
            "MarfaMacUITests/WindowTests.swift": {"instructions"},
            "MarfaMac/Views/Sidebar.swift": {"instructions"},
            "TestPlans/Unit.xctestplan": set(),
            "MarfaMac.xcodeproj/project.pbxproj": {"instructions"},
            "editor/src/page.ts": {"editor", "instructions"},
            "editor/bridge-messages.json": {"editor"},
            ".github/workflows/checks.yml": {"classifier", "editor", "instructions", "scripts", "workflows"},
            ".github/workflows/release.yml": {"workflows"},
            ".github/scripts/classify_changes.py": {"classifier", "editor", "instructions", "scripts", "workflows"},
            ".github/scripts/test_classify_changes.py": {"classifier", "editor", "instructions", "scripts", "workflows"},
            ".github/scripts/run-unit-tests.sh": set(),
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(classify([path]), expected)

    def test_unmatched_paths_select_all_regular_checks(self):
        expected = {"classifier", "editor", "instructions", "scripts", "workflows"}
        for path in ("Scripts/foo.sh", "new-folder/Source.swift"):
            with self.subTest(path=path):
                self.assertEqual(classify(["docs/model.md", path]), expected)

    def test_checks_from_multiple_paths_are_combined(self):
        self.assertEqual(
            classify(["editor/src/page.ts", "MarfaMac/Localizable.xcstrings"]),
            {"editor", "instructions"},
        )
