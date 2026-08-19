#!/usr/bin/env python3
"""Renders a static, styled index.html for every "folder" in the mirror
bucket, using RGW's flat key listing (there are no real directories) to
reconstruct a tree from the "/" separators in object keys.

Run after any sync job has pushed its files. Reads the full recursive
listing via `rclone lsjson`, writes one index.html per directory level
(including the bucket root) to LOCAL_OUT, then the caller is expected to
`rclone copy` LOCAL_OUT back to the bucket.
"""
import html
import json
import os
import subprocess
import sys
from pathlib import PurePosixPath

BUCKET = os.environ["BUCKET_NAME"]
LOCAL_OUT = os.environ.get("INDEX_OUT_DIR", "/tmp/rendered-index")
STYLE_PATH = os.environ.get("STYLE_PATH", "/opt/tooling/style.css")
MIRROR_TITLE = "Cedille distro mirror"


def human_size(n):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


def list_objects():
    out = subprocess.run(
        ["rclone", "lsjson", "--recursive", f"s3:{BUCKET}", "--s3-no-check-bucket"],
        capture_output=True, check=True, text=True,
    ).stdout
    return json.loads(out)


SKIP_NAMES = {"index.html", ".checksums.json"}


def build_tree(objects):
    # dirs[path] = {"dirs": {name: subpath}, "files": [(name, size, modtime)], "checksums_path": str|None}
    dirs = {"": {"dirs": {}, "files": [], "checksums_path": None}}

    def ensure_dir(path):
        if path not in dirs:
            dirs[path] = {"dirs": {}, "files": [], "checksums_path": None}
            parent = str(PurePosixPath(path).parent)
            parent = "" if parent == "." else parent
            ensure_dir(parent)
            dirs[parent]["dirs"][PurePosixPath(path).name] = path
        return dirs[path]

    for obj in objects:
        if obj.get("IsDir"):
            continue
        path = PurePosixPath(obj["Path"])
        parent = str(path.parent)
        parent = "" if parent == "." else parent
        ensure_dir(parent)
        if path.name == ".checksums.json":
            dirs[parent]["checksums_path"] = obj["Path"]
        elif path.name not in SKIP_NAMES:
            dirs[parent]["files"].append((path.name, obj["Size"], obj.get("ModTime", "")))

    return dirs


def load_checksums(path):
    if path is None:
        return {}
    out = subprocess.run(
        ["rclone", "cat", f"s3:{BUCKET}/{path}", "--s3-no-check-bucket"],
        capture_output=True, check=True, text=True,
    ).stdout
    return json.loads(out)


CHECKSUM_ALGOS = ("sha256", "sha1", "md5")


def checksum_cells(checksums, name):
    entry = checksums.get(name)
    return "".join(
        f'<td class="checksum">{html.escape(entry[algo])}</td>' if entry else '<td class="checksum">-</td>'
        for algo in CHECKSUM_ALGOS
    )


def render(dir_path, entry, style_css):
    breadcrumb_parts = [p for p in dir_path.split("/") if p]
    crumbs = ['<a href="/">root</a>']
    acc = ""
    for part in breadcrumb_parts:
        acc += part + "/"
        crumbs.append(f'<a href="/{html.escape(acc)}">{html.escape(part)}</a>')
    breadcrumb = ' <span class="sep">/</span> '.join(crumbs)

    checksums = load_checksums(entry["checksums_path"])
    empty_checksum_cells = '<td class="checksum">-</td>' * len(CHECKSUM_ALGOS)

    rows = []
    if dir_path:
        parent = str(PurePosixPath(dir_path).parent)
        parent_href = "/" if parent in (".", "") else f"/{parent}/"
        rows.append(
            f'<tr><td><a class="icon-dir" href="{html.escape(parent_href)}">..</a></td>'
            f'<td class="size">-</td><td>-</td>{empty_checksum_cells}</tr>'
        )

    for name in sorted(entry["dirs"]):
        href = f"/{dir_path}/{name}/" if dir_path else f"/{name}/"
        rows.append(
            f'<tr><td><a class="icon-dir" href="{html.escape(href)}">{html.escape(name)}/</a></td>'
            f'<td class="size">-</td><td>-</td>{empty_checksum_cells}</tr>'
        )

    for name, size, modtime in sorted(entry["files"]):
        href = f"/{dir_path}/{name}" if dir_path else f"/{name}"
        modtime_short = modtime[:19].replace("T", " ")
        rows.append(
            f'<tr><td><a class="icon-file" href="{html.escape(href)}">{html.escape(name)}</a></td>'
            f'<td class="size">{human_size(size)}</td><td>{html.escape(modtime_short)}</td>'
            f'{checksum_cells(checksums, name)}</tr>'
        )

    title = f"/{dir_path}/" if dir_path else "/"
    checksum_headers = "".join(f'<th class="checksum">{algo.upper()}</th>' for algo in CHECKSUM_ALGOS)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} — {html.escape(MIRROR_TITLE)}</title>
<style>{style_css}</style>
</head>
<body>
<div class="wrap">
<h1>{html.escape(MIRROR_TITLE)}</h1>
<div class="breadcrumb">{breadcrumb}</div>
<div class="toolbar"><button type="button" onclick="document.getElementById('listing').classList.toggle('show-checksums')">Toggle checksums</button></div>
<div class="table-scroll">
<table id="listing">
<thead><tr><th>Name</th><th class="size">Size</th><th>Last modified</th>{checksum_headers}</tr></thead>
<tbody>
{''.join(rows) if rows else f'<tr><td colspan="{3 + len(CHECKSUM_ALGOS)}" class="muted">Empty</td></tr>'}
</tbody>
</table>
</div>
<footer>Generated by the distro-mirror sync CronJobs.</footer>
</div>
</body>
</html>
"""


def main():
    style_css = open(STYLE_PATH, encoding="utf-8").read()
    objects = list_objects()
    dirs = build_tree(objects)

    for dir_path, entry in dirs.items():
        out_path = os.path.join(LOCAL_OUT, dir_path, "index.html") if dir_path else os.path.join(LOCAL_OUT, "index.html")
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(render(dir_path, entry, style_css))

    print(f"Rendered {len(dirs)} index.html file(s) under {LOCAL_OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
