#!/usr/bin/env bats
# script-name: test-changed-test
# description: test-changed 映射器的映射规则、回退与输入源测试（沙箱 git 仓库）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, git
# category: dev

setup() {
  load '../helpers/test_env'
  load '../helpers/sandbox'
  sandbox_setup
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dev/test-changed.sh"
}

teardown() {
  sandbox_teardown
}

# bats 文件内助手：在沙箱建最小 git 仓库与目录结构（stdin 显式重定向防 TTY 依赖）
init_repo() {
  git -C "$SANDBOX_DIR" init < /dev/null > /dev/null 2>&1
  git -C "$SANDBOX_DIR" config user.name t
  git -C "$SANDBOX_DIR" config user.email t@t
  mkdir -p "$SANDBOX_DIR/scripts/net" "$SANDBOX_DIR/scripts/lib" \
    "$SANDBOX_DIR/test/net" "$SANDBOX_DIR/rules_check_test" \
    "$SANDBOX_DIR/hooks" "$SANDBOX_DIR/docs"
  touch "$SANDBOX_DIR/test/net/dummy.bats"
}

run_helper() {
  run bash -c "cd '$SANDBOX_DIR' && '$SCRIPT' $* < /dev/null"
}

@test "--files 单脚本映射到对应 .bats" {
  init_repo
  touch "$SANDBOX_DIR/scripts/net/dummy.sh"
  run_helper --files scripts/net/dummy.sh
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/dummy.bats" ]
}

@test "--files 脚本缺测试时警告不阻断" {
  init_repo
  touch "$SANDBOX_DIR/scripts/net/orphan.sh"
  run_helper --files scripts/net/orphan.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"脚本缺测试"* ]]
  [[ "$output" != *"dummy.bats"* ]]
}

@test "--files 测试文件自身映射到自身" {
  init_repo
  run_helper --files test/net/dummy.bats
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/dummy.bats" ]
}

@test "--files rules_check_test 映射到运行器回归" {
  init_repo
  mkdir -p "$SANDBOX_DIR/rules_check_test/bad"
  touch "$SANDBOX_DIR/rules_check_test/bad/new-fixture.sh"
  run_helper --files rules_check_test/bad/new-fixture.sh
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/rules_check_test.bats" ]
}

@test "--files scripts/lib 回退全量" {
  init_repo
  touch "$SANDBOX_DIR/scripts/lib/common.sh"
  run_helper --files scripts/lib/common.sh
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/dummy.bats" ]
}

@test "--files 门禁基础设施回退全量（hooks/Makefile/配置）" {
  init_repo
  touch "$SANDBOX_DIR/hooks/new-hook.sh" "$SANDBOX_DIR/Makefile"
  run_helper --files hooks/new-hook.sh --files Makefile
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/dummy.bats" ]
}

@test "--files 仅 docs 变更跳过并提示" {
  init_repo
  touch "$SANDBOX_DIR/docs/note.md"
  run_helper --files docs/note.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"无匹配用例，跳过"* ]]
}

@test "混合批次：docs + lib 任一回退项触发全量" {
  init_repo
  touch "$SANDBOX_DIR/docs/note.md" "$SANDBOX_DIR/scripts/lib/log.sh"
  run_helper --files docs/note.md --files scripts/lib/log.sh
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/dummy.bats" ]
}

@test "--staged 取暂存区变更（基线提交后仅增量）" {
  init_repo
  git -C "$SANDBOX_DIR" add -A
  git -C "$SANDBOX_DIR" commit -qm base
  touch "$SANDBOX_DIR/scripts/net/staged.sh" "$SANDBOX_DIR/test/net/staged.bats"
  git -C "$SANDBOX_DIR" add -A
  run_helper --staged
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/staged.bats" ]
}

@test "--base 两点 diff 覆盖多提交且去重" {
  init_repo
  touch "$SANDBOX_DIR/scripts/net/a.sh" "$SANDBOX_DIR/test/net/a.bats"
  git -C "$SANDBOX_DIR" add -A
  git -C "$SANDBOX_DIR" commit -qm base
  local base_hash
  base_hash="$(git -C "$SANDBOX_DIR" rev-parse HEAD)"
  touch "$SANDBOX_DIR/scripts/net/b.sh" "$SANDBOX_DIR/test/net/b.bats"
  git -C "$SANDBOX_DIR" add -A
  git -C "$SANDBOX_DIR" commit -qm second
  run bash -c \
    "cd '$SANDBOX_DIR' && '$SCRIPT' --base '$base_hash' < /dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "$SANDBOX_DIR/test/net/b.bats" ]
}

@test "非 git 目录返回 2" {
  sandbox_setup
  run bash -c "cd '$SANDBOX_DIR' && '$SCRIPT' --files x.sh < /dev/null"
  [ "$status" -eq 2 ]
  [[ "$output" == *"不在 git 仓库内"* ]]
}

@test "--run 失败用例返回 1" {
  init_repo
  touch "$SANDBOX_DIR/scripts/net/broken.sh"
  printf '@test "broken" { false; }\n' > "$SANDBOX_DIR/test/net/broken.bats"
  run_helper --run --files scripts/net/broken.sh
  [ "$status" -eq 1 ]
}

@test "--run 空文件用例返回 0" {
  init_repo
  touch "$SANDBOX_DIR/scripts/net/ok.sh"
  run_helper --run --files scripts/net/ok.sh
  [ "$status" -eq 0 ]
}

@test "未知参数返回 2" {
  init_repo
  run_helper --bogus
  [ "$status" -eq 2 ]
}
