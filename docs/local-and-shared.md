# 本地环境与协作内容的边界

本约定用于判断一项内容应放在仓库、个人环境还是临时交付目录。每个开发阶段都沿用这些分类；环境搭建阶段集中记录机器路径、工具版本、代理需求和外置目录，后续只在本地环境或配置变化时更新这些记录。团队共同需要的事实和步骤进入仓库文档、依赖声明或脚本。

## 按用途归属

| 内容 | 归属与做法 |
| --- | --- |
| RTL、testbench、约束、构建入口及团队验证脚本 | 团队源码，提交到 `soc/`、`sim/`、`tools/` 等对应目录。可复现的团队流程写入 README 或脚本。 |
| FPGA 工程输入与 IP 配置 | 共享引脚/时序约束、重建工程的 Tcl、必要的 IP 配置及工具版本要求。Vivado 的缓存、综合/实现运行目录、机器专属路径保持本地；依赖的授权资料按授权范围管理。 |
| 依赖声明与环境检查 | 团队约定，提交依赖清单、版本约束和检查/安装脚本。个人安装位置留在本地。 |
| 工具链原始分发包 | 团队共享的可复现输入；本项目的交叉工具链 tarball 通过 Git LFS 跟踪。 |
| 工具链展开目录、虚拟环境、缓存 | 机器生成或下载的本地副本，不提交。展开的工具链可放 `$HOME/.local/opt/`，Python 虚拟环境可放项目 `.venv/`；运行缓存按工具约定存入 XDG cache。 |
| 模板与通用样例 | 可供队友复用的无机器信息模板提交到仓库。本地配置从模板复制后放入个人配置位置；不得把个人路径、代理端点或凭据填回模板。 |
| 仿真波形、Vivado 运行目录和其他可重建产物 | 本地生成物。使用 `.gitignore` 已列出的忽略规则，或放到仓库外构建目录。 |
| 黄金测试输入、参考图与回归预期 | 经审阅的团队测试资产，保存产生方法、来源与预期。二进制/hex 等后缀可能命中通用忽略规则，应为选定的测试资产目录制定精确例外，再核对可跟踪性。 |
| `outputs/` 中的当前交付 | 本地待审阅交付，根目录 `outputs/` 当前按本项目约定忽略。审阅并确认需要长期协作后，将适当的文档或源文件整理到 `docs/`；发布产物按团队选定的发布渠道交付。 |
| 机器路径、代理需求、工具版本与本机故障记录 | 根 `LOCAL.md` 提供本机导航，详细记录放入被忽略的 `requirements/local/README.md` 和用户配置。凭据使用个人安全存储；不要进入仓库、模板、日志或提交记录。 |

按阶段持续应用上述归属。代码、文档和交付进入下一阶段时，仍检查其中的路径、凭据、生成物和团队复现信息；环境阶段汇总一次选择，后续按差异维护。

## 本项目目录规划

| 位置 | 保存内容 |
| --- | --- |
| `soc/`、`sw/`、`sim/`、`ref/`、`tools/` | 团队源码、验证代码、参考实现与可复现工具 |
| `docs/`、各级 README、`AGENTS.md` | 维护中的团队设计、流程和规则 |
| `requirements/` | 团队环境入口、检查/安装脚本、通用模板和 LFS 工具链归档；本地解压目录与整个 `requirements/local/` 由忽略规则管理 |
| `.codex/file-management/project.json` | 使用 Codex 本地文件管理时可按需保留的本机参数；它不构成团队工具要求 |
| `requirements/local/README.md`、`LOCAL.md`、用户配置目录 | 本机环境记录、导航、工具路径、外置构建根和个人选项 |
| `$HOME/.local/opt/la32r/` | 本项目选择的用户级工具链安装位置；XDG 规范未规定该 opt 路径 |
| `$HOME/build/la32r/` | 本项目选择的外置构建根，含 smoke 与 vga 子目录；通过 LA32R_BUILD 设置 |
| `.codex/file-management/work/`、`outputs/` | 可选的本地过程记录与待审阅交付；团队不依赖 Codex 文件管理工具 |
| `.vscode/`、`.codebuddy/` | 当前按本地工具实例忽略；共享编辑器设置应逐项审阅后另行纳入，不开放整个个人目录 |

以上目录按需要创建。Python 虚拟环境也可置于仓库外的个人目录；WSL 本机的实际 VHDX 位置和路径映射记录在 `requirements/local/README.md`。

环境配置本身同时包含团队与个人两类内容：安装步骤、依赖/工具链版本要求、检查脚本和通用配置项供团队共同维护；安装实例、具体路径、代理和凭据由个人环境管理。开发阶段继续共享新增依赖、测试输入和构建要求，并将日常运行产物放到构建目录。现有依赖脚本安装发行版提供的版本，严格固定版本或 CI 环境可在团队确定复现要求后补充。

