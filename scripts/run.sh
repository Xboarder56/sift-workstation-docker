#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-sift-workstation:latest}"
CASE_DIR="${CASE_DIR:-$(pwd)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${CASE_DIR}/artifacts}"

if [[ ! -d "${CASE_DIR}" ]]; then
  echo "CASE_DIR does not exist: ${CASE_DIR}" >&2
  exit 1
fi

if [[ ! -d "${EVIDENCE_DIR}" ]]; then
  echo "EVIDENCE_DIR does not exist: ${EVIDENCE_DIR}" >&2
  exit 1
fi

exec docker run --rm -it \
  --volume "${CASE_DIR}:/case" \
  --volume "${EVIDENCE_DIR}:/evidence:ro" \
  --workdir /case \
  "${IMAGE}" \
  "$@"
