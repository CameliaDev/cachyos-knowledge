# Cinnamon Wayland 截图粘贴修复指南

## 问题描述

在 Cinnamon Wayland 环境下，截屏后无法通过 Ctrl+V 粘贴图片到其他应用（如微信、Telegram等）。粘贴出来的是纯文本（文件名）或者纯红色图片。

## 根本原因

**flameshot 的 `-c` 选项只能复制到 X11 剪贴板**，而 Wayland 应用（如微信）读取的是 Wayland 剪贴板。两者是隔离的，导致图片数据丢失。

### 问题链路

```
flameshot gui -c -p ~/图片/截图
    ↓
flameshot 通过 XWayland 运行
    ↓
-c 选项将图片复制到 X11 剪贴板 (XA_CLIPBOARD)
    ↓
Wayland 应用微信读取 Wayland 剪贴板 (wl-copy)
    ↓
Wayland 剪贴板为空 → 粘贴失败/显示异常
```

## 解决方案

### 1. 修改 prtsc-screenshot.sh 脚本

**文件位置：** `/home/arch/.local/bin/prtsc-screenshot.sh`

**关键修改：**
- 移除 flameshot 的 `-c` 选项（在 Wayland 下不工作）
- 截屏后用 `wl-copy` 手动复制图片到 Wayland 剪贴板

```bash
#!/usr/bin/env bash
# 修复: flameshot的-c只能复制到X11剪贴板，需要额外用wl-copy复制到Wayland剪贴板

# Region capture: -p -> save to folder (不要用-c)
flameshot gui -p "$SCREENSHOT_DIR" "$@"
FLAMESHOT_EXIT=$?

if [ $FLAMESHOT_EXIT -eq 0 ]; then
    # 找到刚保存的截图，用wl-copy复制到Wayland剪贴板
    LATEST_FILE=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$LATEST_FILE" ]; then
        wl-copy -t image/png < "$LATEST_FILE"
    fi
fi
```

### 2. 禁用 Cinnamon 默认截屏快捷键（可选）

如果同时使用自定义截屏脚本和 Cinnamon 默认截屏，Print 键会触发两次，导致屏幕闪烁。

```bash
# 禁用 Print 键相关的默认截屏
dconf write /org/cinnamon/desktop/keybindings/media-keys/screenshot "['']"
dconf write /org/cinnamon/desktop/keybindings/media-keys/screenshot-clip "['']"
```

### 3. 重启 prtsc-listener 服务

```bash
sudo systemctl restart prtsc-listener.service
```

## 验证

```bash
# 测试剪贴板是否包含图片
wl-paste --list-types | grep image/png

# 测试粘贴图片
wl-paste --type image/png > /tmp/test.png
file /tmp/test.png
```

## 相关文件

| 文件 | 用途 |
|------|------|
| `scripts/prtsc-screenshot.sh` | 截图脚本（已修复 Wayland 剪贴板问题） |
| `scripts/prtsc-input-listener` | Print Screen evdev 监听器 |
| `services/prtsc-listener.service` | Print Screen 服务的 systemd unit |

## 参考链接

- [Arch Wiki - Screen capture](https://wiki.archlinux.org/title/Screen_capture)
- [wl-clipboard GitHub](https://github.com/bugaevc/wl-clipboard)
- [flameshot Wayland 支持](https://github.com/flameshot-org/flameshot/wiki/Troubleshooting)
