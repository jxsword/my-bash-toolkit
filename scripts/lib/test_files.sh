#!/usr/bin/env bash
# script-name: test-files
# description: 测试收集共享库——输出仓库 test/ 下全部 .bats 清单（排除 test/libs 子模块 fixtures）
# usage: （库，被 source；collect_bats_files [root] 输出每行一个文件）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: find
# category: lib

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出 .bats 清单（排序；root 缺省为本仓库根，可传沙箱仓库根）
collect_bats_files() {
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
  fi
  find "$root/test" -name '*.bats' -not -path '*/libs/*' | sort
}
