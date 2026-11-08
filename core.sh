#!/system/bin/sh
# ============================================================
# DeepSeek 余额监控 · 核心逻辑
# 用法:
#   sh core.sh check    手动检查一次
#   sh core.sh daemon   后台常驻循环
#   sh core.sh test     发送测试通知
# ============================================================

MODDIR="$(cd "$(dirname "$0")" && pwd)"
. "$MODDIR/common/functions.sh"

load_config() {
  [ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null
}

# ---------- 状态读写 ----------
write_state() {
  local label="$1" cur="$2" total="$3" level="$4"
  local tmp="$STATE_FILE.tmp"
  grep -v "^${label}|${cur}|" "$STATE_FILE" 2>/dev/null > "$tmp" 2>/dev/null
  echo "${label}|${cur}|${total}|${level}" >> "$tmp" 2>/dev/null
  mv -f "$tmp" "$STATE_FILE" 2>/dev/null
}

# ---------- 查询单个 key 余额 ----------
query_balance() {
  local key="$1"
  local auth="Authorization: Bearer ${key}"
  http_get "$API_URL" "$API_HOST" "$API_PATH" "$auth"
}

# ---------- 处理单个 key ----------
process_key() {
  local key="$1"
  local label=$(key_label "$key")
  local resp=$(query_balance "$key")

  if [ -z "$resp" ]; then
    log_msg "[$label] 请求失败或无响应"
    echo "[$label] 请求失败"
    return 1
  fi

  if echo "$resp" | grep -q '"error"'; then
    local emsg=$(echo "$resp" | sed -nE 's/.*"message":"([^"]*)".*/\1/p')
    log_msg "[$label] API错误: ${emsg:-未知}"
    echo "[$label] 错误: ${emsg:-未知}"
    return 1
  fi

  local infos=$(parse_balance_infos "$resp")
  if [ -z "$infos" ]; then
    log_msg "[$label] 解析失败: $resp"
    echo "[$label] 解析失败"
    return 1
  fi

  local out=""
  local n=0
  local tmp_lines="$STATE_FILE.lines.$$"
  printf '%s\n' "$infos" > "$tmp_lines" 2>/dev/null
  while IFS= read -r item; do
    [ -z "$item" ] && continue

    local cur=$(extract_field "$item" "currency")
    local total=$(extract_field "$item" "total_balance")
    local grant=$(extract_field "$item" "granted_balance")
    local topup=$(extract_field "$item" "topped_up_balance")
    [ -z "$cur" ] && continue

    # 币种过滤
    if [ -n "$CURRENCY_FILTER" ] && [ "$cur" != "$CURRENCY_FILTER" ]; then
      continue
    fi

    # 上次状态
    local prev_line=$(grep "^${label}|${cur}|" "$STATE_FILE" 2>/dev/null | tail -n1)
    local prev_total=$(echo "$prev_line" | cut -d'|' -f3)
    local prev_level=$(echo "$prev_line" | cut -d'|' -f4)
    [ -z "$prev_level" ] && prev_level=0

    # 本周期消费（自上次检查的减少量）
    local spend=""
    if [ -n "$prev_total" ] && num_cmp "$prev_total" ">" "$total"; then
      spend=$(awk -v a="$prev_total" -v b="$total" 'BEGIN{printf "%.4f", a-b}')
    fi

    # 判断级别: 0正常 1警告 2严重
    local level=0
    if num_cmp "$total" "<" "${CRITICAL_THRESHOLD:-5}"; then
      level=2
    elif num_cmp "$total" "<" "${WARN_THRESHOLD:-20}"; then
      level=1
    fi

    # 通知
    local title=""
    local body=""
    if [ "$level" = "2" ] && [ "$prev_level" != "2" ]; then
      title="[严重] DeepSeek 余额不足"
      body="key ${label} | ${cur}余额 ${total} | 阈值 ${CRITICAL_THRESHOLD}"
      notify "$title" "$body" 2
      do_vibrate 800
    elif [ "$level" = "1" ] && [ "$prev_level" != "1" ] && [ "$prev_level" != "2" ]; then
      title="[警告] DeepSeek 余额偏低"
      body="key ${label} | ${cur}余额 ${total} | 阈值 ${WARN_THRESHOLD}"
      notify "$title" "$body" 1
      do_vibrate 400
    elif [ "$level" = "0" ] && [ "$prev_level" != "0" ] && [ "${NOTIFY_ON_RECOVER:-1}" = "1" ]; then
      title="[恢复] DeepSeek 余额已回升"
      body="key ${label} | ${cur}余额 ${total}"
      notify "$title" "$body" 1
    fi

    write_state "$label" "$cur" "$total" "$level"

    local spend_str=""
    [ -n "$spend" ] && spend_str=" 消费:${spend}"
    out="${out}[${cur}] 余额:${total} 充值:${topup} 赠送:${grant}${spend_str} | "
    n=$((n + 1))
  done < "$tmp_lines"
  rm -f "$tmp_lines" 2>/dev/null

  if [ "$n" -eq 0 ]; then
    echo "[$label] 无符合币种(${CURRENCY_FILTER:-全部})"
    return 0
  fi
  echo "[$label] ${out}"
  return 0
}

# ---------- 常驻通知刷新（读 state 显示最新余额） ----------
refresh_ongoing_notify() {
  [ -f "$STATE_FILE" ] || return 0
  local line=$(tail -n1 "$STATE_FILE" 2>/dev/null)
  [ -z "$line" ] && return 0
  local label=$(echo "$line" | cut -d'|' -f1)
  local cur=$(echo "$line" | cut -d'|' -f2)
  local total=$(echo "$line" | cut -d'|' -f3)
  local level=$(echo "$line" | cut -d'|' -f4)
  [ -z "$total" ] && return 0
  local body=""
  case "$level" in
    2) body="严重 | ${label} ${cur}余额 ${total}（阈值 ${CRITICAL_THRESHOLD:-5}）";;
    1) body="警告 | ${label} ${cur}余额 ${total}（阈值 ${WARN_THRESHOLD:-20}）";;
    *) body="正常 | ${label} ${cur}余额 ${total}";;
  esac
  notify_ongoing "DeepSeek 余额监控" "$body"
}

