#!/usr/bin/env bash
# script-name: set-proxy
# description: 设置/清除当前 shell 代理环境变量（设计为 source 生效；直接执行仅打印对应语句供 eval）
# usage: set-proxy.sh <on|local|off> [host:port]
# option: （子命令）on     使用 WSL 宿主网关代理（默认 172.19.240.1:10808）
# option: （子命令）local  使用本机回环代理（默认 127.0.0.1:10808）
# option: （子命令）off    清除 http_proxy/https_proxy/all_proxy
# option: （可选参数）host:port    覆盖对应子命令的默认地址
# example: source scripts/net/set-proxy.sh on
# example: eval "$(scripts/net/set-proxy.sh local)"
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bash
# category: net

_PROXY_ADDR_ON='172.19.240.1:10808'
_PROXY_ADDR_LOCAL='127.0.0.1:10808'

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 应用代理动作；sourced=true 直接改当前 shell，否则打印语句
apply_proxy() {
  local addr="$1" mode="$2" sourced="$3"
  if [[ "$mode" == "off" ]]; then
    if [[ "$sourced" == "true" ]]; then
      unset http_proxy https_proxy all_proxy
      echo "已清除代理环境变量" >&2
    else
      printf 'unset http_proxy https_proxy all_proxy\n'
    fi
    return 0
  fi
  if [[ "$sourced" == "true" ]]; then
    export http_proxy="$addr"
    export https_proxy="$addr"
    export all_proxy="socks5://$addr"
    echo "代理已设置: $addr" >&2
  else
    printf "export http_proxy='%s'\n" "$addr"
    printf "export https_proxy='%s'\n" "$addr"
    printf "export all_proxy='socks5://%s'\n" "$addr"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——参数解析、地址校验与 source/执行分派；不污染调用方 shell 选项
main() {
  local u_was="off" pf_was="off" sourced="false" mode addr rc
  [[ $- == *u* ]] && u_was="on"
  if [[ -o pipefail ]]; then pf_was="on"; fi
  set -u -o pipefail
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    sourced="true"
  fi
  mode="${1:-}"
  addr=""
  rc=0
  case "$mode" in
    on) addr="${2:-$_PROXY_ADDR_ON}" ;;
    local) addr="${2:-$_PROXY_ADDR_LOCAL}" ;;
    off) ;;
    *)
      echo "用法: set-proxy.sh <on|local|off> [host:port]" >&2
      echo "  设计为 source 生效；直接执行打印语句（供 eval）" >&2
      rc=2
      ;;
  esac
  if [[ "$rc" -eq 0 && -n "$addr" ]] \
    && ! [[ "$addr" =~ ^[A-Za-z0-9._-]+(:[0-9]+)?$ ]]; then
    echo "错误: 代理地址 '$addr' 格式非法（期望 host:port）" >&2
    rc=1
  fi
  if [[ "$rc" -eq 0 ]]; then
    apply_proxy "$addr" "$mode" "$sourced" || rc=$?
  fi
  if [[ "$sourced" == "true" ]]; then
    [[ "$u_was" == "off" ]] && set +u
    [[ "$pf_was" == "off" ]] && set +o pipefail
  fi
  return "$rc"
}

main "$@"
