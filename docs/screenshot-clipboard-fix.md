# Cinnamon Wayland 截图粘贴修复指南

## 问题描述

在 Cinnamon Wayland 环境下，截屏后无法通过 Ctrl+V 粘贴图片到其他应用（如 Firefox、微信、Telegram等）。粘贴出来的是纯文本（文件名）或者纯红色图片。

## 根本原因

**flameshot 的 `-c` 选项只能复制到 X11 剪贴板**，而 Wayland 应用（如 Firefox Wayland 原生模式、微信）读取的是 Wayland 剪贴板。两者是隔离的，导致图片数据丢失。

### 问题链路

```
flameshot gui -c -p ~/图片/截图
    ↓
flameshot 通过 XWayland 运行
    ↓
-c 选项将图片复制到 X11 剪贴板 (XA_CLIPBOARD)
    ↓
Wayland 应用（Firefox Wayland 原生模式）读取 Wayland 剪贴板
    ↓
Wayland 剪贴板为空 → 粘贴失败/显示异常
```

反过来，如果应用是 XWayland 模式（如没有 MOZ_ENABLE_WAYLAND 的 Firefox），那 `wl-copy` 写入的 Wayland 剪贴板数据同样无法被 XWayland 应用看到。

## 解决方案

### 1. 修改 prtsc-screenshot.sh 脚本

**文件位置：** `/home/arch/.local/bin/prtsc-screenshot.sh`

**关键修改：**
- 移除 flameshot 的 `-c` 选项（在 Wayland 下不工作）
- 截屏后**同时**用 `wl-copy` 和 `xclip` 写入两种剪贴板
- 设置 `WAYLAND_DISPLAY` 环境变量

```bash
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# 截屏
flameshot gui -p "$SCREENSHOT_DIR" "$@"  # 不用 -c

# 双写剪贴板
wl-copy -t image/png < "$LATEST_FILE"   # Wayland 原生应用
xclip -selection clipboard -t image/png -i "$LATEST_FILE"  # XWayland 应用
```

### 2. 修复 prtsc-input-listener 环境变量

**文件位置：** `/usr/local/bin/prtsc-input-listener`

**两个 bug：**
- `WAYLAND_DISPLAY` 缺失 → wl-copy 找不到 Wayland compositor
- `XAUTHORITY` 指向旧文件 → xclip 认证失败

**修复后：**
```python
env = {
    "DISPLAY": ":0",
    "WAYLAND_DISPLAY": "wayland-0",       # ← 新增！
    "XAUTHORITY": xauth,                   # ← 修复为 muffin-Xwaylandauth 路径
    ...
}

# XAUTHORITY 解析：Cinnamon Wayland → muffin-Xwaylandauth
#                  LightDM          → /run/lightdm/<user>/xauthority
#                  其他             → ~/.Xauthority
```

### 3. 添加 MOZ_ENABLE_WAYLAND（让 Firefox 以 Wayland 原生模式运行）

**文件位置：** `~/.config/environment.d/fcitx5.conf`

```bash
MOZ_ENABLE_WAYLAND=1
```

这样 Firefox 以 Wayland 原生模式运行，直接读取 Wayland 剪贴板（wl-copy 写入的数据）。

### 4. 重启 prtsc-listener 服务

```bash
sudo systemctl restart prtsc-listener.service
```

重启 Firefox 以应用 MOZ_ENABLE_WAYLAND（完全关闭 Firefox，再打开）。

## 验证

```bash
# 测试剪贴板是否包含图片
wl-paste --list-types | grep image/png    # 应显示 image/png
xclip -selection clipboard -t TARGETS -o  | grep image/png

# 测试粘贴图片
wl-paste --type image/png > /tmp/test.png
file /tmp/test.png    # 应显示 "PNG image data"
```

## 相关文件

| 文件 | 用途 |
|------|------|
| `scripts/prtsc-screenshot.sh` | 截图脚本（双写剪贴板） |
| `scripts/prtsc-input-listener` | Print Screen evdev 监听器（修复环境变量） |
| `services/prtsc-listener.service` | Print Screen 服务的 systemd unit |
| `configs/fcitx5-env.conf` | 环境变量（含 MOZ_ENABLE_WAYLAND=1） |

## 参考链接

- [Arch Wiki - Screen capture](https://wiki.archlinux.org/title/Screen_capture)
- [wl-clipboard GitHub](https://github.com/bugaevc/wl-clipboard)
- [flameshot Wayland 支持](https://github.com/flameshot-org/flameshot/wiki/Troubleshooting)
