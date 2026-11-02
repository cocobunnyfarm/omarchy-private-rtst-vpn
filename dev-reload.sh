#!/bin/bash
# 개발용: repo 의 Widget.qml 을 설치된 플러그인에 즉시 반영한다 (로그아웃 불필요).
#
#   ./dev-reload.sh           한 번 반영
#   ./dev-reload.sh --watch   Widget.qml 저장할 때마다 자동 반영
#   ./dev-reload.sh --off     개발 모드 해제 (설치본을 git 상태로 되돌림)
#
# 왜 이렇게 하나 (README «개발 중 리로드» 참조):
#   셸은 파일이 바뀌면 리로드하지만 Qt 는 **같은 URL 의 컴파일 결과**와
#   **디렉터리 목록**을 캐시한다. 그래서
#     - 같은 경로에 덮어쓰기   → 옛 위젯이 계속 뜬다
#     - 같은 폴더에 새 이름    → "File name case mismatch" 로 로드 실패
#   **매번 새 디렉터리**에 넣고 manifest 의 entryPoint 를 그쪽으로 돌리면
#   Qt 가 처음 보는 URL·폴더라 새로 컴파일한다.
#
# core/ 는 repo 를 심볼릭 링크로 가리키므로 vpn-ctl 수정은 반영 없이 바로 먹는다.
set -euo pipefail

ID="io.github.cocobunnyfarm.rtst-vpn"
REPO="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID"

[[ -d $PLUGIN ]] || { echo "설치된 플러그인이 없습니다: $PLUGIN" >&2; exit 1; }

deploy() {
  local name="dev-$(date +%s%N)"
  local dir="$PLUGIN/$name"
  mkdir "$dir"
  cp "$REPO/Widget.qml" "$dir/Widget.qml"
  ln -s "$REPO/core" "$dir/core"
  # manifest 는 마지막에 한 번에 바꾼다 — 이게 실제 리로드 트리거다.
  local tmp
  tmp="$(mktemp)"
  jq --arg ep "$name/Widget.qml" '.entryPoints.barWidget = $ep' "$REPO/manifest.json" > "$tmp"
  cat "$tmp" > "$PLUGIN/manifest.json"
  rm -f "$tmp"
  # 이전 개발 디렉터리 정리 (방금 만든 것만 남긴다)
  find "$PLUGIN" -maxdepth 1 -type d -name 'dev-*' ! -name "$name" -exec rm -rf {} +
  sleep 1.5
  local errs
  errs="$(journalctl --user --since "-3s" -o cat 2>/dev/null | grep -F "$ID" | grep -iE "failed|error" || true)"
  if [[ -n $errs ]]; then
    echo "✗ 로드 실패:" >&2; echo "$errs" >&2
  else
    echo "✓ 반영됨 ($name)"
  fi
}

case "${1-}" in
  --off)
    find "$PLUGIN" -maxdepth 1 -type d -name 'dev-*' -exec rm -rf {} +
    git -C "$PLUGIN" checkout -- manifest.json Widget.qml
    echo "개발 모드 해제. 설치본은 git 상태(마지막 pull)로 돌아갔습니다."
    ;;
  --watch)
    deploy
    echo "Widget.qml 감시 중… (Ctrl+C 종료)"
    # 에디터는 보통 임시파일로 쓰고 rename 하므로 파일이 아니라 폴더를 본다.
    inotifywait -m -q -e close_write,moved_to --format '%f' "$REPO" |
      while read -r f; do [[ $f == Widget.qml ]] && deploy; done
    ;;
  "")
    deploy
    ;;
  *)
    sed -n '2,6p' "$0"; exit 2
    ;;
esac
