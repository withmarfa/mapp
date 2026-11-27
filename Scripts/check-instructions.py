#!/usr/bin/env python3
"""Checks that MarfaMac's agent instructions and docs have not drifted. Standard library only.

    python3 Scripts/check-instructions.py [repository root]

Each failure prints `path:line: message` (and a GitHub annotation in Actions); the exit status is 1 if there is any.

Instruction files, each `AGENTS.md` at any depth:

1. It is under 200 lines.
2. Its chain from the root `AGENTS.md` down (the root, every ancestor's file, then that file) is under 32,000 bytes.
   Codex stops reading at 32 KiB, and the root file states this limit.
3. It has a `CLAUDE.md` beside it that is a symlink to it, and no `CLAUDE.md` stands without one.
4. Under `MarfaMac/`, it and its `CLAUDE.md` are in the MarfaMac target's membership exceptions in
   `MarfaMac.xcodeproj/project.pbxproj`, and no exception names one that is gone. The folder is synchronized, so a file
   missing from the list becomes an app resource and the build fails on duplicates.

Instruction files and the pages in `docs/`:

5. Each is within its word budget in `BUDGETS`, not counting a page's frontmatter, and no bullet is over 60 words.
6. None holds a status, a release, a date, a session or a board's number (`BANNED`). `docs/agreed.md` alone may
   say what is not built. `this Mac` is for the pages on settings and on ownership.
7. Each backticked name exists. Anything that fits neither of these is skipped:
   - A path (it holds `/`, or ends in a file extension such as `.swift` or `.ts`) exists from the repository root or from
     the file's own folder, or ends a path in the source: `ValueEditing/` matches any folder of that name.
   - A Swift or TypeScript symbol (`Name`, `Type.member` or `name(_:)`, with a capital letter that is not all it has) is
     declared in the source, or used there outside a comment; each later part is a word of the code.
   The source is `MarfaMac/`, the two test folders and `editor/` (`SOURCE_SUFFIXES`), without built output.
   A contract statement (`types/delete-in-use`) and another repository are skipped. `UNTRACKED` names the ignored files that may be named.
8. Each page in `docs/` is in the root `AGENTS.md`, and each page that file names exists. Each page starts with
   frontmatter: a `summary`, and `paths`, where each glob matches a file.
9. Each relative Markdown link and its anchor resolves, in `README.md` too.
10. No run of 12 words stands in two of the files, because a rule with two homes goes stale in one of them.

`.claude/`, any folder starting with a dot, `node_modules/` and build output are never searched for instruction files.
"""

import glob
import os
import re
import sys

