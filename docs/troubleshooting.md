# 故障排查指南

## 截图粘贴不工作

**现象：** 按 Print → flameshot 截图 → 剪贴板没图、粘贴无效、或双闪。

### 排查顺序

**1. 确认 wl-copy 进程在后台常驻**

```bash
pgrep -a wl-copy
# 应有: wl-copy -f -t image/png
```
如果进程不在 → 截图脚本没跑或 wl-copy 被杀，检查下一条。

**2. 确认剪贴板有数据**

```bash
wl-paste --list-types | grep image/png
```
如果显示 `image/png` 但读取数据为空 → muffin 缓存了 metadata 但数据源进程已死。`pkill wl-copy` 后手动重放图。

**3. 确认 Firefox 是 Wayland 原生模式**

```bash
cat /proc/$(pgrep -o firefox)/environ | tr '\0' '\n' | grep MOZ_ENABLE_WAYLAND
# 应显示 MOZ_ENABLE_WAYLAND=1
```
如果没有 → Firefox 跑在 XWayland，读不到 Wayland 剪贴板。在 `~/.config/environment.d/fcitx5.conf` 加 `MOZ_ENABLE_WAYLAND=1`，重启 Firefox。

**4. 确认目标输入框类型**

```bash
# 打开测试页验证
firefox file:///tmp/paste-test2.html
```
- contenteditable / 富文本编辑器 → 支持图片粘贴 ✅
- `<input type=text>` / `<textarea>` → Web 标准限制，不支持图片 ❌
- 豆包等 AI 聊天框 → 看具体实现，可能需要拖文件

**5. 确认不是双闪问题**

```bash
ls -lt ~/Pictures/Screenshots/ | head -3
```
如果这里有新文件 → `csd-media-keys` 仍在触发 `gnome-screenshot`。运行：
```bash
sudo mv /usr/bin/gnome-screenshot /usr/bin/gnome-screenshot.disabled
```

---

## 输入法切换不工作

### 检查顺序

**1. 确认 fcitx5 在运行**
```bash
ps aux | grep fcitx5 | grep -v grep
fcitx5-remote    # 应返回 1 或 2
```

**2. 确认 shift-ime-toggle 服务在运行**
```bash
sudo systemctl status shift-ime-toggle
```

**3. 实时查看切换日志（按 Shift 同时观察输出）**
```bash
sudo journalctl -u shift-ime-toggle -f
```
正常输出：每次按 Shift 出现 `IME → EN` 或 `IME → 中`

**4. 确认环境变量没有被 ibus 覆盖**
```bash
systemctl --user show-environment | grep -iE 'ibus|fcitx|im_module'
```
应该全是 `fcitx`，不应出现 `ibus`

**5. 如有 ibus 残留，修正**
```bash
systemctl --user set-environment QT_IM_MODULES="fcitx;wayland"
fcitx5 -r    # 重启 fcitx5
```

### 常见故障模式

| 现象 | 根因 | 修复 |
|------|------|------|
| 按 Shift 无反应，日志无输出 | shift-ime-toggle 服务停了 | `sudo systemctl restart shift-ime-toggle` |
| 按一次 Shift 日志输出两次 toggle | 设备过滤不严导致重复事件 | 已通过设备名过滤修复（当前版本 OK） |
| 日志有输出但输入法不变 | 环境变量有 ibus 或 dbus 地址错了 | 检查 `sudo journalctl` 有无权限错误 |

---

## Cinnamon 快捷键不工作

**预期行为：** Cinnamon Wayland 下所有自定义快捷键 (`custom-keybindings`) 都不工作。

**例外：** `csd-media-keys` 对一些内置按键（Print 等）有硬编码处理，可能导致意外行为。

**验证：**
```bash
dconf read /org/cinnamon/desktop/keybindings/custom-list
```

如果确实不工作，**不要尝试修复 Cinnamon**——这是已知 bug。改用 evdev 方案。

---

## 剪贴板数据丢失

**现象：** `wl-paste --list-types` 显示 `image/png` 但读取数据为空。

**根因：** Cinnamon muffin compositor 不缓存剪贴板数据——数据源进程退出后数据就丢了。

**修复：** 必须用 `wl-copy -f`（foreground）让进程保持存活。

```bash
# ❌ 错误——数据会在几秒内消失
wl-copy -t image/png < file.png

# ✅ 正确——进程常驻
wl-copy -f -t image/png < file.png &
```

---

## USB 无线键鼠设备索引偏移

如果重启后 evdev 设备号偏移（event15 → event16），shift-ime-toggle 会自动适配（设备发现循环）。但 prtsc-input-listener 硬编码了 `/dev/input/event3`——如果内置键盘的设备号变了，需要更新脚本或改用设备发现逻辑。

---

## Firefox HSTS 证书错误（Steam++ 加速 GitHub）

### 症状

Firefox 访问 github.com 时显示：
```
错误代码：SEC_ERROR_UNKNOWN_ISSUER
```
无法添加安全例外，因为 github.com 启用了 HSTS。

### 根因

Steam++（Watt Toolkit）通过拦截 HTTPS 流程实现加速，安装了自签名的 SteamTools CA 证书。Firefox 默认不信任此证书，且 GitHub 的 HSTS 策略禁止绕过证书验证。

### 解决方案

**方法：将 SteamTools 证书导入 Firefox 证书库**

```bash
# 1. 从系统 NSS 数据库导出证书
certutil -L -d sql:/home/arch/.pki/nssdb/ -n "SteamTools" -a > /tmp/steamtools.crt

# 2. 导入到 Firefox 的证书库
certutil -A -d sql:/home/arch/.mozilla/firefox/*.default-release/ -n "SteamTools" -t "CT,C,C" -i /tmp/steamtools.crt

# 3. 清理
rm /tmp/steamtools.crt
```

### 验证

```bash
certutil -L -d sql:/home/arch/.mozilla/firefox/*.default-release/ | grep SteamTools
```
应显示：`SteamTools  CT,C,C`
