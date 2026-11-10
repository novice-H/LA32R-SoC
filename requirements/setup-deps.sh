#!/usr/bin/env bash
# 一键准备 LA32R / Verilator 开发环境（面向全新 Linux）
#
#   bash requirements/setup-deps.sh           # 安装依赖并检查
#   bash requirements/setup-deps.sh --check   # 只检查，不安装
#
# 支持 Ubuntu/Debian(apt)、Fedora(dnf)、Arch(pacman)；其他发行版请按第 2 节手动装。
set -uo pipefail

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN="$DIR/loongarch32r-linux-gnusf-2022-05-20"
OK=0
FAIL=0

say()  { printf '%s\n' "$*"; }
pass() { printf '  [OK]   %s\n' "$*"; OK=$((OK+1)); }
fail() { printf '  [缺失] %s\n' "$*"; FAIL=$((FAIL+1)); }

detect_pm() {
  for pm in apt-get dnf pacman zypper; do
    command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return; }
  done
  echo "unknown"
}

install_deps() {
  local pm; pm="$(detect_pm)"
  case "$pm" in
    apt-get) sudo apt-get update && sudo apt-get install -y build-essential git python3 ca-certificates verilator gtkwave ;;
    dnf)     sudo dnf install -y gcc gcc-c++ make git python3 verilator gtkwave ;;
    pacman)  sudo pacman -S --needed --noconfirm base-devel git python verilator gtkwave ;;
    zypper)  sudo zypper install -y gcc gcc-c++ make git python3 verilator gtkwave ;;
    *) say "未知包管理器，请手动安装：gcc g++ make git python3 verilator gtkwave"; return 1 ;;
  esac
}

if [ "$CHECK_ONLY" -eq 0 ]; then
  say "== 1/2 安装系统依赖 =="
  install_deps || true
else
  say "== 1/2 检查系统依赖（--check 模式，不安装）=="
fi

say ""
say "== 2/2 检查工具是否可用 =="

check_cmd() {  # name, 最低要求描述
  if command -v "$1" >/dev/null 2>&1; then
    local v; v="$($1 --version 2>/dev/null | head -1)"
    pass "$1  $v"
  else
    fail "$1  （未安装）"
  fi
}

check_cmd gcc
check_cmd g++
check_cmd make
check_cmd git
check_cmd python3

if command -v verilator >/dev/null 2>&1; then
  v="$(verilator --version 2>/dev/null | awk '{print $2}')"
  pass "verilator  $v"
  major="${v%%.*}"; minor="$(( ${v#*.} / 100 ))"
  if [ "${major:-0}" -lt 5 ]; then
    say "        提示：Verilator 低于 5.0，部分 SystemVerilog 特性不可用，建议按 README 2.3 节源码编译 5.x"
  fi
else
  fail "verilator  （未安装）"
fi

check_cmd gtkwave

if [ -x "$TOOLCHAIN/bin/loongarch32r-linux-gnusf-gcc" ]; then
  pass "交叉工具链  $("$TOOLCHAIN/bin/loongarch32r-linux-gnusf-gcc" --version | head -1)"
else
  fail "交叉工具链  （$TOOLCHAIN 下没有 loongarch32r-linux-gnusf-gcc）"
  say "        请按 README 第 3 节把工具链解压到 requirements/ 下"
fi

say ""
say "--------------------------------------------------"
say "通过：$OK 项    缺失：$FAIL 项"
if [ "$FAIL" -eq 0 ]; then
  say "全部就绪。下一步："
  say "  source requirements/env.sh"
  say "  make -C requirements/verilator-smoke"
  exit 0
fi
say "请先补齐缺失项，再参考 requirements/README.md"
exit 1
