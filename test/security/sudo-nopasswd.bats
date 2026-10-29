#!/usr/bin/env bats
# script-name: sudo-nopasswd-test
# description: sudo-nopasswd 的参数校验与 dry-run 测试（[sandbox-only]，不触碰 sudoers）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats
# category: security

setup() {
  load '../helpers/test_env'
  # 环境跳过优先，且可选组件条件加载：bats 的 setup 内 skip 不会中断
  # 后续语句，故用 if 守卫，保证 git bash（未初始化子模块）也能整体 skip
  if env_is_supported ubuntu-26.04 wsl-ubuntu-26.04; then
    load '../../test/libs/bats-support/load'
    load '../../test/libs/bats-assert/load'
  fi
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/security/sudo-nopasswd.sh"
}

# bats 文件内助手：当前用户是否在 sudo/wheel 组
current_user_in_sudo_group() {
  local groups
  groups="$(id -nG "$(id -un)")"
  [[ "$groups" =~ (^|[[:space:]])(sudo|wheel)([[:space:]]|$) ]]
}

@test "无参数输出用法并返回 2" {
  run "$SCRIPT"
  assert_failure 2
  assert_output --partial "用法: sudo-nopasswd"
}

@test "未知模式返回 2" {
  run "$SCRIPT" restart
  assert_failure 2
}

@test "非法用户名被拒绝（返回 1）" {
  run "$SCRIPT" status "../not-a-user"
  assert_failure 1
  assert_output --partial "格式非法"
}

@test "不存在的用户被拒绝（返回 1）" {
  run "$SCRIPT" status no-such-user-xyz
  assert_failure 1
  assert_output --partial "不存在"
}

@test "未知参数被拒绝（返回 2）" {
  run "$SCRIPT" status --bogus
  assert_failure 2
}

@test "enable_nopasswd dry-run 只打印动作不落盘（函数级）" {
  # shellcheck source=../../scripts/security/sudo-nopasswd.sh
  source "$SCRIPT"
  run enable_nopasswd "$(id -un)" true
  assert_success
  assert_output --partial "[dry-run] 将写入"
  [ ! -f "/etc/sudoers.d/$(id -un)-nopasswd" ]
}

@test "disable_nopasswd dry-run 无配置时提示无需恢复（函数级）" {
  if [ -f "/etc/sudoers.d/$(id -un)-nopasswd" ]; then
    skip "当前存在免密配置"
  fi
  # shellcheck source=../../scripts/security/sudo-nopasswd.sh
  source "$SCRIPT"
  run disable_nopasswd "$(id -un)" true
  assert_success
  assert_output --partial "无需恢复"
}

@test "on --dry-run CLI 全链路（需当前用户在 sudo/wheel 组）" {
  if ! current_user_in_sudo_group; then
    skip "当前用户不在 sudo/wheel 组（CI runner 常见）"
  fi
  run "$SCRIPT" on --dry-run
  assert_success
  assert_output --partial "[dry-run] 将写入"
}

@test "off --dry-run CLI 全链路（需在 sudo/wheel 组且无配置）" {
  if [ -f "/etc/sudoers.d/$(id -un)-nopasswd" ]; then
    skip "当前存在免密配置"
  fi
  if ! current_user_in_sudo_group; then
    skip "当前用户不在 sudo/wheel 组（CI runner 常见）"
  fi
  run "$SCRIPT" off --dry-run
  assert_success
  assert_output --partial "无需恢复"
}

@test "status 输出当前状态（需当前用户在 sudo/wheel 组）" {
  if ! current_user_in_sudo_group; then
    skip "当前用户不在 sudo/wheel 组（CI runner 常见）"
  fi
  run "$SCRIPT" status
  assert_success
  assert_output --regexp '免密已开启|正常密码验证'
}
