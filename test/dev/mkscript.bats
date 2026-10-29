#!/usr/bin/env bats
# script-name: mkscript-test
# description: mkscript 的参数校验与骨架生成测试（[sandbox-only]，写入 MKSCRIPT_ROOT 沙箱）
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
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dev/mkscript.sh"
  HOOKS="$BATS_TEST_DIRNAME/../../hooks"
  FAKE_ROOT="$SANDBOX_DIR/repo"
  mkdir -p "$FAKE_ROOT"
  export MKSCRIPT_ROOT="$FAKE_ROOT"
}

teardown() {
  sandbox_teardown
}

@test "无参数输出用法并返回 2" {
  run "$SCRIPT"
  assert_failure 2
  assert_output --partial "用法: mkscript"
}

@test "--help 返回 0 并显示用法" {
  run "$SCRIPT" --help
  assert_success
  assert_output --partial "用法: mkscript"
}

@test "未知选项被拒绝（返回 2）" {
  run "$SCRIPT" demo dev --bogus
  assert_failure 2
}

@test "非法脚本名被拒绝（kebab-case 校验）" {
  run "$SCRIPT" Bad_Name dev
  assert_failure 1
  assert_output --partial "kebab-case"
}

@test "非法分类被拒绝（白名单校验）" {
  run "$SCRIPT" demo nosuchcat
  assert_failure 1
  assert_output --partial "非法"
}

@test "正常生成脚本与测试骨架并打印 SOP 提示" {
  run "$SCRIPT" demo-script text
  assert_success
  [ -x "$FAKE_ROOT/scripts/text/demo-script.sh" ]
  [ -f "$FAKE_ROOT/test/text/demo-script.bats" ]
  assert_output --partial "后续 SOP"
}

@test "生成骨架包含 5 个必需头部 tag" {
  run "$SCRIPT" tag-demo files
  assert_success
  local f="$FAKE_ROOT/scripts/files/tag-demo.sh" tag
  for tag in script-name description usage env category; do
    grep -q "^# $tag:" "$f"
  done
}

@test "已存在文件拒绝覆盖（返回 1）" {
  run "$SCRIPT" dup-demo net
  assert_success
  run "$SCRIPT" dup-demo net
  assert_failure 1
  assert_output --partial "已存在"
}

@test "--force 允许覆盖已存在文件" {
  run "$SCRIPT" force-demo wsl
  assert_success
  run "$SCRIPT" force-demo wsl --force
  assert_success
}

@test "--system 骨架预留 --dry-run 且 env 不含 git-bash" {
  run "$SCRIPT" sys-demo ops --system
  assert_success
  local f="$FAKE_ROOT/scripts/ops/sys-demo.sh"
  grep -q -- '--dry-run' "$f"
  run grep -q 'git-bash' "$f"
  assert_failure
}

@test "系统级骨架 --dry-run 仅打印动作（函数级行为）" {
  run "$SCRIPT" sys-run ops --system
  assert_success
  run "$FAKE_ROOT/scripts/ops/sys-run.sh" --dry-run
  assert_success
  [[ "$output" == *"[dry-run]"* ]]
}

@test "普通骨架无参数输出用法并返回非零（生成物行为）" {
  run "$SCRIPT" cli-demo dev
  assert_success
  run "$FAKE_ROOT/scripts/dev/cli-demo.sh"
  assert_failure
  [[ "$output" == *"用法: cli-demo.sh"* ]]
}

@test "生成的脚本通过 bash -n 语法检查" {
  run "$SCRIPT" syntax-demo text
  assert_success
  run bash -n "$FAKE_ROOT/scripts/text/syntax-demo.sh"
  assert_success
}

@test "生成的骨架通过 check-metadata hook（普通与系统级）" {
  run "$SCRIPT" meta-demo security
  assert_success
  run "$SCRIPT" meta-sys system --system
  assert_success
  run "$HOOKS/check-metadata.sh" \
    "$FAKE_ROOT/scripts/security/meta-demo.sh" \
    "$FAKE_ROOT/test/security/meta-demo.bats" \
    "$FAKE_ROOT/scripts/system/meta-sys.sh" \
    "$FAKE_ROOT/test/system/meta-sys.bats"
  assert_success
}

@test "生成的脚本通过 shfmt -d（shfmt 可用时）" {
  if ! command -v shfmt > /dev/null 2>&1; then
    skip "shfmt 未安装（git bash 可选）"
  fi
  run "$SCRIPT" fmt-demo files
  assert_success
  run shfmt -d -i 2 -ci -bn -sr \
    "$FAKE_ROOT/scripts/files/fmt-demo.sh"
  assert_success
}

@test "生成的脚本通过 shellcheck severity=style（可用时）" {
  if ! command -v shellcheck > /dev/null 2>&1; then
    skip "shellcheck 未安装（git bash 可选）"
  fi
  run "$SCRIPT" sc-demo net
  assert_success
  run shellcheck --severity=style \
    "$FAKE_ROOT/scripts/net/sc-demo.sh"
  assert_success
}
