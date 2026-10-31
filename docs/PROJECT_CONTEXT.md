# PROJECT_CONTEXT —— 新会话上下文总入口

> 最后更新: 2026-10-31 ｜ 维护义务: 新增/修改脚本或决策后必须同步更新本文件（AGENTS.md 有约束条款）
> commit 历史以 `git log` 为准，本文不记录 hash。

## 0. 如何启动新会话（复制即用）

- **全新脚本**：
  「先读 docs/PROJECT_CONTEXT.md 和 AGENTS.md，按脚本引入 SOP 全流程开发新脚本：〈需求描述〉」
- **改造已有脚本**：
  「先读 docs/PROJECT_CONTEXT.md 和 AGENTS.md，我提供已有脚本，按 SOP 规范改造并补测试：〈粘贴脚本〉」
- **开发队列中的脚本**（队列见 docs/BACKLOG.md）：
  「先读 docs/PROJECT_CONTEXT.md、docs/BACKLOG.md 和 AGENTS.md，按 SOP 全流程开发 BL-XXX〈脚本名〉」

读完本文件后，按 §3 文档链补齐规范细节，再按 §8 SOP 开工。

## 1. 项目快照

个人 bash 脚本管理仓库：Google Shell Style 规范 + pre-commit 质量门禁（shfmt/ShellCheck）+ 10 域分类 + `.bash-version` 版本锁定（5.2.0-5.3.9 双向硬阻断）+ Bats-core 单元测试 + 注释抽取文档自动化。

- 仓库: https://github.com/jxsword/my-bash-toolkit （public，main，GitHub Flow）
- 测试状态: Stage 1 WSL Ubuntu 26.04.1（bash 5.3.9）与 Stage 2 GitHub Actions 全绿；Stage 3 git-bash 曾现 jsonq 回归（python3 Store 存根致退出 49），2026-10-31 已加探针+MSYS 加固修复；同日复验又现中文乱码与个别用例停顿，已加 PYTHONUTF8 强制编码 + stdin 显式化 + timeout 60 加固（WSL 侧全绿），**git-bash 侧待用户复验**（需真实 python3 或设 `JSONQ_PYTHON`）。
- 人工闸门 A-D 已全部关闭（详见 development_plan §10）。
- 项目阶段: 三环境闭环完成，**进入脚本开发期**；已立项 17 个日常/运维脚本（BL-001~017），队列见 docs/BACKLOG.md，每项在新会话按 SOP 开发。BL-001 mkscript（2026-10-30）、BL-002 git-wip（2026-10-30）、BL-003 env-dump（2026-10-30）、BL-006 jsonq（2026-10-30）、BL-008 dedup（2026-10-30）、BL-009 bulk-rename（2026-10-30）、BL-010 port-check（2026-10-30）、BL-004 sysinfo（2026-10-30）、BL-005 pkg-export（2026-10-30）与 BL-007 log-grep（2026-10-30）、BL-011 http-probe（2026-10-30）、BL-012 backup-dir（2026-10-30）、BL-013 disk-alert（2026-10-30）、BL-014 wsl-export（2026-10-30）、BL-015 clip（2026-10-30）、BL-016 perm-audit（2026-10-30）、BL-017 bootstrap-dev（2026-10-30）已完成，**队列全部清零**；后续新脚本可用 mkscript 生成规范骨架。

## 2. 决策摘要（详见 docs/decision_log.md）

| DR | 一句话结论 |
|---|---|
| DR-001 | 质量门禁用 shfmt + ShellCheck（README 原 clang 方案官方确认不支持 shell，已废弃） |
| DR-002 | GitHub Flow（main + 短命 feature 分支），完整 git flow 对个人库过重 |
| DR-003 | 单元测试 Bats-core + 官方助手库（bats-support/assert/file，git 子模块） |
| DR-005 | 脚本 10 域分类：system/security/dev/text/files/net/ops/install/wsl + lib（替代 DR-004 的 9 类）；同子域满 3 个脚本才建二级目录 |
| DR-006 | bash 版本锁定：根目录 `.bash-version` 单行 MIN-MAX，越界双向硬阻断，新环境重测通过后更新放行 |
| DR-007 | 文档自动化：头部 tag + 函数级 `# env:` 为唯一事实源，gen-docs.sh 抽取生成 docs/SCRIPTS.md |

## 3. 必读文档链（本文件之后按序）

