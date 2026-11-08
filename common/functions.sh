#!/system/bin/sh
# ============================================================
# DeepSeek 余额监控 · 公共函数库
# 依赖: /system/bin/sh (mksh)、getprop、cmd、curl/wget/openssl、sed/awk
# ============================================================

# 模块目录（未定义时自动探测）
if [ -z "$MODDIR" ]; then
  MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
fi

CONF_FILE="$MODDIR/config.conf"
LOG_FILE="$MODDIR/deepseek_balance.log"
STATE_FILE="$MODDIR/state"
API_HOST="api.deepseek.com"
API_PATH="/user/balance"
API_URL="https://${API_HOST}${API_PATH}"
TAG="deepseek_balance"

# ---------- 日志 ----------
log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
  _rotate_log
}

_rotate_log() {
  local max_kb=512
  local v=$(get_conf "LOG_MAX_KB")
  [ -n "$v" ] && max_kb="$v"
  if [ -f "$LOG_FILE" ]; then
    local bytes=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    local kb=$((bytes / 1024))
    if [ -n "$kb" ] && [ "$kb" -gt "$max_kb" ] 2>/dev/null; then
      mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null
    fi
  fi
}

# ---------- 配置读取 ----------
get_conf() {
  local key="$1"
  grep -E "^[[:space:]]*${key}=" "$CONF_FILE" 2>/dev/null | tail -n1 \
    | sed -E \
      -e "s/^[[:space:]]*${key}=[[:space:]]*//" \
      -e 's/[[:space:]]*#.*$//' \
      -e 's/^"//' \
      -e 's/"$//' \
      -e 's/[[:space:]]*$//'
}

# ---------- 系统信息 ----------
get_sdk() {
  getprop ro.build.version.sdk 2>/dev/null | tr -d '\r\n'
}

get_android_ver() {
  getprop ro.build.version.release 2>/dev/null | tr -d '\r\n'
}

# ---------- 通知权限兜底 (Android 13+) ----------
ensure_notify_perm() {
  local sdk=$(get_sdk)
  if [ -n "$sdk" ] && [ "$sdk" -ge 33 ] 2>/dev/null; then
    cmd appops set com.android.shell POST_NOTIFICATION allow >/dev/null 2>&1
    cmd appops set android POST_NOTIFICATION allow >/dev/null 2>&1
  fi
}

