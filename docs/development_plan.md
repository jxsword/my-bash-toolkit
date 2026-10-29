# my-bash-toolkit 开发计划

- 状态: 三环境闭环完成，进入脚本开发期
- 生成日期: 2026-10-30（v1 规划 → v2 两轮复审 → v3 需求修订 → 实施 → 三环境测试闭环）
- 决策依据: docs/decision_log.md（DR-001 ~ DR-007）
- 实施规格: docs/bash_env_and_doc_spec.md（.bash-version、env 检测、tag 与文档抽取）

## 1. 项目定位

个人 bash 脚本管理仓库，七个支点：

1. 编码规范——Google Shell Style Guide（https://google.github.io/styleguide/shellguide.html ，核实 2026-10-30 可达），精选规则落盘为根目录 `shell_rules.md`。
2. 质量门禁——pre-commit 框架（https://pre-commit.com/ ，核实可达）在提交前强制跑格式化（shfmt）与静态检查（ShellCheck）。
3. 分类管理——scripts/ 按 10 域目录组织，域内按需二级目录（DR-005）。
4. 版本锁定——`.bash-version` 锁定 bash 支持区间（MIN-MAX 语义化版本，双向硬阻断，DR-006），防止低版本缺特性、新版本弃特性。
5. 单元测试——Bats-core（DR-003），默认沙箱运行，系统级脚本强制 dry-run + 备份恢复；三环境测试矩阵（ubuntu 26.04 / wsl ubuntu 26.04 / windows git bash）。
6. 文档自动化——脚本头部 tag + 函数级 env 标注为唯一事实源，gen-docs.sh 批量抽取生成 docs/SCRIPTS.md（DR-007），杜绝文档与脚本不一致。
7. 规范实证——rules_check_test/ 用 good/bad 用例实测检查工具输出，形成「规则 → 检测 → 修复 → 复检通过」闭环。

## 2. README 计划审查结论

| # | 问题 | 证据（2026-10-30 实测） | 修复 |
|---|---|---|---|
| P0 | clang-format/clang-tidy 不支持 shell 脚本，整个门禁方案不可行 | clang.llvm.org/docs/ClangFormat.html 语言列表为 C/C++/Java/JS/Objective-C/Protobuf/C# 等，无 shell；clang.llvm.org/extra/clang-tidy/ 自述 "clang-based C++ linter" | 改用 shfmt + ShellCheck（DR-001） |
| P1 | 完整 git flow 对个人脚本库过重，且仓库尚未 git init | 工作区无 .git | GitHub Flow（DR-002） |
| P2 | 测试框架只要求"对比"，未定选 | 5 框架实测对比 | Bats-core（DR-003，详见对比报告） |
| P3 | 脚本分类未定义 | — | 10 域目录方案（DR-005，替代 DR-004 的 9 类方案） |
| P4 | "沙箱运行、系统修改前备份"缺乏可执行机制 | 本机 Docker 可用 | mktemp 沙箱默认 + Docker 可选 + 强制 --dry-run 条款 + 备份/恢复 helper（§6） |
| P5 | "hook 脚本需要入库"表述模糊 | pre-commit 机制 | 入库对象 = .pre-commit-config.yaml + 自定义 hook 脚本（hooks/）；`pre-commit install` 生成的 .git/hooks 文件不入库 |
| P6 | 小问题若干 | — | "vcode"→VSCode；shell_rules.md 当前为空文件待生成；本机缺 shfmt/shellcheck/pre-commit（需安装），bats 1.13.0 已装 |

## 3. 目标目录结构

