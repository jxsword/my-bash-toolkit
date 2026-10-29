#!/usr/bin/env bats
# script-name: port-check-test
# description: port-check 的本机占用与连通性测试（真实回环端口，无外网依赖）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats, python3
# category: net
# @test 块与 helper 函数对 PORT/SERVER_PID 的写入属同一 bats 子 shell，误报作用域：
# shellcheck disable=SC2030,SC2031

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/net/port-check.sh"
  SERVER_PID=""
  PORT=""
}

teardown() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2> /dev/null || true
    wait "$SERVER_PID" 2> /dev/null || true
  fi
}

# 取一个当前空闲的回环端口（bind 0 后释放）
free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

# 在 127.0.0.1 上启动临时 HTTP 服务并等待 ss 可见
start_server() {
  PORT="$(free_port)"
  python3 -m http.server "$PORT" --bind 127.0.0.1 > /dev/null 2>&1 &
  SERVER_PID=$!
  local i
  for ((i = 0; i < 50; i++)); do
    if ss -ltn 2> /dev/null | grep -q "127.0.0.1:${PORT}"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

@test "监听中的回环端口: 占用=是 连通=通 退出0" {
  start_server
  run "$SCRIPT" 127.0.0.1 "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"目标: 127.0.0.1:${PORT}"* ]]
  [[ "$output" == *"本机占用: 是"* ]]
  [[ "$output" == *"连通性: 通 (nc)"* ]]
  [[ "$output" == *"结论: 端口开放"* ]]
}

@test "本机占用明细含进程名与 pid（当前用户进程）" {
  start_server
  run "$SCRIPT" 127.0.0.1 "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LISTEN 127.0.0.1:${PORT}"* ]]
  [[ "$output" == *"进程 python3 (pid="* ]]
}

@test "--method tcp: /dev/tcp 退化路径对监听端口连通" {
  start_server
  run "$SCRIPT" --method tcp 127.0.0.1 "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"连通性: 通 (tcp)"* ]]
  [[ "$output" == *"结论: 端口开放"* ]]
}

@test "--method nc: 显式指定 nc 探测连通" {
  start_server
  run "$SCRIPT" --method nc 127.0.0.1 "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"连通性: 通 (nc)"* ]]
}

@test "未监听端口: 占用=否 不通 退出1" {
  PORT="$(free_port)"
  run "$SCRIPT" 127.0.0.1 "$PORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"本机占用: 否"* ]]
  [[ "$output" == *"连通性: 不通"* ]]
  [[ "$output" == *"结论: 端口不可达"* ]]
}

@test "--method tcp 对未监听端口返回 1" {
  PORT="$(free_port)"
  run "$SCRIPT" --method tcp --timeout 2 127.0.0.1 "$PORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"连通性: 不通"* ]]
}

@test "localhost 别名可匹配 127.0.0.1 上的监听" {
  start_server
  run "$SCRIPT" localhost "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"本机占用: 是"* ]]
  [[ "$output" == *"结论: 端口开放"* ]]
}

@test "--timeout 选项被接受且不改变结论" {
  start_server
  run "$SCRIPT" --timeout 1 127.0.0.1 "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"连通性: 通"* ]]
}

@test "缺参数返回 2 并输出用法" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"用法: port-check.sh"* ]]
}

@test "只给 host 缺 port 返回 2" {
  run "$SCRIPT" 127.0.0.1
  [ "$status" -eq 2 ]
}

@test "多余参数返回 2" {
  run "$SCRIPT" 127.0.0.1 22 extra
  [ "$status" -eq 2 ]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus 127.0.0.1 22
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "选项缺参数值返回 2" {
  run "$SCRIPT" --timeout
  [ "$status" -eq 2 ]
  run "$SCRIPT" 127.0.0.1 22 --method
  [ "$status" -eq 2 ]
}

@test "非法端口返回 2" {
  run "$SCRIPT" 127.0.0.1 0
  [ "$status" -eq 2 ]
  run "$SCRIPT" 127.0.0.1 70000
  [ "$status" -eq 2 ]
  run "$SCRIPT" 127.0.0.1 abc
  [ "$status" -eq 2 ]
}

@test "非法主机名返回 2" {
  run "$SCRIPT" "bad host" 22
  [ "$status" -eq 2 ]
  run "$SCRIPT" "a/b" 22
  [ "$status" -eq 2 ]
}

@test "--method 非法值返回 2" {
  run "$SCRIPT" --method udp 127.0.0.1 22
  [ "$status" -eq 2 ]
}

@test "--timeout 非法值返回 2" {
  run "$SCRIPT" --timeout 0 127.0.0.1 22
  [ "$status" -eq 2 ]
  run "$SCRIPT" --timeout xyz 127.0.0.1 22
  [ "$status" -eq 2 ]
}

@test "help 正常退出 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--timeout"* ]]
  [[ "$output" == *"--method"* ]]
}
