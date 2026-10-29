#!/usr/bin/env bash
# script-name: log-grep
# description: 多文件日志过滤——时间窗（--since/--until）+ 关键字 AND/OR 组合 + 匹配高亮
# usage: log-grep.sh [选项] <文件>...
# option: -k, --keyword <关键字>       OR 关键字（可重复）：命中任一即输出
# option: -K, --and-keyword <关键字>   AND 关键字（可重复）：必须全部命中
# option: --since <时间>   仅输出此时间之后的行：相对（30s/10m/2h/1d，距现在之前）或绝对（ISO/常见日期）
# option: --until <时间>   仅输出此时间之前的行，格式同 --since
# option: --no-color   禁用匹配高亮（默认高亮关键字）
# option: -h, --help   显示帮助
# example: log-grep.sh -k ERROR app.log
# example: log-grep.sh -k error -K timeout app.log gateway.log
# example: log-grep.sh --since 2h -k WARN syslog.log
# example: log-grep.sh --since 2026-10-30T09:00 --until 2026-10-30T10:00 app.log
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash, coreutils, sed
# category: text

set -u -o pipefail

_LOGGREP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_LOGGREP_ROOT/scripts/lib/common.sh"

# 过滤状态（由 main 解析后写入，_filter_stream 读取）
OR_KWS=()
AND_KWS=()
FILES=()
SINCE_EPOCH=-1
UNTIL_EPOCH=-1
MATCH_COUNT=0
HAS_READ_ERR=0
HL_SED=""
TMP_OUT=""

# 时间戳 → epoch 换算缓存（键=行内时间串，值=epoch 秒）
declare -A _EPOCH_CACHE=()

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法
usage() {
  cat << 'EOF'
用法: log-grep.sh [选项] <文件>...
多文件日志过滤：按时间窗与关键字组合筛选行。文件为 - 时读 stdin。

选项:
  -k, --keyword <关键字>       OR 关键字（可重复）：命中任一即输出
  -K, --and-keyword <关键字>   AND 关键字（可重复）：必须全部命中
  --since <时间>               仅输出此时间之后的行
  --until <时间>               仅输出此时间之前的行
  --no-color                   禁用匹配高亮（默认高亮关键字）
  -h, --help                   显示本帮助

时间格式:
  相对: 30s / 10m / 2h / 1d（均指「距现在之前 N 单位」）
  绝对: ISO 8601（2026-10-30T09:00:00）或常见日期（2026-10-30 09:00:00）

说明:
  - 行内时间戳宽容识别：ISO 8601（含 [T ] 分隔、时区后缀）、syslog
    （Oct 30 09:15:00，可带星期前缀；年份按当前年补全）、方括号包裹。
  - 关键字按固定字符串（非正则）匹配，区分大小写。
  - 时间过滤激活时，无法解析出时间戳的行不输出。
  - 多文件时每行输出前缀「文件名:」；退出码: 0 有匹配；1 无匹配；
    2 用法/参数错误；3 存在不可读文件。
  - 输出重定向到管道/文件时仍默认高亮，建议此时加 --no-color。
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 转义字符串中的 ERE 元字符（供 sed 高亮模式使用）
_sed_escape_ere() {
  printf '%s' "$1" | sed -e 's/[][\\.*^$+?|(){}]/\\&/g'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 解析 --since/--until 时间（相对 Ns/Nm/Nh/Nd 或绝对日期），输出绝对 epoch 秒
_parse_time() {
  local spec="$1"
  local reRel='^([0-9]+)([smhd])$'
  if [[ "$spec" =~ $reRel ]]; then
    local n="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}" sec=0
    case "$unit" in
      s) sec=1 ;;
      m) sec=60 ;;
      h) sec=3600 ;;
      d) sec=86400 ;;
    esac
    echo $(($(date +%s) - n * sec))
    return 0
  fi
  local epoch
  epoch="$(date -d "$spec" +%s 2> /dev/null)" || return 1
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  echo "$epoch"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 从行首提取时间戳并换算 epoch（ISO/syslog 宽容识别，带缓存）
_line_epoch() {
  local line="$1" ts epoch cached
  local reIsoA reIsoB reIsoC reIso reSysA reSysB reSysC reSys
  reIsoA='^\[?[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2})'
  reIsoB='([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?)?'
  reIsoC='([[:space:]]?(Z|[+-][0-9]{2}:?[0-9]{2}))?'
  reIso="${reIsoA}${reIsoB}${reIsoC}"
  reSysA='^\[?[[:space:]]*([A-Z][a-z]{2}[[:space:]]+)?'
  reSysB='([A-Z][a-z]{2}[[:space:]]+[0-9]{1,2}[[:space:]]+'
  reSysC='[0-9]{2}:[0-9]{2}:[0-9]{2})'
  reSys="${reSysA}${reSysB}${reSysC}"
  if [[ "$line" =~ $reIso ]]; then
    ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]:-}${BASH_REMATCH[4]:-}"
  elif [[ "$line" =~ $reSys ]]; then
    ts="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  cached="${_EPOCH_CACHE[$ts]:-}"
  if [[ -n "$cached" ]]; then
    printf '%s\n' "$cached"
    return 0
  fi
  epoch="$(date -d "$ts" +%s 2> /dev/null)" || return 1
  _EPOCH_CACHE["$ts"]="$epoch"
  printf '%s\n' "$epoch"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 对单路输入逐行过滤（关键字 OR/AND + 时间窗），命中行写入 stdout
