#!/usr/bin/env bash
set -euo pipefail

SIFT_USER="${SIFT_USER:-sansforensics}"

failures=()

require_path() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    failures+=("missing path: ${path}")
  fi
}

require_dir() {
  local path="$1"
  if [[ ! -d "${path}" ]]; then
    failures+=("missing directory: ${path}")
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    failures+=("missing command: ${command_name}")
  fi
}

require_user() {
  local user_name="$1"
  if ! id "${user_name}" >/dev/null 2>&1; then
    failures+=("missing user: ${user_name}")
  fi
}

require_user "${SIFT_USER}"
require_command cast
require_command sshd
require_command sudo
require_command python3

require_dir "/home/${SIFT_USER}"
require_dir /case
require_dir /evidence
require_dir /run/sshd
require_dir /opt/dfir/validation
require_dir /mnt/aff
require_dir /mnt/bde
require_dir /mnt/e01
require_dir /mnt/ewf
require_dir /mnt/ewf_mount
require_dir /mnt/iscsi
require_dir /mnt/shadow_mount
require_dir /mnt/usb
require_dir /mnt/vss
require_dir /mnt/windows_mount
require_dir /mnt/windows_mount1
require_dir /mnt/shadow_mount/vss1

require_path "/home/${SIFT_USER}/.Xauthority"
require_path /etc/sudoers.d/sift-user

if [[ -e /etc/ssh/sshd_config ]]; then
  for setting in \
    "UseDNS no" \
    "GSSAPIAuthentication no" \
    "TCPKeepAlive yes" \
    "X11UseLocalhost no"; do
    if ! grep -qxF "${setting}" /etc/ssh/sshd_config; then
      failures+=("missing sshd_config setting: ${setting}")
    fi
  done
else
  failures+=("missing path: /etc/ssh/sshd_config")
fi

if [[ -e /etc/sudoers.d/sift-user ]]; then
  if ! grep -qxF "${SIFT_USER} ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/sift-user; then
    failures+=("sudoers file does not grant expected passwordless sudo")
  fi
fi

if [[ -d "/home/${SIFT_USER}" ]]; then
  owner="$(stat -c '%U:%G' "/home/${SIFT_USER}")"
  if [[ "${owner}" != "${SIFT_USER}:${SIFT_USER}" ]]; then
    failures+=("unexpected /home/${SIFT_USER} owner: ${owner}")
  fi
fi

if (( ${#failures[@]} > 0 )); then
  printf 'Container contract validation failed:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Container contract validation passed."
echo "Checked Docker-layer additions only; SIFT tool validation is owned by Cast/Salt."
echo
echo "Runtime probes:"
printf '  - user: '
id "${SIFT_USER}"
printf '  - cast: '
cast --version
printf '  - python: '
python3 --version
printf '  - sshd: '
sshd -T | awk '/^port / { print }'
