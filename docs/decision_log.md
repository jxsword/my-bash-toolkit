# 决策记录（Decision Records）

编号规则：取文件当前最大编号 + 1。条目为结论级摘要；对话矩阵更细，不一致时以日志为准。

## DR-001 2026-10-30 质量门禁工具链改为 shfmt + ShellCheck [状态: 生效]
- 背景: README 指定 clang-format/clang-tidy 按 Google Shell Style 检查 shell 脚本，但两工具官方文档实测（2026-10-30）均不支持 shell（clang-format 语言列表为 C/C++/Java/JS/C# 等；clang-tidy 自述为 C++ linter）。
- 选项与权衡: 方案A shfmt+ShellCheck（shell 事实标准、有现成 pre-commit hook，采纳）; 方案B 保留 clang 工具（无法解析 bash，技术上不可行，弃用）; 方案C shfmt+ShellCheck+附加 bashate/shellharden（覆盖面更大但规则冲突与维护成本上升，弃用）
- 结论: 格式化用 shfmt（-i 2 -ci -bn -sr 近似 Google 风格），静态检查用 ShellCheck，经 pre-commit 框架集成为提交门禁。
- 理由: shell 领域事实标准；hook 生态现成且活跃（scop/pre-commit-shfmt 96★、shellcheck-py 246★，2026-10-30 实测）。
- 影响: README 工具条款、.pre-commit-config.yaml、rules_check_test/、VSCode 插件推荐。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 项目规划会话

## DR-002 2026-10-30 分支模型采用 GitHub Flow [状态: 生效]
- 背景: README 要求按 git flow 开发，但本仓库为个人脚本库、无多版本发布需求，且 git 尚未初始化。
- 选项与权衡: 方案A GitHub Flow（main+短命 feature 分支，开销最小，采纳）; 方案B 简化 git flow（main+develop，保留发布节奏，当前多余，弃用）; 方案C 完整 git flow（develop/release/hotfix 全套，对个人库成本显著偏高，弃用）
- 结论: main 为唯一长驻分支，脚本改动走短生命周期 feature 分支，合并前过 pre-commit 门禁与 bats 测试。
- 理由: 个人脚本库的变更频率与发布形态不需要 release/hotfix 分支管理。
- 影响: README 工作流条款、后续 git init 的分支约定。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 项目规划会话

## DR-003 2026-10-30 单元测试框架选用 Bats-core [状态: 生效]
- 背景: README 要求对 Bats-core、shUnit2、bash_unit、ShellSpec、bashunit 对比后选型（对比详见 docs/bash_test_framework_comparison.md，数据 2026-10-30 实测）。
- 选项与权衡: 方案A Bats-core（生态与活跃度最佳、本机已装 1.13.0，采纳）; 方案B ShellSpec（功能最全但学习成本高、近期迭代放缓，弃用）; 方案C bashunit（最活跃但社区尚小、官网在本网络不可达，弃用）; 方案D shUnit2/bash_unit（迭代慢/社区小，弃用）
- 结论: test/ 采用 Bats-core，助手库以 bats-support/bats-assert/bats-file 引入，测试文件与脚本一一对应。
- 理由: TAP 输出便于门禁/CI 集成；官方助手库齐备；6335★ MIT 活跃维护；本机开箱即用。
- 影响: test/ 目录设计、Phase 5 实施内容、VSCode bats 插件选择。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 项目规划会话

## DR-004 2026-10-30 脚本目录按 9 类方案组织 [状态: 已替代 → DR-005]
- 背景: README 要求为脚本提供分类类别管理。
- 选项与权衡: 方案A 标准 8 类（system/dev/text/files/net/ops/install/lib，粒度适中）; 方案B 精简 6 类（类少好记但混装运维/安装类）; 方案C 标准 8 类 + wsl/ 环境专用类（采纳）← 未选中的方案保留在案，后续目录膨胀时可回退合并
- 结论: scripts/ 下设 system、dev、text、files、net、ops、install、wsl 九类中的前八类加 lib 共享函数库（共 9 目录）；现有 permission/sudo_nopasswd.sh 归入 system。
- 理由: 本机主环境为 WSL（Ubuntu）+ VMware VM，WSL/VM 互操作脚本量可预期，单列一类收益明确。
- 影响: scripts/ 目录结构、脚本头部元数据模板、README 分类章节。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 项目规划会话

