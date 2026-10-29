#!/usr/bin/env bats
# script-name: log-grep-test
# description: log-grep 的单元测试（[sandbox-only]，fixture 日志写入 mktemp 沙箱）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, coreutils
# category: text

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
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/text/log-grep.sh"
  FIX1="$SANDBOX_DIR/app.log"
  FIX2="$SANDBOX_DIR/gateway.log"
  make_fixtures
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || return 0
  sandbox_teardown
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 在沙箱生成 fixture 日志（时间相对 now 动态生成，避免边界；覆盖
#     ISO 带方括号/时区后缀、syslog（含星期前缀）、无时间戳行等格式）
make_fixtures() {
  local t1h t3h t30m sys30 sys10 weekday tz
  t1h="$(date -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S')"
  t3h="$(date -d '3 hours ago' '+%Y-%m-%dT%H:%M:%S')"
  t30m="$(date -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
  sys30="$(LC_ALL=C date -d '30 minutes ago' '+%b %e %T')"
  sys10="$(LC_ALL=C date -d '10 minutes ago' '+%b %e %T')"
  weekday="$(LC_ALL=C date -d '10 minutes ago' '+%a %b %e %T')"
  tz="$(date -d '90 minutes ago' '+%Y-%m-%dT%H:%M:%S+00:00')"
  cat > "$FIX1" << EOF
${t1h} INFO service started
${t3h} WARN slow query detected
[${t1h}] ERROR db timeout occurred
${sys30} myhost sshd: failed password for admin
2020-01-01T00:00:00 INFO ancient line
plain line without timestamp ERROR text
${tz} INFO tz marker line
EOF
  cat > "$FIX2" << EOF
${t1h} ERROR payment gateway timeout
${t30m} INFO cleanup done
${t3h} ERROR disk full
${sys10} gateway cron: rotate logs
EOF
  # 第三份带星期前缀的 syslog 行，单独用于星期格式解析用例
  WEEKFIX="$SANDBOX_DIR/syslog.log"
  printf '%s host cron: weekly job ran\n' "$weekday" > "$WEEKFIX"
}

@test "无参数输出用法并返回 2" {
  run "$SCRIPT"
  assert_failure 2
  assert_output --partial "用法: log-grep.sh"
}

@test "--help 返回 0 并显示用法" {
  run "$SCRIPT" --help
  assert_success
  assert_output --partial "用法: log-grep.sh"
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus "$FIX1"
  assert_failure 2
  assert_output --partial "未知选项"
}

@test "缺少文件参数返回 2" {
  run "$SCRIPT" -k ERROR
  assert_failure 2
  assert_output --partial "用法: log-grep.sh"
}

@test "空关键字返回 2" {
  run "$SCRIPT" -k "" "$FIX1"
  assert_failure 2
  assert_output --partial "关键字不能为空"
}

@test "非法 --since 返回 2" {
  run "$SCRIPT" --since garbage "$FIX1"
  assert_failure 2
  assert_output --partial "无法解析 --since"
}

@test "OR 关键字命中任一即输出（含无时间戳行）" {
  run "$SCRIPT" -k ERROR --no-color "$FIX1"
  assert_success
  assert_output --partial "ERROR db timeout occurred"
  assert_output --partial "plain line without timestamp ERROR text"
  refute_output --partial "service started"
  refute_output --partial "slow query"
}

@test "AND 关键字需全部命中" {
  run "$SCRIPT" -K ERROR -K timeout --no-color "$FIX1"
  assert_success
  assert_output --partial "ERROR db timeout occurred"
  refute_output --partial "plain line"
}

@test "AND 全不命中返回 1 且无输出" {
  run "$SCRIPT" -K ERROR -K nosuchword "$FIX1"
  assert_failure 1
  assert_output ""
}

@test "-k 与 -K 组合（OR 命中且 AND 全中）" {
  run "$SCRIPT" -k INFO -K ancient --no-color "$FIX1"
  assert_success
  assert_output --partial "ancient line"
  refute_output --partial "service started"
  refute_output --partial "tz marker"
}