# ---------- 字符串转义 ----------
escape() {
  echo "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}

# ---------- HTTP 请求 ----------
# http_get <url> <host> <path> <auth_header>  -> 响应体到 stdout
http_get() {
  local url="$1" host="$2" path="$3" auth="$4"
  local out=""

  if command -v curl >/dev/null 2>&1; then
    out=$(curl -sS --max-time 20 -H "$auth" "$url" 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
  fi

  if command -v wget >/dev/null 2>&1; then
    out=$(wget -q -O - --timeout=20 --header="$auth" "$url" 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
  fi

  if command -v toybox >/dev/null 2>&1 && toybox wget --help >/dev/null 2>&1; then
    out=$(toybox wget -q -O - --header="$auth" "$url" 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
  fi

  if command -v openssl >/dev/null 2>&1; then
    out=$(printf 'GET %s HTTP/1.1\r\nHost: %s\r\n%s\r\nUser-Agent: curl/8.0\r\nConnection: close\r\n\r\n' \
      "$path" "$host" "$auth" | openssl s_client -connect "${host}:443" -quiet 2>/dev/null)
    out=$(echo "$out" | sed -n '/^\r$/,$p' | tail -n +2 | tr -d '\r')
    [ -n "$out" ] && { echo "$out"; return 0; }
  fi

  return 1
}

# ---------- JSON 解析 ----------
# 提取 balance_infos 数组内容（awk 分割，每行一个币种）
parse_balance_infos() {
  local json="$1"
  printf '%s' "$json" | awk '{
    s = $0
    if (match(s, /"balance_infos":\[/)) {
      s = substr(s, RSTART + RLENGTH)
      sub(/].*/, "", s)
      gsub(/},{/, "\n", s)
      print s
    }
  }'
}

# 提取单个字段值（兼容带/不带引号）
extract_field() {
  local item="$1" key="$2"
  echo "$item" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"?([^,\"}]*)\"?.*/\1/p"
}

# ---------- 通知 ----------
# notify <title> <text> <priority>   priority: 1=HIGH 2=MAX
notify() {
  local title="$1" text="$2" prio="${3:-1}"
  ensure_notify_perm
  local sdk=$(get_sdk)
  local tag="ds_$(date +%s)"

  # 关键修复：cmd notification post 必须以 shell(uid2000) 身份运行。
  # 以 root(uid0) 运行时，Android15+/ColorOS 会把通知包名设成 "root"，
  # 触发 PackageManager$NameNotFoundException: root，通知被静默丢弃。
  # 统一 su 2000 降权，内容走环境变量传递，规避引号转义问题。
  if [ -n "$sdk" ] && [ "$sdk" -ge 35 ] 2>/dev/null; then
    # Android 15+ 新语法: -t 标题, -S style(bigtext), <tag> <text>
    DS_N_TITLE="$title" DS_N_TAG="$tag" DS_N_TEXT="$text" \
      su 2000 -c 'cmd notification post -t "$DS_N_TITLE" -S bigtext "$DS_N_TAG" "$DS_N_TEXT"' >/dev/null 2>&1
    return $?
  else
    # Android 8~14 旧语法: -p priority, -c channel, -t title, -S style, <tag> <text>
    DS_N_TITLE="$title" DS_N_TAG="$tag" DS_N_TEXT="$text" DS_N_PRIO="$prio" DS_N_CH="$TAG" \
      su 2000 -c 'cmd notification post -p "$DS_N_PRIO" -c "$DS_N_CH" -t "$DS_N_TITLE" -S bigtext "$DS_N_TAG" "$DS_N_TEXT"' >/dev/null 2>&1
    return $?
  fi
}

# ---------- 常驻通知（固定 tag，每次刷新更新同一条，避免堆叠） ----------
# notify_ongoing <title> <text>
notify_ongoing() {
  local title="$1" text="$2"
  ensure_notify_perm
  local sdk=$(get_sdk)
  local tag="ds_ongoing"
  if [ -n "$sdk" ] && [ "$sdk" -ge 35 ] 2>/dev/null; then
    DS_N_TITLE="$title" DS_N_TAG="$tag" DS_N_TEXT="$text" \
      su 2000 -c 'cmd notification post -t "$DS_N_TITLE" -S bigtext "$DS_N_TAG" "$DS_N_TEXT"' >/dev/null 2>&1
    return $?
  else
    DS_N_TITLE="$title" DS_N_TAG="$tag" DS_N_TEXT="$text" DS_N_PRIO="2" DS_N_CH="$TAG" \
      su 2000 -c 'cmd notification post -p "$DS_N_PRIO" -c "$DS_N_CH" -t "$DS_N_TITLE" -S bigtext "$DS_N_TAG" "$DS_N_TEXT"' >/dev/null 2>&1
    return $?
  fi
}

# ---------- 震动 ----------
do_vibrate() {
  local ms="${1:-600}"
  cmd vibrator vibrate "$ms" >/dev/null 2>&1 && return 0
  cmd vibrator on "$ms" >/dev/null 2>&1 && return 0
  cmd vibrator "$ms" >/dev/null 2>&1 && return 0
  return 1
}

# ---------- 数值比较（awk，支持浮点） ----------
# num_cmp <a> <op> <b>   op 例如: < > <= >= ==
num_cmp() {
  local a="$1" op="$2" b="$3"
  awk -v a="$a" -v b="$b" "BEGIN{exit !(a $op b)}"
}

# ---------- key 显示标签（隐藏完整 key） ----------
key_label() {
  local key="$1"
  local len=${#key}
  if [ "$len" -le 14 ]; then
    echo "$key"
  else
    local tailpos=$((len - 4))
    echo "${key:0:10}...${key:tailpos}"
  fi
}