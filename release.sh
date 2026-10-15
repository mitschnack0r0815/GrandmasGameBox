#!/usr/bin/env bash
# Builds SchiffeVersenken-<version>.zip from the version in the .toc.
# The zip holds the addon folder, ready to unzip into Interface/AddOns.
set -euo pipefail
cd "$(dirname "$0")"

version=$(sed -n 's/^## Version: *//p' SchiffeVersenken.toc | tr -d '\r')
[ -n "$version" ] || { echo "No ## Version in SchiffeVersenken.toc" >&2; exit 1; }

rm -f SchiffeVersenken-*.zip
python3 - "$version" <<'PY'
import os, sys, zipfile
version = sys.argv[1]
os.chdir("..")
skip_files = {".gitignore", "release.sh"}
with zipfile.ZipFile(f"SchiffeVersenken/SchiffeVersenken-{version}.zip", "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk("SchiffeVersenken"):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for f in sorted(files):
            if f not in skip_files and not f.endswith(".zip"):
                z.write(os.path.join(root, f))
PY
echo "Built SchiffeVersenken-$version.zip"
