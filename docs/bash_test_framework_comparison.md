# bash 单元测试框架对比调研报告

- 调研日期: 2026-10-30（所有 URL 与仓库数据当日实测；Star/活跃度来自 GitHub API）
- 调研性质: 项目规划内嵌选型（轻量级），满足 research-workflow 第 2 条全部产出硬性要求；如需升级为正式 4 闸门调研可在此报告基础上扩展。
- 场景约束: 个人 bash 脚本管理仓库；运行环境 WSL2 Ubuntu (bash 5.x)；需与 pre-commit 门禁集成；测试默认沙箱化。

## 对象条目

### Bats-core
- 官网: https://github.com/bats-core/bats-core （核实: 2026-10-30 可达）
- 官方文档: https://bats-core.readthedocs.io/en/latest/ （核实: 2026-10-30 可达）
- 源码: https://github.com/bats-core/bats-core （核实: 2026-10-30 可达）
- 简介: TAP 兼容的 bash 测试框架，`@test "name" { ... }` 语法，事实上是 shell 测试领域使用最广的框架（6335★，MIT，2026-10-27 仍在推送）。本机已安装 Bats 1.13.0。
- 优点: 活跃度与社区规模最大；官方助手库生态完整（bats-support 0BSD、bats-assert CC0-1.0、bats-file CC0-1.0，均实测存在且在维护）；TAP 输出便于 pre-commit/CI 解析；安装途径多（apt/npm/源码）；语法接近纯 bash，上手成本最低。
- 缺点: 断言能力依赖外部助手库，需以子模块或 vendored 目录方式额外引入；框架本身只做运行与 TAP 输出，mock/覆盖率需另配。
- 适用场景: 通用脚本回归测试、与 CI/门禁集成、希望社区案例多、快速上手。

### ShellSpec
- 官网: https://shellspec.info/ （核实: 2026-10-30 可达）
- 官方文档: https://shellspec.info/ （核实: 2026-10-30 可达；详细文档在 GitHub README 与 Wiki）
- 源码: https://github.com/shellspec/shellspec （核实: 2026-10-30 可达）
- 简介: 全功能 BDD 测试框架（1403★，MIT，2025-11-24 推送），官方自述支持 dash/bash/ksh/zsh 与全部 POSIX shell，内建代码覆盖率、mock、参数化测试、并行执行。
- 优点: 单框架功能最全（mock/覆盖率/参数化/并行内建，无需助手库）；对多 shell 兼容性最好；CLI 功能丰富。
- 缺点: BDD DSL 语法学习成本高于 Bats；社区规模与案例数量小于 Bats-core；近期推送频率放缓（2025-11 后）。
- 适用场景: 跨多 shell 的库级项目、需要内建覆盖率与 mock、偏好 BDD 风格描述。

### bashunit (TypedDevs)
- 官网: https://bashunit.io/ （核实: 2026-10-30 不可达——curl 与 WebFetch 双渠道均为 TLS 连接重置；文档只能走 GitHub，禁止引用该 URL 为可达链接）
- 官方文档: https://github.com/TypedDevs/bashunit#readme （核实: 2026-10-30 可达）
- 源码: https://github.com/TypedDevs/bashunit （核实: 2026-10-30 可达）
- 简介: 现代化 TAP 测试框架（438★，MIT，2026-10-29 推送，五个对象中迭代最活跃）。
- 优点: 维护最活跃；现代化 API 与 TAP 输出；有官方行动积极维护文档与示例。
- 缺点: 社区规模尚小（438★），生态与案例少；官网在本网络不可达，文档渠道单薄；采用者需要更多自力更生。
- 适用场景: 愿意跟随新兴项目、对框架现代化程度敏感的场景。

### shUnit2
- 官网: https://github.com/kward/shunit2 （核实: 2026-10-30 可达）
- 官方文档: https://github.com/kward/shunit2#readme （核实: 2026-10-30 可达）
- 源码: https://github.com/kward/shunit2 （核实: 2026-10-30 可达）
- 简介: xUnit 风格的老牌框架（1742★，Apache-2.0，2026-03-15 推送），以单文件库形式发布，兼容 Bourne 系 shell，设计对标 JUnit/PyUnit。
- 优点: 极其成熟稳定；单文件引入零依赖；兼容最老的 shell；Apache-2.0 许可宽松。
- 缺点: 迭代缓慢；无 TAP 原生输出、断言风格偏老；无 mock/覆盖率；测试写法样板代码多。
- 适用场景: 需兼容 Bourne/POSIX 老环境的遗留系统维护。

