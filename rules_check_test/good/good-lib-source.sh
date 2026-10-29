#!/usr/bin/env bash
# script-name: good-lib-source
# description: good 用例——引用共享库的脚本形态（source-path 解析）
# usage: good-lib-source.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# shellcheck source=../../scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/lib/common.sh"

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 演示调用库函数
main() {
  log_info "hello from good-lib-source"
}

main
