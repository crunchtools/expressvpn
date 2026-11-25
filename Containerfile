FROM registry.access.redhat.com/ubi10/ubi

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="ExpressVPN + tinyproxy for Playwright egress routing"

ARG EXPRESSVPN_VERSION=5.1.0.12141
# The installer is not signed, so its bytes are pinned. Re-take this with every
# EXPRESSVPN_VERSION bump.
ARG EXPRESSVPN_SHA256=e1c81b6c08ba94dbba88d4afb2c3d757187754b3c85691a9429424096df51eca

# tinyproxy comes from EPEL 10, checked against Fedora's EPEL 10 key.
COPY etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10 /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10

# The daemon execs iptables and ip6tables for Network Lock, and neither UBI nor
# EPEL ships them: iptables-nft is RHEL AppStream, so this layer registers. It
# registers, installs and unregisters in one layer with a trap, so no RHSM
# consumer outlives the build.
RUN --mount=type=secret,id=activation_key \
    --mount=type=secret,id=org_id <<'EOF'
set -eu
subscription-manager register \
    --activationkey="$(cat /run/secrets/activation_key)" \
    --org="$(cat /run/secrets/org_id)"
trap 'subscription-manager unregister || true; subscription-manager clean || true' EXIT
dnf install -y --nodocs \
    tinyproxy procps-ng psmisc iproute iptables-nft kmod \
    libatomic glib2 libbrotli brotli libnl3 \
    shadow-utils initscripts-service
dnf clean all
rm -rf /var/cache/dnf
EOF

# ExpressVPN v5 universal installer. Its sysvinit service needs Debian's
# update-rc.d and start-stop-daemon, so it installs no service and
# etc/init.d/expressvpn-service is the RHEL equivalent. --force-dependencies
# skips only its privilege and library checks, which a build has no
# /dev/net/tun to pass; tests/image/boot-check.sh runs ldd on every binary.
RUN curl -fsSL https://www.expressvpn.works/clients/linux/expressvpn-linux-universal-${EXPRESSVPN_VERSION}_release.run -o /tmp/expressvpn.run && \
    echo "${EXPRESSVPN_SHA256}  /tmp/expressvpn.run" | sha256sum -c - && \
    sh /tmp/expressvpn.run --accept --quiet --noprogress -- --no-gui --skip-service --force-dependencies && \
    rm -f /tmp/expressvpn.run && \
    dnf clean all && rm -rf /var/cache/dnf
COPY etc/init.d/expressvpn-service /etc/init.d/expressvpn-service
RUN chmod 755 /etc/init.d/expressvpn-service

# Configure tinyproxy: listen on all interfaces, allow container networks.
# EPEL's tinyproxy.conf comments out the log file, the pid file and the CONNECT
# port limit that Ubuntu's set, so those three are turned back on to match.
RUN sed -i 's/^Listen .*/Listen 0.0.0.0/' /etc/tinyproxy/tinyproxy.conf && \
    sed -i 's/^Port .*/Port 8888/' /etc/tinyproxy/tinyproxy.conf && \
    sed -i 's|^#LogFile .*|LogFile "/var/log/tinyproxy/tinyproxy.log"|' /etc/tinyproxy/tinyproxy.conf && \
    sed -i 's|^#PidFile .*|PidFile "/run/tinyproxy/tinyproxy.pid"|' /etc/tinyproxy/tinyproxy.conf && \
    sed -i 's/^#ConnectPort 443$/ConnectPort 443/; s/^#ConnectPort 563$/ConnectPort 563/' /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 10.0.0.0/8' >> /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 172.16.0.0/12' >> /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 192.168.0.0/16' >> /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 127.0.0.0/8' >> /etc/tinyproxy/tinyproxy.conf && \
    for line in 'LogFile "/var/log/tinyproxy/tinyproxy.log"' 'PidFile "/run/tinyproxy/tinyproxy.pid"' \
                'ConnectPort 443' 'ConnectPort 563'; do \
        grep -qxF "$line" /etc/tinyproxy/tinyproxy.conf || { echo "tinyproxy.conf lacks: $line" >&2; exit 1; }; \
    done && \
    mkdir -p /var/log/tinyproxy /run/tinyproxy && \
    chown tinyproxy:tinyproxy /var/log/tinyproxy /run/tinyproxy && \
    chmod 750 /run/tinyproxy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# The boot gate: a VPN cannot connect in CI, so the build proves what it can.
# Here rather than in `sdlc ci`, which cannot build this image without RHSM.
RUN --mount=type=bind,source=tests,target=/run/tests \
    bash /run/tests/image/boot-check.sh

EXPOSE 8888

ENTRYPOINT ["/entrypoint.sh"]
