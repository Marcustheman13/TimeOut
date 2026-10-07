#!/usr/bin/env python3
"""Bundles the TimeOut web demo into one self-contained HTML file.

    python3 build.py            -> dist/TimeOut.html (open it directly, email it, AirDrop it)
    python3 build.py --artifact -> dist/TimeOut-artifact.html (page body only, for claude.ai publishing)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
src = (ROOT / "index.html").read_text()


def inline_css(match):
    href = match.group(1)
    if href.startswith("http"):
        return match.group(0)
    return f"<style>\n{(ROOT / href).read_text()}\n</style>"


def inline_js(match):
    return f"<script>\n{(ROOT / match.group(1)).read_text()}\n</script>"


out = re.sub(r'<link rel="stylesheet" href="([^"]+)">', inline_css, src)
out = re.sub(r'<script src="([^"]+)"></script>', inline_js, out)

artifact = "--artifact" in sys.argv
if artifact:
    # The claude.ai viewer supplies the doctype, head and body, so keep only what goes inside them.
    head = re.search(r"<head>(.*?)</head>", out, re.S).group(1)
    body = re.search(r"<body>(.*?)</body>", out, re.S).group(1)
    head = re.sub(r"<meta[^>]*>\n?", "", head)
    out = head.strip() + "\n" + body.strip() + "\n"

dist = ROOT / "dist"
dist.mkdir(exist_ok=True)
name = "TimeOut-artifact.html" if artifact else "TimeOut.html"
(dist / name).write_text(out)
print(f"Wrote {dist / name} ({len(out) // 1024} KB)")
