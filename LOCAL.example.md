# 本地环境备忘（模板）

> **复制本文件为 `LOCAL.md` 后填写。** `LOCAL.md` 已被 `.gitignore` 忽略，**不会上传**。
>
> 为什么要分：协作内容（构建流程、脚本、目录约定）对所有人生效，写进 `README.md` / `AGENTS.md`；
> 而**只对你这台机器成立**的东西（发行版版本、安装路径、代理地址、磁盘位置、个人副本位置）
> 写在这里。这样既不会污染共享文档、让新人照抄别人的路径，也不会把个人环境泄露到仓库。

## 使用方法

```bash
cp LOCAL.example.md LOCAL.md          # Windows: Copy-Item LOCAL.example.md LOCAL.md
```

机器相关的环境变量另建 **`requirements/env.local.sh`**（被 `.gitignore` 的 `*.local.*` 覆盖），
`requirements/env.sh` 末尾会自动 source 它（若存在）：

```bash
# requirements/env.local.sh 示例
# 工具链指向你自己的副本（不填则由 env.sh 自动探测 requirements/loongarch32r-linux-gnusf*/bin）
export LA32_ROOT="$HOME/LA32R-SoC/requirements/loongarch32r-linux-gnusf-2.0/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0"

# 本机代理（仅在被墙的机器上需要）
export http_proxy=http://127.0.0.1:10808
export https_proxy=$http_proxy
```

同样被忽略的本地文件还有：`Makefile.local`、`*.local.v`、`*.local.sh` 等（匹配 `*.local.*`）。

## 建议填写的字段

| 小节 | 建议内容 |
| --- | --- |
| 机器 | 操作系统与版本、CPU/内存、磁盘位置（例如 WSL 的 VHDX 放在哪个盘） |
| 仓库路径 | Windows 路径 ⇔ WSL/容器内路径的对应关系 |
| 工具版本 | 编译器、python、verilator、gtkwave、交叉工具链的实际版本与安装位置 |
| 网络 | 代理地址、镜像源、是否需要走隧道 |
| 已知问题 | 本机特有的坑（例如某挂载点 noexec、某版本 verilator 编译慢） |
| 待办 | 还没装完的东西 |

## 什么不该写进这里

- 团队都要遵守的规则 → 写 `AGENTS.md`
- 构建/仿真流程 → 写 `requirements/README.md`
- 需要所有人生效的配置 → 写 `.gitattributes` / `.gitignore` / 脚本

## 提交前自检

```bash
git check-ignore -v LOCAL.md            # 必须命中，说明不会被提交
git status --short                      # 不应出现 LOCAL.md / *.local.* / .venv
```