LINE_LIMIT = 200  # an instruction file must have fewer lines than this
CHAIN_LIMIT = 32000  # bytes, for the root file plus every ancestor's plus the nested one
PRUNED = {"node_modules", "build", "build-release", "DerivedData", "dist", "xcuserdata"}
SOURCE_ROOTS = ("MarfaMac", "MarfaMacTests", "MarfaMacUITests", "editor")
OTHER_ROOTS = (".agents", ".github", "Config", "Scripts", "TestPlans")  # searched for paths, not for names
UNTRACKED = (".claude/worktrees/", "Config/Local.xcconfig")  # ignored files a person makes
SOURCE_SUFFIXES = (".swift", ".ts", ".tsx", ".js", ".mjs", ".css")
BUILT_OUTPUT = "MarfaMac/Editor/Page/"
BULLET_LIMIT = 60  # words
RUN_LENGTH = 12  # words that may not stand in two files
BUDGETS = {  # words
    "AGENTS.md": 900,
    "MarfaMac/Editor/AGENTS.md": 1300,
    "MarfaMac/Model/AGENTS.md": 1300,
    "MarfaMac/Model/Marfa/AGENTS.md": 1400,
    "MarfaMac/Settings/AGENTS.md": 500,
    "MarfaMac/Settings/Marfa/AGENTS.md": 450,
    "MarfaMac/Views/AGENTS.md": 600,
    "MarfaMacTests/AGENTS.md": 650,
    "editor/AGENTS.md": 1400,
    "docs/agreed.md": 4500,
    "docs/commands.md": 1200,
    "docs/concepts.md": 2600,
    "docs/editing.md": 900,
    "docs/item-page.md": 1700,
    "docs/lists.md": 1400,
    "docs/look.md": 1200,
    "docs/model.md": 1100,
    "docs/owner-settings.md": 1800,
    "docs/rejected.md": 1350,
    "docs/settings-sync.md": 1100,
    "docs/settings-window.md": 1000,
    "docs/type-looks.md": 900,
    "docs/value-panels.md": 800,
    "docs/window.md": 990,
}
MONTH = r"(?:January|February|March|April|May|June|July|August|September|October|November|December)"
STATUS = [(re.compile(p, re.IGNORECASE), why) for p, why in (
    (r"not yet released", "a page says what is on main"),
    (r"built in v", "a page says what is on main"),
    (r"this branch", "a page says what is on main"),
    (r"\bnot (?:yet )?built\b", "only docs/agreed.md says what is not built"),
    (r"^Status:", "a status goes stale"),
)]
BANNED = [(re.compile(p), why) for p, why in (
    (r"\bv?0\.0\.[1-9]", "a release goes stale"),
    (rf"\b{MONTH} \d{{4}}\b|\b\d{{4}}-\d\d-\d\d\b", "dates are for git"),
    (r"\b[Ss]ession \d{2,}", "history is for git"),
    (r"(?<![\w/.#-])[A-Z]\d{1,3}[a-z]?(?!\w|[.-]\w)", "board numbers change; name the board's file"),
    (r"[\u2014\u00b7]", "no em dash or interpunct"),
)]
THIS_MAC = re.compile(r"\bthis Mac\b")
THIS_MAC_PAGES = ("docs/settings-sync.md", "docs/model.md")
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
COMMENT = re.compile(r"^\s*//.*$|^\s*/?\*.*$", re.MULTILINE)


class Report:
    def __init__(self):
        self.count = 0
        self.names = 0  # backticked names that were looked up

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
                text = COMMENT.sub("", read(os.path.join(directory, name)))
                words.update(WORD.findall(text))
                declared.update(DECLARATION.findall(text))
                for case in CASE_LIST.findall(text):
                    for part in case.split(","):
                        match = WORD.match(part.strip())
                        if match:
                            declared.add(match.group(0))
    for top in OTHER_ROOTS:
        for directory, _, files in os.walk(os.path.join(root, top)):
            paths.update(os.path.join(os.path.relpath(directory, root), name) for name in files)
    return declared, words, paths


def path_exists(root, name, paths, beside):
    trimmed = name.rstrip("/")
    return os.path.exists(os.path.join(root, trimmed)) or os.path.exists(os.path.join(root, beside, trimmed)) or any(
        p == trimmed or p.endswith("/" + trimmed) for p in paths
    )


def symbol_problem(name, declared, words):
    parts = name.split(".")
    if parts[0] not in declared and parts[0] not in words:
        return f"`{name}` is nowhere in the source (`{parts[0]}` is neither declared nor used)"
    for part in parts[1:]:
        if part not in words:
            return f"`{name}` names `{part}`, which the source never mentions"
    return None


def frontmatter(text):
    """The frontmatter's lines and the number of lines it takes up, both empty where there is none."""
    lines = text.splitlines()
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        return [], 0
    end = lines.index("---", 1)
    return lines[1:end], end + 1


def body(text):
    """(line number, line) of each line after the frontmatter and outside a fenced block."""
    _, skip = frontmatter(text)
    found, fenced = [], False
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        elif number > skip and not fenced:
            found.append((number, line))
    return found


