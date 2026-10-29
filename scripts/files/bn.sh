#!/usr/bin/env bash
# script-name: bn
# description: 将文件重命名为 .b 备份并新建同名空文件（backup-and-new）
# usage: bn.sh [--dry-run] <文件>
# option: -n, --dry-run    仅打印将执行的动作，不改动文件
# example: bn.sh notes.txt
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: coreutils
# category: files

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——参数解析、存在性与冲突校验、备份重建
main() {
  local dry="false" arg file backup
  local -a args=()
  for arg in "$@"; do
    case "$arg" in
      -n | --dry-run) dry="true" ;;
      *) args+=("$arg") ;;
    esac
  done
  if ((${#args[@]} != 1)); then
    echo "用法: bn.sh [--dry-run] <文件>" >&2
    return 2
  fi
  file="${args[0]}"
  backup="${file}.b"
  if [[ ! -e "$file" ]]; then
    echo "错误: 文件不存在: $file" >&2
    return 1
  fi
  if [[ -e "$backup" ]]; then
    echo "错误: 备份已存在: $backup（请先处理，避免覆盖）" >&2
    return 1
  fi
  if [[ "$dry" == "true" ]]; then
    echo "[dry-run] 将执行: mv '$file' '$backup' && touch '$file'"
    return 0
  fi
  if ! mv -- "$file" "$backup"; then
    echo "错误: 重命名失败" >&2
    return 1
  fi
  if ! touch -- "$file"; then
    echo "错误: 新建文件失败，原文件保留在 $backup" >&2
    return 1
  fi
  echo "已备份 $file → $backup 并新建空文件"
}

main "$@"
