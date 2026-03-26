FROM registry.fedoraproject.org/fedora:42

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="ExpressVPN + tinyproxy for Playwright egress routing"

ARG EXPRESSVPN_VERSION=5.1.0.12141

RUN dnf install -y tinyproxy procps-ng iproute iptables initscripts && dnf clean all

# ExpressVPN v5 universal installer (sysvinit for container use)
# Fedora has no update-rc.d (Debian-ism) — stub it; initscripts provides 'service' command
RUN mkdir -p /etc/init.d && \
    printf '#!/bin/sh\nexit 0\n' > /usr/sbin/update-rc.d && chmod +x /usr/sbin/update-rc.d && \
    curl -fsSL https://www.expressvpn.works/clients/linux/expressvpn-linux-universal-${EXPRESSVPN_VERSION}_release.run -o /tmp/expressvpn.run && \
    sh /tmp/expressvpn.run --accept --quiet --noprogress -- --no-gui --sysvinit --force-dependencies && \
    rm -f /tmp/expressvpn.run /usr/sbin/update-rc.d

# Configure tinyproxy: listen on all interfaces, allow container networks
RUN sed -i 's/^Listen .*/Listen 0.0.0.0/' /etc/tinyproxy/tinyproxy.conf && \
    sed -i 's/^Port .*/Port 8888/' /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 10.0.0.0/8' >> /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 172.16.0.0/12' >> /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 192.168.0.0/16' >> /etc/tinyproxy/tinyproxy.conf && \
    echo 'Allow 127.0.0.0/8' >> /etc/tinyproxy/tinyproxy.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8888

ENTRYPOINT ["/entrypoint.sh"]
