import unittest

from classify_changes import classify


class ClassifyChangesTests(unittest.TestCase):
    def test_file_selects_its_checks(self):
        cases = {
            "docs/glossary.md": {"instructions"},
            "MarfaMac/Model/AGENTS.md": {"instructions"},
            "MarfaMac/Localizable.xcstrings": {"swift"},
            "MarfaMac/Assets.xcassets/AppIcon.appiconset/Contents.json": {"swift"},
            "MarfaMacUITests/WindowTests.swift": {"instructions", "swift", "uitests"},
            "MarfaMac/Views/Sidebar.swift": {"instructions", "swift", "logic"},
            "TestPlans/Unit.xctestplan": {"swift", "logic", "uitests"},
            "MarfaMac.xcodeproj/project.pbxproj": {"instructions", "swift", "logic", "uitests"},
            "editor/src/page.ts": {"editor", "instructions"},
            ".github/workflows/checks.yml": {
                "classifier", "editor", "instructions", "logic", "scripts", "swift", "uitests", "workflows",
            },
            ".github/workflows/release.yml": {"workflows"},
            ".github/scripts/classify_changes.py": {
                "classifier", "editor", "instructions", "logic", "scripts", "swift", "uitests", "workflows",
            },
            ".github/scripts/test_classify_changes.py": {
                "classifier", "editor", "instructions", "logic", "scripts", "swift", "uitests", "workflows",
            },
            ".github/scripts/run-unit-tests.sh": {"swift", "logic"},
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(classify([path]), expected)

    def test_unmatched_paths_select_all_regular_checks(self):
        expected = {"classifier", "editor", "instructions", "logic", "scripts", "swift", "workflows"}
        for path in ("Scripts/foo.sh", "new-folder/Source.swift"):
            with self.subTest(path=path):
                self.assertEqual(classify(["docs/glossary.md", path]), expected)

    def test_checks_from_multiple_paths_are_combined(self):
        self.assertEqual(
            classify(["editor/src/page.ts", "MarfaMac/Localizable.xcstrings"]),
            {"editor", "instructions", "swift"},
        )
