#!/bin/bash
# ExpressVPN leaves resolv.conf 0700 root after connect and tinyproxy resolves
# as the tinyproxy user. Runs the entrypoint's own share_resolv_conf against a
# 0700 file and proves tinyproxy can read it afterwards, and that the tunnel
# DNS check probes as tinyproxy rather than root. Run inside the image (or any
# host with a tinyproxy user): bash resolv-perms.sh [path/to/entrypoint.sh]
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
entrypoint="${1:-/entrypoint.sh}"
as_tinyproxy() { setpriv --reuid=tinyproxy --regid=tinyproxy --init-groups "$@"; }

id tinyproxy >/dev/null 2>&1 || fail "no tinyproxy user"
defs=$(sed -n -e '/^log() /p' -e '/^share_resolv_conf() {/,/^}/p' "${entrypoint}")
grep -q '^share_resolv_conf() {' <<<"${defs}" || fail "entrypoint has no share_resolv_conf"
eval "${defs}"

t=$(mktemp -d)
trap 'rm -rf "${t}"' EXIT
chmod 0755 "${t}"
f="${t}/resolv.conf"
echo "nameserver 10.0.0.1" > "${f}"
chmod 0700 "${f}"

echo "a 0700 resolv.conf is unreadable to tinyproxy"
if as_tinyproxy cat "${f}" >/dev/null 2>&1; then
  fail "tinyproxy read a 0700 root file; this test proves nothing"
fi

echo "share_resolv_conf makes it readable to tinyproxy"
out=$(share_resolv_conf "${f}")
[ "$(stat -c %a "${f}")" = 644 ] || fail "mode is $(stat -c %a "${f}"), not 644"
grep -q 'was 700; reset to 0644' <<<"${out}" || fail "no log line for the reset: ${out}"
as_tinyproxy grep -q '^nameserver 10.0.0.1$' "${f}" || fail "tinyproxy still cannot read it"

echo "share_resolv_conf is quiet on a file already shared, and on a missing one"
[ -z "$(share_resolv_conf "${f}")" ] || fail "logged a reset on a 0644 file"
share_resolv_conf "${t}/absent" || fail "a missing file is an error"

echo "the tunnel DNS check resolves as tinyproxy, after sharing"
probe=$(sed -n '/^wait_for_tunnel_dns() {/,/^}/p' "${entrypoint}")
grep -q 'share_resolv_conf' <<<"${probe}" || fail "wait_for_tunnel_dns does not share resolv.conf"
grep -q 'setpriv --reuid=tinyproxy' <<<"${probe}" || fail "wait_for_tunnel_dns probes as root"

echo "resolv.conf permission checks passed"
