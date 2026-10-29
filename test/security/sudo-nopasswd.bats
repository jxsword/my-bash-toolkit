#!/usr/bin/env bats
# script-name: sudo-nopasswd-test
# description: sudo-nopasswd 的参数校验与 dry-run 测试（[sandbox-only]，不触碰 sudoers）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats
# category: security

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/security/sudo-nopasswd.sh"
}

@test "无参数输出用法并返回 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"用法: sudo-nopasswd"* ]]
}

@test "未知模式返回 2" {
  run "$SCRIPT" restart
  [ "$status" -eq 2 ]
}

@test "非法用户名被拒绝（返回 1）" {
  run "$SCRIPT" status "../not-a-user"
  [ "$status" -eq 1 ]
  [[ "$output" == *"格式非法"* ]]
}

@test "不存在的用户被拒绝（返回 1）" {
  run "$SCRIPT" status no-such-user-xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"不存在"* ]]
}

@test "未知参数被拒绝（返回 2）" {
  run "$SCRIPT" status --bogus
  [ "$status" -eq 2 ]
}

@test "on --dry-run 只打印动作不落盘" {
  run "$SCRIPT" on --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] 将写入"* ]]
  [ ! -f "/etc/sudoers.d/$(id -un)-nopasswd" ]
}

@test "off --dry-run 在无配置时提示无需恢复" {
  if [ -f "/etc/sudoers.d/$(id -un)-nopasswd" ]; then
    skip "当前存在免密配置，跳过该用例"
  fi
  run "$SCRIPT" off --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"无需恢复"* ]]
}
