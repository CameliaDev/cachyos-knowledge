#!/usr/bin/env bash
# Region screenshot via flameshot: Windows-style selector, saves to folder + clipboard.
# Triggered by evdev prtsc-listener service on the Print (PrtSc) key.
# 同时复制到 Wayland (wl-copy -f 常驻) 和 X11 (xclip) 剪贴板
# wl-copy -f 保持进程在后台——下次截屏时由 pkill 清理旧进程

export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
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
    # 找到刚保存的截图
    LATEST_FILE=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$LATEST_FILE" ]; then
        # 先杀掉旧的 wl-copy（避免残留进程占用剪贴板）
        pkill -f "wl-copy -t image/png" 2>/dev/null || true
        # Wayland 剪贴板 — 必须用 -f 保持前台运行！
        # 否则 Cinnamon muffin 可能不缓存数据导致粘贴失败。
        wl-copy -f -t image/png < "$LATEST_FILE" &
        echo "$(date '+%H:%M:%S') wl-copy -f (bg pid=$!) OK: $LATEST_FILE" >> "$LOG"
        # X11 剪贴板 (XWayland 应用可用)
        xclip -selection clipboard -t image/png -i "$LATEST_FILE" 2>/dev/null
        echo "$(date '+%H:%M:%S') xclip exit=$?" >> "$LOG"
    fi
fi
