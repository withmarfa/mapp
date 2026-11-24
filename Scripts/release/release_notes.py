#!/usr/bin/env python3
"""Writes a release's notes from the commits on main since the tag before it, listing only what a person notices.

    release_notes.py <previous tag, or empty for none> <revision> <output file>

Each commit on main is one squashed pull request with a Conventional Commit subject. A `feat` is listed under New, a
`fix` under Fixed and a `perf` under Faster; every other type, and these types in a scope only developers see (such as
`release` or `ci`), is left out. Names of people and pull request numbers are left out too.
"""

from __future__ import annotations

import re
import subprocess
import sys

SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?!?: (?P<text>.+?)(?: \(#\d+\))*$")
SECTIONS = {"feat": "New", "fix": "Fixed", "perf": "Faster"}
# Scopes whose changes reach no one who uses the app.
UNSEEN_SCOPES = {"build", "ci", "deps", "docs", "release", "test", "tests"}
NOTHING = "Small changes behind the scenes."


def entry(subject: str) -> tuple[str, str] | None:
    """The section and the sentence a subject gives, or None for a change a person does not notice."""
    match = SUBJECT.match(subject.strip())
    if match is None or match["type"] not in SECTIONS:
        return None
    if (match["scope"] or "") in UNSEEN_SCOPES:
        return None
    text = match["text"].strip()
    return SECTIONS[match["type"]], text[:1].upper() + text[1:]


def notes(subjects: list[str]) -> str:
    """Markdown: a heading per section in the order New, Fixed, Faster, each with its sentences oldest first."""
    grouped: dict[str, list[str]] = {name: [] for name in SECTIONS.values()}
    for subject in subjects:
        found = entry(subject)
        if found and found[1] not in grouped[found[0]]:
            grouped[found[0]].append(found[1])
    parts = [f"### {name}\n" + "".join(f"- {line}\n" for line in lines) for name, lines in grouped.items() if lines]
    return "\n".join(parts) if parts else NOTHING + "\n"


def subjects_between(previous: str, revision: str) -> list[str]:
    """The subjects of the commits on the first-parent line from `previous` (exclusive) to `revision`, oldest first."""
    span = f"{previous}..{revision}" if previous else revision
    out = subprocess.run(
        ["git", "log", "--first-parent", "--reverse", "--format=%s", span],
        check=True, capture_output=True, text=True,
    ).stdout
    return [line for line in out.splitlines() if line.strip()]


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: release_notes.py <previous tag, or empty> <revision> <output file>", file=sys.stderr)
        return 2
    previous, revision, output = argv[1:]
    try:
        text = notes(subjects_between(previous, revision))
    except subprocess.CalledProcessError as error:
        print(f"::error::git log failed: {error.stderr.strip()}", file=sys.stderr)
        return 1
    with open(output, "w", encoding="utf-8") as file:
        file.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
