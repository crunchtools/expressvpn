#!/bin/bash
set -euo pipefail

log() { echo "[expressvpn-proxy] $*"; }

if [[ -z "${CODE:-}" ]]; then
  log "ERROR: CODE environment variable is required (ExpressVPN activation code)"
  exit 1
fi

SERVER="${SERVER:-smart}"
export LD_LIBRARY_PATH=/opt/expressvpn/lib

# Unmount container-managed resolv.conf so ExpressVPN can manage DNS
if [[ -f /etc/resolv.conf ]]; then
  cp /etc/resolv.conf /etc/resolv.conf.bak
  umount /etc/resolv.conf &>/dev/null || true
  cp /etc/resolv.conf.bak /etc/resolv.conf
  rm -f /etc/resolv.conf.bak
fi

# Start ExpressVPN daemon via sysvinit
log "Starting ExpressVPN service..."
service expressvpn-service start || service expressvpn start

# Wait for daemon to be ready
log "Waiting for daemon..."
for i in $(seq 1 15); do
  if expressvpnctl status >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! expressvpnctl status >/dev/null 2>&1; then
  log "ERROR: ExpressVPN daemon not responding after 30s"
  exit 1
fi

# Activate via temp file (v5 non-interactive login)
log "Activating ExpressVPN..."
code_file=$(mktemp)
printf '%s' "${CODE}" > "${code_file}"

if ! output=$(expressvpnctl --timeout 60 login "${code_file}" 2>&1); then
  rm -f "${code_file}"
  if grep -qi "Already logged into account" <<< "$output"; then
    log "Already logged in, skipping activation"
  else
    log "Activation failed: $output"
    exit 1
  fi
else
  rm -f "${code_file}"
  log "Activation successful"
fi

expressvpnctl background enable >/dev/null 2>&1 || true

# Connect
log "Connecting to ${SERVER}..."
expressvpnctl set protocol lightwayudp 2>/dev/null || true
expressvpnctl set allowlan true 2>/dev/null || true
expressvpnctl disconnect >/dev/null 2>&1 || true

if ! expressvpnctl connect "${SERVER}"; then
  log "ERROR: Failed to connect to ${SERVER}"
  exit 1
fi

# Wait for connection
for i in $(seq 1 15); do
  state=$(expressvpnctl get connectionstate 2>/dev/null || true)
  if [[ "$state" == "Connected" ]]; then
    break
  fi
  sleep 2
done

log "VPN Status: $(expressvpnctl status 2>/dev/null || echo 'unknown')"

# A connection that reports Connected can still have a dead tunnel resolver.
# After every host reboot the daemon said "Connected to usa-chicago" with tun0
# up and resolv.conf naming the right resolver, and nothing in the container
# could resolve a name until the unit was restarted by hand — so tinyproxy
# spent the week serving an unusable tunnel. Network Lock means resolv.conf
# can only name the tunnel's own resolver, so a name that resolves here
# resolved through the tunnel. Prove that before serving anything.
resolver=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || true)

tunnel_dns_answers() {
  local name
  for name in cloudflare.com github.com; do
    if getent hosts "${name}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

for attempt in 1 2; do
  for i in $(seq 1 10); do
    tunnel_dns_answers && break 2
    sleep 3
  done
  log "In-tunnel DNS via ${resolver:-unknown} is not answering; reconnecting (attempt ${attempt})"
  expressvpnctl disconnect >/dev/null 2>&1 || true
  expressvpnctl connect "${SERVER}" >/dev/null 2>&1 || true
  for i in $(seq 1 15); do
    if [[ "$(expressvpnctl get connectionstate 2>/dev/null || true)" == "Connected" ]]; then
      break
    fi
    sleep 2
  done
done

if ! tunnel_dns_answers; then
  log "ERROR: tunnel is up but in-tunnel DNS via ${resolver:-unknown} never answered"
  exit 1
fi

log "In-tunnel DNS answering via ${resolver:-unknown}"

# Add tinyproxy user to expressvpn group so Network Lock allows its traffic
usermod -aG expressvpn tinyproxy 2>/dev/null || true

# Start tinyproxy in foreground
log "Starting tinyproxy on port 8888..."
exec tinyproxy -d