1. `shell_rules.md` —— 编码规范 R01-R15（每条含工具归属/检测编号/用例名）
2. `docs/bash_env_and_doc_spec.md` —— 环境标识符、bash_env_check 接口、头部 tag 语法、函数 env 标注、gen-docs 抽取规则、.bash-version 更新 checklist
3. `README.md` —— 环境矩阵、门禁安装、常用命令、三阶段测试流水线
4. `docs/development_plan.md` —— 完整计划；§9 = 脚本引入 SOP 原始版；§10 = 执行记录
5. `docs/decision_log.md` —— 决策全文（含被否选项与理由）
6. `docs/bash_test_framework_comparison.md` —— 5 框架实测对比
7. `docs/SCRIPTS.md` —— 现有脚本功能总览（**生成物，禁止手改**）
8. `docs/BACKLOG.md` —— 脚本开发队列（已立项任务从这里取）
9. `docs/test_performance.md` —— 测试性能分析与优化指南（三环境机理、git bash 慢因、基准对比方法）
10. `docs/STAGE3_LOG.md` —— git bash 人工验收日志（按提交粒度，不作为跳过测试的依据）

## 4. 硬约束速查（违反 = 提交被拦或流程违规）

- bash 特性使用不越 `.bash-version`（当前 5.2.0-5.3.9）区间；越界运行被 bash_env_check 阻断。
- 每个函数定义前必须有 `# env: <id,...>`；不支持的环境**不写**（测试与文档自动跳过）。环境 id 只有三个：`ubuntu-26.04` / `wsl-ubuntu-26.04` / `git-bash`。
- 脚本头部 5 个必需 tag：script-name / description / usage / env / category（语法见 spec §4）。
- ShellCheck 以 `--severity=style` 运行（0.11 实测 SC2086/SC2162/SC2006 已降档，warning 档抓不到核心规则）；`.shellcheckrc` 只管 external-sources 与 source-path。
- 行宽 ≤80 列；文件 kebab-case、函数 lower_snake_case；`set -u -o pipefail` 基线。
- 系统级脚本（写 /etc、systemctl、usermod 等）强制 `--dry-run`，测试按 sandbox-only / system-touch 分级。
- `docs/SCRIPTS.md` 是生成物禁手改；改脚本注释后 `make docs` 重新生成并随代码同一提交。
- 三阶段测试顺序强制：本地 WSL 全绿 → 人工确认 → CI → git bash；不得跳步。

## 5. 复用设施清单（先找轮子，不要重复造）

| 设施 | 用途 | 用法 |
|---|---|---|
| scripts/lib/env.sh | 环境识别 + .bash-version 区间判定 | `source` 后用 env_detect_id / env_is_supported / bash_env_check；直接执行 = 自检 |
| scripts/lib/common.sh | 日志 | source 后 log_info / log_err / log_warn |
| scripts/lib/test_files.sh | 全量 .bats 清单收集（排除 libs） | source 后 collect_bats_files [root]；Makefile/run_tests/bench 共用 |
| scripts/dev/test-changed.sh | 变更 → 用例映射器（定向测试引擎） | --run/--staged/--base/--files；映射与回退规则见其 usage；pre-commit `bats-changed` hook 也走它 |
| scripts/dev/bench-tests.sh | 测试基准计时（逐文件分时 + 全跑墙钟） | `make bench-tests ARGS="--save 文件"`；优化前后对比方法见 docs/test_performance.md |
| test/helpers/sandbox.bash | mktemp 沙箱与 HOME/XDG 隔离 | 测试 setup 调 sandbox_setup，teardown 调 sandbox_teardown |
| test/helpers/backup_restore.bash | 系统级测试快照/恢复 | backup_paths / restore_paths（-P 保留绝对路径，仅 system-touch 用） |
| test/helpers/test_env.bash | 按环境跳过用例 | load 后 skip_unless_env <id>...；设 `_TESTENV_FAKE_ENV_ID=<id>` 可确定性模拟任意环境 |
| rules_check_test/ | 规范实证与 golden 机制 | `make check-rules`；新增机检规则时在 bad/ 加用例并 `--update-expected` 重建 golden |
| Makefile | lint / test / test-changed / test-one / bench-tests / check-rules / docs / env-check / doctor | `make help` 看清单 |

## 6. 最小 bats 测试模板（照抄改）

```bash
#!/usr/bin/env bats
# script-name: <脚本名>-test
# description: <脚本名> 的单元测试（[sandbox-only] 或 [system-touch]）
# usage: （bats 测试，make test 触发）
# env: <此测试文件可运行的环境 id 列表>
# deps: bats
# category: <分类>

setup() {
  load '../helpers/test_env'
  skip_unless_env <允许的环境 id>...
  # 需要断言库时（注意：条件加载，见 §9 踩坑 4/5）：
  # load '../../test/libs/bats-support/load'
  # load '../../test/libs/bats-assert/load'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/<分类>/<脚本名>.sh"
}

@test "<用例名>" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"预期片段"* ]]
}
```

