# syntax=docker/dockerfile:1
#
# Stages:
#   sift     Ubuntu + SIFT installed by Cast (slow; the expensive layer)
#   runtime  Per-container hardening + entrypoint shared by all variants
#   desktop  runtime + Ubuntu GNOME desktop over xrdp (RDP on port 3389)
#   server   runtime only (SSH on port 22). Default target (last stage).
#
# Build a variant with --target server|desktop (scripts/build.sh TARGET=...).

ARG BASE_IMAGE=ubuntu:24.04

#############################################################################
FROM ${BASE_IMAGE} AS sift

ARG TARGETARCH
# Cast release. The pinned version's .deb sha256s are pinned below; any other
# version is verified against that release's checksums.txt.
ARG CAST_VERSION=1.0.42
ARG CAST_PINNED_VERSION=1.0.42
ARG CAST_SHA256_AMD64=9775d46a42f77030407cd3ba37d5f32334d50e0d4b021ece113c23cbea2c7573
ARG CAST_SHA256_ARM64=b527fd8592af2520ddd3457cba9538c7e80013b8c58174ab402ac69c03a0c369
ARG SIFT_VERSION=latest
ARG SIFT_TARGET=sift
ARG SIFT_MODE=server
ARG SIFT_USER=sansforensics
ARG SIFT_DESCRIPTION="SANSForensics User"
ARG SIFT_PASS=forensics

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=linux \
    TZ=UTC

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
WORKDIR /tmp

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64) cast_arch="amd64"; pinned_sha="${CAST_SHA256_AMD64}" ;; \
        arm64) cast_arch="arm64"; pinned_sha="${CAST_SHA256_ARM64}" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        curl \
        file \
        git \
        gnupg \
        jq \
        libusb-1.0-0-dev \
        locales \
        lsb-release \
        openssh-server \
        pkg-config \
        python3 \
        python3-dev \
        sudo \
        tzdata \
        wget; \
    locale-gen C.UTF-8; \
    if ! getent group "${SIFT_USER}" >/dev/null; then \
        if getent group 1000 >/dev/null; then \
            existing_group="$(getent group 1000 | cut -d: -f1)"; \
            groupmod -n "${SIFT_USER}" "${existing_group}"; \
        else \
            groupadd -g 1000 "${SIFT_USER}"; \
        fi; \
    fi; \
    if ! id -u "${SIFT_USER}" >/dev/null 2>&1; then \
        if getent passwd 1000 >/dev/null; then \
            existing_user="$(getent passwd 1000 | cut -d: -f1)"; \
            usermod -l "${SIFT_USER}" -d "/home/${SIFT_USER}" -m \
                -c "${SIFT_DESCRIPTION}" -s /bin/bash "${existing_user}"; \
        else \
            useradd -g "${SIFT_USER}" -d "/home/${SIFT_USER}" -s /bin/bash \
                -c "${SIFT_DESCRIPTION}" -u 1000 "${SIFT_USER}"; \
        fi; \
    fi; \
    mkdir -p "/home/${SIFT_USER}"; \
    touch "/home/${SIFT_USER}/.Xauthority"; \
    chown -R "${SIFT_USER}:${SIFT_USER}" "/home/${SIFT_USER}"; \
    usermod -a -G sudo "${SIFT_USER}"; \
    echo "${SIFT_USER}:${SIFT_PASS}" | chpasswd; \
    echo "${SIFT_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/sift-user; \
    chmod 0440 /etc/sudoers.d/sift-user; \
    cast_deb="cast-v${CAST_VERSION}-linux-${cast_arch}.deb"; \
    cast_base="https://github.com/ekristen/cast/releases/download/v${CAST_VERSION}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o "${cast_deb}" "${cast_base}/${cast_deb}"; \
    if [[ "${CAST_VERSION}" == "${CAST_PINNED_VERSION}" ]]; then \
        expected_sha="${pinned_sha}"; \
    else \
        curl -fsSL --retry 3 --retry-delay 2 -o cast-checksums.txt "${cast_base}/checksums.txt"; \
        expected_sha="$(awk -v f="${cast_deb}" '$2 == f { print $1 }' cast-checksums.txt)"; \
        rm -f cast-checksums.txt; \
    fi; \
    if [[ -z "${expected_sha}" ]]; then \
        echo "FATAL: no sha256 available for ${cast_deb}" >&2; exit 1; \
    fi; \
    echo "${expected_sha}  ${cast_deb}" | sha256sum -c -; \
    apt-get install -y "./${cast_deb}"; \
    sift_spec="${SIFT_TARGET}"; \
    if [[ -n "${SIFT_VERSION}" && "${SIFT_VERSION}" != "latest" ]]; then \
        sift_spec="${SIFT_TARGET}@${SIFT_VERSION}"; \
    fi; \
    cast install --mode "${SIFT_MODE}" --user "${SIFT_USER}" "${sift_spec}"; \
    rm -f "./${cast_deb}"

