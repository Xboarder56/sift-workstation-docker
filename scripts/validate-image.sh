#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-${IMAGE:-sift-workstation:latest}}"

docker run --rm -e SIFT_VALIDATE_IMAGE_STATE=true "${IMAGE}" /opt/dfir/validation/validate-container.sh
