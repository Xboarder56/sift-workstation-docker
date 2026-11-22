#!/usr/bin/env bash
# Runtime smoke test for a built image: starts real containers and logs in
# over SSH (password + key) and, for the desktop variant, over RDP.
#
# Usage: scripts/smoke-test.sh IMAGE [server|desktop]
#   SMOKE_OUT_DIR   if set, the RDP desktop screenshot is written here
#   READY_TIMEOUT_S seconds to wait for services (default 120)
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh IMAGE [server|desktop]}"
VARIANT="${2:-server}"
READY_TIMEOUT_S="${READY_TIMEOUT_S:-120}"
SIFT_USER="${SIFT_USER:-sansforensics}"
CLIENT_IMAGE="sift-smoke-client:local"
RUN_ID="$$-${RANDOM}"
NET="sift-smoke-${RUN_ID}"
A="sift-smoke-a-${RUN_ID}"
B="sift-smoke-b-${RUN_ID}"
C="sift-smoke-c-${RUN_ID}"
PASSWORD="smoke-${RANDOM}-${RANDOM}-pass"
WORK="$(mktemp -d)"
OUT_DIR="${SMOKE_OUT_DIR:-${WORK}/out}"
mkdir -p "${OUT_DIR}"

case "${VARIANT}" in server|desktop) ;; *) echo "variant must be server or desktop" >&2; exit 2 ;; esac

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

cleanup() {
  local rc=$?
  if [[ ${rc} -ne 0 ]]; then
    for c in "${A}" "${B}" "${C}"; do
      echo "::group::logs ${c}"; docker logs "${c}" 2>&1 | tail -n 80 || true; echo "::endgroup::"
    done
    docker exec "${A}" sh -c 'tail -n 60 /var/log/xrdp-sesman.log /var/log/xrdp.log 2>/dev/null' || true
  fi
  docker rm -f "${A}" "${B}" "${C}" >/dev/null 2>&1 || true
  docker network rm "${NET}" >/dev/null 2>&1 || true
  rm -rf "${WORK}" 2>/dev/null || true
  exit "${rc}"
}
trap cleanup EXIT

