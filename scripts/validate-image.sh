#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-${IMAGE:-sift-workstation:latest}}"

docker run --rm "${IMAGE}" /opt/dfir/validation/validate-container.sh
