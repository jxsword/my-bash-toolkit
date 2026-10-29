#!/usr/bin/env bash
# script-name: test-env
# description: bats 测试助手——加载 lib/env.sh 并提供按环境跳过用例的 skip_unless_env
# usage: （bats 助手，被 load）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: dev

_TESTENV_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=../../scripts/lib/env.sh
source "$_TESTENV_ROOT/scripts/lib/env.sh"

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 当前环境不在参数列表时跳过用例（bats skip，不支持的直接不测）
skip_unless_env() {
  if ! env_is_supported "$@"; then
    skip "当前环境 $(env_detect_id) 不在 [ $* ]，跳过"
  fi
}
