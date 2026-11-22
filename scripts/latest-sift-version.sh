#!/usr/bin/env bash
# Print the latest teamdfir/sift-saltstack release tag (e.g. v2026.10.19).
#
# Uses GITHUB_TOKEN or GH_TOKEN when set: unauthenticated GitHub API calls are
# limited to 60/hour per IP, which shared CI runners regularly exhaust (403).
set -euo pipefail

url="https://api.github.com/repos/teamdfir/sift-saltstack/releases/latest"
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "${token}" ]]; then
  headers+=(-H "Authorization: Bearer ${token}")
fi

body=""
for attempt in 1 2 3 4 5; do
  if body="$(curl -fsSL --retry 3 --retry-delay 5 --retry-all-errors "${headers[@]}" "${url}")"; then
    break
  fi
  body=""
  echo "GitHub API request failed (attempt ${attempt}/5); retrying" >&2
  sleep $(( attempt * 10 ))
done
[[ -n "${body}" ]] || { echo "Unable to query ${url}" >&2; exit 1; }

tag="$(jq -r '.tag_name // empty' <<<"${body}")"
if [[ -z "${tag}" ]]; then
  echo "Latest release did not include tag_name" >&2
  exit 1
fi
if [[ ! "${tag}" =~ ^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "Unexpected SIFT release tag format: ${tag}" >&2
  exit 1
fi
printf '%s\n' "${tag}"
