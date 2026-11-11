# LA32R-SoC 项目规则

> 本文件是项目的统一约定，**人和 AI 协作者都适用**。新增规则请追加到对应小节，
> 保持「现象 → 规则 → 做法」三段式，写清可直接复制的命令。
>
> 团队环境：Windows 10/11（**PowerShell 7**）+ Linux（Ubuntu 22.04/24.04，或 WSL2 Ubuntu），
> 混合协作。跨平台相关的问题**优先在仓库层解决**（`.gitattributes` / 脚本），不要靠口头约定。

---

## 1. PowerShell 调用规则（强制）

- 只用 **PowerShell 7**，固定绝对路径 `C:\Program Files\PowerShell\7\pwsh.exe`；
  禁止 `powershell` / `powershell.exe` / 裸 `pwsh`，也不得为"选最新版"去做 PATH 扫描或注册表查询。
- 带空格的路径必须用调用运算符 `&`：`& 'C:\Program Files\PowerShell\7\pwsh.exe' -File x.ps1`。
- 每个进程内先固定 UTF-8：
  ```powershell
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  $OutputEncoding = [System.Text.Encoding]::UTF8
  ```
  文件读写显式 `-Encoding utf8`；已知路径用 `-LiteralPath`（避免 `[` `]` 被当通配符）。
- 复杂、多行、含大量引号的命令写进受控 `.ps1`，用 `-File` 执行，不要层层嵌套 `-Command`。
- 执行后**同时**检查 PowerShell 错误和原生命令的 `$LASTEXITCODE`（pwsh 不会因为 exe 返回非 0 就报错）。

---

## 2. 跨平台差异速查表

