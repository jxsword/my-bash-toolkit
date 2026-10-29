#!/usr/bin/env bash
# script-name: mkscript
# description: 新脚本脚手架生成器——按仓库规范生成脚本骨架与配套 bats 测试骨架
# usage: mkscript <名> <分类> [--system] [--force]
# option: --system    系统级脚本骨架（预留 -n, --dry-run 与 env 收窄）
# option: --force     目标文件已存在时允许覆盖
# option: -h, --help  显示帮助
# example: mkscript jsonq text
# example: mkscript backup-dir ops --system
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash, coreutils, sed
# category: dev

set -u -o pipefail

_MK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_MK_ROOT/scripts/lib/common.sh"

readonly -a _MK_CATEGORIES=(
  system security dev text files net ops install wsl
)

# 模板以逐行数组存放而非 heredoc：避免 gen-docs/check-metadata 把模板内容
# 当作真实函数定义解析（数组元素行首为引号，不命中函数定义正则）。
# 模板内 $ 均为字面量（生成物代码），SC2016 属预期，整组关闭。
# shellcheck disable=SC2016
readonly -a _TPL_SCRIPT_PLAIN=(
  '#!/usr/bin/env bash'
  '# script-name: __NAME__'
  '# description: TODO 一句话功能说明（make docs 依赖本行）'
  '# usage: __NAME__.sh <参数>'
  '# example: __NAME__.sh --help'
  '# env: __ENV__'
  '# deps: coreutils'
  '# category: __CAT__'
  ''
  'set -u -o pipefail'
  ''
  '# env: __ENV__'
  '# fn: 打印用法到 stderr'
  'usage() {'
  '  echo "用法: __NAME__.sh <参数>" >&2'
  '  echo "TODO: 补充参数与选项说明" >&2'
  '}'
  ''
  '# env: __ENV__'
  '# fn: 参数解析与入口分派（TODO 替换为实现）'
  'main() {'
  '  if (($# == 0)); then'
  '    usage'
  '    return 2'
  '  fi'
  '  echo "TODO: 实现 __NAME__ 的主要逻辑" >&2'
  '  return 1'
  '}'
  ''
  'if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then'
  '  main "$@"'
  'fi'
)

# shellcheck disable=SC2016
readonly -a _TPL_SCRIPT_SYSTEM=(
  '#!/usr/bin/env bash'
  '# script-name: __NAME__'
  '# description: TODO 一句话功能说明（系统级脚本；make docs 依赖本行）'
  '# usage: __NAME__.sh <参数> [--dry-run]'
  '# option: -n, --dry-run    仅打印将执行的动作，不修改系统'
  '# example: __NAME__.sh --dry-run'
  '# env: __ENV__'
  '# deps: coreutils'
  '# category: __CAT__'
  ''
  'set -u -o pipefail'
  ''
  '# env: __ENV__'
  '# fn: 打印用法到 stderr'
  'usage() {'
  '  echo "用法: __NAME__.sh <参数> [--dry-run]" >&2'
  '  echo "TODO: 补充参数与选项说明；系统级动作必须先 dry-run" >&2'
  '}'
  ''
  '# env: __ENV__'
  '# fn: 参数解析与入口分派（TODO 替换为实现；--dry-run 仅打印动作）'
  'main() {'
  '  local dry="false" arg'
  '  local -a args=()'
  '  for arg in "$@"; do'
  '    case "$arg" in'
  '      -n | --dry-run) dry="true" ;;'
  '      *) args+=("$arg") ;;'
  '    esac'
  '  done'
  '  if [[ "$dry" == "true" ]]; then'
  '    echo "[dry-run] 将执行: TODO（系统级动作，先打印不执行）"'
  '    return 0'
  '  fi'
  '  if ((${#args[@]} == 0)); then'
  '    usage'
  '    return 2'
  '  fi'
  '  echo "TODO: 实现 __NAME__ 的主要逻辑" >&2'
  '  return 1'
  '}'
  ''
  'if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then'
  '  main "$@"'
  'fi'
)

# shellcheck disable=SC2016
readonly -a _TPL_TEST=(
  '#!/usr/bin/env bats'
  '# script-name: __NAME__-test'
  '# description: __NAME__ 的单元测试（[sandbox-only]）'
  '# usage: （bats 测试，make test 触发）'
  '# env: __ENV__'
  '# deps: bats'
  '# category: __CAT__'
  ''
  'setup() {'
  "  load '../helpers/test_env'"
  '  # 可选组件条件加载：bats 的 setup 内 skip 不中断后续语句'
  '  if env_is_supported __ENV_IDS__; then'
  "    load '../../test/libs/bats-support/load'"
  "    load '../../test/libs/bats-assert/load'"
  '  fi'
  '  skip_unless_env __ENV_IDS__'
  '  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__CAT__/__NAME__.sh"'
  '}'
  ''
  '@test "无参数输出用法并返回非零" {'
  '  run "$SCRIPT"'
  '  [ "$status" -ne 0 ]'
  '  [[ "$output" == *"用法: __NAME__.sh"* ]]'
  '}'
  ''
  '@test "TODO: 补充主路径与错误分支用例" {'
  '  skip "骨架占位用例——实现脚本后替换"'
  '}'
)

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  echo "用法: mkscript <名> <分类> [--system] [--force]" >&2
  echo "  <名>     kebab-case 脚本名（不含 .sh）" >&2
  echo "  <分类>   ${_MK_CATEGORIES[*]}" >&2
  echo "  --system 系统级脚本骨架（预留 --dry-run）" >&2
  echo "  --force  目标文件已存在时允许覆盖" >&2
  echo "说明: 生成 scripts/<分类>/<名>.sh 与 test/<分类>/<名>.bats 骨架" >&2
  echo "      目标仓库根默认由脚本位置推导，可设 MKSCRIPT_ROOT 覆盖（测试用）" >&2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 目标仓库根：MKSCRIPT_ROOT 优先，否则由脚本位置推导
