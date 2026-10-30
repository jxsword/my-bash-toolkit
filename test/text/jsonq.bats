#!/usr/bin/env bats
# script-name: jsonq-test
# description: jsonq 的单元测试（[sandbox-only]，fixture 全部写入 mktemp 沙箱）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, python3
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
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/text/jsonq.sh"
  FIXTURE="$SANDBOX_DIR/data.json"
  # python3 缺失的环境（部分 Windows git bash）整体跳过主路径用例
  if ! command -v python3 > /dev/null 2>&1; then
    skip "python3 不可用，跳过 jsonq 测试"
  fi
  make_fixture
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || return 0
  sandbox_teardown
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 在沙箱写入固定 fixture（对象/数组/下标/null/中文各覆盖一处）
make_fixture() {
  cat > "$FIXTURE" << 'EOF'
{
  "user": {"name": "张三", "age": 30, "nick": null, "active": true},
  "items": [
    {"id": 1},
    {"id": 2},
    {"id": 3, "tags": ["x", "y"]}
  ]
}
EOF
}

@test "无参数输出用法并返回 2" {
  run "$SCRIPT"
  assert_failure 2
  assert_output --partial "用法: jsonq.sh"
}

@test "--help 返回 0 并显示用法" {
  run "$SCRIPT" --help
  assert_success
  assert_output --partial "用法: jsonq.sh"
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus "$FIXTURE" user.name
  assert_failure 2
  assert_output --partial "用法: jsonq.sh"
}

@test "缺少路径参数返回 2" {
  run "$SCRIPT" "$FIXTURE"
  assert_failure 2
  assert_output --partial "用法: jsonq.sh"
}

@test "-t 与 -e 同时给出返回 2" {
  run "$SCRIPT" -t -e "$FIXTURE" user.name
  assert_failure 2
  assert_output --partial "用法: jsonq.sh"
}

@test "对象点路径取值（字符串以 JSON 字面量输出）" {
  run "$SCRIPT" "$FIXTURE" user.name
  assert_success
  assert_output '"张三"'
}

@test "数值直接输出" {
  run "$SCRIPT" "$FIXTURE" user.age
  assert_success
  assert_output '30'
}

@test "数组下标取值（items.0.id）" {
  run "$SCRIPT" "$FIXTURE" items.0.id
  assert_success
  assert_output '1'
}

@test "嵌套对象+数组混合路径（items.2.tags.1）" {
  run "$SCRIPT" "$FIXTURE" items.2.tags.1
  assert_success
  assert_output '"y"'
}

@test "数组整体输出为 JSON" {
  run "$SCRIPT" "$FIXTURE" items.2.tags
  assert_success
  assert_output --partial '"x"'
  assert_output --partial '"y"'
}

@test "布尔值输出 true" {
  run "$SCRIPT" "$FIXTURE" user.active
  assert_success
  assert_output 'true'
}

@test "null 值输出 null 且退出码为 0" {
  run "$SCRIPT" "$FIXTURE" user.nick
  assert_success
  assert_output 'null'
}

@test "-t 输出各 JSON 类型名" {
  run "$SCRIPT" -t "$FIXTURE" user
  assert_success
  assert_output 'object'
  run "$SCRIPT" -t "$FIXTURE" items
  assert_success
  assert_output 'array'
  run "$SCRIPT" -t "$FIXTURE" user.name
  assert_success
  assert_output 'string'
  run "$SCRIPT" -t "$FIXTURE" user.age
  assert_success
  assert_output 'number'
  run "$SCRIPT" -t "$FIXTURE" user.active
  assert_success
  assert_output 'boolean'
  run "$SCRIPT" -t "$FIXTURE" user.nick
  assert_success
  assert_output 'null'
}

@test "-t 路径不存在返回 1" {
  run "$SCRIPT" -t "$FIXTURE" no.such
  assert_failure 1
}

@test "-e 存在的路径返回 0 且无输出" {
  run "$SCRIPT" -e "$FIXTURE" user.name
  assert_success
  assert_output ''
}

@test "-e 不存在的路径返回 1" {
  run "$SCRIPT" -e "$FIXTURE" no.such.deep
  assert_failure 1
}

@test "普通查询路径不存在返回 1 并输出错误" {
  run "$SCRIPT" "$FIXTURE" items.9.id
  assert_failure 1
}

@test "下标段用于对象键不存在时返回 1" {
  run "$SCRIPT" "$FIXTURE" user.0
  assert_failure 1
}

@test "负数下标返回 1" {
  run "$SCRIPT" "$FIXTURE" items.-1.id
  assert_failure 1
}

@test "前导 \$ 的路径表达式可用（\$.user.name）" {
  run "$SCRIPT" "$FIXTURE" '$.user.name'
  assert_success
  assert_output '"张三"'
}

@test "路径表达式为根 \$ 时输出整个文档" {
  run "$SCRIPT" "$FIXTURE" '$'
  assert_success
  assert_output --partial '"user"'
  assert_output --partial '"items"'
}

@test "连续点号的路径表达式返回 2" {
  run "$SCRIPT" "$FIXTURE" 'a..b'
  assert_failure 2
  assert_output --partial "非法路径表达式"
}

@test "从 stdin（-）读取 JSON" {
  run bash -c 'printf "{\"a\":{\"b\":42}}" | "$1" - a.b' _ "$SCRIPT"
  assert_success
  assert_output '42'
}

@test "非法 JSON 返回 3 并输出错误" {
  printf '{bad json' > "$SANDBOX_DIR/bad.json"
  run "$SCRIPT" "$SANDBOX_DIR/bad.json" a
  assert_failure 3
  assert_output --partial "非法 JSON"
}

@test "文件不存在返回 3" {
  run "$SCRIPT" "$SANDBOX_DIR/no-such-file.json" a
  assert_failure 3
  assert_output --partial "文件不可读"
}

@test "python3 缺失时返回 3 并给出明确错误" {
  JSONQ_PYTHON=jsonq-no-such-python run "$SCRIPT" "$FIXTURE" user.name
  assert_failure 3
  assert_output --partial "python3"
}

@test "python3 探测失败（存根式，退出 49）返回 3 并提示 JSONQ_PYTHON" {
  # 确定性模拟 Windows Store 存根：解释器存在（command -v 命中），
  # 但执行必失败且退出码 49（9009 经 MSYS 折算）
  local stub="$SANDBOX_DIR/fake-python-stub"
  printf '#!/usr/bin/env bash\nexit 49\n' > "$stub"
  chmod +x "$stub"
  JSONQ_PYTHON="$stub" run "$SCRIPT" "$FIXTURE" user.name
  assert_failure 3
  assert_output --partial "python3 探测失败（退出码 49）"
  assert_output --partial "JSONQ_PYTHON"
}

@test "python3 探测失败不影响输出 stderr 指引（退出码任意非零均拦）" {
  local stub="$SANDBOX_DIR/fake-python-rc1"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$stub"
  chmod +x "$stub"
  JSONQ_PYTHON="$stub" run "$SCRIPT" -e "$FIXTURE" user.name
  assert_failure 3
  assert_output --partial "JSONQ_PYTHON"
}
