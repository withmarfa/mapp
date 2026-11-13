#!/usr/bin/env python3
"""Checks that MAPP's agent instructions and concept docs have not drifted. Standard library only.

    python3 Scripts/check-instructions.py [repository root]

Each failure prints `path:line: message` (and a GitHub annotation in Actions); the exit status is 1 if there is any.

1. Each `AGENTS.md`, at any depth, is under 200 lines.
2. Each chain from the root `AGENTS.md` down to a nested one (the root, every ancestor's file, then that file) is under
   32,000 bytes. Codex stops reading at 32 KiB, and the root file states this limit.
3. Each `AGENTS.md` has a `CLAUDE.md` beside it that is a symlink to it, and no `CLAUDE.md` stands without one.
4. Each backticked name on a "Where it lives" line in `docs/*.md` exists in the source. The line is the paragraph that
   starts `Where it lives:`, up to the next blank line. The source is `MAPP/`, `MAPPTests/`, `MAPPUITests/` and
   `editor/src/` (`.swift`, `.ts`, `.tsx`, `.js`, `.css`), without `MAPP/Editor/Page/`, which is built output.
   A name is checked as follows, and anything that fits none of these is skipped:
   - A path (it holds `/`, or ends in a file extension such as `.swift` or `.ts`) must exist from the repository root,
     or end a path in the source: `ValueEditing/` matches any folder of that name, `ListRows.swift` any file.
   - A Swift or TypeScript symbol (a type, function, constant or member, written `Name` or `Type.member`) must be
     declared in the source: its first part after `struct`, `class`, `enum`, `protocol`, `actor`, `typealias`,
     `extension`, `func`, `let`, `var`, `case`, `function`, `interface`, `type` or `const`; each later part as a word.
   - Skipped as unverifiable: names with no capital letter (plain words, SF Symbol names such as
     `circle.lefthalf.filled`, Marfa type ids such as `core.note`, snake_case keys), names in capitals only
     (environment variables), and anything with spaces, quotes, brackets or other punctuation.
5. Each `AGENTS.md` under `MAPP/` and its `CLAUDE.md` are in the MAPP target's membership exceptions in
   `MAPP.xcodeproj/project.pbxproj`, and no exception names an `AGENTS.md` or `CLAUDE.md` that is gone. The folder is
   synchronized, so a file missing from the list becomes an app resource and the build fails on duplicates.

`.claude/`, any folder starting with a dot, `node_modules/` and build output are never searched for instruction files.
"""

import os
import re
import sys

LINE_LIMIT = 200  # an instruction file must have fewer lines than this
CHAIN_LIMIT = 32000  # bytes, for the root file plus every ancestor's plus the nested one
PRUNED = {"node_modules", "build", "build-release", "DerivedData", "dist", "xcuserdata"}
SOURCE_ROOTS = ("MAPP", "MAPPTests", "MAPPUITests", "editor/src")
SOURCE_SUFFIXES = (".swift", ".ts", ".tsx", ".js", ".css")
BUILT_OUTPUT = "MAPP/Editor/Page/"
FILE_SUFFIXES = (
    ".swift", ".ts", ".tsx", ".js", ".css", ".html", ".json", ".md", ".py", ".sh", ".yml", ".yaml", ".plist",
    ".xcstrings", ".xcconfig", ".entitlements", ".xcodeproj", ".xcassets",
)
DECLARATION = re.compile(
    r"\b(?:struct|class|enum|protocol|actor|typealias|extension|func|let|var|function|interface|type|const|namespace)"
    r"\s+`?([A-Za-z_]\w*)"
)
CASE_LIST = re.compile(r"^\s*(?:indirect\s+)?case\s+(.+)$", re.MULTILINE)
WORD = re.compile(r"[A-Za-z_]\w*")
SYMBOL = re.compile(r"^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$")
PATH = re.compile(r"^[\w./+-]+$")


