#!/usr/bin/env bash
# script-name: line-length
# description: pre-commit 本地 hook——检查 .sh 文件行宽不超过 80 列（行尾 # noqa:line-length 豁免）
# usage: line-length.sh <file.sh>...
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: awk
# category: dev

set -u -o pipefail

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 逐文件检查行宽，任一违规返回非零
main() {
  local file status=0
  for file in "$@"; do
    if ! awk -v file="$file" '
      length($0) > 80 && $0 !~ /# noqa:line-length[ \t]*$/ {
        printf "%s:%d: 行宽 %d 超过 80 列（豁免: 行尾 # noqa:line-length）\n",
          file, FNR, length($0)
        bad = 1
      }
      END { exit bad ? 1 : 0 }
    ' "$file"; then
      status=1
    fi
  done
  return "$status"
}

main "$@"