def blocks(text):
    """(line number, text) of each paragraph, bullet, heading and table row."""
    found = []
    for number, line in body(text):
        starts = not line.strip() or re.match(r"\s*(?:[-*]|\d+\.) |#|\|", line)
        if starts or not found or not found[-1][1]:
            found.append((number, line.strip()))
        else:
            found[-1] = (found[-1][0], found[-1][1] + " " + line.strip())
    return [block for block in found if block[1]]


def check_words(path, text, report):
    _, skip = frontmatter(text)
    count = sum(bool(re.search(r"\w", word)) for word in " ".join(text.splitlines()[skip:]).split())
    if path not in BUDGETS:
        report.fail(path, 1, "has no word budget; give it one in BUDGETS in Scripts/check-instructions.py.")
    elif count > BUDGETS[path]:
        report.fail(path, 1, f"has {count} words; its budget is {BUDGETS[path]}. Cut what the code, a test or a doc "
                    "comment already says.")
    for number, block in blocks(text):
        if re.match(r"(?:[-*]|\d+\.) ", block):
            length = len(block.split()) - 1
            if length > BULLET_LIMIT:
                report.fail(path, number, f"a bullet has {length} words; the limit is {BULLET_LIMIT}. One bullet is one rule.")


def check_banned(path, text, report):
    patterns = BANNED if path == "docs/agreed.md" else BANNED + STATUS
    for number, line in enumerate(text.splitlines(), 1):
        for pattern, why in patterns:
            match = pattern.search(line)
            if match:
                report.fail(path, number, f"holds `{match.group(0)}`: {why}.")
        if path.startswith("docs/") and path not in THIS_MAC_PAGES and THIS_MAC.search(line):
            report.fail(path, number, "holds `this Mac`: where a thing is kept is in PreferencesMap and docs/settings-sync.md.")


def check_names(root, path, text, source, report):
    declared, words, paths = source
    for number, line in body(text):
        for name in re.findall(r"`([^`]+)`", line):
            name = re.sub(r"\([\w:]*\)$", "", name)
            problem = None
            if name in UNTRACKED:
                continue
            first = name.split("/")[0]
            if "/" in name and first == first.lower() and not name.endswith(FILE_SUFFIXES) \
                    and not os.path.isdir(os.path.join(root, first)):
                continue  # a statement in Marfa's contract (`types/delete-in-use`) or another repository
            if PATH.match(name) and ("/" in name or name.endswith(FILE_SUFFIXES)):
                report.names += 1
                if not path_exists(root, name, paths, os.path.dirname(path)):
                    problem = f"`{name}` is not a file or folder in the repository"
            elif SYMBOL.match(name) and re.search(r"[A-Z]", name) and not re.fullmatch(r"[A-Z0-9_.]+", name):
                report.names += 1
                problem = symbol_problem(name, declared, words)
            if problem:
                report.fail(path, number, f"{problem}. Rename it, or remove it.")


def anchors(text):
    found = set()
    for _, line in body(text):
        if line.startswith("#"):
            heading = re.sub(r"[^\w\- ]", "", line.lstrip("#").strip().lower())
            found.add(heading.replace(" ", "-"))
    return found


def check_targets(root, path, text, report):
    for number, line in body(text):
        for target in re.findall(r"\]\(([^)\s]+)\)", line):
            if re.match(r"[a-z]+:", target):
                continue
            file, _, anchor = target.partition("#")
            full = os.path.normpath(os.path.join(root, os.path.dirname(path), file)) if file else os.path.join(root, path)
            if not os.path.exists(full):
                report.fail(path, number, f"links to `{target}`, which does not exist.")
            elif anchor and anchor not in anchors(read(full)):
                report.fail(path, number, f"links to `{target}`, which has no heading for that anchor.")


def check_index(root, pages, report):
    index = read(os.path.join(root, "AGENTS.md"))
    named = {}
    for number, line in enumerate(index.splitlines(), 1):
        for page in re.findall(r"`(docs/[\w.-]+\.md)`", line):
            named.setdefault(page, number)
    for page in pages:
        if page not in named:
            report.fail(page, 1, "is not in the root AGENTS.md's table, so no agent finds it.")
    for page, number in named.items():
        if page not in pages:
            report.fail("AGENTS.md", number, f"names `{page}`, which does not exist.")


