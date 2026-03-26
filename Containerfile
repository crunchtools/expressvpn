FROM ubuntu:22.04

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="ExpressVPN + tinyproxy for Playwright egress routing"

ARG EXPRESSVPN_VERSION=5.1.0.12141

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tinyproxy curl ca-certificates procps psmisc iproute2 iptables kmod \
        libatomic1 libglib2.0-0 libbrotli1 && \
    rm -rf /var/lib/apt/lists/*

# ExpressVPN v5 universal installer
RUN curl -fsSL https://www.expressvpn.works/clients/linux/expressvpn-linux-universal-${EXPRESSVPN_VERSION}_release.run -o /tmp/expressvpn.run && \
    sh /tmp/expressvpn.run --accept --quiet --noprogress -- --no-gui --sysvinit && \
    rm -f /tmp/expressvpn.run

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
