#!/usr/bin/env bash
# Region screenshot via flameshot: Windows-style selector, saves to folder + clipboard.
# Triggered by xbindkeys on the Print (PrtSc) key.
# 修复: flameshot的-c只能复制到X11剪贴板，需要额外用wl-copy复制到Wayland剪贴板

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

SCREENSHOT_DIR="$HOME/图片/截图"
mkdir -p "$SCREENSHOT_DIR"

LOG="/tmp/prtsc-screenshot.log"
echo "$(date '+%H:%M:%S') TRIGGERED DISPLAY=$DISPLAY" >> "$LOG"

# Region capture: -p -> save to folder (不要用-c，flameshot的-c在Wayland下不工作)
flameshot gui -p "$SCREENSHOT_DIR" "$@"
FLAMESHOT_EXIT=$?
echo "$(date '+%H:%M:%S') flameshot exit=$FLAMESHOT_EXIT" >> "$LOG"

if [ $FLAMESHOT_EXIT -eq 0 ]; then
    # 找到刚保存的截图，用wl-copy复制到Wayland剪贴板
    LATEST_FILE=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$LATEST_FILE" ]; then
        wl-copy -t image/png < "$LATEST_FILE"
        echo "$(date '+%H:%M:%S') wl-copy OK: $LATEST_FILE" >> "$LOG"
    fi
fi
