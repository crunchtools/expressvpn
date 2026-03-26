#!/bin/bash
set -e

if [ -z "$ACTIVATION_CODE" ]; then
  echo "ERROR: ACTIVATION_CODE environment variable is required"
  exit 1
fi

VPN_LOCATION="${VPN_LOCATION:-smart}"

echo "[expressvpn-proxy] Starting ExpressVPN daemon..."
expressvpnd &
sleep 3

echo "[expressvpn-proxy] Activating ExpressVPN..."
/usr/bin/expect <<EOF
spawn expressvpn activate
expect {
  "Enter activation code:" {
    send "${ACTIVATION_CODE}\r"
    exp_continue
  }
  "share anonymized crash reports" {
    send "n\r"
    exp_continue
  }
  "share crash reports" {
    send "n\r"
    exp_continue
  }
  "Activated" {
    puts "\n[expressvpn-proxy] Activation successful"
  }
  "already activated" {
    puts "\n[expressvpn-proxy] Already activated"
  }
  timeout {
    puts "\n[expressvpn-proxy] Activation timed out"
    exit 1
  }
  eof
}
EOF

sleep 2
expressvpn preferences set send_diagnostics false 2>/dev/null || true

echo "[expressvpn-proxy] Connecting to $VPN_LOCATION..."
expressvpn connect "$VPN_LOCATION"
sleep 3

echo "[expressvpn-proxy] VPN Status:"
expressvpn status

echo "[expressvpn-proxy] Starting tinyproxy on port 8888..."
exec tinyproxy -d
