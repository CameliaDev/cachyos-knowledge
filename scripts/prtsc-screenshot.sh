#!/usr/bin/env bash
# Region screenshot via flameshot: Windows-style selector, saves to folder + clipboard.
# Triggered by evdev prtsc-listener service on the Print (PrtSc) key.

export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

SCREENSHOT_DIR="$HOME/图片/截图"
mkdir -p "$SCREENSHOT_DIR"

LOG="/tmp/prtsc-screenshot.log"
echo "$(date '+%H:%M:%S') TRIGGERED DISPLAY=$DISPLAY" >> "$LOG"

# Region capture
flameshot gui -p "$SCREENSHOT_DIR" "$@"
FLAMESHOT_EXIT=$?
echo "$(date '+%H:%M:%S') flameshot exit=$FLAMESHOT_EXIT" >> "$LOG"

if [ $FLAMESHOT_EXIT -eq 0 ]; then
    LATEST_FILE=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$LATEST_FILE" ]; then
        # Wayland clipboard — foreground mode so data stays alive
        pkill -f "wl-copy" 2>/dev/null || true
        sleep 0.2
        wl-copy -f -t image/png < "$LATEST_FILE" &
        echo "$(date '+%H:%M:%S') wl-copy pid=$! OK: $LATEST_FILE" >> "$LOG"

        # X11 clipboard
        xclip -selection clipboard -t image/png -i "$LATEST_FILE" 2>/dev/null
        echo "$(date '+%H:%M:%S') xclip exit=$?" >> "$LOG"
    fi
fi
