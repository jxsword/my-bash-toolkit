#!/usr/bin/env bash
# script-name: pkg-export
# description: 导出 apt 手动安装包清单（apt-mark，排序去重落盘），支持与旧清单对比增减；只读不安装
# usage: pkg-export.sh [--out <file>] [--stdout] [--diff <旧清单>] [-h, --help]
# option: --out <file>      输出到指定文件（默认当前目录 pkg-manual-<时间戳>.txt）
# option: --stdout          仅打印清单到 stdout，不落盘
# option: --diff <旧清单>   与旧清单对比输出新增/移除；存在差异退出 1
# option: -h, --help        显示帮助
# example: pkg-export.sh
# example: pkg-export.sh --out ~/pkg-manual.txt
# example: pkg-export.sh --diff pkg-manual-20261030-120000.txt
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: apt-mark, coreutils, grep, sed
# category: system

set -u -o pipefail

_PE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_PE_ROOT/scripts/lib/common.sh"

readonly _PE_DEFAULT_PREFIX="pkg-manual"

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stdout
usage() {
  cat << 'EOF'
用法: pkg-export.sh [--out <file>] [--stdout] [--diff <旧清单>] [-h, --help]
导出 apt 手动安装包清单（apt-mark showmanual，排序去重），脚本自身只读不安装。

选项:
  --out <file>      输出到指定文件（默认当前目录 pkg-manual-<时间戳>.txt）
  --stdout          仅打印清单到 stdout，不落盘
  --diff <旧清单>   与旧清单对比，输出新增/移除的包；存在差异退出 1
  -h, --help        显示本帮助

退出码: 0=成功或无差异 1=存在差异（--diff 模式） 2=用法错误 3=运行时错误
恢复命令提示: xargs apt-get install < <清单文件>
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 获取 apt 手动安装包列表（每行一个；apt-mark 不可用或失败返回 1）
collect_manual() {
  command -v apt-mark > /dev/null 2>&1 || return 1
  apt-mark showmanual 2> /dev/null
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 清单规整——按字典序排序去重并丢弃空行
normalize_list() {
  printf '%s' "$1" | LC_ALL=C sort -u | sed '/^$/d'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 统计清单中的包数量（非空行数）
count_pkgs() {
  printf '%s' "$1" | grep -c . || true
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 将清单写到 stdout（--stdout 模式；空清单不输出任何内容）
print_list() {
  if [[ -n "$1" ]]; then
    printf '%s\n' "$1"
  fi
  return 0
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 导出清单落盘并打印条数与恢复命令提示
do_export() {
  local list="$1" out="$2"
  local target
  if [[ -n "$out" ]]; then
    target="$out"
  else
    target="${_PE_DEFAULT_PREFIX}-$(date +%Y%m%d-%H%M%S).txt"
  fi
  if [[ -e "$target" ]]; then
    log_err "目标文件已存在，拒绝覆盖: $target"
    return 3
  fi
  if [[ -n "$list" ]]; then
    if ! printf '%s\n' "$list" > "$target"; then
      log_err "清单写入失败: $target"
      return 3
    fi
  else
    if ! : > "$target"; then
      log_err "清单写入失败: $target"
      return 3
    fi
  fi
  local n
  n="$(count_pkgs "$list")"
  log_info "已导出 $n 个手动安装包 -> $target"
  log_info "恢复命令提示: xargs apt-get install < $target"
  return 0
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 与旧清单对比输出新增/移除；存在差异返回 1
do_diff() {
  local list="$1" old="$2"
  if [[ ! -r "$old" ]]; then
    log_err "旧清单不可读: $old"
    return 3
  fi
  local old_sorted new_sorted
  old_sorted="$(LC_ALL=C sort -u -- "$old")"
  new_sorted="$(printf '%s' "$list" | LC_ALL=C sort -u)"
  local added removed
  added="$(comm -13 <(printf '%s\n' "$old_sorted") \
    <(printf '%s\n' "$new_sorted"))"
  removed="$(comm -23 <(printf '%s\n' "$old_sorted") \
    <(printf '%s\n' "$new_sorted"))"
  echo "== 对比旧清单: $old =="
  if [[ -z "$added" && -z "$removed" ]]; then
    echo "无差异：手动安装包集合一致"
    return 0
  fi
  echo "新增（新清单有、旧清单无）:"
  if [[ -n "$added" ]]; then
    printf '%s\n' "$added" | sed 's/^/  + /'
  else
    echo "  （无）"
  fi
  echo "移除（旧清单有、新清单无）:"
  if [[ -n "$removed" ]]; then
    printf '%s\n' "$removed" | sed 's/^/  - /'
  else
    echo "  （无）"
  fi
  log_info "恢复命令提示: xargs apt-get install < <新导出清单>"
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 参数解析与模式分派（导出 / stdout / 对比）
main() {
  local out="" to_stdout="false" diff_file=""
  while (($#)); do
    case "$1" in
      --out)
        if (($# < 2)); then
          log_err "--out 需要一个文件路径参数"
          return 2
        fi
        out="$2"
        shift 2
        ;;
      --stdout)
        to_stdout="true"
        shift
        ;;
      --diff)
        if (($# < 2)); then
          log_err "--diff 需要一个旧清单文件参数"
          return 2
        fi
        diff_file="$2"
        shift 2
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
  if [[ -n "$diff_file" && (-n "$out" || "$to_stdout" == "true") ]]; then
    log_err "--diff 与 --out/--stdout 互斥，不能同时使用"
    return 2
  fi

  local raw list
  if ! raw="$(collect_manual)"; then
    log_err "apt-mark 不可用或执行失败，无法获取手动安装包清单"
    return 3
  fi
  list="$(normalize_list "$raw")"

  if [[ -n "$diff_file" ]]; then
    do_diff "$list" "$diff_file"
    return $?
  fi
  if [[ "$to_stdout" == "true" ]]; then
    print_list "$list"
    return 0
  fi
  do_export "$list" "$out"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
