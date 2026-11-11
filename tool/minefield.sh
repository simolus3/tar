#!/bin/sh
set -e

rm -f reference/minefield/*.tar
rm -f reference/minefield/*.json

REF=e3060bda2a54631c37d088914a24dddac34e7360

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Shallow-clone just the pinned commit, we might switch this to downloading a specific release in the future
git -C "$TMP" init --quiet
git -C "$TMP" remote add origin https://github.com/haampie/tar-minefield.git
git -C "$TMP" fetch --quiet --depth 1 origin "$REF"
git -C "$TMP" checkout --quiet FETCH_HEAD

mv "$TMP"/suite/archives/*.tar "$TMP"/suite/archives/*.json reference/minefield/