```text
my-bash-toolkit/
├── README.md                  # 环境矩阵、三阶段测试流程、SOP 摘要
├── AGENTS.md                  # 开发脚本前先读 shell_rules.md；脚本引入 SOP
├── shell_rules.md             # Google Shell Style 精选规则 + 工具映射
├── .bash-version              # bash 支持区间 MIN-MAX（DR-006）
├── .editorconfig              # 已符合规范（2 空格、LF、UTF-8）
├── .pre-commit-config.yaml    # 门禁配置（入库）
├── .shellcheckrc              # ShellCheck 项目级配置（三处共用）
├── Makefile                   # lint / test / check-rules / docs / env-check / doctor
├── run_tests.sh               # 免 make 测试入口（git bash 使用）
├── hooks/                     # 自定义本地 hook：line-length.sh、check-metadata.sh
├── docs/
│   ├── decision_log.md
│   ├── development_plan.md
│   ├── bash_test_framework_comparison.md
│   ├── bash_env_and_doc_spec.md
│   └── SCRIPTS.md             # gen-docs 生成物（入库，勿手改）
├── scripts/                   # 10 域（DR-005），二级目录按需
│   ├── system/                # 服务、包管理、定时任务…
│   ├── security/              # sudoers、权限加固（sudo-nopasswd.sh 在此）
│   ├── dev/                   # gen-docs.sh 等开发辅助
│   ├── text/  files/  net/  ops/  install/  wsl/
│   └── lib/                   # 共享函数库：env.sh、common.sh…（.sh 后缀，被 source）
├── test/                      # 目录镜像 scripts/ 分类结构
│   ├── libs/                  # bats-support / bats-assert / bats-file（git 子模块）
│   ├── helpers/               # sandbox.bash、backup_restore.sh、test_env.bash
│   └── security/sudo-nopasswd.bats
├── rules_check_test/
│   ├── good/  bad/  expected/
│   ├── run_checks.sh          # 运行器（退出码 0=通过 / 非 0=阻断）
│   └── README.md              # bad→修复→通过 演示归档
└── .github/workflows/tests.yml
```

脚本命名与头部规范：可执行脚本无扩展名或 .sh 均可但全库统一用 .sh？——不，按 Google 风格：可执行脚本不带扩展名、库文件带 .sh 被	source。本项目统一：**可执行脚本不带扩展名？** 折中定稿：可执行脚本与库一律 `.sh` 结尾（与 Google 风格的差异记录于 shell_rules.md，理由：三环境识别与 gen-docs 扫描简单可靠）。文件名 kebab-case；头部含元数据 tag（spec §3）；每个函数定义前必须有 `# env:` 标注（spec §4）。

存量脚本迁移整改：permission/sudo_nopasswd.sh 为无 shebang 纯函数定义，迁入 scripts/security/sudo-nopasswd.sh（kebab-case），补 shebang、`on|off|status` 入口、`--dry-run`、头部 tag 与函数级 env 标注；操作 /etc/sudoers 属系统级脚本，测试走参数校验分支 + 容器/VM 快照路径。

## 4. 阶段计划（Phase 0-8）

### Phase 0 决策落定与 README/AGENTS 修订
- README 重写：项目简介、规范与门禁、10 域分类表、测试通过环境矩阵（bash 版本实测回填）、三阶段测试流水线、git bash 测试指引（含 bats 安装）、文档自动化说明、脚本引入 SOP 摘要。
- AGENTS.md 追加：开发 shell 脚本前先读 shell_rules.md；新脚本遵循「脚本引入 SOP」（§9）；env 标注与 tag 规范指向 spec。
- 验收：README 与 decision_log（DR-001~007）完全一致。

### Phase 1 规范基座
- 生成 shell_rules.md（中文为主、术语保留英文）：每条规则按统一字段组织——说明 / 依据（styleguide 锚点）/ 工具归属 `[tool: shfmt|shellcheck|hook|manual]` / 检测编号（SC 编号或 hook 名）/ bad→good 微例 / 对应 rules_check_test 用例名。含：shebang、缩进、≤80 列、引号、$() 优先、[[ ]] 优先、命名、readonly、错误处理、日志、头部 tag、函数 env 标注、系统级脚本 --dry-run。
- 验收：每条可机检规则在 rules_check_test/ 有用例；tag/env 规范与 spec 一致。

### Phase 2 仓库骨架
- git init（main 分支，GitHub Flow 约定入 README）；审定 .gitignore。
- 建立 10 域目录 + test/ + rules_check_test/ + hooks/ + docs/；`.bash-version` 写入 `5.2.0-5.3.9`（MAX=本机 WSL Ubuntu 26.04.1 实测 bash 5.3.9，CI 侧实测后复核）。
- Makefile：lint / test / check-rules / docs / env-check / doctor 六目标。
- permission/sudo_nopasswd.sh 按 §3 整改要求迁入 scripts/security/，原目录删除。
- 验收：目录树与 §3 一致；首个 commit 通过门禁。