RUN set -eux; \
    echo "UseDNS no" >> /etc/ssh/sshd_config; \
    echo "GSSAPIAuthentication no" >> /etc/ssh/sshd_config; \
    echo "PrintLastLog yes" >> /etc/ssh/sshd_config; \
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config; \
    echo "X11DisplayOffset 10" >> /etc/ssh/sshd_config; \
    echo "X11UseLocalhost no" >> /etc/ssh/sshd_config; \
    mkdir -p /run/sshd /case /evidence /opt/dfir/validation; \
    chown -R "${SIFT_USER}:${SIFT_USER}" /case; \
    mkdir -p /mnt/aff /mnt/bde /mnt/e01 /mnt/ewf /mnt/ewf_mount /mnt/iscsi \
        /mnt/shadow_mount /mnt/usb /mnt/vss /mnt/windows_mount; \
    for i in $(seq 1 5); do mkdir -p "/mnt/windows_mount${i}"; done; \
    for i in $(seq 1 30); do mkdir -p "/mnt/shadow_mount/vss${i}"; done; \
    chown -R "${SIFT_USER}:${SIFT_USER}" "/home/${SIFT_USER}"; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /srv /var/cache/salt/* /root/.cache/* /var/lib/apt/lists/* /tmp/*

#############################################################################
FROM sift AS runtime

ARG BASE_IMAGE
ARG BUILD_DATE
ARG GIT_COMMIT
ARG IMAGE_VERSION=dev
ARG IMAGE_SOURCE="https://github.com/xboarder56/sift-workstation-docker"
ARG IMAGE_DOCUMENTATION="https://github.com/xboarder56/sift-workstation-docker#readme"
ARG IMAGE_URL="https://github.com/xboarder56/sift-workstation-docker"
ARG IMAGE_AUTHORS="xboarder56"
ARG CAST_VERSION=1.0.42
ARG SIFT_VERSION=latest
ARG SIFT_MODE=server
ARG SIFT_USER=sansforensics

LABEL org.opencontainers.image.title="SIFT Workstation Docker" \
      org.opencontainers.image.description="SANS SIFT Workstation-style container image" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.documentation="${IMAGE_DOCUMENTATION}" \
      org.opencontainers.image.url="${IMAGE_URL}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.authors="${IMAGE_AUTHORS}" \
      org.opencontainers.image.vendor="xboarder56" \
      org.sans.sift.version="${SIFT_VERSION}" \
      org.sans.sift.cast.version="${CAST_VERSION}" \
      org.sans.sift.install.mode="${SIFT_MODE}"

ENV SIFT_USER=${SIFT_USER}

# tini reaps zombies and forwards signals for the multi-service entrypoint.
# Host keys generated by openssh-server at build time (and any snakeoil TLS
# key) would be shared by every container from this public image, so remove
# them here; the entrypoint creates unique ones per container on start.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends tini; \
    rm -f /etc/ssh/ssh_host_*; \
    rm -f /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem; \
    mkdir -p /etc/ssh/sshd_config.d; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /
COPY validation/ /opt/dfir/validation/
RUN chmod 0755 /usr/local/bin/sift-entrypoint /opt/dfir/validation/*.sh

WORKDIR /home/${SIFT_USER}
VOLUME ["/case", "/evidence"]
EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/sift-entrypoint"]
CMD ["sift-services"]

#############################################################################
FROM runtime AS desktop

ARG RUN_VALIDATION=false
ARG SIFT_VERSION=latest

# GNOME without systemd: /run/systemd/seats (left behind by package installs)
# makes GNOME Shell require logind, so it is removed; and the `sift` session
# is the Ubuntu session minus gsd-power, which cannot run without logind.
# Ubuntu GNOME desktop (the same session a stock SIFT Workstation uses)
# served over RDP by xrdp + xorgxrdp. Connect with any RDP client (mstsc,
# Windows App, Remmina, FreeRDP) as the SIFT user. SIFT's theme (wallpaper,
# bottom dock, favorites) is applied as dconf system defaults.
# The SIFT install also ships autostart entries that misbehave in a remote
# session (screen magnifier/reader/on-screen keyboard popping up, a
# screensaver locking idle sessions); they are hidden for this image.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        xrdp \
        xorgxrdp \
        ubuntu-session \
        gnome-shell \
        gnome-shell-extension-ubuntu-dock \
        gnome-shell-extension-appindicator \
        gnome-session-bin \
        gnome-settings-daemon \
        gnome-terminal \
        nautilus \
        gnome-text-editor \
        gnome-system-monitor \
        eog \
        evince \
        yaru-theme-gtk \
        yaru-theme-icon \
        yaru-theme-gnome-shell \
        yaru-theme-sound \
        fonts-ubuntu \
        fonts-dejavu-core \
        dconf-cli \
        dbus-x11 \
        dbus-user-session \
        at-spi2-core \
        libgl1-mesa-dri \
        xauth \
        x11-xserver-utils \
        xdg-utils \
        xdg-user-dirs \
        polkitd \
        openssl; \
    adduser xrdp ssl-cert; \
    rm -f /etc/xrdp/cert.pem /etc/xrdp/key.pem \
          /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem; \
    sift_ref="${SIFT_VERSION}"; \
    if [[ -z "${sift_ref}" || "${sift_ref}" == "latest" ]]; then sift_ref=master; fi; \
    mkdir -p /usr/share/backgrounds; \
    curl -fsSL --retry 3 --retry-delay 2 -o /usr/share/backgrounds/sift.png \
        "https://raw.githubusercontent.com/teamdfir/sift-saltstack/${sift_ref}/sift/files/sift/images/sift.png"; \
    file /usr/share/backgrounds/sift.png | grep -q 'PNG image'; \
    for entry in magnus-autostart onboard-autostart orca-autostart xscreensaver \
                 snap-userd-autostart unity-settings-daemon unity-fallback-mount-helper \
                 indicator-application indicator-messages geoclue-demo-agent \
                 org.gnome.Evolution-alarm-notify gnome-initial-setup-first-login \
                 gnome-initial-setup-copy-worker update-notifier; do \
        f="/etc/xdg/autostart/${entry}.desktop"; \
        if [[ -f "${f}" ]]; then \
            sed -i '/^Hidden=/d' "${f}"; \
            sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nHidden=true/' "${f}"; \
        fi; \
    done; \
    sed -e 's/^Name=Ubuntu$/Name=SIFT (Ubuntu GNOME over RDP)/' \
        -e 's/org\.gnome\.SettingsDaemon\.Power;//' \
        /usr/share/gnome-session/sessions/ubuntu.session \
        > /usr/share/gnome-session/sessions/sift.session; \
    rm -rf /run/systemd/seats /run/systemd/sessions; \
    printf '%s\n' 'allowed_users=anybody' 'needs_root_rights=no' > /etc/X11/Xwrapper.config; \
    sed -i -E 's/^#?\s*security_layer=.*/security_layer=tls/' /etc/xrdp/xrdp.ini; \
    echo desktop > /etc/sift-image-variant; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/*

COPY rootfs-desktop/ /
RUN set -eux; \
    chmod 0755 /etc/xrdp/startwm.sh; \
    dconf update; \
    if [[ "${RUN_VALIDATION}" == "true" ]]; then \
        SIFT_VALIDATE_IMAGE_STATE=true /opt/dfir/validation/validate-container.sh; \
    else \
        echo "Skipping build-time validation (RUN_VALIDATION=${RUN_VALIDATION})"; \
    fi

LABEL org.sans.sift.image.variant="desktop"
EXPOSE 3389

#############################################################################
# Default target: SSH-only server image.
FROM runtime AS server

ARG RUN_VALIDATION=false

RUN echo server > /etc/sift-image-variant; \
    if [[ "${RUN_VALIDATION}" == "true" ]]; then \
        SIFT_VALIDATE_IMAGE_STATE=true /opt/dfir/validation/validate-container.sh; \
    else \
        echo "Skipping build-time validation (RUN_VALIDATION=${RUN_VALIDATION})"; \
    fi

LABEL org.sans.sift.image.variant="server"
