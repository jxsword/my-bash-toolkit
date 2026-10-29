#!/usr/bin/env bash
# script-name: ftree
# description: tree 的 -F 增强——检测到 -F 时自动补 -C 并过滤行尾星号（独立脚本，不 shadow 系统 tree）
# usage: ftree.sh [tree 参数与路径...]
# option: （透传）-F    触发增强：自动加 -C 并滤掉行尾星号
# option: （透传）-C    已有 -C 时不重复添加
# example: ftree.sh -F /some/dir
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: tree, sed
# category: files

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 扫描参数，识别短选项簇中的 F/C 标记（长选项不参与，修复原 *F* 误匹配）
scan_flags() {
  local arg
  local -a args=()
  _FTREE_HAS_F="false"
  _FTREE_HAS_C="false"
  for arg in "$@"; do
    if [[ "$arg" == -* && "$arg" != --* ]]; then
      [[ "$arg" == *F* ]] && _FTREE_HAS_F="true"
      [[ "$arg" == *C* ]] && _FTREE_HAS_C="true"
    fi
    args+=("$arg")
  done
  _FTREE_ARGS=("${args[@]}")
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——按需补 -C 并过滤 -F 输出的行尾星号
main() {
  if ! command -v tree > /dev/null 2>&1; then
    echo "错误: 未找到 tree 命令" >&2
    return 1
  fi
  scan_flags "$@"
  if [[ "$_FTREE_HAS_F" == "true" && "$_FTREE_HAS_C" == "false" ]]; then
    _FTREE_ARGS=("-C" "${_FTREE_ARGS[@]}")
  fi
  if [[ "$_FTREE_HAS_F" == "true" ]]; then
    command tree "${_FTREE_ARGS[@]}" | sed 's/\*$//'
  else
    command tree "${_FTREE_ARGS[@]}"
  fi
}

main "$@"
