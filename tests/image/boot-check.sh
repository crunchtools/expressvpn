#!/bin/bash
# Boot gate, run INSIDE the image as the Containerfile's last build step. A
# VPN cannot connect in CI (no activation code, no TUN device, no NET_ADMIN),
# so this proves what can be proven: the entrypoint
# parses and fails closed, and every binary production runs (daemon, CLI, tunnel
# protocols, DNS, tinyproxy) is present and has no unresolved shared library.
# NOT covered: activation, connecting, Network Lock, in-tunnel DNS, and
# tinyproxy serving through the tunnel.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "entrypoint parses"
bash -n /entrypoint.sh || fail "entrypoint.sh does not parse"

echo "entrypoint fails closed without CODE"
rc=0
out=$(env -u CODE /entrypoint.sh 2>&1) || rc=$?
[ "$rc" -eq 1 ] && grep -q 'CODE environment variable is required' <<<"$out" \
  || fail "expected exit 1 with the CODE error, got rc=$rc: $out"

echo "VPN client binaries and shared libraries"
export LD_LIBRARY_PATH=/opt/expressvpn/lib
for b in expressvpn-daemon expressvpnctl expressvpn-lightway expressvpn-openvpn expressvpn-unbound; do
  test -x /opt/expressvpn/bin/$b || fail "missing $b"
  if ldd /opt/expressvpn/bin/$b 2>&1 | grep -q "not found"; then
    ldd /opt/expressvpn/bin/$b | grep "not found" >&2
    fail "unresolved libraries for $b"
  fi
done
expressvpnctl --help >/dev/null || fail "expressvpnctl --help failed"
tinyproxy -v || fail "tinyproxy -v failed"
for t in service getent usermod iptables ip; do command -v $t >/dev/null || fail "missing $t"; done
grep -q "^Port 8888" /etc/tinyproxy/tinyproxy.conf || fail "tinyproxy is not on port 8888"
grep -qx "ConnectPort 443" /etc/tinyproxy/tinyproxy.conf || fail "tinyproxy does not limit CONNECT"
test -x /etc/init.d/expressvpn-service || fail "missing /etc/init.d/expressvpn-service"

echo "boot gate passed"