要点：系统级脚本优先测 dry-run 与参数校验分支；测试默认跑在 mktemp 沙箱（sandbox.bash）。

## 7. 新脚本开发 SOP（命令版）

0. **会话自检**：`git pull && make check` 全绿后再开工（基线漂移不得开发）。
1. **定分类**：按 10 域表归位（system/security/dev/text/files/net/ops/install/wsl/lib）；归属模糊时向用户确认。
2. **规范改造/生成**：kebab-case 命名、头部 5 tag、函数级 `# env:`、`set -u -o pipefail`、引用同仓库资源用 `$(dirname "${BASH_SOURCE[0]}")`、系统级脚本加 `--dry-run`、日志走 common.sh。
3. **测试**：`test/<分类>/<名>.bats`（套 §6 模板）；日常迭代 `make test-changed` 只跑变更对应用例（映射/回退规则见 scripts/dev/test-changed.sh usage），CI 侧全量兜底；失败修复循环用 `make test-one F=<文件>` 或 `bats <单文件>` 秒级重跑。
4. **文档**：`make docs` 重新生成 SCRIPTS.md，随代码同一提交。
5. **提交**：pre-commit 门禁通过 → GitHub Flow 短分支或 main 直提 → push；决策类改动提交信息末尾加 `Decision: DR-编号`，新决策先补 decision_log。
6. **回写上下文**：更新本文件（新脚本入 §5 后的清单视角由 SCRIPTS.md 承担，本文件更新快照/坑位/约束如有变化）。

## 8. 三环境差异与用例行为（写测试前必读）

| 环境 | bash | 行为 |
|---|---|---|
| WSL ubuntu-26.04（基准） | 5.3.9 | 全部用例执行 |
| GitHub Actions ubuntu-26.04 | 5.3.9 | runner 用户**不在 sudo/wheel 组**（免密 sudo 由 /etc/sudoers.d 单独授权）：依赖组前提的用例 skip，函数级用例必跑 |
| git-bash（Windows） | 5.2.37 | 无 make（用 ./run_tests.sh）；bats 必装（npm）；shfmt/shellcheck 可选（缺失时 rules 回归 skip）；sudo 类脚本整体 skip |

克隆注意：`git clone --recurse-submodules`；已克隆补 `git submodule update --init --recursive`（test/libs/ 助手库）。

## 9. 踩坑清单（现象 → 对策/固化位置）

