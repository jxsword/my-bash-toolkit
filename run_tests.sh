#!/usr/bin/env bash
# script-name: run-tests
# description: 免 make 的全量测试入口（git bash 等 make 不可用环境使用）
# usage: run_tests.sh [--quiet]
# option: --quiet    透传给 bash_env_check：预检只看退出码
# example: ./run_tests.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, bash
# category: dev

set -u -o pipefail

_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——bash 版本预检后执行 bats 全量测试
main() {
  local pre=()
  if [[ "${1:-}" == "--quiet" ]]; then
    pre+=(--quiet)
  fi
  if ! "$_ROOT/scripts/lib/env.sh" "${pre[@]+"${pre[@]}"}"; then
    echo "run_tests: bash 环境预检未通过，终止" >&2
    return 1
  fi
  if ! command -v bats > /dev/null 2>&1; then
    echo "run_tests: 未找到 bats（安装方式见 README §4）" >&2
    return 2
  fi
  local files=()
  mapfile -t files < <(
    find "$_ROOT/test" -name '*.bats' -not -path '*/libs/*' | sort
  )
  bats "${files[@]}"
}

main "$@"
