#!/usr/bin/env python3
"""Prints the articles `SpeedMeasureTests.testOpeningLargeItems` opens, one JSON object per line: a short one, a long one
(about 50 KB), one with many pictures at web addresses and one with a very long field. The text is fixed by a seed, so
every run opens the same items. `Scripts/measure-ui.sh` makes them with the `marfa` command line and purges them."""
import json
import random

random.seed(7)
WORDS = (
    "the of and to in is that for it as was with be by on not he this are or his from at which but have an had they you "
    "were their one all we can her has there been if more when will would who so no library sidebar editor marfa sync "
    "server window reading article highlight margin typography screen paragraph essay argument evidence history system "
    "pattern signal structure memory attention"
).split()


def sentence():
    return " ".join(random.choice(WORDS) for _ in range(random.randint(8, 22))).capitalize() + "."


def paragraph():
    return " ".join(sentence() for _ in range(random.randint(3, 7)))


def article(limit):
    blocks, size, index = [], 0, 0
    while size < limit:
        if index % 6 == 0:
            blocks.append(f"## {sentence()[:-1]}")
        kind = random.random()
        if kind < 0.15:
            blocks.append("\n".join(f"- {sentence()}" for _ in range(random.randint(3, 6))))
        elif kind < 0.22:
            blocks.append("> " + paragraph())
        else:
            link = f" [a reference](https://example.com/ref/{index})" if random.random() < 0.3 else ""
            blocks.append(paragraph() + link)
        index += 1
        size = sum(len(block) + 2 for block in blocks)
    return "\n\n".join(blocks)


def pictures(count):
    blocks = []
    for index in range(count):
        blocks.append(paragraph())
        blocks.append(f"![Figure {index}: {sentence()[:40]}](https://example.com/images/figure-{index}.jpg)")
    return "\n\n".join(blocks)


def item(title, body, extra=None):
    slug = title.replace(" ", "-")
    properties = {"title": title, "body": body, "author": "Speed open", "url": f"https://example.com/speed-open/{slug}"}
    properties.update(extra or {})
    return properties


for properties in (
    item("Speed open short", article(1500)),
    item("Speed open long", article(50000)),
    item("Speed open pictures", pictures(40)),
    item("Speed open long field", article(2000), {"notes": article(40000)}),
):
    print(json.dumps(properties))