echo "--- Build smoke-test client image ---"
docker build -q -t "${CLIENT_IMAGE}" - >/dev/null <<'EOF'
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-client sshpass freerdp2-x11 xvfb xauth x11-apps imagemagick ca-certificates \
    && rm -rf /var/lib/apt/lists/*
EOF

client() {
  # --init: xvfb-run hangs waiting for Xvfb's ready signal when it is PID 1.
  docker run --rm --init --network "${NET}" -v "${WORK}:/work" -v "${OUT_DIR}:/out" "${CLIENT_IMAGE}" "$@"
}

echo "--- Start containers (${VARIANT}) ---"
docker network create "${NET}" >/dev/null
client ssh-keygen -q -t ed25519 -N '' -f /work/id_smoke
docker run -d --name "${A}" --network "${NET}" --network-alias sift-a \
  -e SIFT_PASSWORD="${PASSWORD}" \
  -e SIFT_AUTHORIZED_KEYS="$(cat "${WORK}/id_smoke.pub")" \
  "${IMAGE}" >/dev/null
# B keeps the image default password (the desktop requires an explicit opt-in).
docker run -d --name "${B}" --network "${NET}" --network-alias sift-b \
  -e SIFT_ALLOW_DEFAULT_PASSWORD=true "${IMAGE}" >/dev/null
# C is keys-only: SSH password auth off and no password set.
docker run -d --name "${C}" --network "${NET}" --network-alias sift-c \
  -e SIFT_SSH_PASSWORD_AUTH=no -e SIFT_ENABLE_XRDP=false \
  -e SIFT_AUTHORIZED_KEYS="$(cat "${WORK}/id_smoke.pub")" \
  "${IMAGE}" >/dev/null

wait_port() {
  local host="$1" port="$2" deadline=$(( $(date +%s) + READY_TIMEOUT_S ))
  while (( $(date +%s) < deadline )); do
    if client bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then return 0; fi
    sleep 2
  done
  fail "${host}:${port} not reachable within ${READY_TIMEOUT_S}s"
}
wait_port sift-a 22
wait_port sift-b 22
wait_port sift-c 22
if [[ "${VARIANT}" == desktop ]]; then wait_port sift-a 3389; wait_port sift-b 3389; fi
pass "services are listening"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR)

echo "--- SSH ---"
who="$(client sshpass -p "${PASSWORD}" ssh "${SSH_OPTS[@]}" -o PubkeyAuthentication=no "${SIFT_USER}@sift-a" 'id -un')"
[[ "${who}" == "${SIFT_USER}" ]] || fail "password login returned '${who}'"
pass "password login with SIFT_PASSWORD"

if client sshpass -p forensics ssh "${SSH_OPTS[@]}" -o PubkeyAuthentication=no "${SIFT_USER}@sift-a" true 2>/dev/null; then
  fail "image default password still works after SIFT_PASSWORD was set"
fi
pass "default password rejected when SIFT_PASSWORD is set"

out="$(client ssh "${SSH_OPTS[@]}" -o BatchMode=yes -i /work/id_smoke "${SIFT_USER}@sift-a" 'sudo -n true && echo sudo-ok')"
[[ "${out}" == "sudo-ok" ]] || fail "key login / sudo failed: '${out}'"
pass "key login with SIFT_AUTHORIZED_KEYS and passwordless sudo"

fp_a="$(client sh -c 'ssh-keyscan -t ed25519 sift-a 2>/dev/null | ssh-keygen -lf -' | awk '{print $2}')"
fp_b="$(client sh -c 'ssh-keyscan -t ed25519 sift-b 2>/dev/null | ssh-keygen -lf -' | awk '{print $2}')"
[[ -n "${fp_a}" && -n "${fp_b}" ]] || fail "could not read SSH host keys"
[[ "${fp_a}" != "${fp_b}" ]] || fail "two containers share the same SSH host key (${fp_a})"
pass "SSH host keys are unique per container"

# Capture first: `docker logs | grep -q` fails under pipefail (SIGPIPE).
logs_b="$(docker logs "${B}" 2>&1)"
[[ "${logs_b}" == *'still uses the image default password'* ]] \
  || fail "no default-password warning without SIFT_PASSWORD"
pass "default-password warning is logged"

out="$(client ssh "${SSH_OPTS[@]}" -o BatchMode=yes -i /work/id_smoke "${SIFT_USER}@sift-c" 'echo key-ok')"
[[ "${out}" == "key-ok" ]] || fail "keys-only container: key login failed"
if client sshpass -p forensics ssh "${SSH_OPTS[@]}" -o PubkeyAuthentication=no "${SIFT_USER}@sift-c" true 2>/dev/null; then
  fail "keys-only container accepted an SSH password"
fi
shadow_c="$(docker exec "${C}" getent shadow "${SIFT_USER}" | cut -d: -f2)"
[[ "${shadow_c}" == "*" ]] || fail "keys-only container left a usable password hash"
pass "keys-only mode: key login works, default password disabled"

mid_a="$(docker exec "${A}" cat /etc/machine-id)"
mid_b="$(docker exec "${B}" cat /etc/machine-id)"
[[ -n "${mid_a}" && "${mid_a}" != "${mid_b}" ]] || fail "machine-id is empty or shared between containers"
pass "machine-id is unique per container"

if docker run --rm -e SIFT_PASSWORD=$'pw\nroot:injected' "${IMAGE}" >"${WORK}/nl.log" 2>&1; then
  fail "a multi-line SIFT_PASSWORD was accepted"
fi
grep -q 'must be a single line' "${WORK}/nl.log" || fail "multi-line password not rejected with a clear error"
pass "multi-line passwords are rejected"

baked="$(docker run --rm "${IMAGE}" sh -c 'ls /etc/ssh/ssh_host_*_key /etc/xrdp/key.pem 2>/dev/null | wc -l')"
[[ "${baked}" == "0" ]] || fail "one-shot container has baked private keys"
who="$(docker run --rm "${IMAGE}" id -un)"
[[ "${who}" == "root" ]] || fail "one-shot command ran as '${who}', expected root (unchanged behavior)"
pass "one-shot commands pass through without starting services"

if [[ "${VARIANT}" == desktop ]]; then
  echo "--- RDP ---"
  if docker run --rm -e SIFT_ENABLE_SSH=false "${IMAGE}" >"${WORK}/nopw.log" 2>&1; then
    fail "desktop started xrdp without a password"
  fi
  grep -q 'RDP desktop needs a password' "${WORK}/nopw.log" || fail "desktop without password: unclear error"
  pass "desktop refuses to start RDP with the default password"

  xrdp_user="$(docker exec "${A}" ps -o user= -C xrdp | sort -u | xargs)"
  [[ "${xrdp_user}" == "xrdp" ]] || fail "xrdp runs as '${xrdp_user}', expected the unprivileged xrdp user"
  pass "xrdp runs as the unprivileged xrdp user"

  # Positive control first, so the negative check below cannot pass merely
  # because the client could not connect at all. (+auth-only only checks
  # connection negotiation with xrdp; real logins are tested further down.)
  client timeout 60 xvfb-run -a xfreerdp /v:sift-a /u:"${SIFT_USER}" /p:"${PASSWORD}" \
      /sec:tls /cert:ignore +auth-only /log-level:OFF >/dev/null 2>&1 \
    || fail "TLS RDP negotiation failed (control for the legacy-security check)"
  if client timeout 60 xvfb-run -a xfreerdp /v:sift-a /u:"${SIFT_USER}" /p:"${PASSWORD}" \
      /sec:rdp /cert:ignore +auth-only /log-level:OFF >/dev/null 2>&1; then
    fail "xrdp accepted legacy (non-TLS) RDP security"
  fi
  pass "legacy non-TLS RDP security is refused"

  cert_a="$(docker exec "${A}" sha256sum /etc/xrdp/cert.pem | awk '{print $1}')"
  cert_b="$(docker exec "${B}" sha256sum /etc/xrdp/cert.pem | awk '{print $1}')"
  [[ "${cert_a}" != "${cert_b}" ]] || fail "two containers share the same xrdp TLS certificate"
  pass "xrdp TLS certificates are unique per container"

  rdp_login() {
    local shot="$1"
    client timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" bash -c "
      xfreerdp /v:sift-a /u:${SIFT_USER} /p:'${PASSWORD}' /cert:ignore /size:1280x800 /log-level:OFF 2>/dev/null &
      rdp=\$!
      sleep 60
      xwd -root -silent | convert xwd:- /out/${shot}
      kill \$rdp 2>/dev/null || true
      wait \$rdp 2>/dev/null || true
    " || true
    docker exec "${A}" pgrep -u "${SIFT_USER}" -x gnome-shell >/dev/null \
      || fail "RDP login did not start a GNOME Shell session"
    if docker exec "${A}" pgrep -u "${SIFT_USER}" -f gnome-session-failed >/dev/null; then
      fail "GNOME session failed to start (\"Oh no! Something has gone wrong\")"
    fi
  }
  rdp_login rdp-desktop.png
  pass "RDP login starts a GNOME desktop session"

  echo "--- Restart ---"
  docker restart "${A}" >/dev/null
  wait_port sift-a 22
  wait_port sift-a 3389
  fp_a2="$(client sh -c 'ssh-keyscan -t ed25519 sift-a 2>/dev/null | ssh-keygen -lf -' | awk '{print $2}')"
  [[ "${fp_a2}" == "${fp_a}" ]] || fail "SSH host key changed across a container restart"
  rdp_login rdp-desktop-after-restart.png
  pass "after restart: same host key, RDP desktop works again"
  if [[ -s "${OUT_DIR}/rdp-desktop.png" ]]; then echo "  screenshot: ${OUT_DIR}/rdp-desktop.png"; fi
fi

echo "--- Smoke test PASSED (${VARIANT}) ---"
