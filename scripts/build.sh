#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-sift-workstation}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
BASE_IMAGE="${BASE_IMAGE:-ubuntu:${UBUNTU_VERSION}}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
CAST_VERSION="${CAST_VERSION:-1.0.13}"
IMAGE_VERSION="${IMAGE_VERSION:-${IMAGE_TAG}}"
GIT_COMMIT="${GIT_COMMIT:-$(git -C "${CONTEXT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
IMAGE_SOURCE="${IMAGE_SOURCE:-https://github.com/xboarder56/sift-workstation-docker}"
IMAGE_DOCUMENTATION="${IMAGE_DOCUMENTATION:-https://github.com/xboarder56/sift-workstation-docker#readme}"
IMAGE_URL="${IMAGE_URL:-https://github.com/xboarder56/sift-workstation-docker}"
IMAGE_AUTHORS="${IMAGE_AUTHORS:-xboarder56}"
SIFT_VERSION="${SIFT_VERSION:-latest}"
SIFT_TARGET="${SIFT_TARGET:-sift}"
SIFT_MODE="${SIFT_MODE:-server}"
RUN_VALIDATION="${RUN_VALIDATION:-false}"
NO_CACHE="${NO_CACHE:-false}"
PROGRESS="${PROGRESS:-auto}"
DRY_RUN="${DRY_RUN:-false}"

args=(
  docker buildx build
  --file "${CONTEXT_DIR}/Dockerfile"
  --platform "${PLATFORMS}"
  --progress "${PROGRESS}"
  --build-arg "BASE_IMAGE=${BASE_IMAGE}"
  --build-arg "BUILD_DATE=${BUILD_DATE}"
  --build-arg "GIT_COMMIT=${GIT_COMMIT}"
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}"
  --build-arg "IMAGE_SOURCE=${IMAGE_SOURCE}"
  --build-arg "IMAGE_DOCUMENTATION=${IMAGE_DOCUMENTATION}"
  --build-arg "IMAGE_URL=${IMAGE_URL}"
  --build-arg "IMAGE_AUTHORS=${IMAGE_AUTHORS}"
  --build-arg "CAST_VERSION=${CAST_VERSION}"
  --build-arg "SIFT_VERSION=${SIFT_VERSION}"
  --build-arg "SIFT_TARGET=${SIFT_TARGET}"
  --build-arg "SIFT_MODE=${SIFT_MODE}"
  --build-arg "RUN_VALIDATION=${RUN_VALIDATION}"
  --tag "${IMAGE_NAME}:${IMAGE_TAG}"
)

if [[ "${NO_CACHE}" == "true" ]]; then
  args+=(--no-cache)
fi

if [[ "${PUSH:-false}" == "true" ]]; then
  args+=(--push)
elif [[ "${LOAD:-true}" == "true" ]]; then
  args+=(--load)
fi

args+=("${CONTEXT_DIR}")

if [[ "${DRY_RUN}" == "true" ]]; then
  printf '%q ' "${args[@]}"
  printf '\n'
  exit 0
fi

exec "${args[@]}"