## DR-005 2026-10-30 脚本分类细化为 10 域 + 按需二级目录 [状态: 生效]
- 背景: 脚本量增长后 9 类平铺定位不便，用户要求进一步细化分类。
- 选项与权衡: 方案A 10 域+按需二级（新增 security 顶层域，同子域满 3 个脚本才建二级目录，采纳）; 方案B 9 域+全量预建二级（空目录多、预分易错需迁移，弃用）; 方案C 顶层 17 域扁平细分（浏览与归类心智负担大，弃用）
- 结论: scripts/ 顶层 10 域：system/security/dev/text/files/net/ops/install/wsl + lib；二级目录按需且最多两级；permission/sudo-nopasswd.sh 归 security。
- 理由: 增量可控、避免空目录与过度设计，随脚本量自然生长；security 独立成域使系统级风险脚本集中管理。
- 影响: scripts/ 目录结构（替代 DR-004）、development_plan §3/§4、脚本引入 SOP、README 分类表。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 规划会话（v3 复审）

## DR-006 2026-10-30 bash 版本锁定（.bash-version MIN-MAX 双向硬阻断） [状态: 生效]
- 背景: 需防止低版本 bash 缺特性、也防止未来新 bash 移除特性导致行为漂移；三目标环境 ubuntu 26.04 / wsl ubuntu 26.04 / windows git bash。
- 选项与权衡: MIN=5.2（三环境当前均 ≥5.2，可用 5.x 特性，采纳）; MIN=4.4.23（兼容存量 git bash 但需回避 5.x 特性，弃用）; MIN=5.0（折中增益有限，弃用）; 超上限=双向硬阻断（采纳）; MAX 仅警告（与锁定目标不符，弃用）
- 结论: 根目录 .bash-version 单行 MIN-MAX 语义化版本（X.Y.Z，端点含），初值 5.2.0-5.3.9（MAX=WSL Ubuntu 26.04.1 实测 bash 5.3.9）；lib/env.sh 的 bash_env_check 统一检测版本+平台+发行版，越界即阻断并提示重测更新流程；新环境实测通过后更新 MAX 放行。
- 理由: 明确支持边界是三环境测试矩阵的前提；双向阻断保证脚本只运行在实测过的版本区间。
- 影响: .bash-version、lib/env.sh、run_tests.sh、make env-check、shell_rules.md、README 环境矩阵、CI workflow。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 规划会话（v3 复审）

## DR-007 2026-10-30 文档自动化：注释抽取生成统一脚本文档 [状态: 生效]
- 背景: 手写文档与脚本易脱节，要求从脚本注释批量抽取参数说明与使用示例，自动生成统一功能说明文档。
- 选项与权衡: 方案A 自建 gen-docs.sh（awk 零依赖、tag 格式自主可控，采纳）; 方案B help-sh（GPL-3.0，交互式 help 形态非批量文档，弃用）; 方案C bash_docstring（GPL-3.0，运行时 docstring 形态非批量文档，弃用）——两候选 2026-10-30 实测可达
- 结论: 头部元数据 tag（script-name/description/usage/option/example/env/deps/category）+ 函数级 `# env:` 标注为唯一事实源；scripts/dev/gen-docs.sh 扫描生成 docs/SCRIPTS.md（入库勿手改）；Makefile docs 目标；check-metadata hook 校验 tag 完整性保证可抽取。
- 理由: 零依赖且抽取格式与环境标注规范一一对应；第三方工具形态不匹配且引入 GPL 依赖考量。
- 影响: shell_rules.md、scripts/dev/gen-docs.sh、docs/SCRIPTS.md、rules_check_test 用例、hooks/check-metadata.sh、AGENTS.md SOP。
- 记录时间 / 会话: 2026-10-30 / my-bash-toolkit 规划会话（v3 复审）
