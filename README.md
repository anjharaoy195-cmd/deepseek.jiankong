Chinese：
# DeepSeek 余额监控模块

后台定时查询 DeepSeek 官方 API 余额，余额低于阈值时弹 heads-up 悬浮通知 + 震动提醒。

## 特性
- 纯 shell 实现，零 APK、零编译、零第三方依赖
- Android 9 ~ 17（API 28 ~ 37）全兼容，运行时探测 SDK 版本
- 多 API Key 支持（逗号分隔）
- 余额警告 / 严重两级阈值 + 余额恢复通知
- 本周期消费自算（对比上次检查的余额差值）
- 直连 `api.deepseek.com`（国内直连，无需梯子）

## 安装
1. 把本目录打包成 zip（根目录直接含 `module.prop`）
2. Magisk / KernelSU / APatch 刷入 zip
3. 重启

## 配置 API Key（三选一）
1. **预填**：刷入前编辑 `config.conf`，填好 `DEEPSEEK_KEYS`
2. **安装时**：Recovery / TTY 环境刷入会交互询问
3. **安装后**：
   ```
   su -c sh /data/adb/modules/deepseek_balance/setup.sh
   ```

## 常用命令
```sh
# 手动检查一次
su -c sh /data/adb/modules/deepseek_balance/core.sh check

# 发送测试通知（验证通知是否正常）
su -c sh /data/adb/modules/deepseek_balance/core.sh test

# 查看日志
su -c cat /data/adb/modules/deepseek_balance/deepseek_balance.log
```

## 配置项说明
| 项 | 默认 | 说明 |
|---|---|---|
| DEEPSEEK_KEYS | 空 | 必填，sk- 开头，多 key 逗号分隔 |
| CURRENCY_FILTER | CNY | CNY / USD / 留空=全部 |
| WARN_THRESHOLD | 20 | 低于此值 -> 警告悬浮通知 |
| CRITICAL_THRESHOLD | 5 | 低于此值 -> 严重通知 + 震动 |
| CHECK_INTERVAL | 1800 | 轮询间隔（秒），最小 60 |
| NOTIFY_ON_RECOVER | 1 | 余额回升是否通知 |
| ONGOING_NOTIFICATION | 0 | 常驻通知开关 |
| LOG_MAX_KB | 512 | 日志自动轮转上限 |

## 依赖说明
HTTPS 请求按以下顺序降级：`curl` → `wget` → `toybox wget` → `openssl`。
- 绝大多数设备自带 `curl` 即可正常使用
- 若设备无可用 HTTPS 客户端，请安装 curl（如 Termux 的 curl 或 Magisk 模块）

## 通知说明
- 通过 `cmd notification post` 发送，优先级 MAX/HIGH
- Android 13+ 自动授予 shell 通知权限
- 少数 ROM 可能将 heads-up 降级为普通通知栏通知（通知 + 震动仍会触发），不影响提醒功能

## 安全提示
- API Key 明文存于模块目录，仅 root 可读
- 建议模块目录权限保持默认（root 专属）

English：
# DeepSeek Balance Monitor Module

Periodically queries the official DeepSeek API balance in the background. When the balance falls below the threshold, it pops up a heads-up floating notification + vibration alert.

## Features
- Pure shell implementation, zero APK, zero compilation, zero third-party dependencies
- Full compatibility with Android 9 ~ 17 (API 28 ~ 37), with runtime SDK version detection
- Multiple API Key support (comma-separated)
- Two-level balance warning / critical thresholds + balance recovery notification
- Self-calculated current-cycle spending (balance difference compared with the previous check)
- Direct connection to `api.deepseek.com` (direct connection in mainland China, no VPN needed)

## Installation
1. Package this directory into a zip (with `module.prop` directly in the root directory)
2. Flash the zip via Magisk / KernelSU / APatch
3. Reboot

## Configure API Key (Choose One of Three)
1. **Pre-fill**: Edit `config.conf` and fill in `DEEPSEEK_KEYS` before flashing
2. **During installation**: Flashing in a Recovery / TTY environment will prompt interactively
3. **After installation**: Use WebUI to fill it in
   ```
   su -c sh /data/adb/modules/deepseek_balance/setup.sh
   ```

## Common Commands
```sh
# Manually check once
su -c sh /data/adb/modules/deepseek_balance/core.sh check

# Send a test notification (to verify notifications work)
su -c sh /data/adb/modules/deepseek_balance/core.sh test

# View logs
su -c cat /data/adb/modules/deepseek_balance/deepseek_balance.log
```

## Configuration
| Item | Default | Description |
|---|---|---|
| DEEPSEEK_KEYS | empty | Required, starts with sk-, multiple keys separated by commas |
| CURRENCY_FILTER | CNY | CNY / USD / leave empty = all |
| WARN_THRESHOLD | 20 | Below this value -> warning floating notification |
| CRITICAL_THRESHOLD | 5 | Below this value -> critical notification + vibration |
| CHECK_INTERVAL | 1800 | Polling interval (seconds), minimum 60 |
| NOTIFY_ON_RECOVER | 1 | Whether to notify when the balance recovers |
| ONGOING_NOTIFICATION | 0 | Persistent notification toggle |
| LOG_MAX_KB | 512 | Log auto-rotation limit |

## Dependencies
HTTPS requests fall back in the following order: `curl` → `wget` → `toybox wget` → `openssl`.
- Most devices have `curl` built in and work normally
- If no HTTPS client is available on the device, install curl (e.g., curl from Termux or a Magisk module)

## Notifications
- Sent via `cmd notification post`, with priority MAX/HIGH
- Android 13+ automatically grants shell notification permission
- A few ROMs may downgrade heads-up to a regular notification shade notification (notification + vibration still trigger), which does not affect the reminder functionality

## Security Notes
- API Keys are stored in plaintext in the module directory, readable only by root
- It is recommended to keep the module directory permissions at default (root-only)