#!/usr/bin/env python3
"""Reads one `marfa ... --json` answer, or a `Measure UI` run's output, on standard input and prints an item id, for
`Scripts/measure-ui.sh`, which removes only the items it recorded. It looks nothing up by name.

  created          the id in the answer of `marfa items create --json`
  made             the id behind each `MADE|<title>|<link>` line the typing test prints: the last part of the link's path
  titled <title>   the answer of `marfa items get --json` when the item has exactly that title, otherwise nothing
"""
import json
import sys
from urllib.parse import urlparse

mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "created":
    print(json.load(sys.stdin)["item"]["id"])
elif mode == "made":
    for line in sys.stdin:
        parts = line.rstrip("\n").split("|", 2)
        if parts[0] == "MADE" and len(parts) == 3:
            print(urlparse(parts[2].strip()).path.rstrip("/").rsplit("/", 1)[-1], parts[1], sep="\t")
elif mode == "titled" and len(sys.argv) == 3:
    item = json.load(sys.stdin).get("item", {})
    if item.get("properties", {}).get("title") == sys.argv[2]:
        print(item["id"])
else:
    sys.exit("usage: measure-ids.py created | made | titled <title>")
