#!/usr/bin/env bash
# script-name: bootstrap-dev
# description: 幂等新机引导——按 min/dev 工具清单逐项检测，默认 dry-run 打印 apt 安装计划
# usage: bootstrap-dev.sh --profile <min|dev> [--apply] [--sudo] [--update] [-h]
# option: --profile <min|dev>  工具清单档位（必需）: min=git/curl; dev=min+其余
# option: --apply              执行安装（缺省 dry-run 仅打印计划）
# option: --sudo               以 sudo -n 前缀调用 apt-get（见提权说明）
# option: --update             安装前先执行 apt-get update
# option: -n, --dry-run        仅打印计划，不执行（与缺省一致）
# option: -h, --help           显示帮助
# example: bootstrap-dev.sh --profile dev
# example: bootstrap-dev.sh --profile dev --update --apply --sudo
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: apt, coreutils
# category: install

set -u -o pipefail

_BD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_BD_ROOT/scripts/lib/common.sh"

# 工具条目格式: 工具名|检测命令|apt 包名（检测命令用 command -v，可与包名不同）
readonly -a _BD_PROFILE_MIN=(
  "git|git|git"
  "curl|curl|curl"
)
readonly -a _BD_PROFILE_DEV=(
  "${_BD_PROFILE_MIN[@]}"
  "make|make|make"
  "bats|bats|bats"
  "shfmt|shfmt|shfmt"
  "shellcheck|shellcheck|shellcheck"
  "pip3|pip3|python3-pip"
)

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stdout（含档位清单、退出码与 zcode-run 提权约定）
usage() {
  cat << 'EOF'
用法: bootstrap-dev.sh --profile <min|dev> [选项]
幂等新机引导: 按档位清单逐项检测（command -v），缺什么列什么；
默认 dry-run 仅打印 apt 安装计划，加 --apply 才安装，全部已装时为无操作。

档位:
  min   git, curl
  dev   min + make, bats, shfmt, shellcheck, pip3（apt 包 python3-pip）

选项:
  --profile <min|dev>  工具清单档位（必需）
  --apply              执行安装（缺省 dry-run）
  --sudo               以 sudo -n 前缀调用 apt-get（见下方提权说明）
  --update             安装前先执行 apt-get update
  -n, --dry-run        仅打印计划，不执行（与缺省一致）
  -h, --help           显示本帮助

退出码: 0=成功（含 dry-run 与无需安装） 1=安装/复检失败 2=用法错误
安装动作: apt-get install -y <缺失包>（非交互，始终带 -y）

提权说明（本脚本不内置 sudo，两种方式二选一）:
  A) zcode-run 包裹并以 sudo -n 运行本脚本:
     wsl -d ubuntu2604 -u ssy -- /usr/local/bin/zcode-run \
       sudo -n /path/to/bootstrap-dev.sh --apply --profile dev
  B) 加 --sudo 由脚本以 sudo -n 前缀调用 apt-get
     （免密 sudo 的开关生命周期由 zcode-run 管理）:
     wsl -d ubuntu2604 -u ssy -- /usr/local/bin/zcode-run \
       /path/to/bootstrap-dev.sh --apply --profile dev --sudo
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 按档位输出工具条目（每行一条「工具|检测命令|apt 包」）
profile_entries() {
  case "$1" in
    min) printf '%s\n' "${_BD_PROFILE_MIN[@]}" ;;
    dev) printf '%s\n' "${_BD_PROFILE_DEV[@]}" ;;
    *)
      log_err "未知档位: $1"
      return 2
      ;;
  esac
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 工具存在性检测（command -v，供 PATH 桩测试驱动）
tool_present() {
  command -v -- "$1" > /dev/null 2>&1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 执行 apt-get（$1=sudo 模式 true|false，其余为 apt-get 参数）
run_apt() {
  local sudo_mode="$1"
  shift
  if [[ "$sudo_mode" == "true" ]]; then
    sudo -n apt-get "$@"
  else
    apt-get "$@"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 生成安装命令展示串（含可选 sudo -n 前缀与 -y）
plan_install_cmd() {
  local sudo_mode="$1"
  shift
  local cmd=""
  if [[ "$sudo_mode" == "true" ]]; then
    cmd="sudo -n "
  fi
  cmd+="apt-get install -y $*"
  printf '%s\n' "$cmd"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 按档位逐条分类输出——已装「p<TAB>工具」，缺失「m<TAB>工具<TAB>包」
classify_entries() {
  local profile="$1" entry tool probe pkg
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    IFS='|' read -r tool probe pkg <<< "$entry"
    if tool_present "$probe"; then
      printf 'p\t%s\n' "$tool"
    else
      printf 'm\t%s\t%s\n' "$tool" "$pkg"
    fi
  done < <(profile_entries "$profile")
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 扫描档位并填充输出数组（$2=已装 $3=缺工具 $4=缺包；nameref 内部名须异于目标名）
scan_profile() {
  local profile="$1"
  local -n out_present="$2"
  local -n out_miss_tool="$3"
  local -n out_miss_pkg="$4"
  local kind tool pkg
  while IFS=$'\t' read -r kind tool pkg; do
    case "$kind" in
      p) out_present+=("$tool") ;;
      m)
        out_miss_tool+=("$tool")
        out_miss_pkg+=("$pkg")
        ;;
    esac
  done < <(classify_entries "$profile")
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印 dry-run 安装计划（缺失明细 + 将执行命令 + 提权提示）
print_plan() {
  local profile="$1" sudo_mode="$2" update="$3"
  local -a present=() miss_tool=() miss_pkg=()
  scan_profile "$profile" present miss_tool miss_pkg
  local total i
  total=$((${#present[@]} + ${#miss_tool[@]}))
  echo "[dry-run] bootstrap-dev 安装计划"
  echo "[dry-run]   profile: $profile（共 $total 个工具）"
  echo "[dry-run]   已安装 ${#present[@]} 个: ${present[*]:-（无）}"
  if ((${#miss_tool[@]} == 0)); then
    echo "[dry-run]   全部已安装，无需安装"
    return 0
  fi
  echo "[dry-run]   缺失 ${#miss_tool[@]} 个:"
  for ((i = 0; i < ${#miss_tool[@]}; i++)); do
    echo "[dry-run]     - ${miss_tool[$i]} -> apt 包: ${miss_pkg[$i]}"
  done
  if [[ "$update" == "true" ]]; then
    echo "[dry-run]   将执行: apt-get update"
  fi
  echo "[dry-run]   将执行: $(plan_install_cmd "$sudo_mode" "${miss_pkg[@]}")"
  echo "[dry-run]   提权: 脚本不内置 sudo; --sudo 时以 sudo -n 前缀执行"
  echo "确认无误后加 --apply 执行"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 执行安装（update 可选、install -y、复检缺失），失败返回 1
do_apply() {
  local profile="$1" sudo_mode="$2" update="$3"
  local -a present=() miss_tool=() miss_pkg=()
  scan_profile "$profile" present miss_tool miss_pkg

  if ((${#miss_tool[@]} == 0)) && [[ "$update" == "false" ]]; then
    log_info "全部工具已安装，无需安装（幂等无操作）"
    return 0
  fi
  if ! command -v apt-get > /dev/null 2>&1; then
    log_err "apt-get 不可用: 本脚本仅支持 apt 系（Debian/Ubuntu）"
    return 1
  fi
  if [[ "$sudo_mode" == "false" && "$EUID" -ne 0 ]]; then
    log_warn "当前非 root 且未加 --sudo: apt-get 可能因权限不足失败"
    log_warn "提权方式见 --help（zcode-run + sudo -n 约定）"
  fi
  if [[ "$update" == "true" ]]; then
    log_info "执行: ${sudo_mode:+sudo -n }apt-get update"
    if ! run_apt "$sudo_mode" update; then
      log_err "apt-get update 失败"
      return 1
    fi
  fi
  if ((${#miss_tool[@]} == 0)); then
    log_info "全部工具已安装，无需安装（已完成 apt-get update）"
    return 0
  fi
  log_info "执行: $(plan_install_cmd "$sudo_mode" "${miss_pkg[@]}")"
  if ! run_apt "$sudo_mode" install -y "${miss_pkg[@]}"; then
    log_err "apt-get install 失败（退出码非零），请检查上方输出"
    return 1
  fi
  local still=0 t
  for t in "${miss_tool[@]}"; do
    if ! tool_present "$t"; then
      log_warn "复检仍缺失: $t"
      still=$((still + 1))
    fi
  done
  if ((still > 0)); then
    log_err "安装命令已成功但复检仍有 $still 个工具不可用（检查包名映射或 PATH）"
    return 1
  fi
  log_info "复检通过: ${miss_tool[*]} 已就绪"
  return 0
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——参数解析、档位校验与 dry-run/apply 分派
main() {
  local profile="" apply="false" sudo_mode="false" update="false"
  while (($# > 0)); do
    case "$1" in
      --profile)
        if (($# < 2)); then
          log_err "选项 --profile 需要参数（min|dev）"
          return 2
        fi
        profile="$2"
        shift 2
        ;;
      --apply)
        apply="true"
        shift
        ;;
      --sudo)
        sudo_mode="true"
        shift
        ;;
      --update)
        update="true"
        shift
        ;;
      -n | --dry-run)
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        log_err "未知选项或多余参数: $1"
        usage >&2
        return 2
        ;;
    esac
  done
  if [[ "$profile" != "min" && "$profile" != "dev" ]]; then
    log_err "--profile 必须为 min 或 dev"
    usage >&2
    return 2
  fi
  if [[ "$apply" == "true" ]]; then
    do_apply "$profile" "$sudo_mode" "$update"
  else
    print_plan "$profile" "$sudo_mode" "$update"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
