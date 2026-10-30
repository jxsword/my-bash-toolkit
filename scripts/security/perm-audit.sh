#!/usr/bin/env bash
# script-name: perm-audit
# description: 只读权限审计——world-writable、无主/无组与 .ssh 私钥权限巡检
# usage: perm-audit.sh [--path <dir>]... [-n, --dry-run] [-h, --help]
# option: --path <dir>     扫描目录，可重复；给出后替代默认（/etc /usr/local）
# option: -n, --dry-run    兼容系统级惯例；本脚本只读，行为与默认一致
# option: -h, --help       显示帮助
# example: perm-audit.sh
# example: perm-audit.sh --path /opt/app --path /srv
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: findutils, coreutils, grep, awk
# category: security

set -u -o pipefail

_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_ROOT/scripts/lib/common.sh"

readonly -a _DEFAULT_PATHS=(/etc /usr/local)

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stdout（错误分支重定向到 stderr）
usage() {
  cat << 'EOF'
用法: perm-audit.sh [选项]
只读权限巡检，不修改任何文件与权限。检查项:
  1) world-writable 文件与目录（目录标注是否缺粘滞位）
  2) 无主/无组条目（uid/gid 无对应用户或组）
  3) ~/.ssh 私钥权限非 600
     私钥识别: 文件名为 id_*（排除 *.pub），或内容含 PRIVATE KEY
退出码: 0=无发现, 1=有发现（供 cron/CI 判断）, 2=用法/参数错误

选项:
  --path <dir>     扫描目录，可重复；给出后替代默认 /etc /usr/local
  -n, --dry-run    兼容系统级惯例；本脚本只读，行为与默认一致
  -h, --help       显示本帮助

