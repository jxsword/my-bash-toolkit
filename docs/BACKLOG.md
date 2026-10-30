# BACKLOG —— 脚本开发队列

> 状态: 2026-10-30 经用户确认全量立项（17 项，BL-001 ~ BL-017）。
> 规则: 每项在**新会话**中按 docs/PROJECT_CONTEXT.md §7 SOP 开发；完成后把状态改为 ✅ 并确认 SCRIPTS.md 已由 make docs 更新。
> 通用验收: 头部 5 tag + 函数级 `# env:` 齐全；bats 测试覆盖主路径与错误分支；三环境行为符合 §"环境" 列；系统级脚本强制 --dry-run。

## 队列总览

| ID | 脚本（路径） | 环境 | 系统级 | 批次 | 状态 |
|---|---|---|---|---|---|
| BL-001 | scripts/dev/mkscript.sh | 三环境 | 否 | 1 | ✅ |
| BL-002 | scripts/dev/git-wip.sh | 三环境 | 否 | 2 | ✅ |
| BL-003 | scripts/dev/env-dump.sh | 三环境 | 否 | 2 | ✅ |
| BL-004 | scripts/system/sysinfo.sh | ubuntu, wsl | 否 | 3 | ✅ |
| BL-005 | scripts/system/pkg-export.sh | ubuntu, wsl | 否 | 3 | ✅ |
| BL-006 | scripts/text/jsonq.sh | 三环境 | 否 | 2 | ✅ |
| BL-007 | scripts/text/log-grep.sh | 三环境 | 否 | 3 | ✅ |
| BL-008 | scripts/files/dedup.sh | 三环境 | 否 | 2 | ✅ |
| BL-009 | scripts/files/bulk-rename.sh | 三环境 | 否 | 2 | ✅ |
| BL-010 | scripts/net/port-check.sh | ubuntu, wsl | 否 | 2 | ✅ |
| BL-011 | scripts/net/http-probe.sh | 三环境 | 否 | 3 | ✅ |
| BL-012 | scripts/ops/backup-dir.sh | ubuntu, wsl | **是** | 3 | ✅ |
| BL-013 | scripts/ops/disk-alert.sh | ubuntu, wsl | 否 | 3 | ✅ |
| BL-014 | scripts/wsl/wsl-export.sh | git-bash | **是** | 4 | ✅ |
| BL-015 | scripts/wsl/clip.sh | wsl | 否 | 3 | ✅ |
| BL-016 | scripts/security/perm-audit.sh | ubuntu, wsl | **是** | 4 | 待开发 |
| BL-017 | scripts/install/bootstrap-dev.sh | ubuntu, wsl | **是** | 4 | 待开发 |

批次含义：1 = 开发基础设施（先行，后续脚手架用）；2 = 高频轻量；3 = 日常运维；4 = 系统级需谨慎测试。

## 各项功能说明

### BL-001 mkscript（scripts/dev/mkscript.sh）
新脚本脚手架生成器：`mkscript <名> <分类> [--system] [--force]`，生成符合规范的脚本骨架（shebang、5 必需 tag 预填、usage 函数、main 入口、`--dry-run` 预留【--system 时】）与配套 `test/<分类>/<名>.bats` 骨架（setup/skip_unless_env/示例用例），并打印后续 SOP 提示。已存在文件拒绝覆盖（--force 解除）。验收：生成的骨架原生通过 pre-commit 与 bats；mkscript 自身有 bats 测试。

### BL-002 git-wip（scripts/dev/git-wip.sh）
个人 git 助手：`wip [备注]`（add -A + `wip: 备注|时间戳` 提交）、`list [n]`（列最近 n 个 wip 提交）、`squash [n]`（交互合并最近 n 个 wip 为一个正式提交；默认拒绝在 main 上 squash，--force 解除）。依赖 git；非 git 目录返回明确错误。

### BL-003 env-dump（scripts/dev/env-dump.sh）
输出环境清单（默认 markdown，`--out <file>` 落盘）：bash 版本、平台/发行版（复用 lib/env.sh）、PATH 各项、常见工具实测版本（git/python3/node/go/docker/bats/shfmt/shellcheck 等，存在才列）、环境变量白名单。用途：跨机比对复现。依赖 lib/env.sh。

