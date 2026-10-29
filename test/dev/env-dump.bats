#!/usr/bin/env bats
# script-name: env-dump-test
# description: env-dump 的清单输出与 --out 落盘测试（[sandbox-only]）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: dev

setup() {
  load '../helpers/test_env'
  # 可选组件条件加载：bats 的 setup 内 skip 不中断后续语句
  if env_is_supported ubuntu-26.04 wsl-ubuntu-26.04 git-bash; then
    load '../../test/libs/bats-support/load'
    load '../../test/libs/bats-assert/load'
  fi
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04 git-bash
  load '../helpers/sandbox'
  sandbox_setup
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dev/env-dump.sh"
}

teardown() {
  sandbox_teardown
}

@test "无参数输出 markdown 环境清单（标题+平台+bash）" {
  run "$SCRIPT"
  assert_success
  assert_output --partial '# 环境清单（env-dump）'
  assert_output --partial '- platform: '
  assert_output --partial '- env id: '
  assert_output --partial '- bash: '
  assert_output --partial '- 生成时间: '
}

@test "--help 返回 0 并显示用法" {
  run "$SCRIPT" --help
  assert_success
  assert_output --partial '用法: env-dump.sh'
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  assert_failure 2
}

@test "输出含 PATH 段落且至少 1 项" {
  run "$SCRIPT"
  assert_success
  assert_output --regexp '## PATH（[0-9]+ 项）'
  assert_output --partial '1. `'
}

@test "输出含工具版本表且 git 必列（三环境均有）" {
  run "$SCRIPT"
  assert_success
  assert_output --partial '## 工具版本'
  assert_output --regexp '\| git \| .+'
}

@test "输出含环境变量白名单（HOME 三环境必设）" {
  run "$SCRIPT"
  assert_success
  assert_output --partial '## 环境变量'
  assert_output --regexp '\| HOME \| .+'
}

@test "环境识别与 lib/env.sh 一致（复用而非重复实现）" {
  run "$SCRIPT"
  assert_success
  local id
  id="$(env_detect_id)"
  assert_output --partial "- env id: $id"
}

@test "--out 将清单写入文件且 stdout 不含正文" {
  local out="$SANDBOX_DIR/env.md"
  run "$SCRIPT" --out "$out"
  assert_success
  [ -s "$out" ]
  assert_output --partial '已写入'
  refute_output --partial '# 环境清单（env-dump）'
  run grep -q '## 工具版本' "$out"
  assert_success
}

@test "--out 目标目录不存在返回 1 并报错" {
  run "$SCRIPT" --out "$SANDBOX_DIR/no/such/env.md"
  assert_failure 1
  assert_output --partial '目录不存在'
}

@test "--out 缺文件参数返回 2" {
  run "$SCRIPT" --out
  assert_failure 2
}

@test "设置白名单变量后清单包含该变量" {
  WSL_DISTRO_NAME="test-distro" EDITOR="vim" run "$SCRIPT"
  assert_success
  assert_output --partial '| WSL_DISTRO_NAME | test-distro |'
  assert_output --partial '| EDITOR | vim |'
}

@test "脚本通过 bash -n 与 check-metadata hook" {
  run bash -n "$SCRIPT"
  assert_success
  run "$BATS_TEST_DIRNAME/../../hooks/check-metadata.sh" "$SCRIPT"
  assert_success
}
