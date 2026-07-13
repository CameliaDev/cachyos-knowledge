#!/usr/bin/env bash
# Deploy all evdev-level hotkey services on CachyOS / Arch Linux
# Run as root: sudo ./setup.sh
set -euo pipefail

USERNAME="${1:-arch}"
USER_UID=$(id -u "$USERNAME" 2>/dev/null || echo 1000)

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

echo "=== Deploying evdev hotkey services ==="

# 1. Ensure python-evdev is installed
pacman -S --needed --noconfirm python-evdev 2>/dev/null || true

# 2. Ensure user is in input group
usermod -a -G input "$USERNAME" 2>/dev/null || true

# 3. Install scripts
cp scripts/shift-ime-toggle /usr/local/bin/shift-ime-toggle
chmod +x /usr/local/bin/shift-ime-toggle

cp scripts/prtsc-input-listener /usr/local/bin/prtsc-input-listener
chmod +x /usr/local/bin/prtsc-input-listener

# 4. Install systemd services
cp services/shift-ime-toggle.service /etc/systemd/system/
cp services/prtsc-listener.service /etc/systemd/system/

# 5. Enable and start
systemctl daemon-reload
systemctl enable --now shift-ime-toggle
systemctl enable --now prtsc-listener

echo ""
echo "=== Deployment complete ==="
systemctl status shift-ime-toggle --no-pager --lines=5
echo ""
systemctl status prtsc-listener --no-pager --lines=5
echo ""
echo "View logs:  sudo journalctl -u shift-ime-toggle -f"
echo "Verify IME: fcitx5-remote  (1=EN, 2=中) — then tap Left Shift"