## 忽略规则的作用范围

Git 的忽略规则适用于未跟踪文件，按规则来源及目录层级共同决定。仓库根目录及子目录中的 `.gitignore` 适合记录团队共享的忽略约定；`.git/info/exclude` 只影响当前克隆；`core.excludesFile` 指定的全局忽略文件只影响当前用户的所有仓库。更具体的目录规则可覆盖较高目录中的匹配；同一文件内后出现的匹配规则可调整先前规则。完整匹配语义见 [Git ignore 文档](https://git-scm.com/docs/gitignore)。

```bash
git check-ignore -v path/to/file   # 查看命中的文件、行号和规则
git status --short --ignored       # 同时查看普通状态与被忽略对象
python3 tools/check-local-isolation.py
```

忽略规则不会让已跟踪文件自动变成本地文件。团队文件应由仓库规则管理；只属于某个克隆或用户的杂项分别放 `.git/info/exclude` 或全局忽略文件。添加共享规则前检查其范围，避免把未来团队源码、约束或模板一起排除。隔离检查脚本只核对列出的本地路径是否忽略、共享路径是否可跟踪及已跟踪忽略项，不读取或扫描凭据内容。

本项目的 `.gitignore` 已包含构建目录、Vivado 生成目录、`.venv/`、解压工具链目录、smoke 对象目录、波形、`LOCAL.md`、`requirements/local/`、`*.local.*`、`.codebuddy/` 与 `outputs/` 等规则，并精确忽略本机文件管理参数和过程目录。`.vscode/` 保持本地；个人额外规则仍可放 `.git/info/exclude`。具体命中项以当前文件和 `git check-ignore -v` 输出为准。

## 个人配置与 XDG 目录

Linux/WSL 用户配置优先留在发行版的个人目录。XDG Base Directory 规范分别定义配置、状态和缓存位置：通常为 `~/.config`、`~/.local/state` 和 `~/.cache`；由 `XDG_CONFIG_HOME`、`XDG_STATE_HOME`、`XDG_CACHE_HOME` 指定自定义根目录。用途和默认值见[官方规范](https://specifications.freedesktop.org/basedir/latest/)。本项目沿用此规范的目录划分，`la32r` 子目录及其中变量是项目约定。

团队依赖契约要求 Linux x86_64 交叉工具链宿主、Verilator 5 或更高版本、C/C++ 编译器与 make、Python 3/Pillow、Git LFS 和 GTKWave。实际主机、工具版本与验证结果记入 `requirements/local/README.md`，不固化在共享安装指南顶部。

`requirements/env.sh` 会自动探测 `requirements/loongarch32r-linux-gnusf*/` 下的已展开工具链，然后依序读取这些可选本机配置：

1. `${XDG_CONFIG_HOME:-$HOME/.config}/la32r/env.sh`
2. `requirements/local/env.sh`
3. `requirements/env.local.sh`（旧路径兼容，最后加载）

日常只选择一个位置维护变量；三个文件都存在时，后加载者会覆盖同名变量。旧 XDG 配置保持原位置，无需迁移。模板 [`requirements/env.example.sh`](../requirements/env.example.sh) 不会自动加载，应复制到选定位置后编辑。`Makefile.local` 虽被忽略，当前 Makefile 没有加载它；忽略规则只控制 Git 状态，不会自动执行配置文件。

根 `LOCAL.md` 是本机导航，详细环境记录位于被忽略的 `requirements/local/README.md`。模板中的外置工具链和代理配置为注释占位，不产生默认配置。工具链副本可放在 `$HOME/.local/opt/`；构建产物可通过 `LA32R_BUILD="$HOME/build/la32r"` 指向发行版文件系统。WSL 下按实际挂载情况选择 ext4 位置，个人绝对路径只保存在本机配置。

Python venv 是项目依赖的隔离安装目录，可按[官方 `venv` 文档](https://docs.python.org/3/library/venv.html)创建；本项目按 `.gitignore` 约定将 `.venv/` 保持为本地环境。团队依赖声明与本地安装结果分开管理：共享依赖声明进入仓库，解释器环境目录不提交。

## 本地记录与交付提升

将 [`LOCAL.example.md`](../LOCAL.example.md) 复制为根目录 `LOCAL.md`，作为本机记录的导航；具体机器、工具版本、路径映射和验证信息位于被忽略的 `requirements/local/README.md`。环境变量从 [`requirements/env.example.sh`](../requirements/env.example.sh) 复制到选定配置位置，避免模板间出现不一致的配置样例。

`outputs/` 可用于保存当前任务的本地交付，供审阅和迭代。确认内容适合长期协作后，整理其可维护源文件、必要说明和来源信息，再提升到 `docs/` 或团队明确的发布渠道；不要把临时中间文件直接当作共享文档。
