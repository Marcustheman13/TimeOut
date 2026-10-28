#!/usr/bin/env python3
"""Bundles the TimeOut web demo into self-contained HTML files.

    python3 build.py            -> dist/TimeOut.html          (the whole site in one file: open it directly, email it, AirDrop it)
    python3 build.py --artifact -> dist/TimeOut-artifact.html (page body only, for claude.ai publishing)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
# Source page -> bundled file. web.html only forwards old links to index.html, so it isn't bundled.
PAGES = {"index.html": "TimeOut.html"}


def inline_css(match):
    href = match.group(1)
    if href.startswith("http"):
        return match.group(0)
    return f"<style>\n{(ROOT / href).read_text()}\n</style>"


def inline_js(match):
    return f"<script>\n{(ROOT / match.group(1)).read_text()}\n</script>"


def bundle(page):
    out = (ROOT / page).read_text()
    out = re.sub(r'<link rel="stylesheet" href="([^"]+)">', inline_css, out)
    out = re.sub(r'<script src="([^"]+)"></script>', inline_js, out)
    for src, dst in PAGES.items():
        out = out.replace(f'href="{src}"', f'href="{dst}"')
    return out


dist = ROOT / "dist"
dist.mkdir(exist_ok=True)

if "--artifact" in sys.argv:
    # The claude.ai viewer supplies the doctype, head and body, so keep only what goes inside them.
    out = bundle("index.html")
    head = re.search(r"<head>(.*?)</head>", out, re.S).group(1)
    body = re.search(r"<body[^>]*>(.*?)</body>", out, re.S).group(1)
    # The viewer supplies its own <body>, so turn on the browser layout's .web class from script.
    body = '<script>document.body.classList.add("web");</script>\n' + body
    head = re.sub(r"<meta[^>]*>\n?", "", head)
    builds = {"TimeOut-artifact.html": head.strip() + "\n" + body.strip() + "\n"}
else:
    builds = {dst: bundle(src) for src, dst in PAGES.items()}

for name, out in builds.items():
    (dist / name).write_text(out)
    print(f"Wrote {dist / name} ({len(out) // 1024} KB)")
