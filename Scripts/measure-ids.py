#!/usr/bin/env python3
"""Reads `marfa search --json` answers on standard input, one after another, and prints the id of each item that a
`Measure UI` run made: a `core.note` titled `Speed measure` and eight hex digits, or a `core.media.article` titled
as `speed-fixtures.py` names it. Matching the type and the exact title in the data, never the table the command
prints, leaves every other item alone. `Scripts/measure-ui.sh` removes what this prints."""
import json
import re
import sys

RULES = {
    "core.note": re.compile(r"Speed measure [0-9A-F]+$"),
    "core.media.article": re.compile(r"Speed open (short|long|pictures|long field)$"),
}

decoder, text, position = json.JSONDecoder(), sys.stdin.read(), 0
while True:
    while position < len(text) and text[position].isspace():
        position += 1
    if position >= len(text):
        break
    answer, position = decoder.raw_decode(text, position)
    for hit in answer.get("data", []):
        item = hit["item"]
        rule = RULES.get(item.get("type"))
        if rule and rule.match(str(item.get("properties", {}).get("title", ""))):
            print(item["id"])
