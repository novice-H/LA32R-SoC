#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
case "$action" in
  lint|compare|trace|wave-gtkwave|wave-vaporview) ;;
  *) echo "Usage: $0 {lint|compare|trace|wave-gtkwave|wave-vaporview}" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LA32R_BUILD="${LA32R_BUILD:-$HOME/build/la32r}"
source "$root/requirements/env.sh"
if [[ "$LA32R_BUILD" != /* ]]; then
  LA32R_BUILD="$(realpath -m "$root/sim/$LA32R_BUILD")"
  export LA32R_BUILD
fi

case "$action" in
  lint) target=lint ;;
  compare) target=compare ;;
  trace|wave-vaporview) target=trace ;;
  wave-gtkwave) target=wave ;;
esac
make -C "$root/sim" "$target"

if [[ "$action" == trace || "$action" == wave-vaporview ]]; then
  vcd="$LA32R_BUILD/vga/vga.vcd"
  printf 'VCD: %s\n' "$vcd"
  if [[ "$action" == wave-vaporview ]]; then
    if command -v code >/dev/null 2>&1; then
      code --reuse-window "$vcd"
    else
      echo "VS Code CLI 'code' is unavailable in this WSL window; open this path in VaporView: $vcd" >&2
      exit 127
    fi
  fi
fi
