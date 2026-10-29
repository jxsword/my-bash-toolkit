#!/usr/bin/env bash
# script-name: sysinfo
# description: 主机巡检摘要——内核/发行版、uptime 与负载、磁盘（超阈值标红）、内存/swap、失败 systemd 单元、最近登录
# usage: sysinfo.sh [--warn <pct>] [--json] [--no-color] [--color] [-h, --help]
# option: --warn <pct>    磁盘使用率告警阈值 0-100（默认 80，>= 阈值标红/标记）
# option: --json          结构化 JSON 输出（自动禁用彩色）
# option: --color         强制启用彩色输出（默认仅 stdout 为终端时启用）
# option: --no-color      禁用彩色输出（优先级高于 --color）
# option: -h, --help      显示帮助
# example: sysinfo.sh
# example: sysinfo.sh --warn 90 --json
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: coreutils, procps, systemd(可选), last(可选)
# category: system

set -u -o pipefail

_SI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_SI_ROOT/scripts/lib/common.sh"

readonly _SI_DEFAULT_WARN=80

# 彩色码（由 set_colors 按运行时开关重设，默认无色）
_SI_RED=''
_SI_OFF=''

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stderr
usage() {
  cat << 'EOF'
用法: sysinfo.sh [--warn <pct>] [--json] [--no-color] [--color] [-h, --help]
一次输出主机巡检摘要，段落:
  1. 系统           内核版本与发行版
  2. 运行时间与负载 uptime 与 1/5/15 分钟负载
  3. 磁盘使用       df -P（tmpfs 等伪文件系统不列），使用率 >= 阈值标红
  4. 内存与 swap    free 实测（IEC 人类可读）
  5. systemd        失败单元列表（无 systemd 自动降级跳过）
  6. 最近登录       last -n 5（last 不可用自动降级跳过）

选项:
  --warn <pct>   磁盘使用率告警阈值 0-100（默认 80）
  --json         结构化 JSON 输出（自动禁用彩色）
  --color        强制彩色输出（默认仅 stdout 为终端时启用）
  --no-color     禁用彩色输出
  -h, --help     显示本帮助

退出码: 0=成功 2=用法错误
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
# fn: 发行版名（/etc/os-release 的 PRETTY_NAME，缺失时 unknown）
get_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release \
      && printf '%s' "${PRETTY_NAME:-unknown}"
  else
    printf 'unknown'
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 运行时间（uptime -p 优先，退化 /proc/uptime 换算）
get_uptime_pretty() {
  local up
  up="$(uptime -p 2> /dev/null || true)"
  if [[ -n "$up" ]]; then
    printf '%s' "$up"
    return 0
  fi
  if [[ -r /proc/uptime ]]; then
    awk '{printf "up %d days, %02d:%02d", int($1 / 86400), \
      int($1 % 86400 / 3600), int($1 % 3600 / 60)}' /proc/uptime
  else
    printf 'unknown'
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 1/5/15 分钟负载（空格分隔；/proc/loadavg 不可用时输出空）
get_loads() {
  [[ -r /proc/loadavg ]] || return 0
  local l1 l5 l15 _
  read -r l1 l5 l15 _ < /proc/loadavg
  printf '%s %s %s' "$l1" "$l5" "$l15"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 磁盘清单（每行: 文件系统<TAB>挂载点<TAB>使用率；伪文件系统不列）
collect_disks() {
  df -P -x tmpfs -x devtmpfs -x squashfs -x efivarfs -x overlay \
    -x iso9660 -x udf 2> /dev/null \
    | awk 'NR > 1 { print $1 "\t" $6 "\t" $5 }'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 内存与 swap 实测（每行: mem|swap<TAB>total<TAB>used<TAB>free，字节）
#     LC_ALL=C 固定 free 输出标签（本地化下 Mem: 会译为其他语言）
collect_mem() {
  LC_ALL=C free -b 2> /dev/null | awk '
    $1 == "Mem:" { printf "mem\t%s\t%s\t%s\n", $2, $3, $4 }
    $1 == "Swap:" { printf "swap\t%s\t%s\t%s\n", $2, $3, $4 }'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 失败 systemd 单元名（每行一个；systemctl 不可用/无运行中实例返回非零）
collect_failed() {
  command -v systemctl > /dev/null 2>&1 || return 1
  systemctl list-units --failed --no-legend --no-pager --plain \
    2> /dev/null | awk '{print $1}'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 最近登录（last -n 5 原始输出；last 不可用返回非零）
collect_last() {
  command -v last > /dev/null 2>&1 || return 1
  last -n 5 2> /dev/null
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 按开关设置彩色码（true 启用 / 其他禁用）
set_colors() {
  if [[ "$1" == "true" ]]; then
    _SI_RED=$'\033[0;31m'
    _SI_OFF=$'\033[0m'
  else
    _SI_RED=''
    _SI_OFF=''
  fi
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
# fn: 字节转 IEC 人类可读（numfmt 缺失时原样输出）
humanize_bytes() {
  numfmt --to=iec --suffix=B -- "$1" 2> /dev/null \
    || printf '%s' "$1"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 渲染文本巡检摘要到 stdout（磁盘超阈值行标红）
render_text() {
  local warn="$1"
  local kernel distro up loads l1 l5 l15
  kernel="$(uname -sr 2> /dev/null || printf 'unknown')"
  distro="$(get_distro)"
  up="$(get_uptime_pretty)"
  loads="$(get_loads)"
  read -r l1 l5 l15 <<< "$loads"

  echo "== 系统 =="
  echo "内核: $kernel"
  echo "发行版: $distro"
  echo
  echo "== 运行时间与负载 =="
  echo "运行时间: ${up:-unknown}"
  if [[ -n "$l1" ]]; then
    echo "负载 (1/5/15min): $l1 / $l5 / $l15"
  else
    echo "负载: 不可用"
  fi
  echo
  echo "== 磁盘使用（阈值 ${warn}%，标红为超限） =="
  printf '%-26s %-24s %6s\n' "文件系统" "挂载点" "使用率"
  local line fs mnt pct num any="false"
  while IFS=$'\t' read -r fs mnt pct; do
    [[ -n "$fs" ]] || continue
    any="true"
    num="$(pct_num "$pct")"
    line="$(printf '%-26s %-24s %6s' "$fs" "$mnt" "$pct")"
    if ((num >= warn)); then
      printf '%s%s%s\n' "$_SI_RED" "$line" "$_SI_OFF"
    else
      printf '%s\n' "$line"
    fi
  done < <(collect_disks)
  [[ "$any" == "true" ]] || echo "（无可用磁盘信息）"
  echo
  echo "== 内存与 swap =="
  local tag total used free mem_any="false"
  while IFS=$'\t' read -r tag total used free; do
    [[ -n "$tag" ]] || continue
    mem_any="true"
    printf '%s: 总计 %s / 已用 %s / 可用 %s\n' "$tag" \
      "$(humanize_bytes "$total")" "$(humanize_bytes "$used")" \
      "$(humanize_bytes "$free")"
  done < <(collect_mem)
  [[ "$mem_any" == "true" ]] || echo "（free 不可用）"
  echo
  echo "== systemd 失败单元 =="
  local failed
  if failed="$(collect_failed)"; then
    if [[ -n "$failed" ]]; then
      printf '%s\n' "$failed"
    else
      echo "（无失败单元）"
    fi
  else
    echo "（systemd 不可用，已降级跳过）"
  fi
  echo
  echo "== 最近登录（last -n 5） =="
  local lastout
  if lastout="$(collect_last)"; then
    if [[ -n "$lastout" ]]; then
      printf '%s\n' "$lastout"
    else
      echo "（无登录记录）"
    fi
  else
    echo "（last 不可用，已降级跳过）"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 渲染 JSON 巡检摘要到 stdout（磁盘项 over 即超阈值标记）
render_json() {
  local warn="$1"
  local kernel distro up loads l1 l5 l15
  kernel="$(json_escape "$(uname -sr 2> /dev/null || printf 'unknown')")"
  distro="$(json_escape "$(get_distro)")"
  up="$(json_escape "$(get_uptime_pretty)")"
  loads="$(get_loads)"
  read -r l1 l5 l15 <<< "$loads"

  local disks_json="" item fs mnt pct num over
  while IFS=$'\t' read -r fs mnt pct; do
    [[ -n "$fs" ]] || continue
    num="$(pct_num "$pct")"
    over="false"
    ((num >= warn)) && over="true"
    item="$(printf \
      '{"fs": "%s", "mount": "%s", "use_pct": %s, "over": %s}' \
      "$(json_escape "$fs")" "$(json_escape "$mnt")" "$num" "$over")"
    disks_json="${disks_json}${item}, "
  done < <(collect_disks)
  disks_json="${disks_json%, }"

  local tag total used free
  local mtotal=0 mused=0 mfree=0 stotal=0 sused=0 sfree=0
  while IFS=$'\t' read -r tag total used free; do
    case "$tag" in
      mem)
        mtotal="${total:-0}"
        mused="${used:-0}"
        mfree="${free:-0}"
        ;;
      swap)
        stotal="${total:-0}"
        sused="${used:-0}"
        sfree="${free:-0}"
        ;;
    esac
  done < <(collect_mem)

  local sd_avail="false" failed_out=""
  if failed_out="$(collect_failed)"; then
    sd_avail="true"
  fi
  local units_json="" u
  if [[ "$sd_avail" == "true" ]]; then
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      units_json="${units_json}\"$(json_escape "$u")\", "
    done <<< "$failed_out"
    units_json="${units_json%, }"
  fi

  local last_json="" ll last_out
  if last_out="$(collect_last)"; then
    while IFS= read -r ll; do
      [[ -n "$ll" ]] || continue
      last_json="${last_json}\"$(json_escape "$ll")\", "
    done <<< "$last_out"
    last_json="${last_json%, }"
  fi

  local json=""
  json="${json}{"
  json="${json} \"warn_pct\": $warn,"
  json="${json} \"kernel\": \"$kernel\","
  json="${json} \"distro\": \"$distro\","
  json="${json} \"uptime\": \"$up\","
  json="${json} \"load1\": ${l1:-null},"
  json="${json} \"load5\": ${l5:-null},"
  json="${json} \"load15\": ${l15:-null},"
  json="${json} \"disks\": [$disks_json],"
  json="${json} \"mem_bytes\":"
  json="${json} {\"total\": $mtotal, \"used\": $mused, \"free\": $mfree},"
  json="${json} \"swap_bytes\":"
  json="${json} {\"total\": $stotal, \"used\": $sused, \"free\": $sfree},"
  json="${json} \"systemd_available\": $sd_avail,"
  json="${json} \"failed_units\": [$units_json],"
  json="${json} \"last_logins\": [$last_json]"
  json="${json}}"
  printf '%s\n' "$json"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 参数解析、彩色开关判定与渲染分派
main() {
  local warn="$_SI_DEFAULT_WARN" json="false" color="auto"
  while (($#)); do
    case "$1" in
      --warn)
        if (($# < 2)); then
          log_err "--warn 需要一个 0-100 的整数参数"
          return 2
        fi
        warn="$2"
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
        return 2
        ;;
    esac
  done
  if ! is_valid_pct "$warn"; then
    log_err "--warn 须为 0-100 的整数: $warn"
    return 2
  fi
  local use_color="false"
  if [[ "$color" == "always" ]]; then
    use_color="true"
  elif [[ "$color" == "auto" && -t 1 ]]; then
    use_color="true"
  fi
  [[ "$json" == "true" ]] && use_color="false"
  set_colors "$use_color"
  if [[ "$json" == "true" ]]; then
    render_json "$warn"
  else
    render_text "$warn"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
