# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security

- `.grype.yaml` for python-sdlc's `container-scan` gate, which `sdlc ci` fails
  on a fixable Critical. The only one in this image is in
  `/opt/expressvpn/bin/expressvpn-decode-legacy-settings`, a v3/v4 settings
  migration shim that ExpressVPN ships prebuilt inside the universal installer
  and built with Go 1.20.5: GO-2024-2887 and GO-2026-6612, plus eleven lesser
  findings in the same stdlib and in `golang.org/x/net` v0.10.0. We download
  that installer and cannot rebuild the binary, and nothing in this container
  invokes it — a fresh container has no legacy settings to migrate, and the
  entrypoint only runs `expressvpnctl`, the daemon and tinyproxy. The file
  ignores those two Criticals at that one path only and says what would retire it: an
  `ARG EXPRESSVPN_VERSION` bump to an installer with the binary rebuilt. Every
  other Go binary in the installer is current (go1.25.0, go1.23.2), so this is
  one frozen artifact rather than a stale toolchain.

### Changed

- Gatehouse triage gets `review_result` from the review job, so a pull request
  whose review died before posting anything is held instead of passing.
- Promote signs the image with the fleet cosign key (`sign: true`), because
  bootc hosts are moving to trust only signed `quay.io/crunchtools` images
  (crunchtools/rhel10-bootc-server#47). Needs the repo's `cosign-signing`
  environment to hold `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD`.
- The container release runs constitution v1.51.0's `container-release.yml`
  (was v1.46.0) and grants it `issues: write`, so a failed scheduled rebuild
  opens an issue instead of only warning. A `v*` promote now also refuses an
  image whose `version` label names a different release of this repo; this
  image sets no `version` label of its own, so the check is inert here.

## [1.0.1] - 2026-11-11

### Fixed

- **The proxy no longer serves a tunnel whose DNS is dead.** A connection
  that reports `Connected` can still have an unusable resolver: after a host
  reboot the daemon said "Connected to usa-chicago", `tun0` was up and
  `resolv.conf` named the right in-tunnel resolver, and nothing in the
  container could resolve a name — for days, until the unit was restarted by
  hand, which fixed it in under a minute. The entrypoint now resolves a name
  through the tunnel before starting tinyproxy, reconnects once if it cannot,
  and exits non-zero rather than proxying through a tunnel that does not
  work. The resolver is read from `resolv.conf`, never assumed: it is
  `100.64.100.1` here but other setups report `10.72.0.1`.

### Changed

- Added `.specify/memory/constitution.md` as a v1.18.0 manifest: it holds
  only what is specific to this repo; fleet and profile rules apply by
  reference.
- Constitution validation is pinned to the inherited release via
  `.github/workflows/constitution.yml`.
- Dependabot auto-merges GitHub Actions minor and patch updates.

## [1.0.0] - 2026-09-20

First tagged release. This image has been running in production since
before it had version control; this release marks the current state as
the baseline going forward.
