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
  # python3 缺失的环境（部分 Windows git bash）跳过真实解释器用例；
  # 「桩」前缀用例用 JSONQ_PYTHON 显式指定假解释器，不依赖本机 python3
  if ! command -v python3 > /dev/null 2>&1 \
    && [[ "$BATS_TEST_NAME" != "桩："* ]]; then
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

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 写入读 stdin 的假 python 桩——探针调用（2 个参数）读 stdin 并记录
#   到 STUB_REPORT；查询调用（4 个参数）读 stdin、记录表达式与 stdin
#   内容、stdout 输出 STUBVAL。用于确定性验证 jsonq 的 python 调用
#   stdin 绑定与 timeout 包装（不依赖本机 python3）
make_stdin_stub() {
  cat > "$SANDBOX_DIR/stub-python" << 'EOF'
#!/usr/bin/env bash
report="${STUB_REPORT:?STUB_REPORT 未设置}"
if [[ "$1" == "-c" && "$#" -eq 2 ]]; then
  probe_in="$(cat)"
  printf 'probe|stdin=%s|\n' "$probe_in" >> "$report"
  exit 0
fi
data="$(cat)"
printf 'query|expr=%s|stdin=%s|\n' "$3" "$data" >> "$report"
echo "STUBVAL"
exit 0
EOF
  chmod +x "$SANDBOX_DIR/stub-python"
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

@test "桩：查询调用的 python stdin 绑定输入文件，不继承调用方 stdin" {
  local report="$SANDBOX_DIR/stdin-report.txt"
  : > "$report"
  make_stdin_stub
  # 调用方 stdin 喂入标记数据 CALLER-LEAK；若 python 调用继承它，
  # 桩报告会出现 CALLER-LEAK——断言不得出现
  STUB_REPORT="$report" JSONQ_PYTHON="$SANDBOX_DIR/stub-python" \
    run bash -c 'printf "CALLER-LEAK" | "$1" "$2" user.name' \
    _ "$SCRIPT" "$FIXTURE"
  assert_success
  assert_output "STUBVAL"
  local seen
  seen="$(cat "$report")"
  [[ "$seen" == *'probe|stdin=|'* ]]
  [[ "$seen" == *'"张三"'* ]]
  [[ "$seen" != *'CALLER-LEAK'* ]]
}

@test "桩：健康探针的 python stdin 恒为 /dev/null，不吃调用方 stdin" {
  local report="$SANDBOX_DIR/probe-report.txt"
  : > "$report"
  make_stdin_stub
  STUB_REPORT="$report" JSONQ_PYTHON="$SANDBOX_DIR/stub-python" \
    run bash -c 'printf "CALLER-LEAK" | "$1" "$2" user.name' \
    _ "$SCRIPT" "$FIXTURE"
  assert_success
  local seen
  seen="$(cat "$report")"
  # 探针 stdin 若继承调用方管道会读到 CALLER-LEAK——断言为空
  [[ "$seen" == *'probe|stdin=|'* ]]
  [[ "$seen" != *'probe|stdin=CALLER-LEAK'* ]]
  [[ "$seen" == *'"张三"'* ]]
}

@test "桩：查询调用悬挂被 timeout 上限快速终止并返回 3" {
  local stub="$SANDBOX_DIR/slow-python"
  cat > "$stub" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" && "$#" -eq 2 ]]; then
  exit 0
fi
sleep 30
EOF
  chmod +x "$stub"
  # JSONQ_PY_TIMEOUT=1 验证包装生效（远小于 60s 默认上限）
  JSONQ_PYTHON="$stub" JSONQ_PY_TIMEOUT=1 \
    run "$SCRIPT" "$FIXTURE" user.name
  assert_failure 3
  assert_output --partial "超时"
}

@test "桩：探针悬挂同样被 timeout 上限终止（探测失败返回 3）" {
  local stub="$SANDBOX_DIR/slow-probe-python"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$stub"
  chmod +x "$stub"
  JSONQ_PYTHON="$stub" JSONQ_PY_TIMEOUT=1 \
    run "$SCRIPT" "$FIXTURE" user.name
  assert_failure 3
  assert_output --partial "python3 探针超时"
  assert_output --partial "JSONQ_PYTHON"
}
