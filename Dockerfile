ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG BUILD_DATE
ARG GIT_COMMIT
ARG IMAGE_VERSION=dev
ARG IMAGE_SOURCE="https://github.com/xboarder56/sift-workstation-docker"
ARG IMAGE_DOCUMENTATION="https://github.com/xboarder56/sift-workstation-docker#readme"
ARG IMAGE_URL="https://github.com/xboarder56/sift-workstation-docker"
ARG IMAGE_AUTHORS="xboarder56"
ARG TARGETARCH
ARG CAST_VERSION=1.0.13
ARG SIFT_VERSION=latest
ARG SIFT_TARGET=sift
ARG SIFT_MODE=server
ARG SIFT_USER=sansforensics
ARG SIFT_DESCRIPTION="SANSForensics User"
ARG SIFT_PASS=forensics
ARG RUN_VALIDATION=false

LABEL org.opencontainers.image.title="SIFT Workstation Docker"
LABEL org.opencontainers.image.description="SANS SIFT Workstation-style container image"
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}"
LABEL org.opencontainers.image.documentation="${IMAGE_DOCUMENTATION}"
LABEL org.opencontainers.image.url="${IMAGE_URL}"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"
LABEL org.opencontainers.image.authors="${IMAGE_AUTHORS}"
LABEL org.opencontainers.image.vendor="xboarder56"
LABEL org.sans.sift.version="${SIFT_VERSION}"
LABEL org.sans.sift.cast.version="${CAST_VERSION}"
LABEL org.sans.sift.install.mode="${SIFT_MODE}"

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
        amd64) cast_arch="amd64" ;; \
        arm64) cast_arch="arm64" ;; \
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
    wget -q "https://github.com/ekristen/cast/releases/download/v${CAST_VERSION}/${cast_deb}"; \
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

COPY validation/ /opt/dfir/validation/
RUN chmod +x /opt/dfir/validation/*.sh
RUN if [[ "${RUN_VALIDATION}" == "true" ]]; then \
        /opt/dfir/validation/validate-container.sh; \
    else \
        echo "Skipping build-time validation (RUN_VALIDATION=${RUN_VALIDATION})"; \
    fi

WORKDIR /home/${SIFT_USER}
VOLUME ["/case", "/evidence"]
EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
