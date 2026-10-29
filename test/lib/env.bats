#!/usr/bin/env bats
# script-name: env-test
# description: lib/env.sh 单元测试——版本区间判定、比较函数、环境识别
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: lib
# bats 用例在子壳中修改探针变量是有意行为（每个用例独立）：
# shellcheck disable=SC2030,SC2031

setup() {
  load '../helpers/test_env'
}

# bats 文件内助手：构造严格高于/低于当前宿主 bash 的版本号，
# 使边界用例不依赖特定宿主版本（git bash 5.2.x 与 ubuntu 5.3.x 通吃）
above_current() {
  if ((BASH_VERSINFO[1] < 99)); then
    printf '%d.%d.0\n' "${BASH_VERSINFO[0]}" "$((BASH_VERSINFO[1] + 1))"
  else
    printf '%d.0.0\n' "$((BASH_VERSINFO[0] + 1))"
  fi
}

below_current() {
  if ((BASH_VERSINFO[2] > 0)); then
    printf '%d.%d.%d\n' \
      "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" "$((BASH_VERSINFO[2] - 1))"
  elif ((BASH_VERSINFO[1] > 0)); then
    printf '%d.%d.99\n' "${BASH_VERSINFO[0]}" "$((BASH_VERSINFO[1] - 1))"
  else
    printf '%d.99.99\n' "$((BASH_VERSINFO[0] - 1))"
  fi
}

@test "env_version_cmp 相等输出 0" {
  run env_version_cmp 5.2.0 5.2.0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "env_version_cmp 小于输出 -1" {
  run env_version_cmp 5.2.1 5.3.0
  [ "$status" -eq 0 ]
  [ "$output" = "-1" ]
}

@test "env_version_cmp 大于输出 1" {
  run env_version_cmp 5.3.9 5.2.0
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "env_parse_range 解析合法区间" {
  local f status=0
  f="$(mktemp)"
  printf '# 注释行\n5.2.0-5.3.9\n' > "$f"
  env_parse_range "$f" || status=$?
  rm -f "$f"
  [ "$status" -eq 0 ]
  [ "$_ENV_MIN" = "5.2.0" ]
  [ "$_ENV_MAX" = "5.3.9" ]
}

@test "env_parse_range 非法格式返回 2" {
  local f
  f="$(mktemp)"
  printf 'not-a-range\n' > "$f"
  run env_parse_range "$f"
  rm -f "$f"
  [ "$status" -eq 2 ]
}

@test "bash_env_check 区间内返回 0（动态边界）" {
  local f
  f="$(mktemp)"
  printf '%s-%s\n' "$(below_current)" "$(above_current)" > "$f"
  export BASH_VERSION_FILE="$f"
  run bash_env_check --quiet
  rm -f "$f"
  unset BASH_VERSION_FILE
  [ "$status" -eq 0 ]
}

@test "bash_env_check 高于 MAX 返回 1（动态边界）" {
  local f
  f="$(mktemp)"
  printf '0.0.0-%s\n' "$(below_current)" > "$f"
  export BASH_VERSION_FILE="$f"
  run bash_env_check --quiet
  rm -f "$f"
  unset BASH_VERSION_FILE
  [ "$status" -eq 1 ]
}

@test "bash_env_check 低于 MIN 返回 1（动态边界）" {
  local f
  f="$(mktemp)"
  printf '%s-9.9.9\n' "$(above_current)" > "$f"
  export BASH_VERSION_FILE="$f"
  run bash_env_check --quiet
  rm -f "$f"
  unset BASH_VERSION_FILE
  [ "$status" -eq 1 ]
}

@test "bash_env_check 配置非法返回 2" {
  local f
  f="$(mktemp)"
  printf 'malformed\n' > "$f"
  export BASH_VERSION_FILE="$f"
  run bash_env_check --quiet
  rm -f "$f"
  unset BASH_VERSION_FILE
  [ "$status" -eq 2 ]
}

@test "bash_env_check 配置缺失返回 2" {
  export BASH_VERSION_FILE="/nonexistent/.bash-version"
  run bash_env_check --quiet
  unset BASH_VERSION_FILE
  [ "$status" -eq 2 ]
}

@test "env_detect_id 输出合法标识符" {
  run env_detect_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(ubuntu-26\.04|wsl-ubuntu-26\.04|git-bash|unknown)$ ]]
}

@test "env_detect_id 在本环境为 wsl-ubuntu-26.04" {
  skip_unless_env wsl-ubuntu-26.04
  run env_detect_id
  [ "$status" -eq 0 ]
  [ "$output" = "wsl-ubuntu-26.04" ]
}

@test "env_is_supported 命中当前环境返回 0" {
  run env_is_supported "$(env_detect_id)"
  [ "$status" -eq 0 ]
}

@test "env_is_supported 未命中返回 1" {
  run env_is_supported some-other-env
  [ "$status" -eq 1 ]
}
