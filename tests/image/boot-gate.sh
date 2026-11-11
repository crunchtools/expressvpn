#!/usr/bin/env bash
# Boot gate for the expressvpn image. A VPN cannot connect in CI (no activation
# code, no TUN device, no NET_ADMIN), so this proves what can be proven: the
# entrypoint parses and fails closed, and every binary production runs
# (daemon, CLI, tunnel protocols, DNS, tinyproxy) is present and has no
# unresolved shared library. NOT covered: activation, connecting, Network Lock,
# in-tunnel DNS, and tinyproxy serving through the tunnel.
# Usage: IMAGE=<ref> tests/image/boot-gate.sh   (or pass the image as $1)
set -euo pipefail
IMAGE="${1:-${IMAGE:?set IMAGE or pass the image as an argument}}"
run() { podman run --rm --entrypoint bash "$IMAGE" -c "$1"; }

echo "entrypoint parses"
run 'bash -n /entrypoint.sh'

echo "entrypoint fails closed without CODE"
rc=0
out=$(podman run --rm "$IMAGE" 2>&1) || rc=$?
[ "$rc" -eq 1 ] && grep -q 'CODE environment variable is required' <<<"$out" \
  || { echo "FAIL: expected exit 1 with the CODE error, got rc=$rc: $out"; exit 1; }

echo "VPN client binaries and shared libraries"
run '
set -e
export LD_LIBRARY_PATH=/opt/expressvpn/lib
for b in expressvpn-daemon expressvpnctl expressvpn-lightway expressvpn-openvpn expressvpn-unbound; do
  test -x /opt/expressvpn/bin/$b || { echo "FAIL: missing $b"; exit 1; }
  if ldd /opt/expressvpn/bin/$b 2>&1 | grep -q "not found"; then
    echo "FAIL: unresolved libraries for $b"; ldd /opt/expressvpn/bin/$b | grep "not found"; exit 1
  fi
done
expressvpnctl --help >/dev/null
tinyproxy -v
for t in service getent usermod iptables ip; do command -v $t >/dev/null || { echo "FAIL: missing $t"; exit 1; }; done
grep -q "^Port 8888" /etc/tinyproxy/tinyproxy.conf
'
echo "boot gate passed"
