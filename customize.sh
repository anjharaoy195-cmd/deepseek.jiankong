#!/system/bin/sh
# ============================================================
# DeepSeek 余额监控 · 安装时配置 (customize.sh)
# ============================================================

ui_print() { echo "$1"; }

CFG="$MODPATH/config.conf"
OLD_CFG="/data/adb/modules/deepseek_balance/config.conf"

# 1) 升级场景：从旧模块恢复配置
if [ -f "$OLD_CFG" ]; then
  ui_print "- 检测到旧配置，已保留"
  cp -f "$OLD_CFG" "$CFG"
  exit 0
fi

# 2) 已预填 key（用户提前改过 config.conf）
if grep -qE '^[[:space:]]*DEEPSEEK_KEYS="[^"]+' "$CFG" 2>/dev/null; then
  ui_print "- 已检测到预填 API Key"
  exit 0
fi

# 3) 交互填 key（仅 TTY 环境生效，如 Recovery 刷入）
if [ -t 0 ]; then
  ui_print "----------------------------------------"
  ui_print " 请输入 DeepSeek API Key (sk- 开头)"
  ui_print " 多个用英文逗号分隔；直接回车跳过"
  ui_print "----------------------------------------"
  printf "API Key: "
  read -r INPUT_KEYS 2>/dev/null
  if [ -n "$INPUT_KEYS" ]; then
    sed -i "s|^DEEPSEEK_KEYS=.*|DEEPSEEK_KEYS=\"$INPUT_KEYS\"|" "$CFG"
    ui_print "- API Key 已写入"
    exit 0
  fi
fi

# 4) 兜底提示
ui_print "! 未检测到 API Key，安装完成后请执行:"
ui_print "  su -c sh /data/adb/modules/deepseek_balance/setup.sh"

exit 0