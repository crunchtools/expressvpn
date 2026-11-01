# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
