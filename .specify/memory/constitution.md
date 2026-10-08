# expressvpn Constitution

> **Version:** 1.0.0
> **Ratified:** 2026-10-02
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.21.0
> **Profile:** Container Image

This file holds what is specific to the expressvpn image. The fleet rules and
the Container Image profile apply at the inherited version and are checked
against this repo's files by `constitution.yml`. They are not restated here.

## Image Purpose

ExpressVPN client plus tinyproxy, giving Playwright an egress route through
the VPN: other containers point their HTTP proxy at this one. Published to
`quay.io/crunchtools/expressvpn` and `ghcr.io/crunchtools/expressvpn`.

## Base Image Deviation

Built on `ubuntu:22.04`, not UBI or Hummingbird. The image started on
`fedora:42`; after a run of workarounds for the ExpressVPN v5 universal
installer there (creating `/etc/init.d`, stubbing `update-rc.d`, installing
initscripts), the base was switched to Ubuntu 22.04 for ExpressVPN v5
compatibility. Packages come
from apt: `tinyproxy`, `curl`, `ca-certificates`, `procps`, `psmisc`,
`iproute2`, `iptables`, `kmod`, and the v5 runtime libraries `libatomic1`,
`libglib2.0-0`, `libbrotli1`.

## ExpressVPN Client

- **Version:** pinned by `ARG EXPRESSVPN_VERSION` (currently 5.1.0.12141),
  installed from the vendor's universal `.run` installer with `--no-gui
  --sysvinit`. The daemon is started with `service`, not systemd.
- **Connection:** protocol `lightwayudp`, `allowlan` on, server from `SERVER`
  (default `smart`). `tinyproxy` is added to the `expressvpn` group so Network
  Lock lets its traffic through.
- **DNS:** the entrypoint unmounts the container-managed `/etc/resolv.conf`
  (keeping its content) so ExpressVPN can manage DNS.

## Credentials

| Variable | Required | Purpose |
|----------|----------|---------|
| `CODE` | yes | ExpressVPN activation code; the entrypoint exits if it is unset |
| `SERVER` | no | location to connect to, default `smart` |

The activation code is passed to `expressvpnctl login` through a temp file
that is removed immediately, never on the command line. Nothing
credential-bearing is baked into the image.

## Proxy

tinyproxy listens on `0.0.0.0:8888` (the only exposed port) and allows only
private and loopback ranges: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
`127.0.0.0/8`. Port 8888 MUST NOT be published to a public interface. It runs
in the foreground as the container's main process.

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-10-02 | Initial constitution, written as a v1.18.0 manifest |
