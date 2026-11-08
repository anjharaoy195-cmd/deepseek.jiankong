#!/system/bin/sh
# ============================================================
# DeepSeek 余额监控 · 交互式配置向导
# 用法: su -c sh /data/adb/modules/deepseek_balance/setup.sh
# ============================================================

MODDIR="$(cd "$(dirname "$0")" && pwd)"
CFG="$MODDIR/config.conf"

[ -f "$CFG" ] || { echo "未找到 config.conf"; exit 1; }

# 读取当前值
. "$CFG" 2>/dev/null

echo ""
echo "========================================"
echo "  DeepSeek 余额监控 · 配置向导"
echo "  (直接回车 = 保持当前值)"
echo "========================================"

ask() {
  local prompt="$1" cur="$2"
  printf "%s [%s]: " "$prompt" "$cur"
  read -r IN
  if [ -n "$IN" ]; then
    echo "$IN"
  else
    echo "$cur"
  fi
}

DEEPSEEK_KEYS=$(ask "API Key (sk-开头,多key逗号分隔)" "${DEEPSEEK_KEYS:-}")
CURRENCY_FILTER=$(ask "币种过滤(CNY/USD/留空=全部)" "${CURRENCY_FILTER:-CNY}")
WARN_THRESHOLD=$(ask "警告阈值" "${WARN_THRESHOLD:-20}")
CRITICAL_THRESHOLD=$(ask "严重阈值" "${CRITICAL_THRESHOLD:-5}")
CHECK_INTERVAL=$(ask "轮询间隔(秒)" "${CHECK_INTERVAL:-1800}")
NOTIFY_ON_RECOVER=$(ask "余额回升通知(1=开/0=关)" "${NOTIFY_ON_RECOVER:-1}")
ONGOING_NOTIFICATION=$(ask "常驻通知(1=开/0=关)" "${ONGOING_NOTIFICATION:-0}")
LOG_MAX_KB=$(ask "日志上限(KB)" "${LOG_MAX_KB:-512}")

# 写回（保留注释，只改值）
set_val() {
  local key="$1" val="$2"
  local esc=$(echo "$val" | sed -e 's/[\/&]/\\&/g')
  sed -i "s|^\([[:space:]]*${key}=\)[[:space:]]*.*|\1\"${esc}\"|" "$CFG"
}

set_val "DEEPSEEK_KEYS" "$DEEPSEEK_KEYS"
set_val "CURRENCY_FILTER" "$CURRENCY_FILTER"
set_val "WARN_THRESHOLD" "$WARN_THRESHOLD"
set_val "CRITICAL_THRESHOLD" "$CRITICAL_THRESHOLD"
set_val "CHECK_INTERVAL" "$CHECK_INTERVAL"
set_val "NOTIFY_ON_RECOVER" "$NOTIFY_ON_RECOVER"
set_val "ONGOING_NOTIFICATION" "$ONGOING_NOTIFICATION"
set_val "LOG_MAX_KB" "$LOG_MAX_KB"

echo ""
echo "配置已保存: $CFG"
echo "手动检查: su -c sh $MODDIR/core.sh check"
echo "测试通知: su -c sh $MODDIR/core.sh test"