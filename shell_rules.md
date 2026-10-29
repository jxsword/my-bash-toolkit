# shell_rules.md —— 本仓库 shell 编码规范

依据：Google Shell Style Guide（https://google.github.io/styleguide/shellguide.html ，核实 2026-10-30）。
每条规则六字段：**说明 / 依据 / 工具归属 / 检测编号 / bad→good 微例 / rules_check_test 用例**。
工具归属取值：`shfmt`（格式化，参数 -i 2 -ci -bn -sr）、`shellcheck`（severity=warning，配置见 .shellcheckrc）、`hook`（本地 hook：line-length.sh、check-metadata.sh）、`manual`（评审人工）。
bash 版本区间与环境标注规格见 docs/bash_env_and_doc_spec.md。

通用约定：文件名 kebab-case；扩展名统一 `.sh`（对 Google 风格「可执行脚本不带扩展名」的显式偏离，理由：三环境文件识别与 gen-docs 扫描的确定性）；二级目录按需（DR-005）。

## R01 shebang
- 说明: 可执行脚本首行 `#!/usr/bin/env bash`；库文件（lib/*.sh）同样建议，便于工具识别
- 依据: styleguide「File Header」
- 工具: shellcheck + hook
- 检测: SC2148
- 微例: 直接写函数体 → 首行加 `#!/usr/bin/env bash`
- 用例: bad/bad-shebang-missing.sh

## R02 缩进
- 说明: 2 空格缩进，禁用 tab；switch-case 缩进（-ci）；二元运算符行首（-bn）；重定向符号后空格（-sr）
- 依据: styleguide「Indentation」
- 工具: shfmt
- 检测: shfmt -d 非空
- 微例: 4 空格或 tab 缩进 → 2 空格
- 用例: bad/bad-indent.sh

## R03 行宽
- 说明: 每行 ≤80 列；确需超长（如 URL）行尾加 `# noqa:line-length` 豁免
- 依据: styleguide「Line Length」
- 工具: hook (line-length.sh)
- 检测: hooks/line-length.sh
- 微例: 120 列长命令 → 用 `\` 续行拆分
- 用例: bad/bad-long-line.sh

## R04 引号
- 说明: 变量展开与命令替换一律双引号 `"$var"` `"$(cmd)"`；无需展开的字符串用单引号
- 依据: styleguide「Quoting」
- 工具: shellcheck
- 检测: SC2086 等
- 微例: `rm $file` → `rm "$file"`
- 用例: bad/bad-unquoted-var.sh

## R05 命令替换
- 说明: 用 `$(cmd)`，不用反引号
- 依据: styleguide「Command Substitution」
- 工具: shellcheck
- 检测: SC2006
- 微例: ``d=`pwd` `` → `d="$(pwd)"`
- 用例: bad/bad-backticks.sh

## R06 read
- 说明: read 必须带 `-r`，保留反斜杠字面义
- 依据: styleguide + ShellCheck
- 工具: shellcheck
- 检测: SC2162
- 微例: `read line` → `read -r line`
- 用例: bad/bad-read-nor.sh

## R07 条件表达式
- 说明: bash 下条件用 `[[ ]]`；`[` 仅用于 POSIX 兼容场景
- 依据: styleguide「Test」
- 工具: manual（对应 SC2292 为 style 级，默认 severity=warning 下不触发，靠评审）
- 检测: SC2292（未启用）
- 微例: `[ "$a" == b* ]` → `[[ "$a" == b* ]]`
- 用例: 无（manual）

## R08 命名
- 说明: 函数 lower_snake_case；常量 UPPER_CASE 且 readonly；私有函数 `_` 前缀；脚本文件 kebab-case
- 依据: styleguide「Naming Conventions」
- 工具: manual
- 检测: 人工评审
- 微例: `Getdata()` → `get_data()`
- 用例: 无（manual）

## R09 头部元数据 tag
- 说明: 每个脚本头部含必需 tag：script-name / description / usage / env / category（可选 option/example/deps），语法见 spec §4
- 依据: 本项目 DR-007
- 工具: hook (check-metadata.sh)
- 检测: hooks/check-metadata.sh
- 微例: 只有 shebang → 补齐 5 个必需 tag
- 用例: bad/bad-missing-header.sh

## R10 函数级环境标注
- 说明: 每个函数定义前必须有紧邻 `# env: <id,...>`（可选 `# fn: 说明`）；不支持的环境不写
- 依据: 本项目 DR-006/DR-007
- 工具: hook (check-metadata.sh)
- 检测: hooks/check-metadata.sh
- 微例: 裸函数定义 → 上方补 `# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash`
- 用例: bad/bad-missing-env-annotation.sh

## R11 变量作用域
- 说明: 函数内变量一律 `local`；模块级常量 `readonly`；避免隐式全局
- 依据: styleguide「Variables」
- 工具: manual
- 检测: 人工评审
- 微例: 函数内 `tmp=$(mktemp -d)` → `local tmp`
- 用例: 无（manual）

## R12 错误处理
- 说明: 基线 `set -u -o pipefail`；`set -e` 按脚本性质谨慎启用；关键命令显式检查退出码并给可行动错误信息
- 依据: styleguide「Error Handling」
- 工具: manual
- 检测: 人工评审
- 微例: `cmd || exit 1`（无信息）→ `cmd || { echo "错误: …" >&2; exit 1; }`
- 用例: 无（manual）

## R13 输出与 dry-run
- 说明: 错误与日志输出到 stderr；系统级脚本（写 /etc、systemctl、usermod 等）必须支持 `--dry-run`
- 依据: 本项目 DR-006 + 运维安全要求
- 工具: manual
- 检测: 人工评审（usage tag 应体现 --dry-run）
- 微例: 直接写 /etc/sudoers → 先 `--dry-run` 打印将执行动作
- 用例: 无（manual，参考 scripts/security/sudo-nopasswd.sh）

## R14 库文件纯净
- 说明: lib/*.sh 只含函数定义与 readonly 常量，被 source 时零副作用
- 依据: styleguide「Libraries」
- 工具: manual
- 检测: 人工评审
- 微例: 库顶层直接执行初始化命令 → 包进函数
- 用例: 无（manual）

## R15 相对路径稳健
- 说明: 脚本引用同仓库资源用 `$(dirname "${BASH_SOURCE[0]}")` 定位，不依赖调用方 CWD
- 依据: styleguide「Environment」
- 工具: manual
- 检测: 人工评审
- 微例: `source lib/common.sh` → `source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"`
- 用例: 无（manual）
