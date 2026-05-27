# SIFT Workstation Docker

A containerized build of the SANS SIFT Workstation forensics environment.
Built from the upstream `teamdfir/sift-saltstack` release via Cast, on
Ubuntu 24.04. Multi-arch images for `linux/amd64` and `linux/arm64`.

The goal is a reproducible, scriptable SIFT environment for evidence
processing in CI/CD and on workstations where the full SIFT desktop VM is
impractical. This is not a desktop replacement.

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

Default user inside the container: `sansforensics` (password `forensics`,
passwordless sudo). The shell starts in `/home/sansforensics` with the full
SIFT tooling on the PATH.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | Moving — newest upstream SIFT release |
| `vYYYY.MM.DD` | Pinned to a specific upstream SIFT release (immutable) |
| `sha-<commit>` | Pinned to a specific build of this image |

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

## Persistent SSH service

For VM-like use, run the container as a long-lived SSH server via Compose:

```bash
curl -O https://raw.githubusercontent.com/xboarder56/sift-workstation-docker/main/docker-compose.example.yml
curl -O https://raw.githubusercontent.com/xboarder56/sift-workstation-docker/main/.env.example
mv docker-compose.example.yml docker-compose.yml
mv .env.example .env
docker compose up -d
ssh sansforensics@127.0.0.1 -p 2222
```

Edit `.env` to change the SSH port, container name, image tag, or cases mount.

The compose profile runs privileged with `/dev/fuse`, `SYS_ADMIN`, and
`MKNOD` because several forensic mounting workflows need them. For
non-privileged one-shot work, use the `docker run` form above.

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
./scripts/build.sh
```

Common overrides:

```bash
# Pin a specific SIFT release
SIFT_VERSION=v2026.04.21 IMAGE_TAG=v2026.04.21 ./scripts/build.sh

# Build for arm64 only
PLATFORMS=linux/arm64 IMAGE_TAG=arm64 ./scripts/build.sh

# Force a clean rebuild with verbose output
NO_CACHE=true PROGRESS=plain ./scripts/build.sh

# Print the build command without running it
DRY_RUN=true ./scripts/build.sh
```

Resolve the latest published SIFT release tag:

```bash
./scripts/latest-sift-version.sh
SIFT_VERSION="$(./scripts/latest-sift-version.sh)" ./scripts/build.sh
```

Multi-arch publish to a registry:

```bash
PLATFORMS=linux/amd64,linux/arm64 \
IMAGE_NAME=ghcr.io/YOUR_ORG/sift-workstation \
IMAGE_TAG=v2026.04.21 \
PUSH=true \
LOAD=false \
./scripts/build.sh
```

### Validate an image

```bash
./scripts/validate-image.sh sift-workstation:latest
```

This checks the Docker-layer contract: user creation, SSH setup, case and
evidence mount points, helper directories, sudo policy, and Cast
availability. It does not re-validate the forensic tools themselves
(Plaso, SleuthKit, Volatility, Zimmerman); those are owned by the upstream
SIFT Salt states.

### Build notes

On arm64, some Python packages installed by the SIFT salt states (notably
`leechcorepyc` during the Volatility3 state) lack prebuilt wheels and must
compile from source. The Dockerfile installs `build-essential`,
`libusb-1.0-0-dev`, `pkg-config`, and `python3-dev` before Cast runs to
support this. A failure mentioning `libusb.h`, `libusb-1.0.pc`, or
`-lusb-1.0` usually means those packages were not present early enough —
force a clean rebuild:

```bash
NO_CACHE=true PROGRESS=plain \
SIFT_VERSION=v2026.04.21 \
PLATFORMS=linux/arm64 \
IMAGE_TAG=v2026.04.21-arm64 \
./scripts/build.sh
```

### GitHub Actions

Two workflows live in `.github/workflows/`:

- **`build.yml`** — validates amd64 builds on every push and PR. Manual
  dispatch can also publish a multi-arch image when `publish_ghcr` and/or
  `publish_dockerhub` are toggled on.
- **`release-watch.yml`** — polls upstream `teamdfir/sift-saltstack` every
  six hours, builds and publishes a new multi-arch image whenever a new
  release appears. Skips work if the matching tag already exists. Can also
  be run manually with `force_rebuild: true`.

Both workflows resolve `SIFT_VERSION=latest` to the actual upstream release
tag before publishing, so the pinned `:vYYYY.MM.DD` tag is always produced.

For a fork to publish under its own namespace:

1. Edit the hardcoded `GHCR_IMAGE` and default `dockerhub_image` in both
   workflow files.
2. Update the OCI URL labels in `Dockerfile` and `scripts/build.sh`.
3. Add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repo secrets if you want
   Docker Hub publishing.
4. Set the repo variable `PUBLISH_DOCKERHUB=true` to enable Docker Hub from
   the scheduled cron.

Other optional repo variables:

| Variable | Default |
| --- | --- |
| `DOCKERHUB_IMAGE` | `xboarder56/sift-workstation` |
| `UBUNTU_VERSION` | `24.04` |
| `CAST_VERSION` | `1.0.13` |
| `PUBLISH_PLATFORMS` | `linux/amd64,linux/arm64` |

### Build arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `BASE_IMAGE` | `ubuntu:24.04` | Full base image reference used by `FROM` |
| `UBUNTU_VERSION` | `24.04` | Convenience value used by helper scripts and tags |
| `IMAGE_VERSION` | `dev` | OCI image version label |
| `GIT_COMMIT` | current git SHA or `unknown` | OCI revision label |
| `BUILD_DATE` | current UTC time | OCI created label |
| `IMAGE_SOURCE` | repository URL | OCI source label |
| `IMAGE_DOCUMENTATION` | README URL | OCI documentation label |
| `IMAGE_URL` | repository URL | OCI URL label |
| `IMAGE_AUTHORS` | `xboarder56` | OCI authors label |
| `CAST_VERSION` | `1.0.13` | Cast release version without leading `v` |
| `SIFT_VERSION` | `latest` | SIFT saltstack release. `latest` resolves to current at install time; `v2026.04.21` pins via `sift@v2026.04.21` |
| `SIFT_TARGET` | `sift` | Cast distro alias or repository |
| `SIFT_MODE` | `server` | SIFT install mode |
| `RUN_VALIDATION` | `false` | Run `/opt/dfir/validation/validate-container.sh` during build |

The image creates the standard `sansforensics` user with the default SIFT
lab password `forensics`. Override `SIFT_USER` and `SIFT_PASS` at build
time if you publish an image outside a private lab.
