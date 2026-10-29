#!/usr/bin/env bash
# script-name: wcd
# description: Windows 路径转 WSL 路径并切换目录（设计为 source 生效；直接执行仅打印目标路径）
# usage: wcd.sh <Windows 或 WSL 路径>
# example: source scripts/wsl/wcd.sh 'D:\proj\foo'
# example: cd "$(scripts/wsl/wcd.sh 'D:\proj\foo')"
# env: wsl-ubuntu-26.04
# deps: wslpath, coreutils
# category: wsl

# env: wsl-ubuntu-26.04
# fn: 解析并校验目标路径，返回规范化的 WSL 绝对路径
resolve_target() {
  local target="${1:-}" converted
  if [[ -z "$target" ]]; then
    echo "用法: wcd.sh <Windows 或 WSL 路径>" >&2
    return 2
  fi
  if ! command -v wslpath > /dev/null 2>&1; then
    echo "错误: 未找到 wslpath（仅 WSL 环境可用）" >&2
    return 1
  fi
  converted=""
  if converted="$(wslpath -a "$target" 2> /dev/null)"; then
    :
  elif [[ "$target" == /* && -d "$target" ]]; then
    # wslpath 对 WSL 原生路径可能失败，存在的绝对路径直接采用
    converted="$target"
  else
    echo "错误: 无法转换路径 '$target'" >&2
    return 1
  fi
  if [[ "$converted" != "/" && "$converted" == */ ]]; then
    converted="${converted%/}"
  fi
  if [[ ! -d "$converted" ]]; then
    echo "错误: 目标目录不存在: $converted" >&2
    return 1
  fi
  printf '%s\n' "$converted"
}

# env: wsl-ubuntu-26.04
# fn: 入口——source 时切换目录，直接执行时打印路径；不污染调用方 shell 选项
main() {
  local u_was="off" pf_was="off" sourced="false" target rc
  [[ $- == *u* ]] && u_was="on"
  if [[ -o pipefail ]]; then pf_was="on"; fi
  set -u -o pipefail
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    sourced="true"
  fi
  target="$(resolve_target "${1:-}")"
  rc=$?
  if [[ "$sourced" == "true" ]]; then
    [[ "$u_was" == "off" ]] && set +u
    [[ "$pf_was" == "off" ]] && set +o pipefail
    if [[ "$rc" -eq 0 ]]; then
      cd -- "$target" || rc=1
    fi
  fi
  if [[ "$rc" -ne 0 ]]; then
    return "$rc"
  fi
  if [[ "$sourced" == "false" ]]; then
    printf '%s\n' "$target"
  fi
  return 0
}

main "$@"