示例:
  perm-audit.sh
  perm-audit.sh --path /opt/app --path /srv
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 统计字符串非空行数（awk 计数，规避 herestring+wc -l 多计 1 的坑位）
_count_lines() {
  printf '%s\n' "$1" | awk 'NF { c++ } END { print c + 0 }'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 将 mode\tpath 聚合串格式化为 "mode  path" 显示行（跳过空行）
_format_pairs() {
  local mode path
  while IFS=$'\t' read -r mode path; do
    if [[ -z "$mode" ]]; then
      continue
    fi
    printf '%s  %s\n' "$mode" "$path"
  done <<< "$1"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: world-writable 目录格式化；缺粘滞位（1000 位）的条目追加标注
_format_ww_dirs() {
  local mode path
  while IFS=$'\t' read -r mode path; do
    if [[ -z "$mode" ]]; then
      continue
    fi
    if ((8#$mode & 8#1000)); then
      printf '%s  %s\n' "$mode" "$path"
    else
      printf '%s  %s（无粘滞位）\n' "$mode" "$path"
    fi
  done <<< "$1"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 缩进打印聚合内容（每行前加两空格，跳过空行）
_print_lines() {
  local line
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    printf '  %s\n' "$line"
  done <<< "$1"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 单路径 find（$1=错误暂存文件, $2=路径, 其余=find 表达式），结果按路径排序
_find_sort() {
  local err="$1" p="$2"
  shift 2
  local out
  out="$(find "$p" "$@" 2>> "$err")" || true
  printf '%s' "$out" | sort -t$'\t' -k2,2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 扫描各路径 world-writable 文件/目录（$1=f|d, $2=错误暂存, 其余=路径）
_scan_ww() {
  local type="$1" err="$2"
  shift 2
  local p out all=""
  for p in "$@"; do
    out="$(_find_sort "$err" "$p" -type "$type" -perm -0002 -printf '%m\t%p\n')"
    # 命令替换会剥掉结尾换行，聚合时需补回，避免多路径条目粘连
    if [[ -n "$out" ]]; then
      all="${all}${out}"$'\n'
    fi
  done
  printf '%s' "$all"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 扫描各路径无主/无组条目（$1=错误暂存, 其余=路径），输出聚合行
_scan_unowned() {
  local err="$1"
  shift
  local p out all=""
  for p in "$@"; do
    out="$(_find_sort "$err" "$p" \( -nouser -o -nogroup \) -printf '%m\t%p\n')"
    # 命令替换会剥掉结尾换行，聚合时需补回，避免多路径条目粘连
    if [[ -n "$out" ]]; then
      all="${all}${out}"$'\n'
    fi
  done
  printf '%s' "$all"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 检查 $HOME/.ssh 私钥权限（非 600 即报告），输出 mode\tpath 聚合行
_check_ssh_keys() {
  local home_dir="${HOME:-}"
  if [[ -z "$home_dir" || ! -d "$home_dir/.ssh" ]]; then
    return 0
  fi
  local dir="$home_dir/.ssh"
  local out="" f base mode first is_key
  for f in "$dir"/*; do
    if [[ ! -f "$f" || -L "$f" ]]; then
      continue
    fi
    base="$(basename -- "$f")"
    case "$base" in
      *.pub | known_hosts* | authorized_keys* | config | environment)
        continue
        ;;
    esac
    is_key="false"
    case "$base" in
      id_*)
        is_key="true"
        ;;
    esac
    if [[ "$is_key" != "true" ]]; then
      first=""
      IFS= read -r first < "$f" || true
      if [[ "$first" == *'PRIVATE KEY'* ]]; then
        is_key="true"
      fi
    fi
    if [[ "$is_key" != "true" ]]; then
      continue
    fi
    mode="$(stat -c '%a' -- "$f" 2> /dev/null)" || continue
    if [[ "$mode" == "600" ]]; then
      continue
    fi
    out="${out}${mode}"$'\t'"${f}"$'\n'
  done
  printf '%s' "$out"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: n>0 时输出小节（标题含计数、缩进行与空行分隔）
_emit_section() {
  local title="$1" content="$2" n="$3"
  if ((n == 0)); then
    return 0
  fi
  printf '== %s ==\n' "$title"
  _print_lines "$content"
  printf '\n'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——参数解析、路径校验、四类扫描与发现汇总（有发现退出 1）
main() {
  local -a opt_paths=()
  local p
  while (($# > 0)); do
    case "$1" in
      --path)
        if (($# < 2)); then
          log_err "选项 --path 缺少目录参数"
          return 2
        fi
        opt_paths+=("$2")
        shift 2
        ;;
      # 只读脚本没有写动作；保留 --dry-run 仅为对齐系统级脚本惯例
      -n | --dry-run)
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        log_err "未知选项: $1"
        usage >&2
        return 2
        ;;
      *)
        log_err "不接受位置参数: $1（扫描目录请用 --path 指定）"
        return 2
        ;;
    esac
  done

  local -a given=() scan=()
  if ((${#opt_paths[@]} > 0)); then
    given=("${opt_paths[@]}")
  else
    given=("${_DEFAULT_PATHS[@]}")
  fi
  for p in "${given[@]}"; do
    if [[ -d "$p" ]]; then
      scan+=("$p")
    else
      log_warn "跳过无效目录（不存在或不是目录）: $p"
    fi
  done
  if ((${#scan[@]} == 0)); then
    log_err "没有可扫描的有效目录"
    return 2
  fi

  local err ww_files ww_dirs unowned ssh_bad sec n total=0
  err="$(mktemp)" || {
    log_err "无法创建临时文件（mktemp）"
    return 1
  }
  # 立即展开临时文件路径，规避 EXIT 触发时局部变量已出栈的问题
  # shellcheck disable=SC2064
  trap "rm -f -- $(printf '%q' "$err")" EXIT

  printf '[审计] 只读权限巡检（不修改任何文件）\n'
  printf '[审计] 扫描目录: %s\n' "${scan[*]}"
  if [[ -n "${HOME:-}" && -d "${HOME}/.ssh" ]]; then
    printf '[审计] ssh 私钥检查: %s\n' "${HOME}/.ssh"
  else
    printf '[审计] ssh 私钥检查: ~/.ssh（不存在，跳过）\n'
  fi

  ww_files="$(_scan_ww f "$err" "${scan[@]}")"
  ww_dirs="$(_scan_ww d "$err" "${scan[@]}")"
  unowned="$(_scan_unowned "$err" "${scan[@]}")"
  ssh_bad="$(_check_ssh_keys)"

  n="$(grep -c . -- "$err")" || n=0
  if ((n > 0)); then
    log_warn "有 ${n} 条路径无法读取（权限不足），结果可能不完整"
  fi

  sec="$(_format_pairs "$ww_files")"
  n="$(_count_lines "$sec")"
  _emit_section "world-writable 文件 (${n})" "$sec" "$n"
  total=$((total + n))

  sec="$(_format_ww_dirs "$ww_dirs")"
  n="$(_count_lines "$sec")"
  _emit_section "world-writable 目录 (${n})" "$sec" "$n"
  total=$((total + n))

  sec="$(_format_pairs "$unowned")"
  n="$(_count_lines "$sec")"
  _emit_section "无主/无组 (${n})" "$sec" "$n"
  total=$((total + n))

  sec="$(_format_pairs "$ssh_bad")"
  n="$(_count_lines "$sec")"
  _emit_section "ssh 私钥权限非 600 (${n})" "$sec" "$n"
  total=$((total + n))

  if ((total > 0)); then
    log_info "共发现 ${total} 项权限问题"
    return 1
  fi
  log_info "未发现权限问题"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
