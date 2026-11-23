# SIFT Workstation Docker

A containerized build of the SANS SIFT Workstation forensics environment.
Built from the upstream `teamdfir/sift-saltstack` release via Cast, on
Ubuntu 24.04. Multi-arch images for `linux/amd64` and `linux/arm64`.

The goal is a reproducible, scriptable SIFT environment for evidence
processing in CI/CD and on workstations where the full SIFT VM is
impractical. Two variants are published:

| Variant | Tag | Access |
| --- | --- | --- |
| Server | `latest`, `vYYYY.MM.DD` | Shell / one-shot commands, SSH (port 22) |
| Desktop | `desktop`, `vYYYY.MM.DD-desktop` | Everything in server, plus the SIFT GNOME desktop over RDP (port 3389) |

## Quick start

Pull from GHCR (preferred):

```bash
docker pull ghcr.io/xboarder56/sift-workstation:latest
```

Or from Docker Hub:

```bash
docker pull xboarder56/sift-workstation:latest
```

Run an interactive shell against a case directory:

```bash
docker run --rm -it \
  -v "$PWD/case:/case" \
  -v "$PWD/evidence:/evidence:ro" \
  ghcr.io/xboarder56/sift-workstation:latest bash
```

One-shot commands (like `bash` above) run directly as `root`, exactly as in
earlier images; no services are started. The SIFT user is `sansforensics`
with passwordless sudo, and the full SIFT tooling is on the PATH.

## Desktop over RDP

