#!/usr/bin/env bats
# script-name: git-wip-test
# description: git-wip 的单元测试（[sandbox-only]，git 操作全部在 mktemp 沙箱仓库执行）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, git
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
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dev/git-wip.sh"
  WIP_SEQ=0
  REPO=""
}

teardown() {
  # 先离开可能已被删除的沙箱目录，再清理
  cd "$BATS_TEST_DIRNAME" || return 0
  sandbox_teardown
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 在沙箱创建带初始提交的仓库（$1=目录名 $2=分支）并 cd 进去，设 REPO
new_repo() {
  local dir="$1" branch="${2:-main}"
  REPO="$SANDBOX_DIR/$dir"
  git init -q -b "$branch" "$REPO"
  git -C "$REPO" config user.name tester
  git -C "$REPO" config user.email tester@example.com
  printf 'base\n' > "$REPO/base.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "base"
  WIP_SEQ=0
  cd "$REPO" || return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 在 REPO 中追加一个确定性消息的 wip 提交（wip: noteN|时间戳）
add_wip() {
  WIP_SEQ=$((WIP_SEQ + 1))
  printf 'v%s\n' "$WIP_SEQ" >> "$REPO/track.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "wip: note${WIP_SEQ}|20260101-0000${WIP_SEQ}"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出 REPO 中当前 wip 提交数量
wip_count() {
  git -C "$REPO" log --grep='^wip: ' --format='%H' | wc -l
}

@test "无参数输出用法并返回 2" {
  run "$SCRIPT"
  assert_failure 2
  assert_output --partial "用法: git-wip.sh"
}

@test "--help 返回 0 并显示用法" {
  run "$SCRIPT" --help
  assert_success
  assert_output --partial "用法: git-wip.sh"
}

@test "未知子命令返回 2" {
  run "$SCRIPT" bogus
  assert_failure 2
  assert_output --partial "用法: git-wip.sh"
}

@test "非 git 目录返回明确错误（返回 1）" {
  cd "$SANDBOX_DIR"
  run "$SCRIPT" wip
  assert_failure 1
  assert_output --partial "git 仓库"
}

@test "wip 无变更时跳过提交（返回 0）" {
  new_repo clean-main
  run "$SCRIPT" wip
  assert_success
  assert_output --partial "无变更"
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 1 ]
}

@test "wip 提交全部改动并带备注与时间戳" {
  new_repo wip-note
  printf 'hello\n' > "$REPO/new.txt"
  run "$SCRIPT" wip 测试备注
  assert_success
  local subject
  subject="$(git -C "$REPO" log -1 --format=%s)"
  [[ "$subject" == "wip: 测试备注|"* ]]
}

@test "wip 无备注时提交信息为时间戳格式" {
  new_repo wip-nots
  printf 'hello\n' > "$REPO/new.txt"
  run "$SCRIPT" wip
  assert_success
  local subject
  subject="$(git -C "$REPO" log -1 --format=%s)"
  [[ "$subject" =~ ^wip:\ [0-9]{8}-[0-9]{6}$ ]]
}

@test "wip 在仓库子目录执行也能生效" {
  new_repo wip-sub
  mkdir -p "$REPO/sub"
  printf 'hello\n' > "$REPO/sub/new.txt"
  cd "$REPO/sub" || return 1
  run "$SCRIPT" wip 子目录
  assert_success
  [ "$(wip_count)" -eq 1 ]
}

@test "list 默认列出全部 wip 提交（倒序）" {
  new_repo list-all
  add_wip
  add_wip
  add_wip
  run "$SCRIPT" list
  assert_success
  [ "$(grep -c 'note' <<< "$output")" -eq 3 ]
  [[ "$output" == *"note3"* ]]
}

@test "list n 只列最近 n 个 wip 提交" {
  new_repo list-n
  add_wip
  add_wip
  add_wip
  run "$SCRIPT" list 2
  assert_success
  [ "$(grep -c 'note' <<< "$output")" -eq 2 ]
  [[ "$output" == *"note3"* ]]
  [[ "$output" != *"note1"* ]]
}

@test "list 无 wip 提交时提示（返回 0）" {
  new_repo list-empty
  run "$SCRIPT" list
  assert_success
  assert_output --partial "没有 wip 提交"
}

@test "list 非数字参数返回 2" {
  new_repo list-bad
  run "$SCRIPT" list abc
  assert_failure 2
  assert_output --partial "正整数"
}

@test "squash main 分支默认拒绝" {
  new_repo sq-main main
  add_wip
  add_wip
  run "$SCRIPT" squash
  assert_failure 1
  assert_output --partial "main"
  [ "$(wip_count)" -eq 2 ]
}

@test "squash main 分支 --force 解除并合并成功" {
  new_repo sq-force main
  add_wip
  add_wip
  run "$SCRIPT" squash --force -m "feat: 完成"
  assert_success
  [ "$(wip_count)" -eq 0 ]
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
  [[ "$(git -C "$REPO" log -1 --format=%s)" == "feat: 完成" ]]
}

@test "squash 特性分支默认 n=2 合并最近两个 wip" {
  new_repo sq-feat feat
  add_wip
  add_wip
  add_wip
  run "$SCRIPT" squash -m "feat: 合并两个"
  assert_success
  [ "$(wip_count)" -eq 1 ]
  [[ "$(git -C "$REPO" log -1 --format=%s)" == "feat: 合并两个" ]]
}

@test "squash 工作区有未提交改动时拒绝" {
  new_repo sq-dirty feat
  add_wip
  add_wip
  printf 'dirty\n' > "$REPO/dirty.txt"
  run "$SCRIPT" squash -m "feat: x"
  assert_failure 1
  assert_output --partial "工作区"
}

@test "squash wip 提交不足 n 个时拒绝" {
  new_repo sq-few feat
  add_wip
  run "$SCRIPT" squash 2 -m "feat: x"
  assert_failure 1
  assert_output --partial "不足"
}

@test "squash wip 提交不连续时拒绝" {
  new_repo sq-gap feat
  add_wip
  printf 'mid\n' > "$REPO/mid.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "mid"
  add_wip
  run "$SCRIPT" squash 2 -m "feat: x"
  assert_failure 1
  assert_output --partial "不连续"
  [ "$(wip_count)" -eq 2 ]
}

@test "squash n=1 返回错误" {
  new_repo sq-one feat
  add_wip
  run "$SCRIPT" squash 1 -m "feat: x"
  assert_failure 1
  assert_output --partial "至少"
}

@test "squash 缺少 -m 参数值返回 2" {
  new_repo sq-nomsg feat
  add_wip
  add_wip
  run "$SCRIPT" squash -m
  assert_failure 2
}

@test "squash 交互输入提交信息（stdin 管道）" {
  new_repo sq-tty feat
  add_wip
  add_wip
  printf 'feat: 来自交互输入\n' > "$SANDBOX_DIR/msg.txt"
  run "$SCRIPT" squash < "$SANDBOX_DIR/msg.txt"
  assert_success
  [[ "$(git -C "$REPO" log -1 --format=%s)" == "feat: 来自交互输入" ]]
}

@test "squash 交互输入为空时取消" {
  new_repo sq-empty feat
  add_wip
  add_wip
  run "$SCRIPT" squash < /dev/null
  assert_failure 1
  assert_output --partial "取消"
  [ "$(wip_count)" -eq 2 ]
}