### BL-004 sysinfo（scripts/system/sysinfo.sh）
一次输出巡检摘要：内核/发行版、uptime 与负载、磁盘使用（df -P，超阈值标红）、内存/swap、失败的 systemd 单元（systemctl --failed，无 systemd 自动降级）、最近登录（last -n 5）。`--json` 结构化输出可选。

### BL-005 pkg-export（scripts/system/pkg-export.sh）
导出 apt 手动安装包清单（apt-mark showmanual，带时间戳落盘），`--diff <旧清单>` 输出增减；打印恢复命令提示（`xargs apt-get install`），脚本自身不安装。

### BL-006 jsonq（scripts/text/jsonq.sh）
无 jq 依赖的轻量 JSON 查询（python3 兜底）：`jsonq <file|-> <点路径表达式>`（支持数组下标）、`-t` 类型判断、`-e` 存在性退出码；非法 JSON 返回非零。

### BL-007 log-grep（scripts/text/log-grep.sh）
多文件日志过滤：`--since/--until`（相对如 10m/2h 与绝对时间）、多关键字 AND/OR 组合、默认高亮匹配、`--no-color`；时间格式宽容（ISO/常见 syslog）。

### BL-008 dedup（scripts/files/dedup.sh）
递归目录按内容找重复文件（先大小分桶再 sha256sum），按组列出；默认只列；`--delete` 逐组交互确认（y/n/a/q）；跳过空文件与符号链接。

### BL-009 bulk-rename（scripts/files/bulk-rename.sh）
批量重命名：`--prefix/--suffix/--start <序号>/--regex s/old/new/`；**默认 dry-run 打印 mv 计划**，`--apply` 执行；目标已存在即拒绝该条。

### BL-010 port-check（scripts/net/port-check.sh）
`port-check <host> <port>`：本机占用（ss -ltnp 匹配，含进程）+ 远端连通（优先 nc，退化 timeout + bash /dev/tcp）；结构化结论输出。

### BL-011 http-probe（scripts/net/http-probe.sh）
URL 健康检查（参数或 -f 文件列表）：curl 记录状态码与耗时，受控并发（默认 4），汇总表格；`--fail-only` 只显异常；退出码 = 存在异常。依赖 curl。

### BL-012 backup-dir（scripts/ops/backup-dir.sh）【系统级】
目录 tar 快照：`--dest`（默认 ~/backups）、`--keep <n>` 滚动保留；每次快照生成配套 restore.sh（对齐 test/helpers/backup_restore 语义）；**默认 dry-run 打印计划，--apply 执行**。

### BL-013 disk-alert（scripts/ops/disk-alert.sh）
df -P 使用率检查：`--warn <pct>`（默认 80）/`--crit <pct>`（默认 90），超限输出着色告警行；`--json` 供 cron/CI；退出码：crit=2、warn=1、正常=0。

### BL-014 wsl-export（scripts/wsl/wsl-export.sh）【系统级，Windows 侧执行】
包装 `wsl.exe --export`：解析 `wsl -l -v` 列发行版、校验目标盘剩余空间、导出后校验 tar 非空并追加记录清单；**默认 dry-run，--apply 执行**。usage 写明须在 Windows 侧（git bash）运行。

### BL-015 clip（scripts/wsl/clip.sh）
WSL↔Windows 剪贴板：stdin → clip.exe（复制）；无参数 → powershell.exe Get-Clipboard（粘贴）。interop 不可用时给出开启指引（wsl.conf 段说明）。

### BL-016 perm-audit（scripts/security/perm-audit.sh）【系统级】
安全巡检（默认只列不改动）：指定目录（默认 /etc /usr/local）下 world-writable 文件与目录（-perm -0002）、无主/无组文件（-nouser/-nogroup）、~/.ssh 私钥权限非 600 的检查；`--path` 自定义。

### BL-017 bootstrap-dev（scripts/install/bootstrap-dev.sh）【系统级】
幂等新机引导：`--profile min|dev` 工具清单（min: git/curl；dev: +bats/shfmt/shellcheck/make/pip 等），逐项检测→缺什么列什么；**默认 dry-run 打印计划，--apply 才安装**；提权说明按 zcode-run 约定写入 usage。