### bash_unit
- 官网: https://github.com/pgrange/bash_unit （核实: 2026-10-30 可达）
- 官方文档: https://github.com/pgrange/bash_unit#readme （核实: 2026-10-30 可达；默认分支 main）
- 源码: https://github.com/pgrange/bash_unit （核实: 2026-10-30 可达）
- 简介: 极简 xUnit 风格框架（637★，GPL-3.0，2026-02-11 推送），强调零依赖、单文件、易读的测试输出。
- 优点: 上手极快、依赖最少；输出可读性好。
- 缺点: GPL-3.0 许可（作为开发工具使用无碍，但生态上偏保守）；功能集与生态均弱于 Bats-core/ShellSpec。
- 适用场景: 极小项目、想要一个文件搞定的轻量测试。

## 选择策略矩阵

| 维度 | Bats-core | ShellSpec | bashunit | shUnit2 | bash_unit |
|---|---|---|---|---|---|
| 测试风格 | TAP，`@test` 语法 | BDD DSL | TAP，现代语法 | xUnit | xUnit，极简 |
| Star（2026-10-30） | 6335 | 1403 | 438 | 1742 | 637 |
| 最近推送 | 2026-10-27 | 2025-11-24 | 2026-10-29 | 2026-03-15 | 2026-02-11 |
| 许可证 | MIT | MIT | MIT | Apache-2.0 | GPL-3.0 |
| 内建 mock/覆盖率 | 无（助手库补） | 内建 | 部分 | 无 | 无 |
| 助手生态 | 官方 support/assert/file | 内建为主 | 官方示例 | 少 | 少 |
| 安装依赖 | 独立二进制/npm/apt | 独立脚本包 | 单二进制 | 单文件 | 单文件 |
| 本机就绪 | 已装 1.13.0 | 需安装 | 需安装 | 需引入文件 | 需引入文件 |
| 与 pre-commit/CI 集成 | 成熟（TAP） | 成熟 | 成熟（TAP） | 一般 | 一般 |

## 按场景的选择结论

- 想要生态最大、集成最省事、团队/未来协作者最容易看懂：**Bats-core**（本仓库采纳，DR-003）。
- 跨多 shell 的库级项目或需要内建 mock/覆盖率：ShellSpec。
- 追踪新兴现代化框架且不介意社区小：bashunit。
- 维护必须跑在 Bourne 老环境上的遗留脚本：shUnit2。
- 只要"一个文件 + 几个断言"的最小方案：bash_unit。

## 本仓库集成方式（Bats-core）

1. 运行器: 本机已装 apt 版 Bats 1.13.0，直接使用；README 记录最低版本要求（≥1.11，保证 TAP 与助手库兼容），CI 复现用官方安装脚本；不引入 npm 双轨，减少版本漂移源。
2. 助手库: bats-support / bats-assert / bats-file 以 git submodule（.gitmodules 入库）为主选引入；网络不稳时兜底 vendored 到 `test/libs/`（Makefile 目标不变），三者许可证（0BSD/CC0-1.0）均允许直接随仓库分发。
3. 文件对应: `test/<脚本名>.bats` 对应 `scripts/<分类>/<脚本名>.sh`，一脚本一测试文件。
4. 沙箱: 测试默认在 `mktemp -d` 临时目录中运行（隔离 HOME/PATH/XDG）；涉及系统文件/配置的脚本强制实现 `--dry-run`，真实执行前用 tar 备份目标路径并生成自动恢复脚本，或在 Docker 容器内运行（本机 Docker 可用）。
5. 入口: `make test` 统一跑 `bats test/`；另有纯 bash 的 `run_tests.sh` 免 make 入口（Windows git bash 使用）；pre-commit 只做格式与静态检查，测试由 make/run_tests.sh 手动或 CI 触发，避免提交卡顿。
6. 环境分层测试: 脚本/函数按 `# env:` 标注声明支持环境（ubuntu-26.04 / wsl-ubuntu-26.04 / git-bash），不支持的环境用 bats skip 直接跳过；测试顺序强制三阶段——本地 WSL ubuntu2604 全绿并经人工确认 → GitHub Actions（runs-on: ubuntu-26.04）→ 用户在 Windows git bash 手动批量执行；lib/env.sh 的 bash_env_check 按 .bash-version（MIN-MAX 双向硬阻断，DR-006）做预检与环境识别。
