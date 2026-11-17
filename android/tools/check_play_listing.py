#!/usr/bin/env python3
"""Checks the character limits of the fields in PLAY_STORE_LISTING.md."""
import pathlib, re, sys

LIMITS = {"App name": 30, "Short description": 80, "Full description": 4000}
text = (pathlib.Path(__file__).resolve().parent.parent / "PLAY_STORE_LISTING.md").read_text(encoding="utf-8")
ok = True
for lang_block in re.split(r"^## ", text, flags=re.M)[1:]:
    lang = lang_block.splitlines()[0]
    for field, body in re.findall(r"\*\*(.+?)\*\*\n```\n(.*?)\n```", lang_block, flags=re.S):
        if field in LIMITS:
            n = len(body)
            flag = "ok" if n <= LIMITS[field] else "TOO LONG"
            ok &= n <= LIMITS[field]
            print(f"{lang:22} {field:18} {n:5}/{LIMITS[field]}  {flag}")
sys.exit(0 if ok else 1)
