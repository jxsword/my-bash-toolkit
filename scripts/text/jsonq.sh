#!/usr/bin/env bash
# script-name: jsonq
# description: 无 jq 依赖的轻量 JSON 查询——点路径取值/类型判断/存在性检测（python3 兜底）
# usage: jsonq.sh [-t|-e] <file|-> <点路径>
# option: -t    输出目标值的 JSON 类型（object/array/string/number/boolean/null）
# option: -e    仅检测路径是否存在：存在返回 0，不存在返回 1，无输出
# option: -h, --help  显示帮助
# example: jsonq.sh data.json user.name
# example: jsonq.sh data.json items.0.id
# example: cat data.json | jsonq.sh - items.2.tags
# example: jsonq.sh -t data.json user.age
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash, coreutils, python3
# category: text

set -u -o pipefail

_JSONQ_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_JSONQ_ROOT/scripts/lib/common.sh"

# python3 兜底解析器。路径表达式语法：
#   点分隔段；数值段为数组下标（仅非负整数）；前导 $ 可省略（$ 与 $.x 合法）。
# 退出码：0 找到；1 路径不存在；2 路径表达式非法；3 非法 JSON。
# 输出：get 模式打印值的 JSON 字面量（字符串带引号）；type 模式打印类型名。
# shellcheck disable=SC2016
readonly _JSONQ_PY='
import json
import sys


def type_name(v):
    if isinstance(v, bool):
        return "boolean"
    if v is None:
        return "null"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    return "object"


def parse_expr(expr):
    if expr == "$":
        return []
    if expr.startswith("$"):
        expr = expr[1:]
        if expr.startswith("."):
            expr = expr[1:]
    if expr == "":
        return []
    segs = expr.split(".")
    if "" in segs:
        return None
    return segs


MISSING = object()


def walk(data, segs):
    cur = data
    for s in segs:
        if isinstance(cur, dict):
            if s not in cur:
                return MISSING
            cur = cur[s]
        elif isinstance(cur, list):
            if s.isdigit() and int(s) < len(cur):
                cur = cur[int(s)]
            else:
                return MISSING
        else:
            return MISSING
    return cur


def main():
    if len(sys.argv) != 3:
        print("jsonq: 内部参数错误", file=sys.stderr)
        return 2
    expr, mode = sys.argv[1], sys.argv[2]
    try:
        data = json.load(sys.stdin)
    except ValueError as exc:
        print("jsonq: 非法 JSON: %s" % exc, file=sys.stderr)
        return 3
    segs = parse_expr(expr)
    if segs is None:
        print("jsonq: 非法路径表达式: %s" % expr, file=sys.stderr)
        return 2
    cur = walk(data, segs)
    if cur is MISSING:
        return 1
    if mode == "exists":
        return 0
    if mode == "type":
        print(type_name(cur))
        return 0
    print(json.dumps(cur, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
'

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  echo "用法: jsonq.sh [-t|-e] <file|-> <点路径>" >&2
  echo "  <file|->  JSON 文件路径，或 - 表示从 stdin 读取" >&2
  echo "  <点路径>  点分隔路径，数值段为数组下标，如 user.name / items.0.id" >&2
  echo "  -t        输出目标值的 JSON 类型" >&2
  echo "  -e        仅检测路径是否存在（存在 0 / 不存在 1，无输出）" >&2
  echo "退出码: 0 成功；1 路径不存在；2 用法/路径表达式错误；3 输入错误（文件不可读、非法 JSON、python3 缺失或不可用）" >&2
  echo "说明: 值以 JSON 字面量输出（字符串带引号）；依赖 python3 兜底解析，无 jq 依赖" >&2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: python 解释器健康探针——command -v 命中不代表可执行
#   （git bash 下 Windows Store 存根退出 9009，MSYS 折算 49）
_jsonq_check_python() {
  local py="$1" probe_rc
  # </dev/null：探针不吃调用方 stdin；ARG_CONV_EXCL：防 MSYS 改写
  MSYS2_ARG_CONV_EXCL='*' \
    "$py" -c 'import json' > /dev/null 2>&1 < /dev/null
  probe_rc=$?
  if ((probe_rc == 0)); then
    return 0
  fi
  log_err "python3 探测失败（退出码 $probe_rc）：存在但不可用"
  log_err "      git bash 常见根因：python3 是 Windows Store 存根"
  log_err "      （真实退出 9009，MSYS 折算 49）或 MSYS 参数改写"
  log_err "      对策：装真 python3，或 JSONQ_PYTHON 指定解释器"
  return 3
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 调用 python3 兜底解析器执行查询，透传其退出码与错误
run_query() {
  local expr="$1" mode="$2" src="$3"
  local py="${JSONQ_PYTHON:-python3}"
  if ! command -v "$py" > /dev/null 2>&1; then
    log_err "python3 未找到——jsonq 依赖 python3 兜底解析 JSON"
    log_err "      请先安装 python3（或用 JSONQ_PYTHON 指定解释器路径）"
    return 3
  fi
  _jsonq_check_python "$py" || return 3
  local out rc
  # MSYS2_ARG_CONV_EXCL='*'：git bash 下禁用 MSYS 对 -c 内联代码与
  # 路径表达式参数的 POSIX 路径改写；非 MSYS 环境该变量无副作用。
  if [[ "$src" == "-" ]]; then
    out="$(MSYS2_ARG_CONV_EXCL='*' "$py" -c "$_JSONQ_PY" \
      "$expr" "$mode")"
  else
    out="$(MSYS2_ARG_CONV_EXCL='*' "$py" -c "$_JSONQ_PY" \
      "$expr" "$mode" < "$src")"
  fi
  rc=$?
  if ((rc != 0)); then
    return "$rc"
  fi
  if [[ "$mode" == "exists" ]]; then
    return 0
  fi
  printf '%s\n' "$out"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 参数解析与入口分派
main() {
  local mode="get" arg
  local -a operands=()
  for arg in "$@"; do
    case "$arg" in
      -t)
        if [[ "$mode" != "get" ]]; then
          usage
          return 2
        fi
        mode="type"
        ;;
      -e)
        if [[ "$mode" != "get" ]]; then
          usage
          return 2
        fi
        mode="exists"
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -)
        operands+=("$arg")
        ;;
      -*)
        usage
        return 2
        ;;
      *)
        operands+=("$arg")
        ;;
    esac
  done
  if ((${#operands[@]} != 2)); then
    usage
    return 2
  fi
  local src="${operands[0]}" expr="${operands[1]}"
  if [[ "$src" != "-" && ! -r "$src" ]]; then
    log_err "文件不可读: $src"
    return 3
  fi
  run_query "$expr" "$mode" "$src"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