class Report:
    def __init__(self):
        self.count = 0
        self.names = 0  # names on "Where it lives" lines that were looked up

    def fail(self, path, line, message):
        self.count += 1
        print(f"{path}:{line}: {message}")
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::error file={path},line={line}::{message}")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def instruction_files(root, name):
    """Relative paths of every file called `name` outside pruned folders, sorted."""
    found = []
    for directory, folders, files in os.walk(root):
        folders[:] = [f for f in folders if not f.startswith(".") and f not in PRUNED]
        if name in files:
            found.append(os.path.relpath(os.path.join(directory, name), root))
    return sorted(found)


def check_lines(root, agents, report):
    for path in agents:
        count = len(read(os.path.join(root, path)).splitlines())
        if count >= LINE_LIMIT:
            report.fail(path, LINE_LIMIT, f"has {count} lines; an instruction file must stay under {LINE_LIMIT}. "
                        "Move detail about one type to its doc comment and a concept to docs/.")


def check_chains(root, agents, report):
    sizes = {path: os.path.getsize(os.path.join(root, path)) for path in agents}
    for path in agents:
        chain, directory = [], os.path.dirname(path)
        while True:
            candidate = os.path.join(directory, "AGENTS.md")
            if candidate in sizes:
                chain.append(candidate)
            if not directory:
                break
            directory = os.path.dirname(directory)
        total = sum(sizes[p] for p in chain)
        if total >= CHAIN_LIMIT:
            parts = ", ".join(f"{p} {sizes[p]}" for p in reversed(chain))
            report.fail(path, 1, f"its chain is {total} bytes; the limit is under {CHAIN_LIMIT} ({parts}).")


def check_links(root, agents, claudes, report):
    for path in agents:
        link = os.path.join(os.path.dirname(path), "CLAUDE.md")
        full = os.path.join(root, link)
        if not os.path.lexists(full):
            report.fail(path, 1, f"has no {link}; add it with `ln -s AGENTS.md CLAUDE.md` beside the file.")
    for link in claudes:
        directory = os.path.dirname(link)
        full = os.path.join(root, link)
        if not os.path.exists(os.path.join(root, directory, "AGENTS.md")) and not os.path.islink(full):
            report.fail(link, 1, "stands without an AGENTS.md beside it; keep the text in AGENTS.md.")
        elif not os.path.islink(full):
            report.fail(link, 1, "is a regular file; it must be a symlink to AGENTS.md "
                        "(`rm CLAUDE.md && ln -s AGENTS.md CLAUDE.md`), so the text exists once.")
        elif os.readlink(full) != "AGENTS.md":
            report.fail(link, 1, f"points to `{os.readlink(full)}`; it must point to `AGENTS.md`.")
        elif not os.path.exists(os.path.join(root, directory, "AGENTS.md")):
            report.fail(link, 1, "points to an AGENTS.md that does not exist.")


def source_index(root):
    """What the source declares, every word it holds, and every file and folder path in it."""
    declared, words, paths = set(), set(), set()
    for top in SOURCE_ROOTS:
        base = os.path.join(root, top)
        for directory, folders, files in os.walk(base):
            folders[:] = [f for f in folders if not f.startswith(".") and f not in PRUNED]
            relative = os.path.relpath(directory, root)
            if relative + "/" == BUILT_OUTPUT or (relative + "/").startswith(BUILT_OUTPUT):
                continue
            paths.add(relative)
            for name in files:
                paths.add(os.path.join(relative, name))
                if not name.endswith(SOURCE_SUFFIXES):
                    continue
                text = read(os.path.join(directory, name))
                words.update(WORD.findall(text))
                declared.update(DECLARATION.findall(text))
                for case in CASE_LIST.findall(text):
                    for part in case.split(","):
                        match = WORD.match(part.strip())
                        if match:
                            declared.add(match.group(0))
    return declared, words, paths