| # | 现象 | 对策（已固化位置） |
|---|---|---|
| 1 | clang-format/clang-tidy 无法处理 shell 脚本 | 工具链改 shfmt+ShellCheck（DR-001；README §2） |
| 2 | shellcheck 0.11 严重级别降档（SC2086→info、SC2162→info、SC2006→style），warning 档漏检核心规则 | 门禁与运行器统一 `--severity=style`（.pre-commit-config.yaml） |
| 3 | .shellcheckrc 的 severity 键不被自动应用 | severity 经 CLI 传；rc 只放 external-sources/source-path |
| 4 | bats 1.13 目录扫描不递归，且会误收子模块 fixtures | Makefile/run_tests 用 find 收集 `-not -path '*/libs/*'` |
| 5 | bats setup 内 `skip` 不中断后续语句 | 可选组件用 `if env_is_supported ...` 条件加载（sudo-nopasswd.bats setup） |
| 6 | Windows 普通克隆缺子模块，load bats-assert 报错 | README 克隆命令带 --recurse-submodules；run_tests.sh 预检提示 |
| 7 | golden 输出与工具版本耦合，升级即碎 | run_checks 归一化关键行比对；工具升级按 spec §8 checklist 复核 |
| 8 | GH runner 组前提 / /mnt/c（DrvFs）权限语义 | 测试两层拆分（函数级必跑 + CLI 组前提 skip）；沙箱不设 /mnt/*、仓库保持 ext4 |
| 9 | bash 5.3 实测：`arr[$k]+="${arr[$k]:-}x"` 自引用追加会把值翻倍（dedup 开发踩中）；`wc -l <<< "$str"` 因 herestring 追加换行恒多计 1 | 关联数组累积一律用整体赋值 `arr[$k]="${arr[$k]:-}…"`；计数用 `printf '%s' "$str" \| wc -l`，不用 herestring |
| 10 | nameref（`local -n ref="$2"`）的引用名与目标名相同（如都叫 present）→ 运行时报「循环的名称引用」且数组追加静默丢失（bootstrap-dev 开发踩中） | nameref 引用名一律用 `out_` 前缀内部名，与调用方传入的数组名错开（见 bootstrap-dev scan_profile）；写完后必须跑一次真实调用验证回填 |
| 11 | bats `run` 会继承调用方 stdin：脚本内 `[ -t 0 ]` 自动判定在 TTY 终端跑测试时失真，非终端分支用例失败（clip 踩中） | 依赖 stdin 终端判定的用例必须显式固化前提，如 `run "$SCRIPT" < /dev/null`（见 test/wsl/clip.bats） |
| 12 | git-bash 下 `command -v python3` 命中≠可执行：可能是 Windows Store 应用执行别名存根（真实退出 9009，MSYS `$?` 截断为 49、无输出），且 `-c` 内联代码/参数可能受 MSYS2 参数改写（jsonq Stage 3 回归踩中） | 解释器调用三件套：先健康探针（`"$py" -c 'import json'`，任何非零→退出 3 提示 `JSONQ_PYTHON`）+ 局部 `MSYS2_ARG_CONV_EXCL='*'` 传参 + 探针自带 `</dev/null`（见 jsonq `_jsonq_check_python`；该变量在非 MSYS 环境无副作用） |
| 13 | git-bash 下 `JSONQ_PYTHON` 指向 Windows 本机 python（如 scoop）时，jsonq 中文错误消息乱码（ASCII 片段完好，形如 `jsonq: □Ƿ□ JSON`）：本机 python 对管道/重定向默认按系统 ANSI 代码页（中文 Windows = GBK/cp936）编码 stdout/stderr，中文经它写出变 GBK 字节，bats 按 UTF-8 比对失败；bash printf 输出（MSYS 程序 UTF-8 直写）不受影响 | 所有 python 调用统一加 `PYTHONUTF8=1` + `PYTHONIOENCODING=utf-8` 环境前缀，python 代码内 `sys.stdout/stderr.reconfigure(encoding="utf-8")` 双保险；Linux 下前缀无副作用（jsonq `run_query`/`_jsonq_check_python`；与 #12 同为"command -v 命中≠按预期工作"一族） |
| 14 | git bash 全量测试慢（10-25 分钟量级）：MSYS 进程创建开销（每进程几十 ms，约为 Linux 几十倍）× bats 全程数百次进程派生，叠加 Windows Defender 实时扫描逐个放大 | 脚本侧无法根治，做文档化：建议在 Windows 安全中心把仓库目录、Git 安装目录、python/scoop 安装目录加入排除项；git bash 侧 10 分钟量级属预期，**验收以用例结果为准，不追求速度**（README §4 同步；jsonq 另加 timeout 60 包装防个别 python 调用悬挂放大停顿）。深层机理/优化分级/基准方法已展开为 docs/test_performance.md；日常规避用变更驱动定向测试（scripts/dev/test-changed.sh） |

## 11. CI 演进备案（单一事实源）

- **决策（2026-10-31）**：CI 保持全量（当前测试段约 1 分钟，定向收益约 50 秒，不值定向 CI 的边界漏测面）；定向测试只做在本地（提交门禁 bats-changed hook + `make test-changed` / `run_tests.sh --changed`）。
- **升级触发条件**：CI 测试段 >10 分钟，或全量验证实际阻塞迭代节奏。
- **切换路径**（届时约 30 分钟）：.github/workflows/tests.yml 改 `fetch-depth: 0`，测试步骤换成 `scripts/dev/test-changed.sh --run --base "$base"`——push 事件 base 取 `github.event.before`（两点 diff `event.before..HEAD` 覆盖多提交推送；`event.before` 为全零时回退全量），PR 事件 base 取 merge-base；lib/hooks/门禁基础设施变更由 helper 内建回退规则自动转全量。
- **正交备案**：若届时只是少数脚本测试特别耗时（而非整体变多），优先考虑快慢分层（push 跑快层、scheduled/手动跑全层）而非 diff 定向。

## 12. 常用命令速查

```bash
make check         # lint + check-rules + test 全量
make env-check     # 当前环境识别与版本区间判定
make test-changed  # 只运行与变更文件对应的用例（本地定向）
make test-one F=test/lib/env.bats   # 单文件重跑
make bench-tests   # 测试基准计时（ARGS="--save 文件"）
./run_tests.sh     # 免 make 测试入口（git bash 用；--changed 定向）
make docs          # 重新生成 docs/SCRIPTS.md
make doctor        # 打印工具链实测版本
pre-commit run --all-files   # 手动全量门禁
scripts/lib/env.sh # 环境自检报告
```
