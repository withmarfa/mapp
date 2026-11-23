#!/usr/bin/env python3
"""Turns a release tag into the version, build number and channel the app is built with.

    version.py v0.0.59-rc1

prints `key=value` lines (version, build, candidate, channel, tag) that a workflow step can append to
`$GITHUB_OUTPUT`. A tag that is not a version, would build 0.0.0 or cannot be numbered exits with status 1.

The build number is what Sparkle compares (`CFBundleVersion`): X*10000000 + Y*100000 + Z*100 + N for a candidate
`vX.Y.Z-rcN`, and the same with 99 in place of N for the release `vX.Y.Z`, so a candidate always sorts below the
release it is a candidate for and a rebuilt tag gets the number it had.
"""

from __future__ import annotations

import re
import sys
from typing import NamedTuple

TAG = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-rc([1-9][0-9]*))?$")

# Each part must stay inside its decimal places in the build number.
MAX_MAJOR = 99
MAX_MINOR = 99
MAX_PATCH = 999
MAX_CANDIDATE = 98
RELEASE_SUFFIX = 99


class TagError(ValueError):
    pass


class Release(NamedTuple):
    tag: str
    version: str
    build: int
    candidate: bool

    @property
    def channel(self) -> str:
        return "beta" if self.candidate else "default"


def parse(tag: str) -> Release:
    match = TAG.fullmatch(tag)
    if match is None:
        raise TagError(f"The tag {tag} is not a version such as v1.2.3 or a candidate such as v1.2.3-rc1.")
    major, minor, patch = (int(part) for part in match.group(1, 2, 3))
    candidate = match.group(4) is not None
    number = int(match.group(4)) if candidate else RELEASE_SUFFIX
    if (major, minor, patch) == (0, 0, 0):
        raise TagError(f"The tag {tag} would build version 0.0.0.")
    if major > MAX_MAJOR or minor > MAX_MINOR or patch > MAX_PATCH:
        raise TagError(f"The tag {tag} is out of range: the version is at most {MAX_MAJOR}.{MAX_MINOR}.{MAX_PATCH}.")
    if candidate and number > MAX_CANDIDATE:
        raise TagError(f"The tag {tag} is out of range: a candidate is at most -rc{MAX_CANDIDATE}.")
    build = major * 10_000_000 + minor * 100_000 + patch * 100 + number
    return Release(tag=tag, version=f"{major}.{minor}.{patch}", build=build, candidate=candidate)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: version.py <tag>", file=sys.stderr)
        return 2
    try:
        release = parse(argv[1])
    except TagError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print(f"tag={release.tag}")
    print(f"version={release.version}")
    print(f"build={release.build}")
    print(f"candidate={'true' if release.candidate else 'false'}")
    print(f"channel={release.channel}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
