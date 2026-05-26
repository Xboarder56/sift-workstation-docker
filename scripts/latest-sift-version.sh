#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import urllib.request

url = "https://api.github.com/repos/teamdfir/sift-saltstack/releases/latest"
with urllib.request.urlopen(url) as response:
    release = json.load(response)

tag = release.get("tag_name")
if not tag:
    raise SystemExit("latest release did not include tag_name")

print(tag)
PY
