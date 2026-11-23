#!/usr/bin/env python3
"""Adds a release to Marfa for Mac's Sparkle appcast.

    appcast.py --feed live.xml --out appcast.xml --tag v0.0.59-rc1 --downloads-url https://example.com/marfa-mac/ \\
        --signature <EdDSA signature> --length <bytes> --notes notes.md --releases-url <page>

`--feed` is the feed as it is published now; a file that does not exist starts a new feed. The new item goes in front,
an item for the same build (a rebuilt tag) is replaced, and each channel keeps its newest ten items. A candidate's item
is in the `beta` channel, which only a person who turned on Beta Versions is offered; a release's item has no channel.
Everything written into the feed from the tag, the notes or the arguments is escaped, never inserted as markup.
"""

from __future__ import annotations

import argparse
import datetime
import email.utils
import html
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urljoin

import version

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)

MINIMUM_SYSTEM_VERSION = "27.0.0"
ITEMS_PER_CHANNEL = 10
BETA_CHANNEL = "beta"
APP_NAME = "Marfa"


def sparkle(name: str) -> str:
    return f"{{{SPARKLE}}}{name}"


def new_feed(releases_url: str) -> ET.ElementTree:
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = f"{APP_NAME} for Mac"
    ET.SubElement(channel, "link").text = releases_url
    ET.SubElement(channel, "description").text = f"The versions of {APP_NAME} for Mac."
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(root)


def item_build(item: ET.Element) -> int:
    text = (item.findtext(sparkle("version")) or "").strip()
    return int(text) if text.isdigit() else -1


def item_channel(item: ET.Element) -> str:
    return (item.findtext(sparkle("channel")) or "").strip()


URL = re.compile(r"https?://[^\s<>\"']+")
BOLD = re.compile(r"\*\*(.+?)\*\*")


def inline(text: str) -> str:
    """One line of notes as HTML: the text escaped, with bold and bare links the way GitHub writes them."""
    escaped = html.escape(text, quote=True)

    def link(match: re.Match) -> str:
        address = match.group(0)
        trailing = ""
        while address and address[-1] in ".,;:!?)":
            trailing = address[-1] + trailing
            address = address[:-1]
        return f'<a href="{address}">{address}</a>{trailing}'

    return BOLD.sub(r"<strong>\1</strong>", URL.sub(link, escaped))


def notes_to_html(notes: str) -> str:
    """GitHub's generated release notes (headings, bullets, paragraphs) as simple HTML, with every character escaped."""
    notes = re.sub(r"<!--.*?-->", "", notes, flags=re.DOTALL)
    blocks: list[str] = []
    bullets: list[str] = []
    paragraph: list[str] = []

    def flush() -> None:
        if bullets:
            blocks.append("<ul>" + "".join(f"<li>{inline(line)}</li>" for line in bullets) + "</ul>")
            bullets.clear()
        if paragraph:
            blocks.append("<p>" + "<br>".join(inline(line) for line in paragraph) + "</p>")
            paragraph.clear()

    for raw in notes.splitlines():
        line = raw.strip()
        heading = re.match(r"^#{1,6}\s+(.*)$", line)
        bullet = re.match(r"^[*-]\s+(.*)$", line)
        if not line:
            flush()
        elif heading:
            flush()
            blocks.append(f"<h3>{inline(heading.group(1))}</h3>")
        elif bullet:
            if paragraph:
                flush()
            bullets.append(bullet.group(1))
        else:
            if bullets:
                flush()
            paragraph.append(line)
    flush()
    return "".join(blocks)


def make_item(
    release: version.Release,
    downloads_url: str,
    file_name: str,
    signature: str,
    length: int,
    notes: str,
    releases_url: str,
    published: datetime.datetime,
) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"{APP_NAME} {release.tag.removeprefix('v')}"
    ET.SubElement(item, "pubDate").text = email.utils.format_datetime(published, usegmt=True)
    ET.SubElement(item, sparkle("version")).text = str(release.build)
    ET.SubElement(item, sparkle("shortVersionString")).text = release.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    if release.candidate:
        ET.SubElement(item, sparkle("channel")).text = BETA_CHANNEL
    ET.SubElement(item, sparkle("fullReleaseNotesLink")).text = releases_url
    ET.SubElement(item, "description").text = notes_to_html(notes)
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": urljoin(downloads_url, file_name),
            "length": str(length),
            "type": "application/octet-stream",
            sparkle("edSignature"): signature,
        },
    )
    return item


def build(
    feed: ET.ElementTree | None,
    release: version.Release,
    downloads_url: str,
    file_name: str,
    signature: str,
    length: int,
    notes: str,
    releases_url: str,
    published: datetime.datetime,
) -> ET.ElementTree:
    """The feed with the release added, replaced if its build is already there, and each channel cut to its newest ten."""
    tree = feed if feed is not None else new_feed(releases_url)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ValueError("The feed has no channel element.")
    items = [item for item in channel.findall("item") if item_build(item) != release.build]
    items.append(make_item(release, downloads_url, file_name, signature, length, notes, releases_url, published))
    for item in channel.findall("item"):
        channel.remove(item)
    # Newest build first; the sort is stable, so items with the same build keep their order.
    items.sort(key=item_build, reverse=True)
    kept: dict[str, int] = {}
    for item in items:
        name = item_channel(item)
        kept[name] = kept.get(name, 0) + 1
        if kept[name] <= ITEMS_PER_CHANNEL:
            channel.append(item)
    ET.indent(tree, space="  ")
    return tree


def parse_date(text: str | None) -> datetime.datetime:
    if text is None:
        return datetime.datetime.now(datetime.timezone.utc)
    return datetime.datetime.fromisoformat(text).astimezone(datetime.timezone.utc)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--feed", type=Path, help="the published feed; a missing file starts a new feed")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--downloads-url", required=True, help="the folder the files are published in, with a trailing slash")
    parser.add_argument("--file-name", help="the file's name in that folder; Marfa-<tag without v>.dmg when left out")
    parser.add_argument("--signature", required=True, help="the file's EdDSA signature from sign_update")
    parser.add_argument("--length", required=True, type=int, help="the file's size in bytes")
    parser.add_argument("--notes", type=Path, help="the release notes, as GitHub generates them")
    parser.add_argument("--releases-url", required=True)
    parser.add_argument("--date", help="the publication time as ISO 8601; now when left out")
    args = parser.parse_args(argv[1:])
    try:
        release = version.parse(args.tag)
        feed = ET.parse(args.feed) if args.feed is not None and args.feed.exists() else None
        notes = args.notes.read_text(encoding="utf-8") if args.notes is not None else ""
        file_name = args.file_name or f"{APP_NAME}-{args.tag.removeprefix('v')}.dmg"
        tree = build(
            feed, release, args.downloads_url, file_name, args.signature, args.length, notes, args.releases_url,
            parse_date(args.date),
        )
    except (version.TagError, ValueError, ET.ParseError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    tree.write(args.out, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
