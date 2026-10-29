#!/usr/bin/env bats
# script-name: sysinfo-test
# description: sysinfo 的单元测试（[sandbox-only]，只断言段落与关键行存在性，不做数值断言）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats, python3
# category: system

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/system/sysinfo.sh"
}

@test "默认输出包含全部六个段落标题" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"== 系统 =="* ]]
  [[ "$output" == *"== 运行时间与负载 =="* ]]
  [[ "$output" == *"== 磁盘使用（阈值 80%"* ]]
  [[ "$output" == *"== 内存与 swap =="* ]]
  [[ "$output" == *"== systemd 失败单元 =="* ]]
  [[ "$output" == *"== 最近登录（last -n 5） =="* ]]
}

@test "系统段含内核与发行版行" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"内核: "* ]]
  [[ "$output" == *"发行版: "* ]]
}

@test "运行段含运行时间与负载行" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"运行时间: "* ]]
  [[ "$output" == *"负载 (1/5/15min): "* ]]
}

@test "磁盘段含表头与根挂载点行" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"文件系统"* ]]
  # 根挂载点行: <文件系统> / <使用率>（对齐空白分隔）
  grep -Eq '^[^[:space:]]+[[:space:]]+/[[:space:]]+[0-9]+%' <<< "$output"
}

@test "内存段含 mem 与 swap 行（LC_ALL=C 固定标签）" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mem: 总计 "* ]]
  [[ "$output" == *"swap: 总计 "* ]]
}

@test "systemd 段正常列出、无失败或降级三者取一" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local after
  local re='[a-zA-Z0-9@._-]+\.(service|timer|socket|mount|target'
  re="${re}|path|slice|scope|swap|automount|device)"
  after="${output#*== systemd 失败单元 ==}"
  [[ "$after" == *"（无失败单元）"* ]] \
    || [[ "$after" == *"（systemd 不可用，已降级跳过）"* ]] \
    || [[ "$after" =~ $re ]]
}

@test "最近登录段有内容或降级说明，不崩溃" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local after
  after="${output#*== 最近登录（last -n 5） ==}"
  [[ -n "$after" ]]
}

@test "--json 输出合法 JSON 且含关键字段" {
  local jf="$BATS_TEST_TMPDIR/sysinfo.json"
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$jf"
  run python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("kernel", "distro", "uptime", "load1", "disks",
          "mem_bytes", "swap_bytes", "systemd_available",
          "failed_units", "last_logins", "warn_pct"):
    assert k in d, k
assert isinstance(d["disks"], list)
assert isinstance(d["mem_bytes"], dict)
' "$jf"
  [ "$status" -eq 0 ]
}

@test "--json 磁盘项含 fs/mount/use_pct/over 字段" {
  local jf="$BATS_TEST_TMPDIR/sysinfo-disk.json"
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$jf"
  run python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["disks"], "根挂载点所在盘必然存在"
for it in d["disks"]:
    for k in ("fs", "mount", "use_pct", "over"):
        assert k in it, k
' "$jf"
  [ "$status" -eq 0 ]
}

@test "--warn 0 --color 时磁盘行存在红色转义" {
  run "$SCRIPT" --warn 0 --color
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[0;31m'* ]]
}

@test "--warn 100 --color 时无红色转义" {
  run "$SCRIPT" --warn 100 --color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[0;31m'* ]]
}

@test "--no-color 时无 ANSI 转义（即使低阈值）" {
  run "$SCRIPT" --warn 0 --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
}

@test "--json 与 --color 同给时自动无色" {
  run "$SCRIPT" --json --color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
}

@test "--warn 自定义值被采纳（标题反映阈值）" {
  run "$SCRIPT" --warn 90
  [ "$status" -eq 0 ]
  [[ "$output" == *"== 磁盘使用（阈值 90%"* ]]
}

@test "--warn 缺参数值返回 2" {
  run "$SCRIPT" --warn
  [ "$status" -eq 2 ]
  [[ "$output" == *"--warn 需要"* ]]
}

@test "--warn 非法值返回 2" {
  run "$SCRIPT" --warn abc
  [ "$status" -eq 2 ]
  run "$SCRIPT" --warn 101
  [ "$status" -eq 2 ]
  run "$SCRIPT" --warn -1
  [ "$status" -eq 2 ]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "多余位置参数按未知选项拒绝返回 2" {
  run "$SCRIPT" extra
  [ "$status" -eq 2 ]
}

@test "--help 退出 0 并含选项说明" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--warn"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--no-color"* ]]
}