| 类别 | Windows / PowerShell | Linux / bash | 本项目做法 |
| --- | --- | --- | --- |
| 换行符 | CRLF（`\r\n`） | LF（`\n`） | 仓库内**一律 LF**，`.gitattributes` 强制（见第 3 节） |
| 可执行位 | NTFS 无 x 位，`core.filemode=false` | 有 `rwx` 位 | 入库用 `git update-index --chmod=+x`；大二进制用 tar 包（见第 4 节） |
| 路径分隔符 | `\`（也接受 `/`） | `/` | 脚本内用 `/`；跨 shell 传路径用 `wslpath` |
| 大小写 | 不区分（`core.ignorecase=true`） | 区分 | 文件名与 `include` 全小写（见第 5 节） |
| 非法文件名字符 | `: * ? " < > \|`、`CON/PRN/AUX/NUL/COM1-9`、结尾空格/点 | 基本都允许 | 文件名只用 `[A-Za-z0-9._-]` |
| 路径长度上限 | 260（需显式开启长路径） | ≈4096 | 目录层级别太深 |
| 软链接 | 需开发者模式/管理员，`core.symlinks=false` | 原生支持 | 仓库内不放 symlink |
| 文件编码 | GBK/UTF-16 常见 | UTF-8 | 源码统一 **UTF-8 无 BOM**（见第 6 节） |
| 环境变量引用 | `$env:FOO` | `$FOO` / `export FOO=` | 脚本各自写，别互相抄 |
| PATH 分隔符 | `;` | `:` | 不在跨平台脚本里硬编码 PATH 拼接 |
| 引号/转义 | `'`不插值、`"`插值，转义符是反引号 | `'`不插值、`"`插值，转义符是 `\` | 简单命令外层用单引号 |
| 行继续 | 反引号（易错，建议避免） | `\` | 长命令优先写 `.ps1` / `.sh` 文件 |
| 退出码 | `$LASTEXITCODE` / `$?` | `$?` | bash 脚本 `set -euo pipefail` |
| 管道 | 传**对象** | 传**文本** | `Select-String` ↔ `grep`，`Measure-Object` ↔ `wc -l` |
| 脚本互调 | `.ps1` 用 `pwsh -File` | `.sh` 用 `bash` | `.sh` **不能**直接双击/在 pwsh 里跑 |
| 默认 shell | pwsh | bash | CI / 文档命令标明所属 shell |

---

## 3. 换行符：CRLF vs LF

### 现象

- `bash: $'\r': command not found`、`/usr/bin/env: 'bash\r': No such file or directory`
- `Makefile:12: *** missing separator. Stop.`（行尾多了 `\r`）
- `git diff` 一改就是整文件全红，review 没法看
- Windows 编辑器打开脚本显示 `bash^M`
- Python 在 Windows 上 `print()` 重定向生成的文件是 CRLF，`.mem` / `.hex` 被 `$readmemh` 读错或报错

### 规则

1. **仓库里只存 LF**，由 `.gitattributes` 决定，不依赖个人 `core.autocrlf`。
2. 二进制文件显式 `binary`，防止被当文本转换。
3. 新增文本类型（如 `*.tcl`、`*.xdc`、`*.do`）要顺手加进 `.gitattributes`。

现状（`.gitattributes`）：

```
* text=auto                     # 默认：入库规范化成 LF
*.v *.sv *.vh *.svh            text eol=lf
*.c *.h *.S *.ld               text eol=lf
*.md *.py *.sh  Makefile       text eol=lf
*.png *.jpg *.drawio *.pdf *.bit *.dcp   binary
requirements/*.tar.gz          filter=lfs diff=lfs merge=lfs -text
```

### `core.autocrlf` 三档（本机当前是 `true`）

| 取值 | 检出到工作区 | 提交时 | 说明 |
| --- | --- | --- | --- |
| `true` | LF → CRLF | CRLF → LF | Windows 默认；仓库仍存 LF，但工作区全是 CRLF |
| `input` | 不转换（保持 LF） | CRLF → LF | **Windows 上推荐**，配合 `.gitattributes` |
| `false` | 不转换 | 不转换 | Linux 默认 |

`.gitattributes` 的优先级**高于** `core.autocrlf`，所以有了规则就不怕个人配置不一致。

### 处理命令

```powershell
# pwsh：单文件转 LF（不写 BOM）
$p = 'requirements/env.sh'
$t = [IO.File]::ReadAllText($p) -replace "`r`n", "`n"
[IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($false))
```

```bash
# bash
sed -i 's/\r$//' requirements/env.sh      # 或 dos2unix requirements/env.sh
git add --renormalize .                    # 规则改动后统一重刷一遍
git ls-files --eol | grep crlf             # 检查有没有漏网的 CRLF
git diff --check                           # 检查行尾空白/CR
```

编辑器侧：VS Code 设 `"files.eol": "\n"`、`"files.insertFinalNewline": true`。

---

## 4. 文件权限：可执行位与软链接

### 现象

- Linux 上 `./tools/build.sh` → `Permission denied`，Windows 上一切正常
- `git status` 显示莫名修改（filemode 抖动）
- 工具链 / 脚本在 Linux 拉下来后没法执行，得手动 `chmod -R +x`

### 规则

1. 需要执行的脚本、二进制，**入库模式必须是 `100755`**；`git add` 在 Windows 上写不出该位。
2. 大体积二进制分发用 **tar 包**（归档内保存权限），不要展开提交（本项目工具链即如此）。
3. 仓库内不放软链接（`core.symlinks=false` 时会被检出成内容为路径的普通文本文件，Linux 侧再提交会污染仓库）。

### 做法

```bash
git update-index --chmod=+x tools/build.sh   # 显式标可执行
git ls-files -s tools/build.sh               # 核对：100755 hash 0  path
git ls-files -s | grep '^100644' | grep -E '\.(sh|ps1)$'   # 找出漏标的脚本
```

**坑**：在 WSL 里对 `/mnt/f/...`（drvfs）执行 `chmod` 是**无效**的，别指望这样修权限；
权限只能靠 git 索引里的 mode，或在 ext4 上操作。

---

## 5. 路径与文件名

| 问题 | 现象 | 做法 |
| --- | --- | --- |
| 大小写不敏感 | Windows 上 `include "Top.v"` 能找到 `top.v`，Linux 报 `No such file` | 文件名、`include`、`` `include ``、Makefile 里的依赖全小写 |
| 反斜杠 | bash 里 `\` 是转义符，`dir\file` 变成 `dirfile` | 脚本内一律 `/`；pwsh 传给原生工具也优先 `/` |
| WSL 路径映射 | `F:\CursorProject\X` 与 `/mnt/f/CursorProject/X` 是同一份 | `wslpath -u 'F:\CursorProject\X'` / `wslpath -w /mnt/f/...` |
| 空格路径 | `C:\Program Files\...` 被拆成两段 | pwsh 用 `& '...'`，bash 用引号 |
| 非法字符 | Linux 上创作的文件名在 Windows 上 `git checkout` 直接失败 | 只用 `[A-Za-z0-9._-]`，禁用 `: * ? " < > \|` |
| 保留名 | 名为 `CON`、`AUX`、`NUL` 的文件 Windows 建不出来 | 同上，靠命名规范规避 |
| 路径长度 | Windows 260 上限，深层 `obj_dir` 报路径过长 | 目录别太深；必要时开 `LongPathsEnabled` |

**不要**在脚本里硬编码某台机器的绝对路径。`requirements/env.sh`、`requirements/setup-deps.sh`
都按脚本自身位置推导路径，就是为了换机器/换平台不用改。

---

## 6. 文件编码

### 规则

1. 所有源码与文档：**UTF-8 无 BOM**，LF。
2. Windows 下固定 `pwsh 7`（默认 UTF-8）；**禁用 Windows PowerShell 5.1**（默认 UTF-16LE / GBK 代码页，中文必乱码）。
3. 不要用 GBK 保存任何进仓库的文件（中文注释在 Linux 上是乱码）。
4. BOM 的具体危害：`#!/bin/bash` 变成 `\xef\xbb\xbf#!/bin/bash` → `bad interpreter`；
   部分 Makefile / 脚本解析器与老工具链会把 BOM 当正文，报 `stray '\357'`。

### 检查

```bash
# 找出带 BOM 的文件（bash）
grep -rlI $'\xef\xbb\xbf' --include='*.v' --include='*.c' --include='*.sh' .
```

```powershell
# pwsh 检查前 3 字节是否为 EF BB BF
Get-ChildItem -Recurse -Include *.v,*.c,*.sh | ForEach-Object {
  $b = [IO.File]::ReadAllBytes($_.FullName)[0..2]
  if ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $_.FullName }
}
```

终端中文乱码时（Windows 控制台）：`chcp 65001`；WSL 里默认已是 UTF-8。

---

## 7. shell 语法对照（写脚本时最容易踩）

| 目的 | pwsh 7 | bash |
| --- | --- | --- |
| 变量赋值 | `$x = 1` | `x=1`（等号两边不能有空格） |
| 读环境变量 | `$env:FOO` | `$FOO` |
| 设环境变量 | `$env:FOO = 'v'` | `export FOO=v` |
| 命令输出到变量 | `$o = git rev-parse HEAD` | `o=$(git rev-parse HEAD)` |
| 判断命令成败 | `if ($LASTEXITCODE -eq 0)` | `if cmd; then ... fi` |
| 严格模式 | `Set-StrictMode -Version Latest`、`$ErrorActionPreference='Stop'` | `set -euo pipefail` |
| 循环文件 | `Get-ChildItem *.v \| ForEach-Object { ... }` | `for f in *.v; do ...; done` |
| 文本匹配 | `Select-String -Pattern 'x'` | `grep -n 'x'` |
| 判空 | `if ([string]::IsNullOrEmpty($s))` | `if [ -z "$s" ]` |
| 数字比较 | `-lt -gt -eq` | `-lt -gt -eq`（`[[ ]]`）或 `-lt` |
| 删除 | `Remove-Item -LiteralPath x -Force` | `rm -f x` |

**互调**：`.sh` 只能由 `bash` 执行（WSL / Git Bash / Linux）；
`.ps1` 只能由 `pwsh -File` 执行。shebang 在 Windows 上被忽略，
所以 `.sh` 不要指望在 Windows 原生环境里跑起来（本项目统一在 WSL2 里跑构建与仿真）。

---

## 8. 构建与产物

| 坑 | 现象 | 做法 |
| --- | --- | --- |
| Makefile 必须 Tab 缩进 | `*** missing separator` | 编辑器对 `Makefile` 关掉"空格转 Tab"；VS Code 设 `[makefile] indent_style=tab` |
| `.mem` / `.hex` 换行 | `$readmemh` 解析异常或数值错 | 生成时强制 LF：Python `open(p,'w',newline='\n')`，或生成后 `sed -i 's/\r$//'` |
| 二进制产物入库 | 仓库膨胀、diff 无意义 | `.gitignore` 已排除 `*.bin/*.elf/*.hex/build/out/obj_dir/`，不要 `git add -f` |
| 产物跨平台复用 | Windows 上跑不了 Linux 编的 `obj_dir` 可执行文件 | 各平台各自 `make clean && make` |
| 文件被占用 | Windows 上 `make clean` 删不掉 `obj_dir`，报 `being used by another process` | 先关掉 GTKWave / 仿真进程再删 |
| 行尾影响 diff | 全文件变化 | 见第 3 节 |

---

## 9. Git 配置与协作

### 本机现状（Windows）

```
core.autocrlf = true      # 工作区 CRLF；仓库仍是 LF（由 .gitattributes 保证）
core.filemode = false     # 写不出可执行位
core.symlinks = false     # 软链接降级为普通文件
core.ignorecase = true    # 文件名大小写不敏感
```

建议 Windows 开发者执行（不影响他人、不改变仓库内容）：

```bash
git config core.autocrlf input     # 与 .gitattributes 配合，减少无谓转换
git config core.quotepath false    # 中文路径正常显示，不再 \344\275\240
```

### 规则

1. **新文件类型先想换行与二进制属性**，再提交。
2. 大文件（>10 MB 或二进制分发）走 **Git LFS**；LFS **不保存可执行位**，
   所以整个工具链打成 tar.gz（见 `requirements/README.md` 9.4）。
3. 跨平台协作改 `.gitattributes` 后，必须 `git add --renormalize .` 并单独提交，
   否则每个人的工作区状态不一致。
4. 提交前跑一遍自检（见第 10 节）。

---

## 10. 提交前自检清单

```bash
# 1) 有没有 CRLF 混进索引
git ls-files --eol | grep -i crlf

# 2) 有没有该可执行却存成 100644 的脚本
git ls-files -s | grep -E '\.(sh)$' | grep '^100644'

# 3) 行尾空白 / 混合换行
git diff --check

# 4) 有没有误加产物（应为空）
git status --short | grep -E '\.(bin|elf|hex|o|dcp|bit)$'

# 5) 中文路径是否正常
git status --short
```

```powershell
# pwsh 等价写法
git ls-files --eol | Select-String 'crlf'
git ls-files -s   | Select-String '\.sh$' | Select-String '^100644'
git diff --check
git status --short
```

---

## 11. WSL 与 Windows 混用的注意事项

1. **仓库放哪**：放 Windows 盘（`/mnt/f/...`）时 drvfs 不支持 Linux 权限位、
   IO 慢 3–10 倍、`inotify` 不可靠（`make` / Verilator 的文件监视会失效）。
   在 WSL 里做构建时，建议仓库放 `~/`（ext4），Windows 侧用 `\\wsl$\Ubuntu\home\...` 打开。
2. **`chmod` 无效**：WSL 用 **DrvFs（9p 协议）** 挂载 Windows 盘到 `/mnt/x`，NTFS 没有 POSIX 权限位，
   默认不启用 `metadata`，所以文件恒为 `0777`、`chmod` 无效、`core.filemode` 形同虚设。
   **可以修**，见 11.2。
3. **两侧同时 git**：同一仓库在 Windows 与 WSL 各跑一次 git 没问题，但
   `core.filemode` / `core.autocrlf` 会因所在文件系统不同而被 git 自动改写，注意别把这类差异提交上去。
4. **脚本执行**：WSL 里跑 `bash requirements/setup-deps.sh`；Windows 侧跑
   `& 'C:\Program Files\PowerShell\7\pwsh.exe' -File xxx.ps1`。两套脚本各自维护，不互相调用。
5. **换行**：用 Windows 编辑器改过 `requirements/*.sh` 后，务必确认仍是 LF
   （`git diff` 里不应出现整文件重写）。

---

### 11.1 为什么 `/mnt` 上"很多功能无效"

| 表现 | 根因 | 能否修 |
| --- | --- | --- |
| `chmod` 无效、`filemode` 判断错 | DrvFs 默认不保存 Linux 权限（未开 `metadata`） | ✅ 开 `metadata`（11.2） |
| IO 慢 3–10 倍、`git status` / `make` 卡 | 每次文件操作走 9p RPC（`msize=65536`），无本地页缓存 | ❌ 只能把热数据放 ext4 |
| `inotify` 监视不触发 | 9p 不透传 inotify 事件 | ❌ 同上（`make` 不靠它，IDE 热重载会失效） |
| 文件名大小写跟随 NTFS | NTFS 不区分大小写 | ⚠️ 可设 `case=force`，但会让 Windows 侧混乱，不建议 |
| 符号链接 / 硬链接异常 | DrvFs 对二者支持有限 | ❌ 别在 Windows 盘上建 |

结论：`/mnt/x` 只适合**存放源码**，不适合放"需要 Linux 语义"的东西（权限、监视、高 IO 的构建目录）。

### 11.2 开启 metadata 让权限生效

在**发行版内部**（文件位于 VHDX，物理路径形如 `F:\WSL\<distro>`）编辑 `/etc/wsl.conf`：

```ini
[automount]
enabled = true
options = "metadata,umask=22,fmask=11"
```

然后在 **Windows 侧**重启该发行版（`wsl.conf` 按发行版生效，约 8 秒后配置才加载）：

```powershell
wsl --terminate Ubuntu-26.04
```

校验：`wsl -e bash -lc "findmnt -no OPTIONS /mnt/f | tr ',' '\n' | grep metadata"`。

注意：

- `metadata` 会往 NTFS 写扩展属性，个别备份/同步工具会丢；
- `[automount] options` 对**所有**自动挂载的 Windows 盘生效；只对某个盘生效请改用 `/etc/fstab`；
- 开启后建议**重新解压一次工具链**，让归档里的 `0755` 落到文件上
  （`tar xzf requirements/loongarch32r-linux-gnusf-2.0.tar.gz -C requirements/`）。

### 11.3 `.wslconfig` 的位置改不了，配置放哪

`%USERPROFILE%\.wslconfig` 是 WSL 硬编码的全局配置，**没有环境变量可以重定向**（微软文档未提供该机制）。
故约定：

| 配置 | 放哪 | 说明 |
| --- | --- | --- |
| 全局 VM 设置（网络/内存/swap） | `%USERPROFILE%\.wslconfig` | 只能在这里；保持最小化 |
| 发行版设置（automount/interop/user） | `/etc/wsl.conf` | 在 VHDX 内，`wsl --terminate` 生效 |
| 本机工具链/代理/构建目录覆盖 | `~/.config/la32r/env.sh` | 由 `requirements/env.sh` 自动 source |
| shell 启动项 | `~/.bashrc` | 只写 `source .../requirements/env.sh` 这类引用 |
| 构建产物（obj_dir 等） | `~/build/la32r/`（ext4） | 别放 `/mnt`，见 11.1 |

以上除 `.wslconfig` 外**全部位于发行版内部**，物理上都在 `F:\WSL\<distro>` 的 VHDX 中，
**不会落进工程目录**，也不会进 git。

---

## 12. 协作文件 vs 本地个性化文件

原则：**对所有人成立的内容进仓库，只对你这台机器成立的内容留在本地。**

| 文件 / 模式 | 归属 | 说明 |
| --- | --- | --- |
| `README.md`、`AGENTS.md`、`docs/**` | 协作（提交） | 全体适用的流程与规范 |
| `requirements/README.md`、`env.sh`、`setup-deps.sh` | 协作（提交） | 路径全部按脚本自身位置推导，不写死机器 |
| `.gitattributes`、`.gitignore` | 协作（提交） | 跨平台行为的唯一权威来源 |
| `LOCAL.example.md` | 协作（提交） | 本地备忘的**模板**，只放字段与用法 |
| `LOCAL.md` | **本地（忽略）** | 你自己的版本、路径、代理、磁盘位置，**禁止提交** |
| `*.local.*`（`requirements/env.local.sh`、`Makefile.local`、`*.local.v`） | **本地（忽略）** | 机器相关覆盖项，由 `env.sh` 按需 source |
| `~/.config/la32r/env.sh` | **本地（仓库外）** | WSL/Linux 侧覆盖的**首选**位置，在发行版内部（VHDX 在 `F:\WSL`），不落工程目录 |
| `.venv/`、`.vscode/`、`obj_dir/`、`*.vcd` | **本地（忽略）** | 工具链/IDE/仿真生成物 |
| `requirements/loongarch32r-linux-gnusf*/` | **本地（忽略）** | 解压出来的工具链（压缩包本身走 LFS，必须提交） |

### 规则

1. 新机器上手：`cp LOCAL.example.md LOCAL.md`（Windows 用 `Copy-Item`），填完再开始干活。
2. 发现"这条规则只对我有效"时，**不要改** `README.md` / `AGENTS.md`，写进 `LOCAL.md`。
3. 反过来，需要所有人生效的改动，**必须**进 `.gitattributes` / `.gitignore` / 脚本，不能只写在自己本地。
4. 任何带**凭据、内网地址、个人绝对路径、机器名**的内容（token、代理口令、`C:\Users\你的名字\...`）
   一律只写 `LOCAL.md` 或 `env.local.sh`。
5. 提交前确认：`git check-ignore -v LOCAL.md` 有命中，`git status --short` 里不出现上面标"本地"的路径。
