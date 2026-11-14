# LA32R 用户环境模板；由 bash source，复制后按本机实际情况填写。
# 首选目标：${XDG_CONFIG_HOME:-$HOME/.config}/la32r/env.sh
# 仓库级目标：requirements/local/env.sh（在用户配置之后加载）。
# 旧入口 requirements/env.local.sh 保留兼容；日常选择一个实际配置位置。
# 此模板由 Git 跟踪；实际配置保持本地。

# 外置构建根；WSL 使用发行版 ext4 路径。
export LA32R_BUILD="$HOME/build/la32r"

# 外置工具链：设为包含 bin/loongarch32r-linux-gnusf-gcc 的目录。
# 未设置时，requirements/env.sh 自动探测仓库 requirements 下的展开目录。
# export LA32_ROOT="$HOME/.local/opt/la32r/loongarch32r-linux-gnusf-2.0/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0"

# 代理按本机网络要求填写；凭据由凭据管理器或受保护的本地机制提供。
# export http_proxy="http://<proxy-host>:<port>"
# export https_proxy="$http_proxy"