def check_frontmatter(root, path, text, report):
    lines, _ = frontmatter(text)
    if not any(re.match(r"summary: \S", line) for line in lines):
        report.fail(path, 1, "has no `summary` in its frontmatter: one sentence, what the page decides.")
    globs = [line.strip()[2:].strip() for line in lines if line.startswith("  - ")]
    if "paths:" not in lines or not globs:
        report.fail(path, 1, "has no `paths` in its frontmatter: the globs of the code it governs.")
    for pattern in globs:
        if not glob.glob(os.path.join(root, pattern), recursive=True):
            report.fail(path, 1, f"its path `{pattern}` matches no file.")


def check_repeats(texts, report):
    seen = {}
    for path, text in texts.items():
        for number, block in blocks(text):
            words = re.findall(r"[a-z0-9]+", block.lower())
            told = False
            for start in range(len(words) - RUN_LENGTH + 1):
                run = tuple(words[start:start + RUN_LENGTH])
                first = seen.setdefault(run, (path, number))
                if first[0] != path and not told:
                    told = True
                    report.fail(path, number, f"repeats {first[0]}:{first[1]} (\"{' '.join(run)}\"). Keep it in one of them.")


def check_docs(root, agents, report):
    folder = os.path.join(root, "docs")
    pages = sorted(f"docs/{name}" for name in os.listdir(folder) if name.endswith(".md")) if os.path.isdir(folder) else []
    texts = {path: read(os.path.join(root, path)) for path in agents + pages}
    source = source_index(root)
    for path, text in texts.items():
        check_words(path, text, report)
        check_banned(path, text, report)
        check_names(root, path, text, source, report)
        check_targets(root, path, text, report)
    for path in pages:
        check_frontmatter(root, path, texts[path], report)
    for path in BUDGETS:
        if path not in texts:
            report.fail(path, 1, "has a word budget and does not exist; remove it from BUDGETS.")
    if os.path.exists(os.path.join(root, "README.md")):
        check_targets(root, "README.md", read(os.path.join(root, "README.md")), report)
    check_index(root, pages, report)
    check_repeats(texts, report)
    return len(pages)


def check_project(root, agents, claudes, report):
    project = "MarfaMac.xcodeproj/project.pbxproj"
    full = os.path.join(root, project)
    nested = sorted(p[len("MarfaMac/"):] for p in agents + claudes if p.startswith("MarfaMac/"))
    if not os.path.exists(full):
        if nested:
            report.fail(project, 1, "is missing, so the instruction files under MarfaMac/ cannot be checked.")
        return
    lines = read(full).splitlines()
    marker = next((i for i, l in enumerate(lines) if 'Exceptions for "MarfaMac" folder in "MarfaMac" target' in l), None)
    start = next((i for i in range(marker or 0, len(lines)) if "membershipExceptions = (" in lines[i]), None) \
        if marker is not None else None
    if start is None:
        if nested:
            report.fail(project, 1, 'has no `Exceptions for "MarfaMac" folder in "MarfaMac" target` with membershipExceptions.')
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
                not os.path.lexists(os.path.join(root, "MarfaMac", entry)):
            report.fail(project, line, f"membershipExceptions lists `{entry}`, which no longer exists; remove it.")


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
    report = Report()
    agents, claudes = instruction_files(root, "AGENTS.md"), instruction_files(root, "CLAUDE.md")
    check_lines(root, agents, report)
    check_chains(root, agents, report)
    check_links(root, agents, claudes, report)
    pages = check_docs(root, agents, report)
    check_project(root, agents, claudes, report)
    if report.count:
        print(f"{report.count} problem{'s' if report.count != 1 else ''} in the agent instructions and docs.")
        return 1
    print(f"Agent instructions and docs agree: {len(agents)} AGENTS.md files, {pages} pages and {report.names} names checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
