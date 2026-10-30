#!/usr/bin/env bats
# script-name: disk-alert-test
# description: disk-alert 的水位判定、JSON 输出、着色与错误分支测试（[sandbox-only]，df 用桩驱动）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats
# category: ops

setup() {
  load '../helpers/test_env'
  # 可选组件条件加载：bats 的 setup 内 skip 不中断后续语句
  if env_is_supported ubuntu-26.04 wsl-ubuntu-26.04; then
    load '../../test/libs/bats-support/load'
    load '../../test/libs/bats-assert/load'
  fi
  # sandbox 先于 skip 加载，保证 teardown 中 sandbox_teardown 可用
  load '../helpers/sandbox'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/ops/disk-alert.sh"
}

teardown() {
  sandbox_teardown
}

# 在沙箱 bin 下写一个假 df：
# FAKE_DF_ROWS 提供数据行（POSIX 列序），FAKE_DF_EXIT 控制退出码，
# FAKE_DF_ARGS_FILE 非空时把收到的参数追加记录到该文件（供断言过滤参数）
_write_df_stub() {
  mkdir -p "$SANDBOX_DIR/bin"
  cat > "$SANDBOX_DIR/bin/df" << 'EOF'
#!/usr/bin/env bash
if [[ -n "${FAKE_DF_ARGS_FILE:-}" ]]; then
  printf '%s\n' "$*" >> "$FAKE_DF_ARGS_FILE"
fi
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
if [[ -n "${FAKE_DF_ROWS:-}" ]]; then
  printf '%s\n' "$FAKE_DF_ROWS"
fi
exit "${FAKE_DF_EXIT:-0}"
EOF
  chmod +x "$SANDBOX_DIR/bin/df"
}

# 以桩 df 运行被测脚本: $1=数据行, 其余透传给脚本参数
_run_df() {
  local rows="$1"
  shift
  FAKE_DF_ROWS="$rows" PATH="$SANDBOX_DIR/bin:$PATH" run "$SCRIPT" "$@"
}

@test "help 退出 0 并展示关键选项与退出码语义" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--warn"* ]]
  [[ "$output" == *"--crit"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"退出码"* ]]
}

@test "全部低于 warn 水位返回 0 且无着色" {
  sandbox_setup
  _write_df_stub
  local rows
  rows="/dev/sda1 100000 40000 60000 40% /
/dev/sdb1 100000 79000 21000 79% /data"
  _run_df "$rows"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CRIT=0 WARN=0 OK=2"* ]]
  [[ "$output" != *$'\033['* ]]
}

@test "存在 warn 水位行返回 1" {
  sandbox_setup
  _write_df_stub
  local rows
  rows="/dev/sda1 100000 40000 60000 40% /
/dev/sdb1 100000 85000 15000 85% /data"
  _run_df "$rows"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"85%"* ]]
  [[ "$output" == *"CRIT=0 WARN=1 OK=1"* ]]
}

@test "存在 crit 水位行返回 2" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sda1 100000 95000 5000 95% /home'
  [ "$status" -eq 2 ]
  [[ "$output" == *"CRIT"* ]]
  [[ "$output" == *"95%"* ]]
}

@test "warn 与 crit 同时存在时 crit 优先返回 2" {
  sandbox_setup
  _write_df_stub
  local rows
  rows="/dev/sda1 100000 85000 15000 85% /data
/dev/sdb1 100000 95000 5000 95% /home"
  _run_df "$rows"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CRIT=1 WARN=1"* ]]
}

@test "使用率等于阈值按 >= 判定" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sda1 100000 85000 15000 85% /data' --warn 85 --crit 90
  [ "$status" -eq 1 ]
  _run_df $'/dev/sda1 100000 90000 10000 90% /data' --warn 85 --crit 90
  [ "$status" -eq 2 ]
}

@test "自定义阈值生效（--warn 20 --crit 30）" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sda1 100000 40000 60000 40% /' --warn 20 --crit 30
  [ "$status" -eq 2 ]
  [[ "$output" == *"warn>=20%"* ]]
}

@test "--color 下 warn 行黄色 crit 行红色" {
  sandbox_setup
  _write_df_stub
  local rows
  rows="/dev/sda1 100000 85000 15000 85% /data
/dev/sdb1 100000 95000 5000 95% /home"
  _run_df "$rows" --color
  [ "$status" -eq 2 ]
  [[ "$output" == *$'\033[0;33m'* ]]
  [[ "$output" == *$'\033[0;31m'* ]]
  [[ "$output" == *$'\033[0m'* ]]
}

