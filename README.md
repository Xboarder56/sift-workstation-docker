# SIFT Workstation Docker

This repository builds a SIFT Workstation-style container image. The default
target is Ubuntu 24.04 in server mode, using a pinned Cast `.deb` to apply the
SIFT salt states.

The goal is not to replace the SIFT desktop VM. The goal is a reproducible,
containerized SIFT environment for evidence processing where case artifacts are
mounted read-only and outputs land in a case workspace.

## Layout

```text
sift-workstation-docker/
├── .github/workflows/build.yml
├── .github/workflows/release-watch.yml
├── .gitignore
├── Dockerfile
├── docker-compose.example.yml
├── scripts/
│   ├── build.sh
│   ├── latest-sift-version.sh
│   ├── run.sh
│   └── validate-image.sh
└── validation/
    └── validate-container.sh
```

## Local Build

Build an amd64 Ubuntu 24.04 image and load it into the local Docker engine:

```bash
cd sift-workstation-docker
./scripts/build.sh
```

Useful overrides:

```bash
UBUNTU_VERSION=24.04 IMAGE_TAG=dev ./scripts/build.sh
BASE_IMAGE=ubuntu:24.04 IMAGE_TAG=dev ./scripts/build.sh
SIFT_VERSION=v2026.04.21 IMAGE_TAG=v2026.04.21 ./scripts/build.sh
PLATFORMS=linux/arm64 IMAGE_TAG=arm64 ./scripts/build.sh
RUN_VALIDATION=true ./scripts/build.sh
NO_CACHE=true PROGRESS=plain ./scripts/build.sh
DRY_RUN=true ./scripts/build.sh
SIFT_MODE=server ./scripts/build.sh
```

Resolve the latest published SIFT saltstack release:

```bash
./scripts/latest-sift-version.sh
SIFT_VERSION="$(./scripts/latest-sift-version.sh)" ./scripts/build.sh
```

For a multi-arch publish build:

```bash
PLATFORMS=linux/amd64,linux/arm64 \
IMAGE_NAME=ghcr.io/YOUR_ORG/sift-workstation \
IMAGE_TAG=v2026.04.21 \
PUSH=true \
LOAD=false \
./scripts/build.sh
```

## Validate

Run the container-contract validation against a built image:

```bash
./scripts/validate-image.sh sift-workstation:latest
```

The validation checks the Docker-layer contract: user creation, SSH service
setup, case/evidence mount points, helper directories, sudo policy, and Cast
availability. It intentionally does not re-check SIFT forensic tools such as
Plaso, SleuthKit, Volatility, or Zimmerman tools. Those are installed and
validated by the upstream SIFT Salt states; if Salt exits successfully, our
image should not second-guess their package inventory.

## Build Notes

On arm64, some Python packages installed by the SIFT salt states may not have
prebuilt wheels. The Dockerfile installs native build prerequisites before Cast
runs so packages such as `leechcorepyc` can compile during the Volatility3
state. A failure mentioning `libusb.h`, `libusb-1.0.pc`, or `-lusb-1.0`
usually means the build did not use the patched Dockerfile layer or the base
build dependencies were not present early enough in the image.

If the build log's `apt-get install` line does not include
`build-essential`, `libusb-1.0-0-dev`, `pkg-config`, and `python3-dev`, force a
clean rebuild:

```bash
NO_CACHE=true PROGRESS=plain \
SIFT_VERSION=v2026.04.21 \
PLATFORMS=linux/arm64 \
IMAGE_TAG=v2026.04.21-arm64 \
./scripts/build.sh
```

## Run Against A Case

The runtime expects:

```text
cases/CASE_NAME/
├── artifacts/      mounted read-only at /evidence
├── working_dir/    writeable through /case/working_dir
└── output/         writeable through /case/output
```

Example:

```bash
CASE_DIR="$(pwd)/../cases/CASE_001" \
EVIDENCE_DIR="$(pwd)/../cases/CASE_001/artifacts" \
IMAGE=sift-workstation:latest \
./scripts/run.sh bash
```

Example Plaso command from inside the container:

```bash
log2timeline.py --status_view none -z UTC \
  --storage_file /case/working_dir/timeline.plaso \
  /evidence/disk.E01
```

## Persistent SSH Service

For VM-like use, start the container through Compose:

```bash
cd sift-workstation-docker
cp docker-compose.example.yml docker-compose.yml
cp .env.example .env
docker compose up -d
ssh sansforensics@127.0.0.1 -p 2222
```