_filter_stream() {
  local prefix="$1" line kw hit ts
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((${#OR_KWS[@]} > 0)); then
      hit=0
      for kw in "${OR_KWS[@]}"; do
        if [[ "$line" == *"$kw"* ]]; then
          hit=1
          break
        fi
      done
      if ((hit == 0)); then
        continue
      fi
    fi
    for kw in "${AND_KWS[@]}"; do
      if [[ "$line" != *"$kw"* ]]; then
        continue 2
      fi
    done
    if ((SINCE_EPOCH >= 0 || UNTIL_EPOCH >= 0)); then
      ts="$(_line_epoch "$line")" || continue
      if ((SINCE_EPOCH >= 0 && ts < SINCE_EPOCH)); then
        continue
      fi
      if ((UNTIL_EPOCH >= 0 && ts > UNTIL_EPOCH)); then
        continue
      fi
    fi
    MATCH_COUNT=$((MATCH_COUNT + 1))
    printf '%s%s\n' "$prefix" "$line"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 遍历文件（- 为 stdin），多文件时逐行加「文件名:」前缀
_run_filter() {
  local f use_prefix="no"
  if ((${#FILES[@]} > 1)); then
    use_prefix="yes"
  fi
  for f in "${FILES[@]}"; do
    if [[ "$f" == "-" ]]; then
      _filter_stream ""
    elif [[ ! -r "$f" ]]; then
      log_err "文件不可读: $f"
      HAS_READ_ERR=1
    elif [[ "$use_prefix" == "yes" ]]; then
      _filter_stream "${f}:" < "$f"
    else
      _filter_stream "" < "$f"
    fi
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 清理临时文件（EXIT trap 调用）
_cleanup() {
  rm -f "${TMP_OUT:-}"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 参数解析、过滤执行与高亮输出；退出码见 usage
main() {
  local -a or_kws=() and_kws=() files=()
  local since_epoch=-1 until_epoch=-1 color="on"
  while (($# > 0)); do
    case "$1" in
      -k | --keyword)
        [[ $# -ge 2 ]] || {
          usage >&2
          return 2
        }
        [[ -n "$2" ]] || {
          log_err "关键字不能为空"
          return 2
        }
        or_kws+=("$2")
        shift 2
        ;;
      -K | --and-keyword)
        [[ $# -ge 2 ]] || {
          usage >&2
          return 2
        }
        [[ -n "$2" ]] || {
          log_err "关键字不能为空"
          return 2
        }
        and_kws+=("$2")
        shift 2
        ;;
      --since)
        [[ $# -ge 2 ]] || {
          usage >&2
          return 2
        }
        since_epoch="$(_parse_time "$2")" || {
          log_err "无法解析 --since 时间: $2"
          return 2
        }
        shift 2
        ;;
      --until)
        [[ $# -ge 2 ]] || {
          usage >&2
          return 2
        }
        until_epoch="$(_parse_time "$2")" || {
          log_err "无法解析 --until 时间: $2"
          return 2
        }
        shift 2
        ;;
      --no-color)
        color="off"
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      --)
        shift
        while (($# > 0)); do
          files+=("$1")
          shift
        done
        ;;
      -)
        files+=("$1")
        shift
        ;;
      -*)
        log_err "未知选项: $1"
        usage >&2
        return 2
        ;;
      *)
        files+=("$1")
        shift
        ;;
    esac
  done
  if ((${#files[@]} == 0)); then
    usage >&2
    return 2
  fi

  OR_KWS=("${or_kws[@]}")
  AND_KWS=("${and_kws[@]}")
  FILES=("${files[@]}")
  SINCE_EPOCH="$since_epoch"
  UNTIL_EPOCH="$until_epoch"

  if [[ "$color" == "on" ]] \
    && ((${#OR_KWS[@]} > 0 || ${#AND_KWS[@]} > 0)); then
    local esc kw alt
    local -a escd=()
    esc="$(printf '\033')"
    for kw in "${OR_KWS[@]}" "${AND_KWS[@]}"; do
      escd+=("$(_sed_escape_ere "$kw")")
    done
    alt="$(
      IFS='|'
      printf '%s' "${escd[*]}"
    )"
    HL_SED="s/(${alt})/${esc}[1;31m&${esc}[0m/g"
  fi

  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/log-grep.XXXXXX")" || {
    log_err "无法创建临时文件"
    return 1
  }
  TMP_OUT="$tmp_out"
  trap _cleanup EXIT

  _run_filter > "$tmp_out"

  local rc=0
  if ((HAS_READ_ERR == 1)); then
    rc=3
  fi
  if ((MATCH_COUNT > 0)); then
    if [[ -n "$HL_SED" ]]; then
      sed -E -e "$HL_SED" < "$tmp_out"
    else
      cat < "$tmp_out"
    fi
  fi
  if ((rc == 0 && MATCH_COUNT == 0)); then
    rc=1
  fi
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
