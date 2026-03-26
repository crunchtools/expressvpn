FROM registry.fedoraproject.org/fedora:42

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="ExpressVPN + tinyproxy for Playwright egress routing"

RUN dnf install -y tinyproxy procps-ng iproute iptables expect && dnf clean all

# ExpressVPN Linux CLI
RUN curl -fsSL https://www.expressvpn.works/clients/linux/expressvpn_3.87.0.3-1.x86_64.rpm -o /tmp/expressvpn.rpm && \
    dnf install -y /tmp/expressvpn.rpm && \
    rm -f /tmp/expressvpn.rpm

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
