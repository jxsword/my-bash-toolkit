#!/usr/bin/env bats
# script-name: http-probe-test
# description: http-probe 的真实回环 HTTP 探测测试（python3 临时服务，无外网依赖）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats, python3, curl
# category: net
# @test 块与 helper 函数对 PORT/SERVER_PID/DOCROOT/LIST 的写入属同一 bats 子
# shell，误报作用域：
# shellcheck disable=SC2030,SC2031

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/net/http-probe.sh"
  SERVER_PID=""
  PORT=""
  DOCROOT=""
  LIST=""
}

teardown() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2> /dev/null || true
    wait "$SERVER_PID" 2> /dev/null || true
  fi
  [[ -n "${DOCROOT:-}" ]] && rm -rf "$DOCROOT"
  [[ -n "${LIST:-}" ]] && rm -f "$LIST"
  return 0
}

# 取一个当前空闲的回环端口（bind 0 后释放）
free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

# 在 127.0.0.1 启动临时 HTTP 服务（docroot 含 index.html），等 curl 可达
start_server() {
  PORT="$(free_port)"
  DOCROOT="$(mktemp -d)"
  printf 'probe-ok\n' > "$DOCROOT/index.html"
  python3 -m http.server "$PORT" --bind 127.0.0.1 \
    --directory "$DOCROOT" > /dev/null 2>&1 &
  SERVER_PID=$!
  local i
  for ((i = 0; i < 50; i++)); do
    if curl -s --noproxy '*' -o /dev/null \
      "http://127.0.0.1:${PORT}/index.html"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# 在 127.0.0.1 启动慢响应服务（GET 后 sleep 3 秒才回包）
start_slow_server() {
  PORT="$(free_port)"
  python3 -c "
import http.server, time
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(3)
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args):
        pass
http.server.HTTPServer(('127.0.0.1', ${PORT}), H).serve_forever()
" > /dev/null 2>&1 &
  SERVER_PID=$!
  local i
  for ((i = 0; i < 50; i++)); do
    if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${PORT}" \
      2> /dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

@test "单 URL 200: 表格含状态码与耗时列 汇总正常 退出0" {
  start_server
  run "$SCRIPT" "http://127.0.0.1:${PORT}/index.html"
  [ "$status" -eq 0 ]
  [[ "$output" == *'状态'* ]]
  [[ "$output" == *'耗时(s)'* ]]
  [[ "$output" == *"200"*"http://127.0.0.1:${PORT}/index.html"* ]]
  [[ "$output" == *'汇总: 共 1 个 URL, 正常 1, 异常 0'* ]]
}

@test "404 路径: 状态码 404 计入异常 退出1" {
  start_server
  run "$SCRIPT" "http://127.0.0.1:${PORT}/no-such-path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"404"*"http://127.0.0.1:${PORT}/no-such-path"* ]]
  [[ "$output" == *'汇总: 共 1 个 URL, 正常 0, 异常 1'* ]]
}

@test "连接拒绝: ERR 行与 curl 错误信息 退出1" {
  PORT="$(free_port)"
  run "$SCRIPT" "http://127.0.0.1:${PORT}/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR(7)"* ]]
  [[ "$output" == *'curl: (7)'* ]]
  [[ "$output" == *'异常 1'* ]]
}

@test "多 URL 混合: 200 与 404 并存时统计正确" {
  start_server
  run "$SCRIPT" "http://127.0.0.1:${PORT}/index.html" \
    "http://127.0.0.1:${PORT}/no-such-path"
  [ "$status" -eq 1 ]
  [[ "$output" == *'汇总: 共 2 个 URL, 正常 1, 异常 1'* ]]
}

@test "--fail-only: 隐藏正常行 保留异常行与汇总" {
  start_server
  run "$SCRIPT" --fail-only "http://127.0.0.1:${PORT}/index.html" \
    "http://127.0.0.1:${PORT}/no-such-path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"404"* ]]
  [[ "$output" == *'汇总: 共 2 个 URL, 正常 1, 异常 1'* ]]
  [[ "$output" != *"index.html"* ]]
}

@test "-f 文件列表: 空行与 # 注释忽略 可与位置参数混用" {
  start_server
  LIST="$(mktemp)"
  {
    echo '# 注释行'
    echo ''
    echo "http://127.0.0.1:${PORT}/index.html"
    echo "  http://127.0.0.1:${PORT}/no-such-path  "
  } > "$LIST"
  run "$SCRIPT" -f "$LIST" "http://127.0.0.1:${PORT}/index.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *'汇总: 共 3 个 URL, 正常 2, 异常 1'* ]]
}

@test "--concurrency 2: 多 URL 受控并发全部完成" {
  start_server
  run "$SCRIPT" --concurrency 2 "http://127.0.0.1:${PORT}/index.html" \
    "http://127.0.0.1:${PORT}/index.html" \
    "http://127.0.0.1:${PORT}/index.html"
  [ "$status" -eq 0 ]
  [[ "$output" == *'汇总: 共 3 个 URL, 正常 3, 异常 0'* ]]
}

@test "--timeout 1 对慢响应(3s)服务: ERR(28) 超时异常" {
  start_slow_server
  run "$SCRIPT" --timeout 1 "http://127.0.0.1:${PORT}/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR(28)"* ]]
}

@test "回环目标不受代理环境变量影响（连接拒绝如实上报）" {
  PORT="$(free_port)"
  HTTP_PROXY=http://127.0.0.1:1 HTTPS_PROXY=http://127.0.0.1:1 \
    http_proxy=http://127.0.0.1:1 https_proxy=http://127.0.0.1:1 \
    NO_PROXY='' no_proxy='' \
    run "$SCRIPT" "http://127.0.0.1:${PORT}/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR(7)"* ]]
}

@test "--concurrency 非法值返回 2" {
  start_server
  run "$SCRIPT" --concurrency 0 "http://127.0.0.1:${PORT}/"
  [ "$status" -eq 2 ]
  [[ "$output" == *'--concurrency'* ]]
  run "$SCRIPT" --concurrency abc "http://127.0.0.1:${PORT}/"
  [ "$status" -eq 2 ]
}

@test "--timeout 非法值返回 2" {
  run "$SCRIPT" --timeout 0 "http://127.0.0.1:1/"
  [ "$status" -eq 2 ]
  [[ "$output" == *'--timeout'* ]]
}

@test "无 URL 返回 2 并输出用法" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'用法: http-probe.sh'* ]]
}

@test "-f 文件不存在返回 2" {
  run "$SCRIPT" -f /nonexistent/urls.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *'无法读取 URL 列表文件'* ]]
}

@test "未知选项与缺参数值返回 2" {
  run "$SCRIPT" --bogus "http://127.0.0.1:1/"
  [ "$status" -eq 2 ]
  [[ "$output" == *'未知选项'* ]]
  run "$SCRIPT" --concurrency
  [ "$status" -eq 2 ]
  run "$SCRIPT" --file
  [ "$status" -eq 2 ]
}

@test "help 正常退出 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'--concurrency'* ]]
  [[ "$output" == *'--timeout'* ]]
  [[ "$output" == *'--fail-only'* ]]
}
