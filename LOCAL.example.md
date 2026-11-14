# 本地环境备忘（模板）

复制本文件为 `LOCAL.md` 后填写。`LOCAL.md` 已由仓库 `.gitignore` 忽略。这里只记录本机信息；团队共用的规则、依赖和构建流程进入 README、`AGENTS.md`、脚本或 `docs/`。本地与共享内容的分类说明见 [`docs/local-and-shared.md`](docs/local-and-shared.md)。

## 使用方法

```bash
cp LOCAL.example.md LOCAL.md
# Windows PowerShell 7: Copy-Item -LiteralPath LOCAL.example.md -Destination LOCAL.md
```

本机环境记录从根 `LOCAL.md` 导航，详细版本、路径和验证信息放在被忽略的 `requirements/local/README.md`。环境变量配置只选一个日常位置：XDG 用户配置目录 `${XDG_CONFIG_HOME:-$HOME/.config}/la32r/env.sh`，或项目本地目录 `requirements/local/env.sh`。旧路径 `requirements/env.local.sh` 仍兼容并最后加载；不建议与前两种同时维护。

以下复制步骤用于首次配置；目标已有内容时，合并所需字段并保留本机现值。

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/la32r"
cp requirements/env.example.sh "${XDG_CONFIG_HOME:-$HOME/.config}/la32r/env.sh"
# 或者：mkdir -p requirements/local && cp requirements/env.example.sh requirements/local/env.sh
```

[`requirements/env.example.sh`](requirements/env.example.sh) 是纯模板，不会被自动加载；其中外置工具链与代理项是注释占位，构建根使用 `$HOME/build/la32r` 的通用示例。复制后只填写当前机器需要的变量，不要把凭据写入本文件、模板或仓库。

实际加载顺序为 XDG `env.sh` → `requirements/local/env.sh` → 兼容路径 `requirements/env.local.sh`，后者优先级最高。`Makefile.local` 虽被忽略，当前 Makefile 并未加载它。现有 XDG 配置保持原位置，无需迁移。

## 建议记录

| 小节 | 建议内容 |
| --- | --- |
| 系统 | 操作系统/发行版与版本、CPU、内存 |
| 仓库路径 | Windows、WSL 或容器中的路径映射 |
| 工具版本 | 编译器、Python、Verilator、GTKWave、交叉工具链版本 |
| 存储位置 | 工具链副本和构建目录的位置，例如 `$HOME/.local/opt/`、`$HOME/build/la32r/` |
| 网络 | 是否需要代理、使用的非敏感镜像信息 |
| 已知问题 | 本机特有的挂载、权限、GUI 或工具版本问题 |
| 待办 | 尚未完成的本机配置 |

## 提交前检查

```bash
git check-ignore -v LOCAL.md
git status --short
python3 tools/check-local-isolation.py
```

隔离检查只核对约定的本地路径忽略、共享路径可跟踪性和已跟踪忽略文件，不检查凭据内容。若发现个人配置进入暂存区，先从暂存区移除并核对 `.gitignore` 规则。
