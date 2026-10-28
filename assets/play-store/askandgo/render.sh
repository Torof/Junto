#!/usr/bin/env bash
# Renders the six Play images at 2160×3840 (density ×2: sharp when zoomed,
# Play's maximum side). Firefox's --screenshot ignores devPixelsPerPx, so the
# page is zoomed ×2 in CSS and captured in a window twice the size.
#   bash render.sh          (all six)   ·   bash render.sh 3   (one)
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
W="$HOME/snap/firefox/common/claude-shot"   # snap Firefox can only read under ~/snap
P="$HOME/snap/firefox/common/claude-shot2x"
mkdir -p "$W" "$P"

gen() {  # $1 = image number, $2 = html out
  case "$1" in
    1) python3 "$S/carte1.py" "$2" ;;
    2|5) python3 "$S/single.py" "$1" "$2" ;;
    3|4) python3 "$S/two.py" "$1" "$2" ;;
    6) python3 "$S/_variants.py" >/dev/null && python3 "$S/_gen_skirando.py" 6 "$2" && rm -f "$S"/_gen_*.py ;;
  esac
}
name() { case "$1" in 1) echo 1-carte;; 2) echo 2-sortie;; 3) echo 3-partenaires;; 4) echo 4-canaux;; 5) echo 5-confiance;; 6) echo 6-pros;; esac; }

for n in ${1:-1 2 3 4 5 6}; do
  html="$W/render_$n.html"; gen "$n" "$html" >/dev/null
  sed -i 's#</head>#<style>html{zoom:2}</style></head>#' "$html"
  grep -q 'html{zoom:2}' "$html" || { echo "no </head> in $html" >&2; exit 1; }
  timeout 120 firefox --headless --profile "$P" --window-size=2160,3840 \
    --screenshot "$W/render_$n.png" "file://$html" >/dev/null 2>&1
  cp "$W/render_$n.png" "$S/$(name "$n").png"
  echo "$(name "$n").png"
done
