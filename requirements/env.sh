# 用法：source requirements/env.sh
# 作用：把交叉工具链加入 PATH，并导出常用变量。路径按本文件位置自动推导，换机器不用改。

_LA32_REQ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LA32_ROOT="$_LA32_REQ_DIR/loongarch32r-linux-gnusf-2022-05-20"

if [ ! -x "$LA32_ROOT/bin/loongarch32r-linux-gnusf-gcc" ]; then
  echo "环境变量已设置，但没找到工具链：$LA32_ROOT" >&2
  echo "请先按 requirements/README.md 第 3 节把工具链解压到 requirements/ 下。" >&2
else
  case ":$PATH:" in
    *":$LA32_ROOT/bin:"*) ;;
    *) export PATH="$LA32_ROOT/bin:$PATH" ;;
  esac
  export CROSS=loongarch32r-linux-gnusf-
  echo "LA32R 工具链已就绪：$("$LA32_ROOT/bin/loongarch32r-linux-gnusf-gcc" --version | head -1)"
fi

unset _LA32_REQ_DIR