### Phase 3 工具链安装与 pre-commit 门禁
- 安装：pre-commit（pip --user）、shfmt、shellcheck（apt，经 zcode-run wrapper 提权）。
- .pre-commit-config.yaml：pre-commit-hooks 卫生检查（trailing-whitespace、end-of-file-fixer、check-merge-conflict、check-yaml）+ 本地 hook：shfmt -d（system 二进制）、shellcheck（system 二进制）、line-length（≤80 列）、check-metadata（头部 tag + 函数 env 标注）、rules-check-test 回归。
- 本地 hook 选择 system 二进制而非 scop/pre-commit-shfmt（其需 golang 构建首跑慢；本机 go 虽在，速度与确定性优先），版本要求写入 README，Makefile doctor 打印版本。
- .shellcheckrc：`--severity=warning` + `source-path=SCRIPTDIR`（lib 引用降噪），CLI/pre-commit/VSCode 三处共用。
- 验收：`pre-commit run --all-files` 全绿；违规脚本被拦截且输出含规则编号与修复建议；make 六目标可用。

### Phase 4 rules_check_test 用例
- 前置：引入 bats 与助手库（git 子模块 bats-support/bats-assert/bats-file 入 test/libs/），Makefile test/check-rules 目标就位。
- good/ ≥3 个（完整元数据、lib 引用、子 shell 等正常形态）；bad/ 每条可机检规则 ≥1 个：缩进、行宽、未引号变量（SC2086）、反引号（SC2006）、shebang 缺失（SC2148）、头部 tag 缺失、函数 env 标注缺失等。
- run_checks.sh：对用例跑 shfmt -d / shellcheck / check-metadata，与 expected/ 做归一化关键行比对；退出码 0=通过/非 0=阻断。
- 流程归档：rules_check_test/README.md 记录 ≥1 个「bad→按建议修复→复检通过」完整演示。
- 验收：`make check-rules` 全绿；运行器自身 bats 用例全绿。

### Phase 5 lib/env.sh 与测试体系
- lib/env.sh：env_detect_platform / env_detect_id / env_is_supported / bash_env_check（接口见 spec §2，退出码 0/1/2；MAX 双向硬阻断）。**交付后由用户手动验证**（验证步骤清单见 §10）。
- test/helpers/：test_env.bash（skip_unless_env 按标注跳过不支持环境）、sandbox.bash（mktemp -d 沙箱，隔离 HOME/XDG_*）、backup_restore.sh（tar 快照与恢复）。
- 测试文件镜像分类结构：test/<分类>/<脚本名>.bats；run_tests.sh 免 make 入口（git bash 可用，内置 bash_env_check 预检）。
- 示例测试：test/security/sudo-nopasswd.bats（参数校验分支）。
- 验收：`make test` 全绿（Stage 1 达成）；bash_env_check 交用户手动验证。

### Phase 6 文档自动化与 CI
- scripts/dev/gen-docs.sh（awk 零依赖）→ docs/SCRIPTS.md（生成物入库，头部标注勿手改）；Makefile docs 目标。
- .github/workflows/tests.yml：runs-on ubuntu-26.04；步骤 = checkout（含子模块）→ apt 装 bats/shfmt/shellcheck → pip 装 pre-commit → `pre-commit run --all-files` → `make check-rules` → `make test`。
- 验收：SCRIPTS.md 内容与脚本注释一致（抽查）；workflow YAML 语法校验通过。

### Phase 7 VSCode 配置
- 插件已由用户手动安装（mkhl.shfmt、timonwong.shellcheck、jetmartin.bats、EditorConfig、可选 rogalmic.bash-debug）；本轮仅补 .vscode/extensions.json（推荐清单）+ settings.json（[shellscript] defaultFormatter=mkhl.shfmt + formatOnSave；shellcheck 插件读 .shellcheckrc 同源配置）。
- 注意：foxundermoon.shell-format 与 mkhl.shfmt 重叠，只保留其一。
- 验收：保存即格式化、实时 lint、bats 高亮。

### Phase 8 收尾
- 生成 docs/SCRIPTS.md；README 环境矩阵回填实测 bash 版本；development_plan §10 执行记录更新。
- 验收：新克隆者按 README 可复现全流程；Stage 1（本地全绿）达成后移交用户确认。

