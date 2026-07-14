# 故障排查指南

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
| 有时能切有时不能切 | 按键时间超过 200ms 阈值 | 调高 `TAP_TIMEOUT_MS` (当前 200ms) |

---

## Cinnamon 快捷键不工作

**预期行为：** Cinnamon Wayland 下所有自定义快捷键 (`custom-keybindings`) 都不工作。

**验证：**
```bash
dconf read /org/cinnamon/desktop/keybindings/custom-list
# 应显示 ['custom0', 'custom1', ...]
```

如果确实不工作，**不要尝试修复 Cinnamon**——这是已知 bug。改用 evdev 方案。

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

# 3. 清理临时文件
rm /tmp/steamtools.crt
```

**参数说明：**
- `CT` - 始终信任此 CA 用于 SSL/TLS
- `C` - 信任用于签发其他证书
- `C` - 信任用于签发代码签名证书

### 验证

```bash
# 检查证书是否已导入
certutil -L -d sql:/home/arch/.mozilla/firefox/*.default-release/ | grep SteamTools
```

应显示：`SteamTools  CT,C,C`

### 注意事项

- 此操作会信任 SteamTools 签发的所有证书
- 重启 Firefox 后生效
- Steam++ 更新后可能需要重新导入证书
