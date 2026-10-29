#!/usr/bin/env bash
# script-name: port-check
# description: 端口检查——本机占用（ss -ltnp 含进程）+ 远端连通（nc 优先，退化 /dev/tcp）
# usage: port-check.sh [--timeout <秒>] [--method <auto|nc|tcp>] <host> <port>
# option: -t, --timeout <秒>    连接超时秒数（默认 3）
# option: -m, --method <方式>   探测方式: auto(默认)/nc/tcp（nc 缺失退化 tcp）
# option: -h, --help            显示帮助
# example: port-check.sh 127.0.0.1 22
# example: port-check.sh --timeout 5 --method tcp 127.0.0.1 8080
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: ss, coreutils, nc(可选)
# category: net

set -u -o pipefail

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stderr
usage() {
  cat << 'EOF'
用法: port-check.sh [--timeout <秒>] [--method <auto|nc|tcp>] <host> <port>
检查端口两件事:
  1. 本机占用: ss -ltnp 匹配 LISTEN 套接字（含进程名与 pid，仅限当前用户可见）
  2. 远端连通: 优先 nc -z，无 nc 时退化 timeout + bash /dev/tcp

输出为结构化结论行（目标/本机占用/连通性/结论）。
退出码: 0=端口开放（本机占用或连通任一成立） 1=不可达 2=用法错误

选项:
  -t, --timeout <秒>    连接超时秒数（默认 3）
  -m, --method <方式>   探测方式: auto（默认）/ nc / tcp
  -h, --help            显示本帮助
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 端口合法性（1-65535 纯数字）
is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  ((port >= 1 && port <= 65535))
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 主机合法性（主机名/IPv4/IPv6 字面量的保守白名单）
is_valid_host() {
  local host="$1"
  [[ "$host" =~ ^[A-Za-z0-9._:-]+$ ]]
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 判断 ss 本地地址列是否覆盖目标 host（含通配与 localhost 别名）
addr_covers_host() {
  local host="$1" addr="$2"
  if [[ "$host" == "localhost" ]]; then
    case "$addr" in
      "127.0.0.1" | "::1" | "[::1]" | "*" | "0.0.0.0" | "::" | "[::]")
        return 0
        ;;
    esac
  fi
  case "$addr" in
    "$host" | "*" | "0.0.0.0" | "::" | "[::]") return 0 ;;
  esac
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 用 ss -ltnp 找本机 LISTEN 套接字；命中打印明细行，退出码 0=占用 1=未占用 2=ss 不可用
find_listen_matches() {
  local host="$1" port="$2" ss_out
  local laddr rest addr detail
  local re='users:\(\("([^"]+)".*pid=([0-9]+)'
  if ! ss_out="$(ss -H -ltnp 2> /dev/null)"; then
    if ! ss_out="$(ss -H -ltn 2> /dev/null)"; then
      return 2
    fi
  fi
  local found="false"
  # ss 列: State Recv-Q Send-Q Local Peer [Process]，前三列丢弃
  while read -r _ _ _ laddr rest; do
    [[ -n "$laddr" ]] || continue
    [[ "${laddr##*:}" == "$port" ]] || continue
    addr="${laddr%:*}"
    addr_covers_host "$host" "$addr" || continue
    found="true"
    detail="LISTEN ${laddr}"
    if [[ "$rest" =~ $re ]]; then
      detail="${detail}, 进程 ${BASH_REMATCH[1]} (pid=${BASH_REMATCH[2]})"
    fi
    echo "$detail"
  done <<< "$ss_out"
  [[ "$found" == "true" ]]
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 连通探测（nc 优先，退化 timeout + bash /dev/tcp）；stdout 报告方式，退出码即结论
check_connectivity() {
  local host="$1" port="$2" timeout="$3" method="$4"
  if [[ "$method" == "nc" ]] && ! command -v nc > /dev/null 2>&1; then
    echo "警告: --method nc 但 nc 不可用，退化 /dev/tcp" >&2
  fi
  if [[ "$method" != "tcp" ]] && command -v nc > /dev/null 2>&1; then
    if nc -z -w "$timeout" "$host" "$port" > /dev/null 2>&1; then
      echo "通 (nc)"
      return 0
    fi
    return 1
  fi
  # $1/$2 由子 bash 展开，单引号有意为之
  # shellcheck disable=SC2016
  if timeout "$timeout" bash -c 'exec 3<>/dev/tcp/$1/$2' \
    _ "$host" "$port" 2> /dev/null; then
    echo "通 (tcp)"
    return 0
  fi
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——参数解析、两项检查与结构化结论输出
main() {
  local timeout=3 method="auto"
  local -a args=()
  while (($#)); do
    case "$1" in
      -t | --timeout)
        if (($# < 2)); then
          echo "错误: $1 缺少参数值" >&2
          return 2
        fi
        timeout="$2"
        shift 2
        ;;
      -m | --method)
        if (($# < 2)); then
          echo "错误: $1 缺少参数值" >&2
          return 2
        fi
        method="$2"
        shift 2
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        echo "错误: 未知选项: $1" >&2
        usage >&2
        return 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  if [[ "$method" != "auto" && "$method" != "nc" && "$method" != "tcp" ]]; then
    echo "错误: --method 仅支持 auto|nc|tcp: $method" >&2
    return 2
  fi
  if [[ ! "$timeout" =~ ^[0-9]+$ ]] || ((timeout < 1)); then
    echo "错误: --timeout 须为正整数秒: $timeout" >&2
    return 2
  fi
  if ((${#args[@]} != 2)); then
    usage >&2
    return 2
  fi
  local host="${args[0]}" port="${args[1]}"
  if ! is_valid_host "$host"; then
    echo "错误: 主机名含非法字符: $host" >&2
    return 2
  fi
  if ! is_valid_port "$port"; then
    echo "错误: 端口须为 1-65535 的整数: $port" >&2
    return 2
  fi

  echo "目标: ${host}:${port}"

  local occ_out occ_rc occupied
  occ_out="$(find_listen_matches "$host" "$port")"
  occ_rc=$?
  case "$occ_rc" in
    0)
      occupied="是"
      echo "本机占用: 是 (${occ_out//$'\n'/; })"
      ;;
    1)
      occupied="否"
      echo "本机占用: 否"
      ;;
    *)
      occupied="未知"
      echo "本机占用: 未知 (ss 不可用)" >&2
      ;;
  esac

  local conn_out reachable="否"
  if conn_out="$(check_connectivity "$host" "$port" "$timeout" "$method")"; then
    reachable="是"
  fi
  echo "连通性: ${conn_out:-不通}"

  if [[ "$occupied" == "是" || "$reachable" == "是" ]]; then
    echo "结论: 端口开放"
    return 0
  fi
  echo "结论: 端口不可达"
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