mkscript_root() {
  if [[ -n "${MKSCRIPT_ROOT:-}" ]]; then
    printf '%s\n' "$MKSCRIPT_ROOT"
    return 0
  fi
  printf '%s\n' "$_MK_ROOT"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 校验脚本名符合 kebab-case
validate_name() {
  local name="$1"
  local re='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
  if ! [[ "$name" =~ $re ]]; then
    log_err "脚本名 '$name' 不符合 kebab-case"
    log_err "      （小写字母开头，仅小写字母/数字/连字符）"
    return 1
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 校验分类在 10 域白名单内（lib 库文件骨架不适用，不在列）
validate_category() {
  local category="$1" c
  for c in "${_MK_CATEGORIES[@]}"; do
    [[ "$c" == "$category" ]] && return 0
  done
  log_err "分类 '$category' 非法，可选: ${_MK_CATEGORIES[*]}"
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 按系统级/普通模板生成脚本骨架并落盘（占位符经 sed 替换）
gen_script() {
  local file="$1" name="$2" category="$3" system="$4"
  local env_csv env_ids
  if [[ "$system" == "true" ]]; then
    env_csv="ubuntu-26.04, wsl-ubuntu-26.04"
    env_ids="ubuntu-26.04 wsl-ubuntu-26.04"
  else
    env_csv="ubuntu-26.04, wsl-ubuntu-26.04, git-bash"
    env_ids="ubuntu-26.04 wsl-ubuntu-26.04 git-bash"
  fi
  local -a tpl=()
  if [[ "$system" == "true" ]]; then
    tpl=("${_TPL_SCRIPT_SYSTEM[@]}")
  else
    tpl=("${_TPL_SCRIPT_PLAIN[@]}")
  fi
  printf '%s\n' "${tpl[@]}" | sed \
    -e "s|__NAME__|$name|g" \
    -e "s|__CAT__|$category|g" \
    -e "s|__ENV__|$env_csv|g" \
    -e "s|__ENV_IDS__|$env_ids|g" > "$file" \
    || {
      log_err "写入失败: $file"
      return 1
    }
  chmod 755 "$file"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 生成配套 bats 测试骨架并落盘（环境跳过与可选组件条件加载）
gen_test() {
  local file="$1" name="$2" category="$3" system="$4"
  local env_csv env_ids
  if [[ "$system" == "true" ]]; then
    env_csv="ubuntu-26.04, wsl-ubuntu-26.04"
    env_ids="ubuntu-26.04 wsl-ubuntu-26.04"
  else
    env_csv="ubuntu-26.04, wsl-ubuntu-26.04, git-bash"
    env_ids="ubuntu-26.04 wsl-ubuntu-26.04 git-bash"
  fi
  printf '%s\n' "${_TPL_TEST[@]}" | sed \
    -e "s|__NAME__|$name|g" \
    -e "s|__CAT__|$category|g" \
    -e "s|__ENV__|$env_csv|g" \
    -e "s|__ENV_IDS__|$env_ids|g" > "$file" \
    || {
      log_err "写入失败: $file"
      return 1
    }
  chmod 644 "$file"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 生成成功后打印后续 SOP 步骤提示
print_next_steps() {
  local name="$1" category="$2"
  log_info "后续 SOP 步骤（详见 docs/PROJECT_CONTEXT.md §7）:"
  log_info "  1. 编辑 scripts/$category/$name.sh 填入实现，补 deps/example"
  log_info "  2. 补全 test/$category/$name.bats 主路径与错误分支用例"
  log_info "  3. make test 全绿"
  log_info "  4. make docs 重新生成 docs/SCRIPTS.md"
  log_info "  5. pre-commit 通过后按 GitHub Flow 提交"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 参数解析、校验与骨架生成分派
main() {
  local name="" category="" system="false" force="false" arg
  local -a positional=()
  for arg in "$@"; do
    case "$arg" in
      --system) system="true" ;;
      --force) force="true" ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        usage
        return 2
        ;;
      *) positional+=("$arg") ;;
    esac
  done
  if ((${#positional[@]} != 2)); then
    usage
    return 2
  fi
  name="${positional[0]}"
  category="${positional[1]}"
  validate_name "$name" || return 1
  validate_category "$category" || return 1
  local root script_file test_file
  root="$(mkscript_root)"
  script_file="$root/scripts/$category/$name.sh"
  test_file="$root/test/$category/$name.bats"
  if [[ -e "$script_file" && "$force" != "true" ]]; then
    log_err "已存在: $script_file（--force 解除拒绝覆盖）"
    return 1
  fi
  if [[ -e "$test_file" && "$force" != "true" ]]; then
    log_err "已存在: $test_file（--force 解除拒绝覆盖）"
    return 1
  fi
  mkdir -p "$root/scripts/$category" "$root/test/$category" \
    || {
      log_err "目录创建失败: $root/{scripts,test}/$category"
      return 1
    }
  gen_script "$script_file" "$name" "$category" "$system" || return 1
  gen_test "$test_file" "$name" "$category" "$system" || return 1
  log_info "已生成: $script_file"
  log_info "已生成: $test_file"
  print_next_steps "$name" "$category"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
