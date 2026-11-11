# 用法：source requirements/env.sh
# 作用：把交叉工具链加入 PATH，并导出常用变量。路径按本文件位置自动推导，换机器不用改。
# 当前分发的工具链：LA32 v2.0（2023-09-03），包名 requirements/loongarch32r-linux-gnusf-2.0.tar.gz，
# 由 Git LFS 分发；与文档初版的 2022-05-20 版不同，见 README 3.0 节。
# 兼容两种目录布局（env.sh 会自动找 bin/loongarch32r-linux-gnusf-gcc）：
#   requirements/loongarch32r-linux-gnusf-*/bin/...
#   requirements/loongarch32r-linux-gnusf-*/loongson-gnu-toolchain-*/bin/...

_LA32_REQ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LA32_GCC=loongarch32r-linux-gnusf-gcc
LA32_ROOT=""

for _cand in "$_LA32_REQ_DIR"/loongarch32r-linux-gnusf*/; do
  [ -d "$_cand" ] || continue
  for _sub in "$_cand" "$_cand"*/; do
    if [ -x "${_sub}bin/$_LA32_GCC" ]; then
      LA32_ROOT="${_sub%/}"
      break 2
    fi
  done
done

if [ -z "$LA32_ROOT" ]; then
  echo "环境变量未设置：没找到工具链。" >&2
  echo "请先拉取 LFS 内容再解压（见 requirements/README.md 第 3 节）：" >&2
  echo "  git lfs pull && tar xzf requirements/loongarch32r-linux-gnusf-*.tar.gz -C requirements/" >&2
else
  case ":$PATH:" in
    *":$LA32_ROOT/bin:"*) ;;
    *) export PATH="$LA32_ROOT/bin:$PATH" ;;
  esac
  export CROSS=loongarch32r-linux-gnusf-
  echo "LA32R 工具链已就绪：$("$LA32_ROOT/bin/$_LA32_GCC" --version | head -1)"
fi

unset _LA32_REQ_DIR _LA32_GCC _cand _sub
