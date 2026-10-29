#!/usr/bin/env bash
# script-name: bad-indent
# description: bad 用例——4 空格缩进（R02，shfmt 应报格式差异）
# usage: bad-indent.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
main() {
    echo "indent with 4 spaces"
}

main
