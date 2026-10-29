#!/usr/bin/env bats
# script-name: rules-check-test-test
# description: rules_check_test 运行器自身的回归测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, shfmt, shellcheck
# category: dev

@test "run_checks.sh 全量通过（退出码 0）" {
  run "$BATS_TEST_DIRNAME/../rules_check_test/run_checks.sh" --quiet
  [ "$status" -eq 0 ]
}

@test "run_checks.sh 输出汇总统计" {
  run "$BATS_TEST_DIRNAME/../rules_check_test/run_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rules_check_test: pass="* ]]
  [[ "$output" == *"fail=0"* ]]
}
