#!/usr/bin/env bash
set -euo pipefail

SIFT_USER="${SIFT_USER:-sansforensics}"
SIFT_VARIANT="${SIFT_VARIANT:-$(cat /etc/sift-image-variant 2>/dev/null || echo unknown)}"
# Set to true when validating the image filesystem itself (build time / fresh
# `docker run --rm IMAGE validate-container.sh`), not a running container
# whose entrypoint has already created per-container secrets.
SIFT_VALIDATE_IMAGE_STATE="${SIFT_VALIDATE_IMAGE_STATE:-false}"

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
require_command tini
require_command ssh-keygen

require_path /usr/local/bin/sift-entrypoint

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

if [[ "${SIFT_VALIDATE_IMAGE_STATE}" == "true" ]]; then
  # Per-container secrets must never be baked into the published image.
  for key in /etc/ssh/ssh_host_*_key /etc/xrdp/key.pem /etc/ssl/private/ssl-cert-snakeoil.key; do
    if [[ -e "${key}" ]]; then
      failures+=("image contains a shared private key: ${key}")
    fi
  done
fi

case "${SIFT_VARIANT}" in
  server) ;;
  desktop)
    require_command xrdp
    require_command xrdp-sesman
    require_command gnome-session
    require_command gnome-shell
    require_command gnome-terminal
    require_command nautilus
    require_command dbus-daemon
    require_path /usr/lib/xorg/modules/libxorgxrdp.so
    require_path /etc/xrdp/startwm.sh
    require_path /usr/share/gnome-session/sessions/sift.session
    if grep -q 'SettingsDaemon.Power' /usr/share/gnome-session/sessions/sift.session 2>/dev/null; then
      failures+=("sift GNOME session still requires gsd-power (needs logind)")
    fi
    if [[ -e /run/systemd/seats ]]; then
      failures+=("/run/systemd/seats exists; GNOME Shell would require logind")
    fi
    require_path /usr/share/backgrounds/sift.png
    require_path /etc/dconf/db/local
    if [[ -e /etc/xrdp/startwm.sh ]] && ! grep -q 'gnome-session --session=sift' /etc/xrdp/startwm.sh; then
      failures+=("xrdp startwm.sh does not start the Ubuntu GNOME session")
    fi
    if ! grep -qx 'allowed_users=anybody' /etc/X11/Xwrapper.config 2>/dev/null; then
      failures+=("Xwrapper.config does not allow xrdp Xorg sessions")
    fi
    for entry in magnus-autostart orca-autostart onboard-autostart xscreensaver; do
      f="/etc/xdg/autostart/${entry}.desktop"
      if [[ -f "${f}" ]] && ! grep -qx 'Hidden=true' "${f}"; then
        failures+=("desktop autostart entry is not hidden: ${f}")
      fi
    done
    if ! id -nG xrdp 2>/dev/null | grep -qw ssl-cert; then
      failures+=("xrdp user is not in the ssl-cert group")
    fi
    ;;
  *) failures+=("unknown image variant: ${SIFT_VARIANT}") ;;
esac

if (( ${#failures[@]} > 0 )); then
  printf 'Container contract validation failed:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Container contract validation passed."
echo "Checked Docker-layer additions only; SIFT tool validation is owned by Cast/Salt."
echo
echo "Runtime probes:"
printf '  - variant: %s\n' "${SIFT_VARIANT}"
printf '  - user: '
id "${SIFT_USER}"
printf '  - cast: '
cast --version
printf '  - python: '
python3 --version
printf '  - sshd: '
# sshd -T needs host keys; probe with a throwaway key so this works on a
# fresh image without creating persistent keys.
probe_key="$(mktemp -u)"
ssh-keygen -q -t ed25519 -N '' -f "${probe_key}"
sshd -T -h "${probe_key}" | awk '/^port / { print }'
rm -f "${probe_key}" "${probe_key}.pub"
if [[ "${SIFT_VARIANT}" == "desktop" ]]; then
  printf '  - xrdp: '
  xrdp --version 2>&1 | head -n1
fi
