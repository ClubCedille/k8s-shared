#!/usr/bin/env python3
"""Computes SHA256/SHA1/MD5 for every regular file under a directory tree in
a single read pass per file, writing a .checksums.json sidecar into each
directory that contains files. Upstream only publishes SHA256 (ISOs) or
SHA256+MD5 (cloud images), inconsistently -- computing all three ourselves
keeps the mirror's checksum data uniform across every distro/artifact type.

Usage: compute_checksums.py <root-dir>
"""
import hashlib
import json
import os
import sys

CHUNK_SIZE = 8 * 1024 * 1024


def hash_file(path):
    sha256, sha1, md5 = hashlib.sha256(), hashlib.sha1(), hashlib.md5()
    with open(path, "rb") as f:
        while chunk := f.read(CHUNK_SIZE):
            sha256.update(chunk)
            sha1.update(chunk)
            md5.update(chunk)
    return {"sha256": sha256.hexdigest(), "sha1": sha1.hexdigest(), "md5": md5.hexdigest()}


def main():
    root = sys.argv[1]
    for dirpath, _dirnames, filenames in os.walk(root):
        real_files = sorted(f for f in filenames if not f.startswith("."))
        if not real_files:
            continue
        checksums = {name: hash_file(os.path.join(dirpath, name)) for name in real_files}
        with open(os.path.join(dirpath, ".checksums.json"), "w", encoding="utf-8") as out:
            json.dump(checksums, out)
        print(f"hashed {len(real_files)} file(s) in {dirpath}", file=sys.stderr)


if __name__ == "__main__":
    main()