def lives_lines(text):
    """(first line number, text) of each paragraph that starts `Where it lives:`."""
    lines, found, index = text.splitlines(), [], 0
    while index < len(lines):
        if lines[index].startswith("Where it lives:"):
            start, block = index + 1, []
            while index < len(lines) and lines[index].strip():
                block.append(lines[index])
                index += 1
            found.append((start, " ".join(block)))
        index += 1
    return found


def path_exists(root, name, paths):
    trimmed = name.rstrip("/")
    return os.path.exists(os.path.join(root, trimmed)) or any(
        p == trimmed or p.endswith("/" + trimmed) for p in paths
    )


def symbol_problem(name, declared, words):
    parts = name.split(".")
    if parts[0] not in declared:
        return f"`{name}` is not declared in the source (`{parts[0]}` has no struct, class, enum, func, let, var or case)"
    for part in parts[1:]:
        if part not in words:
            return f"`{name}` names `{part}`, which the source never mentions"
    return None


def check_docs(root, report):
    docs = os.path.join(root, "docs")
    if not os.path.isdir(docs):
        return
    declared, words, paths = source_index(root)
    for page in sorted(os.listdir(docs)):
        if not page.endswith(".md"):
            continue
        relative = f"docs/{page}"
        for start, block in lives_lines(read(os.path.join(docs, page))):
            for name in re.findall(r"`([^`]+)`", block):
                problem = None
                if PATH.match(name) and ("/" in name or name.endswith(FILE_SUFFIXES)):
                    report.names += 1
                    if not path_exists(root, name, paths):
                        problem = f"`{name}` is not a file or folder in the repository"
                elif SYMBOL.match(name):
                    if re.search(r"[A-Z]", name) and not re.fullmatch(r"[A-Z0-9_.]+", name):
                        report.names += 1
                        problem = symbol_problem(name, declared, words)
                if problem:
                    report.fail(relative, start, f"Where it lives: {problem}. Rename it in the doc, or remove it.")


def check_project(root, agents, claudes, report):
    project = "MAPP.xcodeproj/project.pbxproj"
    full = os.path.join(root, project)
    nested = sorted(p[len("MAPP/"):] for p in agents + claudes if p.startswith("MAPP/"))
    if not os.path.exists(full):
        if nested:
            report.fail(project, 1, "is missing, so the instruction files under MAPP/ cannot be checked.")
        return
    lines = read(full).splitlines()
    marker = next((i for i, l in enumerate(lines) if 'Exceptions for "MAPP" folder in "MAPP" target' in l), None)
    start = next((i for i in range(marker or 0, len(lines)) if "membershipExceptions = (" in lines[i]), None) \
        if marker is not None else None
    if start is None:
        if nested:
            report.fail(project, 1, 'has no `Exceptions for "MAPP" folder in "MAPP" target` with membershipExceptions.')
        return
    listed, index = {}, start + 1
    while index < len(lines) and lines[index].strip() != ");":
        listed[lines[index].strip().rstrip(",")] = index + 1
        index += 1
    for path in nested:
        if path not in listed:
            report.fail(project, start + 1, f"membershipExceptions lacks `{path}`; add it, or the build fails on "
                        "duplicate resources.")
    for entry, line in listed.items():
        if os.path.basename(entry) in ("AGENTS.md", "CLAUDE.md") and \
                not os.path.lexists(os.path.join(root, "MAPP", entry)):
            report.fail(project, line, f"membershipExceptions lists `{entry}`, which no longer exists; remove it.")


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
    report = Report()
    agents, claudes = instruction_files(root, "AGENTS.md"), instruction_files(root, "CLAUDE.md")
    check_lines(root, agents, report)
    check_chains(root, agents, report)
    check_links(root, agents, claudes, report)
    check_docs(root, report)
    check_project(root, agents, claudes, report)
    if report.count:
        print(f"{report.count} problem{'s' if report.count != 1 else ''} in the agent instructions and docs.")
        return 1
    print(f"Agent instructions and docs agree: {len(agents)} AGENTS.md files and {report.names} names checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
