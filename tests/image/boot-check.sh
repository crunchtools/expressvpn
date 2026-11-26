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

bash "$(dirname "$0")/resolv-perms.sh" /entrypoint.sh

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
for t in service getent usermod iptables ip setpriv stat; do command -v $t >/dev/null || fail "missing $t"; done
grep -q "^Port 8888" /etc/tinyproxy/tinyproxy.conf || fail "tinyproxy is not on port 8888"
grep -qx "ConnectPort 443" /etc/tinyproxy/tinyproxy.conf || fail "tinyproxy does not limit CONNECT"
test -x /etc/init.d/expressvpn-service || fail "missing /etc/init.d/expressvpn-service"

# The init script against a stub daemon: the real one would write its state
# into the image.
echo "init script start, status, stop"
t=$(mktemp -d)
printf '#!/bin/sh\nexec sleep 300\n' > "$t/daemon"
chmod +x "$t/daemon"
sed -e "s|^DAEMON=.*|DAEMON=$t/daemon|" -e "s|^PIDFILE=.*|PIDFILE=$t/pid|" \
  /etc/init.d/expressvpn-service > "$t/init"
chmod +x "$t/init"
grep -qx "DAEMON=$t/daemon" "$t/init" && grep -qx "PIDFILE=$t/pid" "$t/init" \
  || fail "init script no longer sets DAEMON and PIDFILE on lines of their own"
status_rc() { local rc=0; "$t/init" status >/dev/null || rc=$?; echo "$rc"; }
gone() { for _ in 1 2 3 4 5; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done; return 1; }

[ "$(status_rc)" = 3 ] || fail "status before start is not 3"
"$t/init" start
pid=$(cat "$t/pid")
kill -0 "$pid" 2>/dev/null || fail "start did not leave the daemon running"
[ "$(status_rc)" = 0 ] || fail "status of a running daemon is not 0"
"$t/init" start
[ "$(cat "$t/pid")" = "$pid" ] || fail "start on a running daemon launched another"
"$t/init" stop
[ ! -e "$t/pid" ] || fail "stop left the pidfile"
gone "$pid" || fail "stop did not end the daemon"

echo 2147483647 > "$t/pid"
[ "$(status_rc)" = 3 ] || fail "status with a stale pidfile is not 3"
"$t/init" start
pid=$(cat "$t/pid")
kill -0 "$pid" 2>/dev/null || fail "start over a stale pidfile did not start the daemon"
"$t/init" stop
gone "$pid" || fail "stop after a stale pidfile did not end the daemon"

rc=0; "$t/init" restart >/dev/null || rc=$?
[ "$rc" -eq 5 ] || fail "an unknown action exited $rc, not 5"
rm -rf "$t"

echo "boot gate passed"