# ---------- 单次完整检查 ----------
do_check() {
  load_config
  local keys=$(echo "$DEEPSEEK_KEYS" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')
  if [ -z "$keys" ]; then
    echo "未配置 DEEPSEEK_KEYS，请先编辑 config.conf 或执行 setup.sh"
    return 1
  fi

  log_msg "========== 开始检查 (Android $(get_android_ver), SDK $(get_sdk)) =========="

  local any_ok=0
  local oldIFS=$IFS
  IFS='
'
  for key in $keys; do
    IFS=$oldIFS
    process_key "$key" && any_ok=1
  done
  IFS=$oldIFS

  log_msg "========== 检查结束 =========="
  [ "$any_ok" = "1" ] && return 0 || return 1
}

# ---------- 后台常驻循环 ----------
daemon_loop() {
  # 单实例保护：避免重复启动导致多实例轮询、功耗翻倍
  local pidfile="$MODDIR/daemon.pid"
  if [ -f "$pidfile" ]; then
    local oldpid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      log_msg "已有 daemon 实例运行 (pid $oldpid)，跳过重复启动"
      exit 0
    fi
  fi
  echo $$ > "$pidfile" 2>/dev/null

  load_config
  local interval=$(get_conf "CHECK_INTERVAL")
  [ -z "$interval" ] && interval=1800
  # 防呆：最小 60 秒
  if [ "$interval" -lt 60 ] 2>/dev/null; then
    interval=60
  fi

  local ninterval=$(get_conf "NOTIFY_INTERVAL")
  [ -z "$ninterval" ] && ninterval=60
  # 通知重发防呆：最小 10 秒，避免刷爆通知栏
  if [ "$ninterval" -lt 10 ] 2>/dev/null; then
    ninterval=10
  fi

  log_msg "守护进程启动，检查间隔 ${interval} 秒，通知重发间隔 ${ninterval} 秒"
  local last_notify=0
  while true; do
    do_check

    # 独立通知重发计时：通知被系统清理后，最多 ninterval 秒自动补发
    local now=$(date +%s)
    if [ $((now - last_notify)) -ge "$ninterval" ]; then
      if [ "$(get_conf ONGOING_NOTIFICATION)" = "1" ]; then
        refresh_ongoing_notify
      fi
      last_notify=$now
    fi

    sleep "$interval"
  done
}

# ---------- 测试通知 ----------
test_notify() {
  local sdk=$(get_sdk)
  notify "[测试] DeepSeek 余额监控" "Android $(get_android_ver) (SDK $sdk) 通知测试正常" 2
  do_vibrate 300
  echo "测试通知已发送"
}

# ---------- 入口 ----------
case "${1:-}" in
  daemon)
    daemon_loop
    ;;
  test)
    test_notify
    ;;
  check|*)
    do_check
    ;;
esac