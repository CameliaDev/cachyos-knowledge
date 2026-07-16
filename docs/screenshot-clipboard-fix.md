# Cinnamon Wayland 截图粘贴修复指南

## 问题描述

在 Cinnamon Wayland 环境下，截屏后无法通过 Ctrl+V 粘贴图片到 Firefox。可能有多种症状：
- 粘贴出来的是纯文本（文件名）
- 粘贴无效（什么都不出现）
- 截屏时屏幕闪烁两次

## 三个独立问题及修复

### 问题 1：双闪 —— csd-media-keys 与 evdev listener 冲突

**症状：** 按 Print 键时屏幕闪烁两次，`Pictures/Screenshots/` 和 `图片/截图/` 同时出现文件。

**根因：** 两个进程在抢 Print 键：
| 触发器 | 程序 |
|--------|------|
| prtsc-input-listener (evdev) | flameshot gui |
| Cinnamon csd-media-keys | gnome-screenshot |

Cinnamon 的 `csd-media-keys` 对 Print 键有硬编码处理，即使 dconf 里相关的 screenshot 快捷键都设为空，它仍会调用 `gnome-screenshot`。

**修复：**
```bash
# 禁用 gnome-screenshot（csd-media-keys 找不到它就不会触发）
sudo mv /usr/bin/gnome-screenshot /usr/bin/gnome-screenshot.disabled

# 同时禁用 dconf custom-keybindings 中的 Print 绑定
dconf write /org/cinnamon/desktop/keybindings/custom-keybindings/custom2/binding "['']"
```

### 问题 2：粘贴不了 —— 环境变量缺失

**症状：** 截图保存正常，但 Ctrl+V 无法粘贴图片。`wl-paste --list-types` 可能为空。

**根因：** `prtsc-input-listener`（root systemd service）传给截图脚本的环境变量缺少：
- `WAYLAND_DISPLAY` — wl-copy 需要它找到 Wayland compositor
- `XAUTHORITY` 指向过期文件 — Cinnamon Wayland 用 muffin-Xwaylandauth，不是 ~/.Xauthority

**修复 (`/usr/local/bin/prtsc-input-listener`)：**
```python
import glob
xauth = f"/home/{USER}/.Xauthority"          # fallback
muffin = glob.glob(f"/run/user/{UID}/.muffin-Xwaylandauth.*")
if muffin:
    xauth = muffin[0]                        # Cinnamon Wayland

env = {
    "DISPLAY": ":0",
    "WAYLAND_DISPLAY": "wayland-0",          # ← 新增
    "XAUTHORITY": xauth,                     # ← 修复
    ...
}
```

### 问题 3：粘贴目标限制 —— 不是所有输入框都接受图片

**症状：** 剪贴板有图片（`wl-paste` 能读到），但某些网页输入框 Ctrl+V 无效。

**根因：** 标准 HTML `<input>` 和 `<textarea>` 只接受文本。图片粘贴需要：
- 富文本编辑器（contenteditable、GitHub issue 正文、Notion 等）
- 有 JavaScript `paste` 事件处理的页面
- 文件上传区域

**验证方法：** 打开 `file:///tmp/paste-test.html`（项目中的测试页面），Ctrl+V——如果这里能粘贴，说明剪贴板基础设施正常，问题在目标网页。

## 解决方案总览

### 1. 截图脚本 `/home/arch/.local/bin/prtsc-screenshot.sh`

```bash
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

flameshot gui -p "$SCREENSHOT_DIR" "$@"       # 不用 -c

# 双写剪贴板
pkill -f "wl-copy.*image/png" 2>/dev/null     # 杀旧进程
wl-copy -f -t image/png < "$LATEST_FILE" &    # Wayland (常驻)
xclip -selection clipboard -t image/png -i "$LATEST_FILE"  # X11
```

### 2. Python 监听器 `/usr/local/bin/prtsc-input-listener`

见上文"问题 2"的修复。

### 3. 环境变量 `~/.config/environment.d/fcitx5.conf`

```
MOZ_ENABLE_WAYLAND=1   # Firefox 原生 Wayland 模式
```

### 4. 禁用 csd-media-keys 的 Print 响应

```bash
sudo mv /usr/bin/gnome-screenshot /usr/bin/gnome-screenshot.disabled
```

## 验证

```bash
# 剪贴板
wl-paste --list-types | grep image/png

# 实际数据
wl-paste --type image/png > /tmp/test.png
file /tmp/test.png          # PNG image data

# 测试页面
firefox file:///tmp/paste-test.html
```

## 相关文件

| 文件 | 用途 |
|------|------|
| `scripts/prtsc-screenshot.sh` | 截图脚本（双写剪贴板 + wl-copy -f 常驻） |
| `scripts/prtsc-input-listener` | Print Screen evdev 监听器（修复环境变量） |
| `services/prtsc-listener.service` | Print Screen 服务的 systemd unit |
| `configs/fcitx5-env.conf` | 环境变量 |
| `/usr/bin/gnome-screenshot.disabled` | csd-media-keys 的 Print handler（已禁用） |