Defaults live in `.env.example`. Copy or export those values if you want a
different image tag, host SSH port, static container IP, or cases mount:

```bash
SIFT_IMAGE=ghcr.io/YOUR_ORG/sift-workstation \
SIFT_TAG=latest \
SIFT_SSH_PORT=2222 \
docker compose -f docker-compose.example.yml up -d
```

The Compose profile is privileged and includes `/dev/fuse`, `SYS_ADMIN`, and
`MKNOD` because several forensic mounting workflows need them. Use the one-shot
`scripts/run.sh` path for safer non-privileged command execution.

## Privileged Mounting

The default run path avoids privileged Docker flags. Some workflows that mount
E01/raw images through FUSE or loop devices may need additional flags such as:

```bash
docker run --rm -it \
  --privileged \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  -v "$CASE_DIR:/case" \
  -v "$EVIDENCE_DIR:/evidence:ro" \
  sift-workstation:latest bash
```

Prefer direct image-reading tools where possible. Use privileged mode only when
the case workflow requires kernel/FUSE access.

## GitHub Actions

### Build Workflow

The workflow at `.github/workflows/build.yml` does two things when this
directory is used as its own repository:

1. Builds and validates an amd64 image for pull requests and pushes.
2. Publishes multi-arch images on manual dispatch when GHCR and/or Docker Hub
   publishing is enabled.

The default package name is:

```text
ghcr.io/xboarder56/sift-workstation
```

Docker Hub publishing is optional. Configure these repository secrets before
enabling the Docker Hub publish input:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

### Upstream SIFT Release Watcher

The workflow at `.github/workflows/release-watch.yml` polls the latest
`teamdfir/sift-saltstack` GitHub release every six hours and can also be run
manually.

On each run it:

1. Resolves the latest upstream SIFT release tag.
2. Checks whether the matching GHCR image tag already exists.
3. Skips the build if the tag is already present, unless `force_rebuild=true`.
4. Builds and publishes `linux/amd64` and `linux/arm64`.
5. Tags the image with the upstream SIFT release and updates moving tags.

For SIFT release `v2026.04.21` (Ubuntu 24.04 base), GHCR tags are:

```text
ghcr.io/xboarder56/sift-workstation:latest
ghcr.io/xboarder56/sift-workstation:v2026.04.21
ghcr.io/xboarder56/sift-workstation:sha-<commit>
```

The base OS lives in the OCI `org.opencontainers.image.base.name` label, not
the tag. When a future Ubuntu base ships, the moving `:latest` rolls forward
and existing pinned tags (`:v2026.04.21`) keep their original base.

Docker Hub publishing from the release watcher is optional. To enable it for
scheduled runs, set this repository variable:

```text
PUBLISH_DOCKERHUB=true
```

Optional repository variables:

```text
DOCKERHUB_IMAGE=xboarder56/sift-workstation
UBUNTU_VERSION=24.04
CAST_VERSION=1.0.13
PUBLISH_PLATFORMS=linux/amd64,linux/arm64
```

## Build Arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `BASE_IMAGE` | `ubuntu:24.04` | Full base image reference used by `FROM` |
| `UBUNTU_VERSION` | `24.04` | Convenience value used by helper scripts/tags |
| `IMAGE_VERSION` | image tag | OCI image version label |
| `GIT_COMMIT` | current git SHA or `unknown` | OCI revision label |
| `BUILD_DATE` | current UTC time | OCI created label |
| `IMAGE_SOURCE` | repository URL | OCI source label |
| `IMAGE_DOCUMENTATION` | README URL | OCI documentation label |
| `IMAGE_URL` | repository URL | OCI URL label |
| `IMAGE_AUTHORS` | `xboarder56` | OCI authors label |
| `CAST_VERSION` | `1.0.13` | Cast release version without the leading `v` |
| `SIFT_VERSION` | `latest` | SIFT saltstack release. `latest` lets Cast resolve current; `v2026.04.21` pins a release via `sift@v2026.04.21` |
| `SIFT_TARGET` | `sift` | Cast distro alias or repository |
| `SIFT_MODE` | `server` | SIFT install mode |
| `RUN_VALIDATION` | `false` | Run `/opt/dfir/validation/validate-container.sh` during the image build |

The image also creates the standard `sansforensics` user with the default SIFT
lab password `forensics`. Override `SIFT_USER` and `SIFT_PASS` at build time if
you publish an image outside a private lab.
