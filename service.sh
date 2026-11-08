#!/system/bin/sh
# ============================================================
# DeepSeek 余额监控 · 开机自启 (service.sh)
# ============================================================

MODDIR="${0%/*}"
. "$MODDIR/common/functions.sh"

# 加载配置
[ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null

# 未配置 key 则跳过
if [ -z "$DEEPSEEK_KEYS" ]; then
  log_msg "未配置 DEEPSEEK_KEYS，跳过启动"
  exit 0
fi

log_msg "模块已启用，准备后台监控"

# 后台常驻（脱离当前 shell，避免阻塞 boot 流程）
nohup sh "$MODDIR/core.sh" daemon >/dev/null 2>&1 &

exit 0