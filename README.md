# my-bash-toolkit

个人 bash 脚本管理仓库：规范（Google Shell Style）+ 自动化质量门禁（pre-commit）+ 分类管理 + bash 版本锁定 + Bats 单元测试 + 注释抽取文档自动化。

## 1. 测试通过环境与 bash 版本锁定

| 环境 | bash 版本（实测） | 测试阶段 | 状态 |
|---|---|---|---|
| WSL Ubuntu 26.04.1（基准环境） | 5.3.9（2026-10-30 实测） | Stage 1 | ✅ 通过 |
| Ubuntu 26.04（GitHub Actions ubuntu-26.04 runner） | 5.3.9（2026-10-30 CI 实测） | Stage 2 | ✅ 通过 |
| Windows Git Bash（Git for Windows） | 5.2.37（2026-10-30 实测） | Stage 3 | ✅ 通过 |

注：GitHub runner 用户的免密 sudo 由 /etc/sudoers.d 单独授权、**不在 sudo/wheel 组**，涉及用户组前提的用例在 CI 上自动 skip（函数级用例仍全覆盖）。

- 版本区间锁定于根目录 `.bash-version`（语义化 MIN-MAX，端点含，双向硬阻断）：当前 `5.2.0-5.3.9`。越界运行/测试会被 `bash_env_check` 阻断；新 bash 版本需重测通过后更新该文件放行（checklist 见 `docs/bash_env_and_doc_spec.md` §8）。
- 手动检查当前环境：

```bash
scripts/lib/env.sh            # 打印 platform / env id / bash 版本 / 区间判定
scripts/lib/env.sh --quiet    # 仅退出码：0=支持 1=不支持 2=配置异常
```

## 2. 编码规范与质量门禁

- 编码规范：Google Shell Style Guide 精选规则见 [`shell_rules.md`](shell_rules.md)（每条规则含工具归属与检测编号）。
- 门禁：pre-commit 框架，提交前强制执行：

```bash
pip3 install --user pre-commit   # 或 pipx install pre-commit
pre-commit install
pre-commit run --all-files       # 手动全量检查
```

- 工具要求（Makefile `doctor` 目标可打印实测版本）：bash ≥5.2（受 .bash-version 锁定）、shfmt、shellcheck（apt 安装发行版版本即可）、bats ≥1.11、pre-commit ≥4。
- hook 清单：shfmt -d（格式，参数 `-i 2 -ci -bn -sr`）、shellcheck、line-length（≤80 列）、check-metadata（头部 tag + 函数 env 标注）、rules-check-test（规范用例回归）。
- `.shellcheckrc`（external-sources、source-path）为项目级配置，CLI / pre-commit / VSCode 插件三处共用；严重级别经 CLI `--severity=style` 传递——shellcheck 0.11 实测 SC2086/SC2162/SC2006 均已降档，warning 档抓不到核心规则。

## 3. 脚本分类（10 域）

| 目录 | 内容 | 目录 | 内容 |
|---|---|---|---|
| scripts/system/ | 服务、包管理、定时任务 | scripts/net/ | 诊断、下载、SSH、API 调试 |
| scripts/security/ | sudoers、权限加固 | scripts/ops/ | 监控、备份、告警、巡检 |
| scripts/dev/ | 开发辅助（gen-docs 等） | scripts/install/ | 安装部署、环境引导 |
| scripts/text/ | 文本与数据、格式转换 | scripts/wsl/ | WSL/VM 专用互操作 |
| scripts/files/ | 批量重命名、去重、归档 | scripts/lib/ | 共享函数库（被 source） |

同子域满 3 个脚本才建二级目录，最多两级（DR-005）。

## 4. 测试

- 框架 Bats-core（≥1.11），助手库 bats-support / bats-assert / bats-file 以 git 子模块置于 test/libs/。
- 测试文件镜像 scripts/ 结构：test/<分类>/<脚本名>.bats；默认在 mktemp 沙箱运行；系统级脚本强制 `--dry-run` + 备份恢复 helper。
- 脚本/函数按 `# env:` 标注声明支持环境，**不支持的环境直接 skip，不测试**。
- **三阶段测试流水线（顺序强制）**：
  1. Stage 1 本地 WSL：`make env-check && make test` 全绿 → 人工确认；
  2. Stage 2 GitHub Actions（ubuntu-26.04）：pre-commit + check-rules + test；
  3. Stage 3 Windows git bash：手动克隆本仓库到 Windows 工作区 → `./run_tests.sh` 批量自动化测试；问题按脚本模块修复后从 Stage 1 依序重跑。
- git bash 指引：git bash 无 make，直接 `./run_tests.sh`；bats 必装（`npm install -g bats` 或从 bats-core releases 下载后加入 PATH）；shfmt/shellcheck 可选——缺失时 rules_check_test 回归用例自动跳过（格式与静态门禁由 Stage 1/2 承担），如需在 Windows 本地跑规则回归可安装两者（如 `scoop install shfmt shellcheck`）。
- git bash 性能预期：全量测试 10-25 分钟属正常——MSYS 进程创建开销（约为 Linux 几十倍）× bats 全程数百次进程派生，叠加 Windows Defender 实时扫描放大；建议在 Windows 安全中心把仓库目录、Git 安装目录与 python/scoop 安装目录加入排除项以缩短时长。**验收以用例结果为准，不追求速度。**
- **克隆本仓库请带子模块**：`git clone --recurse-submodules <url>`；已克隆的补执行 `git submodule update --init --recursive`（bats 助手库在 test/libs/，缺失时依赖它的用例会失败）。

## 5. 常用命令（Makefile）

```bash
make help         # 目标清单
make env-check    # bash 环境/版本判定（.bash-version）
make lint         # pre-commit run --all-files
make test         # bats 全量单元测试
make check-rules  # rules_check_test 规范用例回归
make docs         # 重新生成 docs/SCRIPTS.md
make doctor       # 打印工具链版本
```

## 6. 文档自动化

- 每个脚本头部含元数据 tag（script-name / description / usage / option / example / env / deps / category），每个函数前有 `# env:` 环境标注——**这是唯一事实源**。
- `scripts/dev/gen-docs.sh`（`make docs`）从注释批量抽取生成 `docs/SCRIPTS.md`；该文件是生成物，禁止手改。
- 语法细则见 [`docs/bash_env_and_doc_spec.md`](docs/bash_env_and_doc_spec.md)。

## 7. 脚本引入 SOP（摘要）

你提供已有脚本或需求描述后按此流程处理（完整版 docs/development_plan.md §9）：
定分类（10 域，模糊时确认）→ 规范改造（头部 tag、函数 env 标注、kebab-case、系统级 --dry-run）→ bats 测试（按环境 skip）→ `make docs` → pre-commit 通过 → GitHub Flow 提交。

## 8. 开发流程与文档索引

- 分支模型：GitHub Flow——main + 短生命周期 feature 分支，合并前过门禁与测试（DR-002）。
- 提交信息：决策类改动在正文末尾附 `Decision: DR-编号`。
- 文档：**[PROJECT_CONTEXT（新会话上下文总入口，先读）](docs/PROJECT_CONTEXT.md)** · [开发计划](docs/development_plan.md) · [决策记录](docs/decision_log.md) · [测试框架对比](docs/bash_test_framework_comparison.md) · [环境与文档规格](docs/bash_env_and_doc_spec.md) · [脚本文档（生成物）](docs/SCRIPTS.md)
