#!/usr/bin/env bash
# script-name: disk-alert
# description: df -P 磁盘使用率双水位检查——warn/crit 告警、JSON 与水位退出码
# usage: disk-alert.sh [--warn <pct>] [--crit <pct>] [--json] [-h, --help]
# option: --warn <pct>    warn 水位 0-100（默认 80；>=warn 且 <crit 判 WARN）
# option: --crit <pct>    crit 水位 0-100（默认 90；>=crit 判 CRIT）
# option: --json          结构化 JSON 输出（自动禁用彩色）
# option: --color         强制启用彩色输出（默认仅 stdout 为终端时启用）
# option: --no-color      禁用彩色输出（优先级高于 --color）
# option: -h, --help      显示帮助
# example: disk-alert.sh
# example: disk-alert.sh --warn 75 --crit 85 --json
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: coreutils, awk
# category: ops

set -u -o pipefail

_DA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_DA_ROOT/scripts/lib/common.sh"

readonly _DA_DEFAULT_WARN=80
readonly _DA_DEFAULT_CRIT=90

# 彩色码（由 set_colors 按运行时开关重设，默认无色）
_DA_YELLOW=''
_DA_RED=''
_DA_OFF=''

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stdout（错误分支重定向到 stderr）
usage() {
  cat << 'EOF'
用法: disk-alert.sh [--warn <pct>] [--crit <pct>] [--json] [--no-color]
                    [--color] [-h, --help]
对 df -P 的磁盘使用率做双水位检查（tmpfs 等伪文件系统不列）:
使用率 >= crit 判 CRIT（红），>= warn 且 < crit 判 WARN（黄），其余 OK。
适合 cron/CI 直接按退出码分支处理。

选项:
  --warn <pct>   warn 水位 0-100（默认 80）
  --crit <pct>   crit 水位 0-100（默认 90）
  --json         结构化 JSON 输出（自动禁用彩色）
  --color        强制彩色输出（默认仅 stdout 为终端时启用）
  --no-color     禁用彩色输出
  -h, --help     显示本帮助

退出码: 0=全部正常 1=存在 WARN 2=存在 CRIT 3=用法/运行错误
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 校验 0-100 整数百分比
is_valid_pct() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  ((v >= 0 && v <= 100))
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 使用率列转整数（去 %，非法值按 0）
pct_num() {
  local p="$1"
  p="${p%\%}"
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  printf '%s' "$p"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: JSON 字符串转义（反斜杠/双引号/换行/制表符）
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 磁盘清单（每行: 文件系统<TAB>挂载点<TAB>使用率；伪文件系统不列）
collect_disks() {
  df -P -x tmpfs -x devtmpfs -x squashfs -x efivarfs -x overlay \
    -x iso9660 -x udf 2> /dev/null \
    | awk 'NR > 1 { print $1 "\t" $6 "\t" $5 }'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 单盘水位判定（>=crit→crit；>=warn→warn；否则 ok）
level_for() {
  local num="$1" warn="$2" crit="$3"
  if ((num >= crit)); then
    printf 'crit'
  elif ((num >= warn)); then
    printf 'warn'
  else
    printf 'ok'
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 汇总水位（任一盘 crit→crit；否则任一 warn→warn；否则 ok）
overall_level() {
  local rows="$1" warn="$2" crit="$3"
  local fs mnt pct num level result="ok"
  while IFS=$'\t' read -r fs mnt pct; do
    [[ -n "$fs" ]] || continue
    num="$(pct_num "$pct")"
    level="$(level_for "$num" "$warn" "$crit")"
    if [[ "$level" == "crit" ]]; then
      printf 'crit'
      return 0
    elif [[ "$level" == "warn" ]]; then
      result="warn"
    fi
  done <<< "$rows"
  printf '%s' "$result"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 按开关设置彩色码（true 启用 / 其他禁用）
set_colors() {
  if [[ "$1" == "true" ]]; then
    _DA_YELLOW=$'\033[0;33m'
    _DA_RED=$'\033[0;31m'
    _DA_OFF=$'\033[0m'
  else
    _DA_YELLOW=''
    _DA_RED=''
    _DA_OFF=''
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 渲染文本结果（超限行着色: WARN 黄 / CRIT 红）并输出结论行
render_text() {
  local rows="$1" warn="$2" crit="$3"
  printf '磁盘使用率检查（warn>=%s%%, crit>=%s%%）\n' "$warn" "$crit"
  printf '%-24s %-20s %6s  %s\n' '文件系统' '挂载点' '使用率' '状态'
  local fs mnt pct num level line
  local ok_cnt=0 warn_cnt=0 crit_cnt=0
  while IFS=$'\t' read -r fs mnt pct; do
    [[ -n "$fs" ]] || continue
    num="$(pct_num "$pct")"
    level="$(level_for "$num" "$warn" "$crit")"
    case "$level" in
      ok) ok_cnt=$((ok_cnt + 1)) ;;
      warn) warn_cnt=$((warn_cnt + 1)) ;;
      crit) crit_cnt=$((crit_cnt + 1)) ;;
    esac
    line="$(printf '%-24s %-20s %6s  %s' "$fs" "$mnt" "$pct" \
      "${level^^}")"
    case "$level" in
      warn) printf '%s%s%s\n' "$_DA_YELLOW" "$line" "$_DA_OFF" ;;
      crit) printf '%s%s%s\n' "$_DA_RED" "$line" "$_DA_OFF" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <<< "$rows"
  printf '结论: CRIT=%d WARN=%d OK=%d\n' \
    "$crit_cnt" "$warn_cnt" "$ok_cnt"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 渲染 JSON 结果（level=ok|warn|crit，disks 数组逐盘标注水位）
render_json() {
  local rows="$1" warn="$2" crit="$3" overall="$4"
  local disks_json="" fs mnt pct num level
  while IFS=$'\t' read -r fs mnt pct; do
    [[ -n "$fs" ]] || continue
    num="$(pct_num "$pct")"
    level="$(level_for "$num" "$warn" "$crit")"
    disks_json="${disks_json}{\"fs\": \"$(json_escape "$fs")\","
    disks_json="${disks_json} \"mount\": \"$(json_escape "$mnt")\","
    disks_json="${disks_json} \"use_pct\": $num,"
    disks_json="${disks_json} \"level\": \"$level\"}, "
  done <<< "$rows"
  disks_json="${disks_json%, }"
  printf '{"warn_pct": %s, "crit_pct": %s, "level": "%s", "disks": [%s]}\n' \
    "$warn" "$crit" "$overall" "$disks_json"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——参数解析与校验、df 采集、渲染分派、按汇总水位定退出码
main() {
  local warn="$_DA_DEFAULT_WARN" crit="$_DA_DEFAULT_CRIT"
  local json="false" color="auto"
  while (($#)); do
    case "$1" in
      --warn)
        if (($# < 2)); then
          log_err "--warn 需要一个 0-100 的整数参数"
          return 3
        fi
        warn="$2"
        shift 2
        ;;
      --crit)
        if (($# < 2)); then
          log_err "--crit 需要一个 0-100 的整数参数"
          return 3
        fi
        crit="$2"
        shift 2
        ;;
      --json)
        json="true"
        shift
        ;;
      --color)
        color="always"
        shift
        ;;
      --no-color)
        color="never"
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        log_err "未知选项: $1"
        usage >&2
        return 3
        ;;
    esac
  done
  if ! is_valid_pct "$warn"; then
    log_err "--warn 须为 0-100 的整数: $warn"
    return 3
  fi
  if ! is_valid_pct "$crit"; then
    log_err "--crit 须为 0-100 的整数: $crit"
    return 3
  fi
  if ((crit < warn)); then
    log_err "--crit ($crit) 不得低于 --warn ($warn)"
    return 3
  fi

  local rows
  if ! rows="$(collect_disks)"; then
    log_err "df 执行失败，无法获取磁盘使用率"
    return 3
  fi
  if [[ -z "$rows" ]]; then
    log_err "未获取到任何磁盘信息（df 无输出）"
    return 3
  fi

  local use_color="false"
  if [[ "$color" == "always" ]]; then
    use_color="true"
  elif [[ "$color" == "auto" && -t 1 ]]; then
    use_color="true"
  fi
  [[ "$json" == "true" ]] && use_color="false"
  set_colors "$use_color"

  local overall
  overall="$(overall_level "$rows" "$warn" "$crit")"
  if [[ "$json" == "true" ]]; then
    render_json "$rows" "$warn" "$crit" "$overall"
  else
    render_text "$rows" "$warn" "$crit"
  fi
  case "$overall" in
    crit) return 2 ;;
    warn) return 1 ;;
    *) return 0 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
