"""Select Checks jobs from NUL-delimited paths from git diff --name-only -z."""

import os
import re
import sys


PATH_RULES = {
    "editor": r"^(editor/|MarfaMac/Editor/Page/|\.github/workflows/checks\.yml\Z)",
    "scripts": r"^(Scripts/release/|\.github/workflows/checks\.yml\Z)",
    "classifier": r"^\.github/(scripts/(test_)?classify_changes\.py|workflows/checks\.yml)\Z",
    "workflows": r"^\.github/(workflows/|actionlint\.ya?ml\Z)",
    "instructions": r"^(editor/src/|Scripts/check-instructions\.py\Z|\.github/workflows/checks\.yml\Z)",
}

ALL_CHECKS = set(PATH_RULES)

# The app's own files need no Linux job: their build and tests run locally and on main, not on a pull request.
APP_PATHS = r"^(MarfaMac/|MarfaMacTests/|MarfaMacUITests/|MarfaMac\.xcodeproj/|TestPlans/|Config/|\.github/scripts/run-unit-tests\.sh\Z)"


def classify(paths):
    lanes = set()
    for path in paths:
        path_lanes = {lane for lane, pattern in PATH_RULES.items() if re.search(pattern, path)}
        if path.endswith(".md"):
            path_lanes.add("instructions")
        if not path_lanes and not re.search(APP_PATHS, path):
            lanes.update(ALL_CHECKS)
            continue
        # A change to the rules themselves cannot be judged by them.
        if "classifier" in path_lanes:
            lanes.update(ALL_CHECKS)
            continue

        # Source changes can make references in the docs stale.
        if path.endswith((".swift", "/project.pbxproj")):
            path_lanes.add("instructions")
        lanes.update(path_lanes)
    return lanes


if __name__ == "__main__":
    paths = os.fsdecode(sys.stdin.buffer.read()).split("\0")
    for lane in sorted(classify(filter(None, paths))):
        print(f"{lane}=true")
