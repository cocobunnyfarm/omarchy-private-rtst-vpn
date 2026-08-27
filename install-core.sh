#!/usr/bin/env bash
# core/ 의 CLI 를 ~/.local/bin 에 설치한다 (Omarchy 아닌 환경에서 쓸 때).
# Omarchy 바 위젯으로 쓸 때는 이 스크립트가 필요 없다 —
# `omarchy plugin add` 가 core/ 까지 함께 클론한다.
#
# usage:
#   ./install-core.sh            # 드라이런: 무엇을 할지만 출력
#   ./install-core.sh --apply    # 실제 설치

set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="${HOME}/.local/bin"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

echo "소스: $REPO/core"
echo "대상: $DEST"
echo

if [ "$APPLY" -eq 0 ]; then
  echo "── 드라이런 (아무것도 바꾸지 않음) ──"
fi

for f in "$REPO"/core/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  target="$DEST/$name"

  if [ -e "$target" ] && cmp -s "$f" "$target"; then
    echo "  이미 최신    $name"
    continue
  fi
  if [ -e "$target" ]; then
    echo "  덮어씀       $name  (기존 파일 있음)"
  else
    echo "  설치         $name"
  fi

  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$DEST"
    install -m 0755 "$f" "$target"
  fi
done

echo
if [ "$APPLY" -eq 0 ]; then
  echo "실제 적용: $0 --apply"
else
  echo "완료. PATH 에 $DEST 가 있는지 확인:"
  echo "  command -v vpn-ctl"
fi