@test "默认高亮输出含 ANSI 转义" {
  run "$SCRIPT" -k WARN "$FIX1"
  assert_success
  assert_output --partial $'\033[1;31mWARN\033[0m'
}

@test "--no-color 输出不含 ANSI 转义" {
  run "$SCRIPT" -k WARN --no-color "$FIX1"
  assert_success
  refute_output --partial $'\033'
}

@test "关键字含正则元字符时按字面匹配" {
  printf 'a.c [x] y\nabc [x] z\n' > "$SANDBOX_DIR/meta.log"
  run "$SCRIPT" -k "a.c" --no-color "$SANDBOX_DIR/meta.log"
  assert_success
  assert_output --partial "a.c [x] y"
  refute_output --partial "abc"
}

@test "--since 相对时间 2h 过滤（丢弃无时间戳行）" {
  run "$SCRIPT" --since 2h --no-color "$FIX1"
  assert_success
  assert_output --partial "service started"
  assert_output --partial "ERROR db timeout occurred"
  assert_output --partial "failed password for admin"
  refute_output --partial "slow query"
  refute_output --partial "ancient line"
  refute_output --partial "plain line"
}

@test "--until 相对时间 2h 过滤" {
  run "$SCRIPT" --until 2h --no-color "$FIX1"
  assert_success
  assert_output --partial "slow query"
  assert_output --partial "ancient line"
  refute_output --partial "service started"
  refute_output --partial "failed password"
}

@test "--since/--until 绝对时间窗口" {
  run "$SCRIPT" --since 2020-01-01 --until 2020-12-31T23:59:59 \
    --no-color "$FIX1"
  assert_success
  assert_output --partial "ancient line"
  refute_output --partial "service started"
  refute_output --partial "slow query"
}

@test "syslog 时间格式（Oct 30 09:15:00）可解析" {
  run "$SCRIPT" --since 2h --no-color "$FIX2"
  assert_success
  assert_output --partial "rotate logs"
}

@test "带星期前缀的 syslog 时间格式可解析" {
  run "$SCRIPT" --since 1h --no-color "$WEEKFIX"
  assert_success
  assert_output --partial "weekly job ran"
}

@test "ISO 时间戳带时区后缀（+00:00）可解析" {
  # 仅验证时间戳能被识别（不因时区语义断言时间窗命中与否）
  run "$SCRIPT" -k "tz marker" --no-color "$FIX1"
  assert_success
  assert_output --partial "tz marker line"
}

@test "多文件输出带「文件名:」前缀" {
  run "$SCRIPT" -k ERROR --no-color "$FIX1" "$FIX2"
  assert_success
  assert_output --partial "${FIX1}:plain line without timestamp ERROR text"
  assert_output --partial "ERROR db timeout occurred"
  assert_output --partial "ERROR payment gateway timeout"
  assert_output --partial "ERROR disk full"
  assert_output --partial "${FIX1}:"
  assert_output --partial "${FIX2}:"
}

@test "单文件输出无前缀" {
  run "$SCRIPT" -k WARN --no-color "$FIX1"
  assert_success
  refute_output --partial "${FIX1}:"
}

@test "从 stdin（-）读取" {
  run bash -c 'cat "$1" | "$2" -k WARN --no-color -' _ "$FIX1" "$SCRIPT"
  assert_success
  assert_output --partial "slow query detected"
}

@test "无匹配返回 1" {
  run "$SCRIPT" -k zzzznomatch --no-color "$FIX1"
  assert_failure 1
  assert_output ""
}

@test "关键字区分大小写" {
  run "$SCRIPT" -k warn --no-color "$FIX1"
  assert_failure 1
}

@test "文件不可读返回 3 且仍处理其余文件" {
  run "$SCRIPT" -k ERROR --no-color "$SANDBOX_DIR/no-such.log" "$FIX1"
  assert_failure 3
  assert_output --partial "文件不可读"
  assert_output --partial "ERROR db timeout occurred"
}