The `desktop` image adds the Ubuntu GNOME desktop that a stock SIFT
Workstation uses, served by [xrdp](https://www.xrdp.org/): Yaru theme, the
SIFT wallpaper, and the Ubuntu dock at the bottom with Terminal, Files, and
Text Editor pinned. It works out of the box with any RDP client (Windows
Remote Desktop / `mstsc`, Microsoft Windows App on macOS, Remmina, FreeRDP):

```bash
docker run -d --name sift-desktop \
  -p 127.0.0.1:3389:3389 -p 127.0.0.1:2222:22 \
  --shm-size 1g \
  -e SIFT_PASSWORD='choose-a-strong-password' \
  -v "$PWD/cases:/cases" \
  ghcr.io/xboarder56/sift-workstation:desktop
```

Connect your RDP client to `127.0.0.1:3389` and log in as `sansforensics`
with the password you set. The desktop requires a password: without
`SIFT_PASSWORD`/`SIFT_PASSWORD_FILE` the container refuses to start RDP,
so the well-known default password is never exposed over RDP. Each container generates its own self-signed TLS
certificate on first start, so expect a certificate prompt the first time.
Sessions keep running when you disconnect. Reconnect to resume.

Notes on GNOME in a container:

- Rendering is software-only (no GPU), and animations are off by default.
  It's fine for forensic GUI tools, but not for video.
- Containers have no systemd/logind. The image uses a `sift` GNOME session
  (the Ubuntu session without the power daemon, which needs logind), and
  removes the screen lock, since xrdp handles disconnects. Session logs go
  to `~/.cache/sift-session.log`.
- The desktop session needs GNOME's X11 session, which Ubuntu 24.04 ships.
  Ubuntu 25.10 and later drop it, so the desktop variant stays on a 24.04
  base until xrdp supports Wayland sessions.
- SIFT's own Salt `desktop` mode can't be used inside a container: its
  hostname, timezone, Samba, and `gsettings` steps need systemd and a user
  D-Bus session. The image applies the same theme (wallpaper, dock, and
  favorites) as dconf system defaults instead.

For a persistent setup, use the Compose file below with `SIFT_TAG=desktop`.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | Moving: newest upstream SIFT release, server variant |
| `vYYYY.MM.DD` | Pinned to a specific upstream SIFT release, server variant |
| `desktop` | Moving: newest upstream SIFT release, desktop variant |
| `vYYYY.MM.DD-desktop` | Pinned to a specific upstream SIFT release, desktop variant |
| `sha-<commit>` / `sha-<commit>-desktop` | Pinned to a specific build of this image |

The Ubuntu base version lives in the OCI label
`org.opencontainers.image.base.name`, not the tag. When the base bumps,
`:latest` rolls forward and existing pinned tags keep their original base.

GHCR and Docker Hub publish identical tags and digests.

## Running against a case

Layout the image expects:

```text
cases/CASE_NAME/
├── artifacts/      mounted read-only at /evidence
├── working_dir/    writeable through /case/working_dir
└── output/         writeable through /case/output
```

Example Plaso run:

```bash
docker run --rm \
  -v "$PWD/cases/CASE_001:/case" \
  -v "$PWD/cases/CASE_001/artifacts:/evidence:ro" \
  ghcr.io/xboarder56/sift-workstation:latest \
  log2timeline.py --status_view none -z UTC \
    --storage_file /case/working_dir/timeline.plaso \
    /evidence/disk.E01
```

## Persistent SSH / RDP service

For VM-like use, run the container as a long-lived service via Compose:

```bash
curl -O https://raw.githubusercontent.com/xboarder56/sift-workstation-docker/main/docker-compose.example.yml
curl -O https://raw.githubusercontent.com/xboarder56/sift-workstation-docker/main/.env.example
mv docker-compose.example.yml docker-compose.yml
mv .env.example .env
mkdir -p secrets && printf '%s\n' 'choose-a-strong-password' > secrets/sift_password
chmod 600 secrets/sift_password
docker compose up -d
ssh sansforensics@127.0.0.1 -p 2222
```

Set `SIFT_TAG=desktop` in `.env` for RDP on `127.0.0.1:3389`. Edit `.env` to
change ports, the bind address, the image tag, or the cases mount.

Ports bind to `127.0.0.1` by default. Set `SIFT_BIND_ADDRESS=0.0.0.0` only
when other machines must connect, and only after setting a strong password
or SSH keys.

The compose profile runs privileged with `/dev/fuse`, `SYS_ADMIN`, and
`MKNOD` because several forensic mounting workflows need them. For
non-privileged one-shot work, use the `docker run` form above.

### Runtime settings

These environment variables are read when the container starts its services
(the default command). They have no effect on one-shot commands.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SIFT_PASSWORD` | unset | Password for `sansforensics` (SSH and RDP) |
| `SIFT_PASSWORD_FILE` | unset | Read the password from a file (Docker/Compose secret). Set only one of the two. |
| `SIFT_AUTHORIZED_KEYS` | unset | SSH public keys for `sansforensics` |
| `SIFT_AUTHORIZED_KEYS_FILE` | unset | Read SSH public keys from a file |
| `SIFT_SSH_PASSWORD_AUTH` | `yes` | `no` allows SSH key logins only. Without a password set, this also disables the default password everywhere. |
| `SIFT_ENABLE_SSH` | `true` | Run sshd |
| `SIFT_ENABLE_XRDP` | `true` | Run xrdp (desktop image only) |
| `SIFT_ALLOW_DEFAULT_PASSWORD` | `false` | Let the desktop start RDP with the default password (isolated labs only) |

If no password is provided, the server image keeps the default lab password
`forensics` active for compatibility, and logs a warning on every start.

### Security notes

- Every container generates its own SSH host keys, xrdp TLS certificate,
  xrdp RSA keys, and machine-id on first start. No key from the image is
  ever used. They persist across restarts, and recreating the container
  creates new ones, so SSH clients will warn about a changed host key.
- Change the default password with `SIFT_PASSWORD_FILE` before exposing a
  container. Alternatively, use SSH keys with `SIFT_SSH_PASSWORD_AUTH=no`
  and no password, which disables the default password entirely.
- xrdp runs as its own unprivileged `xrdp` user and only accepts TLS. Its
  VNC and RDP proxy sessions (`vnc-any`, `neutrinordp-any`) are removed, so
  the login screen can't be used to reach other hosts.
- `sansforensics` has passwordless sudo, matching a standard SIFT install.
  Treat SSH/RDP access as root access to the container.

## Privileged image mounting

E01/raw image mounting through FUSE or loop devices needs extra
capabilities. Add them only when the workflow requires kernel access:

```bash
docker run --rm -it \
  --privileged \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  -v "$PWD/case:/case" \
  -v "$PWD/evidence:/evidence:ro" \
  ghcr.io/xboarder56/sift-workstation:latest bash
```

Prefer direct image-reading tools (Plaso, SleuthKit) where possible.

---

## Building from source

This section is for contributors and forks. End users should use the
published images above.

### Local build

```bash
git clone https://github.com/xboarder56/sift-workstation-docker
cd sift-workstation-docker
./scripts/build.sh                 # server variant
TARGET=desktop ./scripts/build.sh  # desktop variant
```

Dockerfile stages: `sift` (Ubuntu + Cast + SIFT, the slow part), `runtime`
(entrypoint and per-container secret handling), `desktop` (adds GNOME and
xrdp), and `server` (the default target).

Common overrides:

```bash
# Pin a specific SIFT release
SIFT_VERSION=v2026.10.19 IMAGE_TAG=v2026.10.19 ./scripts/build.sh

# Build for arm64 only
PLATFORMS=linux/arm64 IMAGE_TAG=arm64 ./scripts/build.sh

# Iterate on the runtime/desktop layers without re-running Cast, reusing a
# published image as the `sift` stage
SIFT_STAGE_IMAGE=ghcr.io/xboarder56/sift-workstation:v2026.10.19 \
PLATFORMS=linux/arm64 TARGET=desktop IMAGE_TAG=desktop-dev ./scripts/build.sh

# Force a clean rebuild with verbose output
NO_CACHE=true PROGRESS=plain ./scripts/build.sh

# Print the build command without running it
DRY_RUN=true ./scripts/build.sh
```

Resolve the latest published SIFT release tag. This requires `curl` and
`jq`, and uses `GITHUB_TOKEN`/`GH_TOKEN` when set, to avoid GitHub's
unauthenticated rate limit:

```bash
./scripts/latest-sift-version.sh
SIFT_VERSION="$(./scripts/latest-sift-version.sh)" ./scripts/build.sh
```

Multi-arch publish to a registry:

```bash
PLATFORMS=linux/amd64,linux/arm64 \
IMAGE_NAME=ghcr.io/YOUR_ORG/sift-workstation \
IMAGE_TAG=v2026.10.19 \
PUSH=true \
LOAD=false \
./scripts/build.sh
```

### Validate an image

```bash
./scripts/validate-image.sh sift-workstation:latest
./scripts/smoke-test.sh sift-workstation:latest server
./scripts/smoke-test.sh sift-workstation:desktop desktop
```

`validate-image.sh` checks the Docker-layer contract: user creation, SSH
setup, case and evidence mount points, helper directories, sudo policy,
Cast availability, the desktop components, and that no private keys are
baked into the image.

`smoke-test.sh` starts real containers and logs in. It checks SSH password
and key logins, that the default password is rejected once a password is
set, and that host keys and TLS certificates are unique per container. For
the desktop image it also opens a real RDP session and confirms that an
GNOME Shell session starts without the GNOME failure screen. Set `SMOKE_OUT_DIR` to keep a screenshot of the
desktop.

Neither script re-validates the forensic tools themselves (Plaso,
SleuthKit, Volatility, Zimmerman). Those are owned by the upstream SIFT
Salt states.

### Build notes

On arm64, some Python packages installed by the SIFT salt states (notably
`leechcorepyc` during the Volatility3 state) lack prebuilt wheels and must
compile from source. The Dockerfile installs `build-essential`,
`libusb-1.0-0-dev`, `pkg-config`, and `python3-dev` before Cast runs to
support this. A failure mentioning `libusb.h`, `libusb-1.0.pc`, or
`-lusb-1.0` usually means those packages were not present early enough.
Force a clean rebuild:

```bash
NO_CACHE=true PROGRESS=plain \
SIFT_VERSION=v2026.10.19 \
PLATFORMS=linux/arm64 \
IMAGE_TAG=v2026.10.19-arm64 \
./scripts/build.sh
```

The Cast `.deb` is verified by SHA-256 before installation. The default
`CAST_VERSION` has its checksums pinned in the Dockerfile. Any other version
is verified against that Cast release's `checksums.txt`.

### GitHub Actions

Four workflows live in `.github/workflows/`:

- **`build.yml`** builds the server and desktop images on amd64 for every
  push and PR. It runs the image validation and the SSH/RDP smoke tests,
  and uploads a screenshot of the RDP desktop as a build artifact. Manual
  dispatch publishes multi-arch images when `publish_ghcr` and/or
  `publish_dockerhub` are toggled on. `test_pipeline` runs the full native
  multi-arch build and smoke tests without publishing any tags. Only a
  `latest` build moves the floating `latest`/`desktop` tags.
- **`release-watch.yml`** checks upstream `teamdfir/sift-saltstack` once a
  day. It publishes both variants when a new release appears, or when any
  expected tag (`vX`, `vX-desktop`) is missing from GHCR. If only Docker
  Hub is behind, it copies the GHCR tags there without rebuilding. It can
  also be run manually with `force_rebuild: true`. The `publish_dockerhub`
  input (`auto`/`true`/`false`) overrides the repository variable.
- **`publish.yml`** is the reusable publish pipeline used by both. Each
  architecture builds on a native runner (`ubuntu-24.04` and
  `ubuntu-24.04-arm`), with no QEMU emulation. Images are pushed untagged by
  digest and smoke-tested from the registry. The public multi-arch tags are
  created only after every architecture and variant passes.
- **`dockerhub-description.yml`** keeps the Docker Hub page in sync with this
  README. `scripts/dockerhub-readme.sh` takes the user-facing part (everything
  above "Building from source") and adds a footer linking back here. The
  workflow checks Docker Hub's 25,000-byte limit and rejects repository-relative
  links, which Hub can't resolve, on every PR that touches the README. It
  updates Docker Hub on `main` when `PUBLISH_DOCKERHUB=true`, which needs a token
  with read/write/delete scope. Preview locally with
  `scripts/dockerhub-readme.sh`. Keep that part of the README to absolute links.

Upstream release lookups are authenticated with the workflow's
`GITHUB_TOKEN`. Unauthenticated GitHub API calls from shared runners hit the
60 requests/hour limit and fail with HTTP 403.

For a fork to publish under its own namespace:

1. Edit the hardcoded `GHCR_IMAGE` in `publish.yml` and `release-watch.yml`,
   and the default `dockerhub_image` inputs.
2. Update the OCI URL labels in `Dockerfile` and `scripts/build.sh`.
3. Add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository **secrets** if
   you want Docker Hub publishing.
4. Set the repository **variable** (not a secret) `PUBLISH_DOCKERHUB=true` to
   enable Docker Hub from the daily release watch:
   `gh variable set PUBLISH_DOCKERHUB --body true`.

Other optional repository variables:

| Variable | Default |
| --- | --- |
| `DOCKERHUB_IMAGE` | `xboarder56/sift-workstation` |
| `UBUNTU_VERSION` | `24.04` |
| `CAST_VERSION` | `1.0.42` |
| `PUBLISH_PLATFORMS` | `linux/amd64,linux/arm64` |

### Build arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `BASE_IMAGE` | `ubuntu:24.04` | Full base image reference used by `FROM` |
| `IMAGE_VERSION` | `dev` | OCI image version label |
| `GIT_COMMIT` | current git SHA or `unknown` | OCI revision label |
| `BUILD_DATE` | current UTC time | OCI created label |
| `IMAGE_SOURCE` | repository URL | OCI source label |
| `IMAGE_DOCUMENTATION` | README URL | OCI documentation label |
| `IMAGE_URL` | repository URL | OCI URL label |
| `IMAGE_AUTHORS` | `xboarder56` | OCI authors label |
| `CAST_VERSION` | `1.0.42` | Cast release version without leading `v` |
| `CAST_SHA256_AMD64` / `CAST_SHA256_ARM64` | pinned for the default version | Expected Cast `.deb` checksums |
| `SIFT_VERSION` | `latest` | SIFT saltstack release. `latest` resolves to the current release at install time; `v2026.10.19` pins via `sift@v2026.10.19` |
| `CAST_INSTALL_ATTEMPTS` | `3` | Retries for `cast install`, which fails on transient outages of the many third-party download sites the SIFT states use |
| `SIFT_TARGET` | `sift` | Cast distro alias or repository |
| `SIFT_MODE` | `server` | SIFT install mode |
| `RUN_VALIDATION` | `false` | Run `/opt/dfir/validation/validate-container.sh` during build |

The image creates the standard `sansforensics` user with the default SIFT
lab password `forensics`. Override it at runtime with `SIFT_PASSWORD` or
`SIFT_PASSWORD_FILE`, or at build time with `SIFT_USER`/`SIFT_PASS`.