## 5. 里程碑顺序与依赖

Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8；Phase 4 前置引入 bats 基础设施，Phase 5 依赖 Phase 4；Phase 6/7 可与 5 并行（以 3 完成为前提）。总工期约 7 个工作日（单人，含三环境测试的人工等待）。

## 6. 沙箱与备份恢复策略

1. 默认沙箱：bats 测试统一在 `mktemp -d` 临时目录运行（test/helpers/sandbox.bash），测试内伪造 HOME/PATH/XDG_*，teardown 清理。
2. 接触系统文件/配置的脚本（写入 /etc、systemctl、usermod 等；sudo-nopasswd.sh 为首个适用对象）：
   - 编码规范强制实现 `--dry-run`（shell_rules.md，manual 检查项）；
   - 真实执行前由 test/helpers/backup_restore.sh 做 tar 快照与自动恢复，测试后恢复；
   - 或整体放入 Docker 容器执行（本机 Docker 可用）；VM 场景用 vm_ubuntu26_desktop 快照回滚。
3. 测试分级：测试文件头部标注 `[sandbox-only]` 或 `[system-touch]`，运行器按级别决定是否需要备份/容器。
4. 环境跳过：脚本/函数 `# env:` 标注未包含当前环境时，测试用 bats skip 跳过（"不支持的直接不用测试"）。

## 7. 先找轮子（Reuse First）结论

| 候选 | URL（实测可达） | Star | 许可证 | 最近推送 | 评估 |
|---|---|---|---|---|---|
| bash3boilerplate | https://github.com/kvz/bash3boilerplate | 2217 | MIT | 2026-10-21 | 单脚本样板（头部元数据、严格模式、日志），借鉴脚本模板与命名规范 |
| bashew | https://github.com/pforret/bashew | 297 | MIT | 2026-09-19 | bash 脚本微框架，借鉴目录组织与 CI 思路；整体引入改造代价大于自建 |
| Aether-0/Template | https://github.com/Aether-0/Template | 172 | 无 | 2023-08 停更 | 无许可证且停更，不合格 |