@test "--no-color 优先于 --color 且默认无着色" {
  sandbox_setup
  _write_df_stub
  local rows
  rows=$'/dev/sda1 100000 95000 5000 95% /home'
  _run_df "$rows" --color --no-color
  [ "$status" -eq 2 ]
  [[ "$output" != *$'\033['* ]]
  _run_df "$rows"
  [ "$status" -eq 2 ]
  [[ "$output" != *$'\033['* ]]
}

@test "--json 输出结构化结果且退出码与文本一致" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sda1 100000 95000 5000 95% /home' --json
  [ "$status" -eq 2 ]
  [[ "$output" == *'"level": "crit"'* ]]
  [[ "$output" == *'"use_pct": 95'* ]]
  [[ "$output" == *'"warn_pct": 80'* ]]
  _run_df $'/dev/sda1 100000 85000 15000 85% /data' --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"level": "warn"'* ]]
  _run_df $'/dev/sda1 100000 40000 60000 40% /' --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"level": "ok"'* ]]
}

@test "--json 输出为合法 JSON（python3 校验）" {
  sandbox_setup
  _write_df_stub
  command -v python3 > /dev/null 2>&1 || skip "python3 不可用"
  local rows
  rows="/dev/sda1 100000 85000 15000 85% /data
/dev/sdb1 100000 40000 60000 40% /"
  _run_df "$rows" --json
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$output"
}

@test "--json 时禁用彩色" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sda1 100000 95000 5000 95% /home' --json --color
  [ "$status" -eq 2 ]
  [[ "$output" != *$'\033['* ]]
}

@test "df 收到 -P 与伪文件系统过滤参数" {
  sandbox_setup
  _write_df_stub
  local args_file="$SANDBOX_DIR/df-args.txt"
  FAKE_DF_ARGS_FILE="$args_file" _run_df $'/dev/sda1 100000 40000 60000 40% /'
  [ "$status" -eq 0 ]
  grep -q -- '-P' "$args_file"
  grep -q -- '-x tmpfs' "$args_file"
  grep -q -- '-x overlay' "$args_file"
}

@test "--warn/--crit 非法值返回 3" {
  sandbox_setup
  _write_df_stub
  local rows
  rows=$'/dev/sda1 100000 40000 60000 40% /'
  _run_df "$rows" --warn abc
  [ "$status" -eq 3 ]
  _run_df "$rows" --warn 101
  [ "$status" -eq 3 ]
  _run_df "$rows" --crit 101
  [ "$status" -eq 3 ]
  _run_df "$rows" --warn -5
  [ "$status" -eq 3 ]
}

@test "--crit 低于 --warn 返回 3" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sda1 100000 40000 60000 40% /' --warn 80 --crit 70
  [ "$status" -eq 3 ]
  [[ "$output" == *"不得低于"* ]]
}

@test "未知选项返回 3" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 3 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "--warn/--crit 缺少参数返回 3" {
  sandbox_setup
  _write_df_stub
  FAKE_DF_ROWS='' PATH="$SANDBOX_DIR/bin:$PATH" run "$SCRIPT" --warn
  [ "$status" -eq 3 ]
  FAKE_DF_ROWS='' PATH="$SANDBOX_DIR/bin:$PATH" run "$SCRIPT" --crit
  [ "$status" -eq 3 ]
}

@test "df 执行失败返回 3 并输出错误" {
  sandbox_setup
  _write_df_stub
  FAKE_DF_EXIT=1 PATH="$SANDBOX_DIR/bin:$PATH" run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"df 执行失败"* ]]
}

@test "df 无数据行返回 3" {
  sandbox_setup
  _write_df_stub
  _run_df ''
  [ "$status" -eq 3 ]
  [[ "$output" == *"未获取到任何磁盘信息"* ]]
}

@test "文件系统名含双引号时 JSON 正确转义" {
  sandbox_setup
  _write_df_stub
  _run_df $'/dev/sd"x 100000 40000 60000 40% /odd' --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"fs": "/dev/sd\"x"'* ]]
  command -v python3 > /dev/null 2>&1 || skip "python3 不可用"
  python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$output"
}
