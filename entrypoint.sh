#!/bin/bash
set -euo pipefail

log() { echo "[expressvpn-proxy] $*"; }

if [[ -z "${CODE:-}" ]]; then
  log "ERROR: CODE environment variable is required (ExpressVPN activation code)"
  exit 1
fi

SERVER="${SERVER:-smart}"
DAEMON=/opt/expressvpn/bin/expressvpn-daemon
export LD_LIBRARY_PATH=/opt/expressvpn/lib

# Unmount container-managed resolv.conf so ExpressVPN can manage DNS
if [[ -f /etc/resolv.conf ]]; then
  cp /etc/resolv.conf /etc/resolv.conf.bak
  umount /etc/resolv.conf &>/dev/null || true
  cp /etc/resolv.conf.bak /etc/resolv.conf
  rm -f /etc/resolv.conf.bak
fi

# Start ExpressVPN daemon directly (bypass sysvinit/systemd)
log "Starting ExpressVPN daemon..."
$DAEMON &
DAEMON_PID=$!

# Wait for daemon to be ready
log "Waiting for daemon..."
for i in $(seq 1 10); do
  if expressvpnctl status >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! expressvpnctl status >/dev/null 2>&1; then
  log "ERROR: ExpressVPN daemon not responding"
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

# Start tinyproxy in foreground
log "Starting tinyproxy on port 8888..."
exec tinyproxy -d
