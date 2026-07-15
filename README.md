# CachyOS 环境问题与解决方案

> 系统：CachyOS (Arch-based, rolling) | 桌面：Cinnamon 6.6.8 (Wayland) | 内核：7.1.3-cachyos

记录在这台机器上遇到的非标准问题及其根因和解决方法。

---

## 目录

- [Cinnamon Wayland 核心缺陷](#cinnamon-wayland-核心缺陷)
- [Fcitx5 输入法架构](#fcitx5-输入法架构)
- [Evdev 级热键方案](#evdev-级热键方案)
- [截图粘贴修复](#截图粘贴修复)
- [键盘设备分析](#键盘设备分析)
- [配置清单](#配置清单)
- [环境变量速查](#环境变量速查)

---

## Cinnamon Wayland 核心缺陷

Cinnamon 6.6.8 + Muffin 6.6.3 在 Wayland 下存在 **合成器级别的功能缺失**，无法通过配置或环境变量修复。

### 三项确认的 bug

| 功能 | 状态 | 证据 |
|------|------|------|
| 自定义快捷键 (`dconf custom-keybindings`) | **完全不工作** | F12、Ctrl+Space、Super+Z 均无反应；`csd-media-keys` 运行但 `HandleKeybinding` dbus 从未触发；xdotool 也无法激活 |
| 输入法热键 (fcitx5 Super+Space) | **完全不工作** | `zwp_input_method_v2` 协议支持不完整；fcitx5 `waylandim` addon 加载但收不到合成器按键事件 |
| 内置输入源切换 (`switch-input-source`) | **完全不工作** | 依赖破损的 IM 协议 |

### 仍正常的功能

- 普通键盘输入、窗口管理快捷键 (Super+Tab, Super+D 等)
- fcitx5 的 XIM/Xwayland 桥接输入

### 根本原因

Cinnamon 的 Wayland 支持是在 GNOME/Mutter 分支上构建的，但对 `zwp_input_method_v2` 协议和自定义快捷键的支持尚未完成——这些是 GNOME 实现但 Cinnamon fork 从 Mutter 继承时遗留下的 "stub" 实现。

---

## Fcitx5 输入法架构

### 软件栈

```
硬件键盘 → evdev (/dev/input/event*)
           ↓ (正常路径 — 被 Cinnamon 拦截)
         Muffin/Cinnamon compositor
           ↓ zwp_input_method_v2 (破损❌)
         fcitx5 waylandim addon      ← 收不到事件！
           ↓
         fcitx5 controller           ← 无法切换

           ↓ (绕过路径 ✅)
         shift-ime-toggle (Python evdev)
           ↓ fcitx5-remote dbus
         fcitx5 controller           ← 正常工作
```

### Ibus 冲突历史

系统同时安装了 fcitx5 和 ibus。Cinnamon 默认会注入 `QT_IM_MODULES=wayland;ibus`，导致部分 Qt 应用加载 ibus 插件与 fcitx5 冲突。

**修复过的问题：**
- `~/.xprofile` — 曾是 ibus 配置
- `~/.bashrc` — 曾是 ibus 配置
- `~/.config/fish/conf.d/fcitx5.fish` — 曾有 `GLFW_IM_MODULE=ibus` typo
- `~/.config/environment.d/fcitx5.conf` — 曾写 `fcitx5` 而非 `fcitx`

---

## Evdev 级热键方案

当 Wayland compositor 不转发按键事件时，唯一可靠的方案是直接读取 `/dev/input/event*`。

### 模式

```
root systemd service → Python evdev (read_loop)
  ↓ 检测目标按键 + 纯按判定
  ↓ sudo -u <user> → 用户 session bus
  ↓ dbus/command → 触发目标操作
```

### shift-ime-toggle

**文件：** `scripts/shift-ime-toggle` | **服务：** `services/shift-ime-toggle.service`

轻按左 Shift（<200ms，无其他按键）→ 切换 fcitx5 中英文。

关键设计决策：
- **幂等切换**：先读当前状态 (`fcitx5-remote`)，再用 `-c` / `-o` 定向设置。盲 toggle (`-t`) 在双键盘事件下会 double-flip（等于没切）
- **线程锁 + 400ms 跨设备 debounce**：一个 Shift 按键会在 event3 和 event15 上各产生一次事件
- **设备名过滤**：只接受名字含 "keyboard" 或 "AT Translated" 且同时有 KEY_A + KEY_SPACE 的设备

### prtsc-input-listener

**文件：** `scripts/prtsc-input-listener` | **服务：** `services/prtsc-listener.service`

监听 Print Screen 键（KEY_SYSRQ）→ 触发截图脚本。同样用 evdev 绕过 X11 keyboard grabs。

---

## 截图粘贴修复

### 问题

Cinnamon Wayland 下，flameshot 截图后无法粘贴到微信等 Wayland 应用。粘贴出来的是纯文本或纯红色图片。

### 根本原因

**flameshot 的 `-c` 选项只能复制到 X11 剪贴板**，而 Wayland 应用读取的是 Wayland 剪贴板。两者隔离，导致图片数据丢失。

### 解决方案

修改 `prtsc-screenshot.sh` 脚本：
1. 移除 flameshot 的 `-c` 选项
2. 截屏后用 `wl-copy` 手动复制到 Wayland 剪贴板

```bash
# 关键代码
flameshot gui -p "$SCREENSHOT_DIR" "$@"  # 不用 -c
wl-copy -t image/png < "$LATEST_FILE"    # 手动复制到 Wayland 剪贴板
```

### 验证

```bash
wl-paste --list-types | grep image/png  # 应显示 image/png
```

详细文档：`docs/screenshot-clipboard-fix.md`

---

## 键盘设备分析

USB 无线键鼠接收器暴露了 **5 个 evdev 节点**，但只有一个对应真正的键盘：

| 设备 | KEY_A | KEY_SPACE | 名字含 "keyboard" | 真实键盘 |
|------|-------|-----------|-------------------|----------|
| event15 (Compx ... Keyboard) | ✓ | ✓ | ✓ | **YES** |
| event3 (AT Translated Set 2) | ✓ | ✓ | ✓ | **YES** (内置) |
| event10 (Compx ... Receiver) | ✓ | ✓ | ✗ | NO — 重复 |
| event13 (Compx ... Consumer Ctrl) | ✗ | ✗ | ✗ | NO |
| event14 (Compx ... System Ctrl) | ✗ | ✗ | ✗ | NO |
| event5 (2.4G Mouse) | ✓ | ✓ | ✗ | NO |
| event8 (2.4G Mouse Consumer Ctrl) | ✓ | ✓ | ✗ | NO |

**教训：** 在这台机器上，任何 evdev 监听器必须同时用 KEY_A + KEY_SPACE + 设备名三个条件过滤，否则每个按键会被重复触发 2-4 次。

### 尝试过但不可行的方案

| 方案 | 失败原因 |
|------|---------|
| keyd `overload()` tap-vs-hold | `overload()` 需要 layer 名而非 key 名；语法不支持直接映射到 F13 |
| 全用 keyd 的 layer 切换 | keyd 配置复杂、表达力不足，且 root 无法直接调 fcitx5-remote |
| Cinnamon 自定义快捷键 | Wayland 下完全不工作 |
| interception-tools | 未安装，功能等价于 evdev 脚本 |
| fcitx5 内置 Shift_L 触发器 | Wayland 下收不到事件 |

---

## 配置清单

| 文件 | 用途 |
|------|------|
| `~/.config/environment.d/fcitx5.conf` | fcitx5 环境变量 |
| `~/.config/fish/conf.d/fcitx5.fish` | Fish shell 下的 fcitx5 变量 |
| `~/.config/fcitx5/config` | fcitx5 热键配置 (Shift_L 触发器已清空——由 evdev 脚本接管) |
| `~/.config/fcitx5/profile` | 输入法分组：keyboard-us + pinyin |
| `/usr/local/bin/shift-ime-toggle` | Shift tap 输入法切换守护进程 |
| `/usr/local/bin/prtsc-input-listener` | Print Screen evdev 监听器 |
| `~/.local/bin/prtsc-screenshot.sh` | 截图脚本（已修复 Wayland 剪贴板问题） |
| `/etc/systemd/system/shift-ime-toggle.service` | Shift tap 服务的 systemd unit |
| `/etc/systemd/system/prtsc-listener.service` | Print Screen 服务的 systemd unit |

---

## 环境变量速查

```
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
QT_IM_MODULES=fcitx;wayland      # 覆盖 Cinnamon 的 ibus 默认值
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=fcitx
```

验证命令：
```bash
# 检查当前 IM 环境变量
systemctl --user show-environment | grep -iE 'ibus|fcitx|im_module'

# 如果 Cinnamon 覆盖了 QT_IM_MODULES，手动修正
systemctl --user set-environment QT_IM_MODULES=fcitx\;wayland

# 验证 fcitx5 连接
fcitx5-remote    # 1=EN, 2=CN

# 查看 shift-ime-toggle 日志
sudo journalctl -u shift-ime-toggle -f
```

---

## 设计原则（本机适用）

1. **不要信任 Wayland 协议支持** — 优先用 evdev 绕过 compositor
2. **所有全局热键 = systemd service + Python evdev** — 这是唯一可靠的模式
3. **幂等操作为王** — 读状态再写，不盲 toggle
4. **双键盘需要跨设备 debounce** — 内置键盘 + 无线键盘 = 同一按键 2 次事件
5. **设备名过滤不可少** — KEY_A + KEY_SPACE 不够，必须过滤名称
