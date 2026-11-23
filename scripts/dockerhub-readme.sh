#!/usr/bin/env bash
# Print the Docker Hub description: the user-facing part of README.md (up to
# "## Building from source", which is contributor material), plus a footer
# linking to the full documentation. Docker Hub limits the description to
# 25,000 bytes and doesn't resolve relative links, so generating it from the
# README keeps Hub as detailed as GitHub without a second copy to maintain.
#
#   scripts/dockerhub-readme.sh > /tmp/dockerhub.md
set -euo pipefail
cd "$(dirname "$0")/.."

repo_url="https://github.com/xboarder56/sift-workstation-docker"

awk '
  /^## Building from source[[:space:]]*$/ { exit }
  { lines[++n] = $0 }
  END {
    # Drop the trailing separator and blank lines before the cut.
    while (n > 0 && (lines[n] ~ /^[[:space:]]*$/ || lines[n] == "---")) n--
    for (i = 1; i <= n; i++) print lines[i]
  }
' README.md

cat <<FOOTER

---

## More

- **Full documentation**, including building from source, image validation and the CI/CD pipeline: [GitHub README](${repo_url}#readme)
- **Source, issues and releases:** [${repo_url#https://}](${repo_url})
- Images are built from the upstream [teamdfir/sift-saltstack](https://github.com/teamdfir/sift-saltstack) releases and published to GHCR and Docker Hub with identical tags and digests, after automated SSH and RDP tests on amd64 and arm64.
FOOTER