文档抽取工具补充调研（DR-007）：[help-sh](https://github.com/dhamidi/help-sh)（GPL-3.0，交互式 help）与 [bash_docstring](https://github.com/Open-Technology-Foundation/bash_docstring)（GPL-3.0，运行时 docstring）2026-10-30 实测可达，但形态均非「批量抽取→markdown 文档」，未采纳；自建 gen-docs.sh。

结论：无可直接整体使用的仓库级模板。自建骨架，借鉴 b3bp 头部模板与 bashew 目录思路；工具集成复用现成 pre-commit hook 生态（本机实施时改用 system 二进制本地 hook，理由见 Phase 3）。

## 8. 风险与待验证项

- 版本漂移：pre-commit-hooks 的 rev 在实施时取最新 tag（计划中的版本号为 2026-10-30 参考值）。
- shfmt 无法检查行宽与 shebang：hooks/line-length.sh 与 check-metadata.sh 补位。
- shellcheck 严重级别实施结论（实测 0.11）：SC2086→info、SC2162→info、SC2006→style，warning 档抓不到 R04/R05/R06 核心规则——门禁采用 `--severity=style`（全库噪音实测仅 1 条，已消除）；severity 键在 .shellcheckrc 中实测不被自动应用，经 CLI 传递。
- pre-commit 首次运行需联网拉取 hook 环境；离线场景需预装。
- golden 输出与工具版本耦合：归一化关键行比对缓解；工具升级后复核 golden（升级 checklist 入 README）。
- WSL 跨文件系统语义：/mnt/c（DrvFs）权限位与属主无意义——沙箱不设在 /mnt/*，仓库保持 ext4。
- pre-commit-shfmt 需 golang 构建首跑慢：本机虽有 go，仍选 system 二进制本地 hook（速度与确定性优先），已落 Phase 3。
- bats 版本策略：以 apt 版（本机 1.13.0）为基准，README 记录最低版本 ≥1.11；CI 用 apt 安装。
- 子模块可用性：test/libs 走 GitHub 子模块，网络不稳时兜底 vendored（许可证 0BSD/CC0-1.0 均允许）。
- Ubuntu 26.04 默认 bash：本机实测 5.3.9（2026-10-30）；CI 侧 ubuntu-26.04 镜像 bash 版本首次运行时核对，差异则复核 .bash-version MAX。
- git bash 无 make/bats：run_tests.sh 纯 bash 兜底；bats 安装指引（MSYS2 pacman 或 npm）写入 README。
- gen-docs tag 语法脆弱：tag 格式锁定进 spec 文档，rules_check_test 用例守护。
- 三阶段测试顺序依赖手动确认节点：README 流程图明示防跳步。

## 9. 脚本引入 SOP（智能体与人工共用）

用户提供**已有脚本**或**需求描述**后，按以下流程执行（同时写入 README 与 AGENTS.md）：

1. **定分类**：按 10 域表归位（含二级子域判断：同子域满 3 个脚本才建目录）；归属模糊时向用户确认。
2. **规范改造**：已有脚本——保留原逻辑，补齐头部元数据 tag、函数级 `# env:` 标注、kebab-case 重命名、错误处理与日志、系统级脚本加 `--dry-run`；新脚本——按需求生成后同样处理。
3. **版本与环境适配**：确认 bash 特性不超出 `.bash-version` 区间；`# env:` 只标注实际支持并测试过的环境，不支持的不标注（测试自动跳过）。
4. **测试**：编写 test/<分类>/<脚本名>.bats（沙箱默认；系统级走 §6 策略）；`make test` 全绿。
5. **文档**：`make docs` 重新生成 docs/SCRIPTS.md，随代码同一提交。
6. **提交**：pre-commit 门禁通过 → GitHub Flow 短分支 → 合并 main；提交信息按约定（决策类改动附 `Decision: DR-编号`）。

## 10. 执行记录与人工闸门

| 阶段 | 状态 | 备注 |
|---|---|---|
| v3 计划文档落盘 | ✅ 完成 | commit 920fabe |
| Phase 0-2 骨架与规范基座 | ✅ 完成 | commit b3fc7e3 |
| Phase 3 门禁（severity=style 实测校准） | ✅ 完成 | commit 96d9381 |
| Phase 4 rules_check_test（11/11 绿） | ✅ 完成 | commit 0421962 |
| Phase 5 bats 体系（23 用例绿） | ✅ 完成 | commit c03163c |
| Phase 6 gen-docs + CI | ✅ 完成 | commit 7912f7b |
| Phase 7 VSCode 配置 | ✅ 完成 | 插件已由用户手动安装 |
| 闸门 A：bash_env_check 手动验证 | ✅ 用户通过 | 2026-10-30 |
| 闸门 B：Stage 1 本地全绿确认 | ✅ 用户通过 | 2026-10-30 |
| 闸门 C：Stage 2（GitHub Actions） | ✅ 通过 | run 40944634779 绿；runner=Ubuntu 26.04.1 bash 5.3.9；发现 runner 用户不在 sudo/wheel 组（sudoers.d 单独授权），sudo-nopasswd 测试已按「函数级必跑 + CLI 组前提 skip」解耦 |
| 闸门 D：Stage 3（git bash） | ✅ 用户亲测通过 | bash 5.2.37；13 执行 + 13 skip 全绿（shfmt/shellcheck 可选，rules 回归按能力 skip）；测试修复：边界用例动态化、环境跳过条件加载 |

### 闸门 A：bash_env_check 手动验证清单

```bash
# 1) 正常路径：应输出 platform=wsl id=wsl-ubuntu-26.04 bash=5.3.9 verdict=OK，退出 0
./scripts/lib/env.sh

# 2) 高于 MAX：应输出 TOO_NEW，退出 1
RV="$(mktemp)"; printf '5.2.0-5.3.3\n' > "$RV"
BASH_VERSION_FILE="$RV" ./scripts/lib/env.sh; echo "exit=$?（期望 1）"

# 3) 低于 MIN：应输出 TOO_OLD，退出 1
printf '5.4.0-5.5.0\n' > "$RV"
BASH_VERSION_FILE="$RV" ./scripts/lib/env.sh; echo "exit=$?（期望 1）"

# 4) 非法格式：退出 2
printf 'garbage\n' > "$RV"
BASH_VERSION_FILE="$RV" ./scripts/lib/env.sh; echo "exit=$?（期望 2）"
rm -f "$RV"
```
