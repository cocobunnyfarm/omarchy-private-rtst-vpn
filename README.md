# omarchy-private-rtst-vpn

RTST 사내망 VPN (openvpn3 + Google SSO) — **코어 CLI + Omarchy 바 위젯**.

> **private repo.** 이름의 `private` 는 우리 자체 네이밍 컨벤션으로,
> 공개 배포하지 않는 플러그인임을 한눈에 구분하기 위한 것이다.
> 구조 자체는 공개 플러그인 규약(`repo 루트 = 플러그인 폴더`)을 그대로 지킨다.

---

## 두 개의 레이어

```
├── manifest.json      ┐
├── Widget.qml         ├─ UI 레이어 — Omarchy 바 위젯. 그리기만 한다
│                      ┘
├── core/              ┐
│   ├── vpn-ctl        ├─ 코어 레이어 — Omarchy 없이 단독 동작
│   ├── vpn-up         │   평범한 CLI 라 우분투·서버에서도 그대로 쓴다
│   └── vpn-down       ┘
│
├── install-core.sh       CLI 용: core/* → ~/.local/bin/
└── dev-reload.sh         개발용: Widget.qml 을 설치된 위젯에 즉시 반영 (아래 «개발 중 리로드»)
```

**UI 는 코어를 `Process` 로 호출해 JSON 을 받아 그리기만 한다.** 로직은 전부 코어에.
이러면 코어를 다른 OS/UI 에서 재사용할 수 있고, QML 없이 단독 테스트할 수 있다.

## 두 가지 용법

### A. Omarchy 바 위젯으로

```bash
omarchy plugin add git@github.com:cocobunnyfarm/omarchy-private-rtst-vpn.git --enable
```

private repo 라도 `omarchy plugin add` 는 내부적으로 `git clone` 이므로
SSH 키가 로드돼 있으면 그대로 동작한다 (keychain 사용 시 자동).

**반드시 위의 SSH 주소(`git@github.com:...`)로 설치할 것.** `https://` 주소로
설치하면 설치본의 remote 가 HTTPS 가 되어, `ssh-add -l` 에 키가 있어도 git 이
키를 쓰지 않고 유저네임/토큰을 물어 `plugin update` 가 실패한다 (새 OS 에서 겪었다).
이미 그렇게 됐다면:

```bash
git -C ~/.config/omarchy/plugins/io.github.cocobunnyfarm.rtst-vpn \
  remote set-url origin git@github.com:cocobunnyfarm/omarchy-private-rtst-vpn.git
```

`core/` 도 함께 클론되므로 별도 설치 없이 self-contained 로 돈다.

### B. 그냥 CLI 로 (Omarchy 아닌 환경)

```bash
git clone git@github.com:cocobunnyfarm/omarchy-private-rtst-vpn.git
cd omarchy-private-rtst-vpn
./install-core.sh          # core/* -> ~/.local/bin/
vpn-up                     # 연결
vpn-down                   # 끊기
vpn-ctl import ~/hell.ovpn # .ovpn 등록 (최초 1회)
vpn-ctl status --json      # 상태 (JSON)
vpn-ctl profiles           # 보관된 .ovpn 목록
```

---

## 코어 CLI 계약 (`vpn-ctl`)

UI 가 이 계약만 알면 되므로, **위젯은 openvpn3 도 RTST 도 모른다.**
다른 백엔드(wireguard 등)를 쓰려면 같은 계약을 구현한 명령을 만들고
위젯 설정의 `ctlCommand` 만 바꾸면 된다.

```
vpn-ctl status --json      # 상태 조회. 항상 종료코드 0, 상태는 JSON 으로
vpn-ctl up [config]        # 연결 시작 (브라우저는 열지 않고 URL 만 출력)
vpn-ctl down [config]      # 끊기 + 좀비 세션 정리
vpn-ctl auth-url           # 현재 세션의 SSO 인증 URL (원하는 브라우저에서 열면 연결)
vpn-ctl import <file>      # .ovpn 보관 + 활성 지정 + openvpn3 등록
vpn-ctl profiles [--json]  # 보관된 .ovpn 목록 (활성 표시)
vpn-ctl use <name>         # 활성 프로파일 전환
vpn-ctl forget <name>      # 보관본 + openvpn3 프로파일 삭제
```

config 인자는 CLI 편의용이며, **위젯은 어떤 명령에도 이름을 넘기지 않는다.**
이름 결정권은 코어 한 곳에 있다 — 매직 상수(`hell` 같은 것)를 두지 않는다.
UI 가 이름을 주면 코어의 자동 발견·복구와 어긋나서, 복구된 프로파일에 대고
존재하지 않는 이름으로 연결을 시도하게 된다. (실제로 겪었다.)

### 보관소 = 등록 여부의 유일한 근거

```
~/.config/rtst-vpn/           # $XDG_CONFIG_HOME/rtst-vpn
├── <name>.ovpn               # 사용자가 고른 원본. 여러 개 가능
└── active                    # 활성 프로파일 이름 한 줄
```

"사용자가 .ovpn 을 등록했는가" 는 **이 디렉터리로만** 판단한다.
`openvpn3 configs-list` 로 판단하지 않는다 —

- configmgr 은 D-Bus on-demand 서비스라 부팅 직후엔 비어 보일 수 있다
- 우리가 넣지 않은 프로파일이 들어 있을 수도 있다
- openvpn3 쪽 프로파일은 실제로 사라진다 (원인 미확정, 아래 «미결» 참조)

그래서 openvpn3 쪽 등록은 **언제든 보관본으로 다시 만들 수 있는 파생 상태**로
취급한다. `status` / `up` 이 사라진 걸 발견하면 조용히 다시 넣는다 —
사용자는 이미 한 번 파일을 골랐고, 그 결정을 다시 묻지 않는다.

`active` 파일이 없거나 가리키는 파일이 없으면 **가장 최근에 넣은 것**으로
승계한다. `active` 가 생기기 전에 `import` 한 사용자도 그대로 동작해야 하므로.

**보관 파일명은 언제나 프로파일 이름과 같다.** 이름을 따로 받아도 그 이름으로
보관한다 (`import x.ovpn hell` → `hell.ovpn` 으로 저장). 이 불변식이 깨지면
상태가 세 갈래로 갈라진다 — 실제로 겪었다:

```
보관본 = hansulee-hell.ovpn    (원본 파일명)
active = hell                  (되짚을 보관본이 없는 이름)
openvpn3 = hell                (세션이 붙는 이름)
```

이러면 `active` 가 해석되지 않아 최신 보관본(`hansulee-hell`)으로 승계되고,
`status` 는 그 이름으로 세션을 찾다가 "세션 없음" 이라고 한다. 그런데 실제
세션은 `hell` 로 인증 대기 중이다. 사용자에게는 **연결 버튼을 눌렀는데
아무 일도 없이 첫 화면으로 돌아가는 것**으로 보인다.

프로파일 이름은 파일명에서 유도한다 (`hansulee-hell.ovpn` → `hansulee-hell`).
`import` 는 멱등하다 — 같은 이름이 있으면 지우고 다시 넣는다. openvpn3 는
이름 중복을 막지 않아서, 안 그러면 파일을 다시 고를 때마다 쌓이고
`configs-list` 첫 줄이 뭔지 예측 불가가 된다.

### `status --json` 응답

```json
{
  "state": "disconnected",
  "detail": "세션 없음",
  "config": "hansulee-hell",
  "actionable": null,
  "profiles": [
    { "name": "hansulee-hell", "file": "hansulee-hell.ovpn", "active": true }
  ]
}
```

`profiles` 를 status 에 함께 실어 보낸다. 별도 조회로 나누면 목록과 상태가
어긋나는 순간이 생기고, 위젯이 "연결 버튼을 잠글지" 를 두 소스로 판단하게 된다.

| `state` | 뜻 | 위젯 표현 |
|---|---|---|
| `missing-backend` | `openvpn3` 미설치 | 금간 쉴드. 클릭 시 설치 안내 |
| `missing-config` | **사용자가 .ovpn 을 등록한 적이 없다** | 금간 쉴드. `.ovpn` 선택 버튼만. 연결 버튼은 아예 없다 |
| `backend-busy` | openvpn3 서비스 응답 없음 (부팅 직후 등) | 쉴드. "확인 중…" — **연결 여부를 단정하지 않는다** |
| `disconnected` | 준비됐고 미연결 | 쉴드 (흐림). 연결 + 프로파일 관리 |
| — | 활성 프로파일엔 세션이 없지만 **다른 이름**으로 살아 있으면 그 세션의 상태를 보고하고 `config` 에 그 이름을 담는다. "끊김" 이라고 거짓말하지 않는다 | |
| `authenticating` | SSO 인증 대기 | 쉴드 (흐림). 인증 URL 복사 버튼 |
| `connected` | 연결됨 | 쉴드 (밝게) |
| `error` | 그 외 (보관본이 있는데 등록에 실패 등) | 금간 쉴드 + `detail` |

`missing-config` 는 백엔드 응답 여부와 **무관하게** 확정할 수 있으므로
`backend-busy` 보다 먼저 판정한다. "아직 아무것도 고르지 않았다" 는
openvpn3 사정과 상관없는 사실이고, 위젯은 이걸 알아야 연결을 잠글 수 있다.

`actionable` 은 사용자가 실행해야 하는 명령 문자열(또는 `null`).
**위젯은 이걸 자동 실행하지 않는다** — 아래 참조.

### 프로파일 관리 UI

연결이 **끊긴 상태에서만** 노출한다 — 연결 중에 프로파일을 갈아치우면 살아
있는 세션과 어긋난다.

- 한 줄에 하나. 활성인 것은 `󰄬` 표시 + 테두리. 이름을 누르면 `use` 로 전환
- `삭제` 는 2단계 — 한 번 더 누르면 실제로 지운다 (`forget`). 4초 후 취소
- `.ovpn 추가` 로 파일을 더 넣는다. 방금 넣은 것이 활성이 된다

보통 1개뿐이라 드롭다운 대신 목록을 쓴다 — 몇 개가 있고 어느 것이 활성인지
펼치지 않고 바로 보인다.

---

## 의존성을 자동 설치하지 않는 이유

`openvpn3` 는 **AUR** 패키지다 (Arch 공식 저장소에 없음). 그리고
`omarchy pkg aur add` 는 `yay -S --noconfirm` 을 **sudo 없이** 실행한다 —
yay 가 스스로 권한을 올리고, `makepkg` 는 root 실행을 거부하기 때문이다.

따라서 위젯(QML)에서 자동 설치는 **기계적으로 불가능**하다:

- 위젯에서 호출 → yay 가 sudo 암호를 물어보는데 **TTY 가 없어 멈춘다**
- `pkexec` 로 우회 → **makepkg 가 root 라서 거부한다**

1st-party `omarchy.tailscale` 도 같은 결론이다 — `which tailscale` 로 **감지만**
하고 (`property bool installed`), 없으면 `Unavailable` 상태를 보여주고 물러난다.
자동 설치하지 않는다.

**우리 방식:** 감지는 자동, 실행은 사용자 확인 후 **보이는 터미널**에서.

```
omarchy-launch-floating-terminal-with-presentation 'omarchy pkg aur add openvpn3'
```

Omarchy 가 자기 `Install →` 메뉴에서 쓰는 방식이라 sudo 프롬프트가 정상 동작하고
빌드 과정이 눈에 보인다.

위젯의 **`AUR 설치 메뉴`** 버튼은 Omarchy 의 AUR 설치기(`Install > AUR` 의 fzf)를
**검색어 `openvpn3` 가 채워진 채로** 띄운다 — 사용자는 Enter 만 누르면 된다.
`omarchy menu summon install.aur` 는 빈 검색창만 띄우고 검색어를 넘길 방법이
없어서, 메뉴 항목과 같은 명령을 직접 실행하고 `FZF_DEFAULT_OPTS` 에
`--query=openvpn3` 를 덧붙인다 (사용자의 기존 값은 보존).

### `.ovpn` 은 사람이 골라야 하지만, 고르는 것 자체는 위젯이 돕는다

파일을 **가져오는** 것은 자동화할 수 없다 (사내 자산). 하지만 **고르는** 것은
Omarchy 의 공식 파일 선택기로 처리한다:

```bash
omarchy-file-select --title "회사 .ovpn 선택" --extensions "ovpn conf"
```

XDG desktop portal 기반 실제 파일 다이얼로그다. 종료 코드가
`1`(아무것도 안 고름 — 정상적인 결정) / `2`(선택기가 안 뜸 — 실패) 로 구분되어
위젯에서 다르게 처리할 수 있다.

고른 파일은 `vpn-ctl import` 가 데이터 디렉터리로 보관하고 openvpn3 에 import 한다.

## 데이터 디렉터리

`.ovpn` 원본은 **repo 안이 아니라** XDG 경로에 보관한다:

```
${XDG_CONFIG_HOME:-~/.config}/rtst-vpn/       # 권한 700, 파일 600
```

repo 상대 경로를 쓰지 않는 이유:

| 후보 | 문제 |
|---|---|
| repo 안 `private/` | 경로가 환경마다 다르다. 코어가 "Omarchy 없이 어디서든" 돌아야 하는 요구와 충돌 |
| `~/.config/omarchy/plugins/<id>/` | `plugin remove`/재설치 때 날아간다. Omarchy 전용 경로 |
| **`~/.config/rtst-vpn/`** | XDG 표준. 플러그인 재설치와 무관. 비-Omarchy 환경에서도 동일 |

import 후에는 openvpn3 가 프로파일을 자체 저장소(`/var/lib/openvpn3/configs`)에
`--persistent` 로 보관하므로 연결에 이 파일이 필요하지 않다. **재부팅을 견딘다.**

그럼에도 원본을 보관하는 이유: `status` 가 프로파일을 못 찾으면 이 파일로 **조용히
복원**한다. 사용자는 이미 한 번 `.ovpn` 을 등록했으므로 그 결정을 다시 묻지 않는다.

> **주의:** "프로파일이 사라진다" 는 오진이었다. 부팅 직후 프로파일이 없다고
> 판정된 원인은 `openvpn3-service-configmgr` 가 **D-Bus on-demand 서비스**라
> 아직 활성화 전이었던 것이고, 코드가 "빈 응답" 과 "물어볼 수 없었음" 을 같게
> 취급한 버그였다. 진짜 수정은 `backend-busy` 구분이고 조용한 복원은 안전망이다.

---

## 셋업

`docs/openvpn-sso-setup.md` 참고 (Arch/Omarchy 기준).
원본 우분투 가이드는 `docs/openvpn-sso-setup.ubuntu-original.md` 로 보존.

요약:

1. `omarchy pkg aur add openvpn3`
2. 회사 `.ovpn` 을 아무 곳에나 받아둔다 (다운로드 폴더 등)
3. `vpn-ctl import <받은 파일 경로>`
   — 파일을 `~/.config/rtst-vpn/` 로 보관하고 파일명에서 유도한 이름으로 import 한다
4. `./install-core.sh --apply` (CLI 용) 또는 `omarchy plugin add ...` (위젯 용)

위젯으로 쓰면 1~3 을 위젯이 안내한다 — 감지해서 필요한 것만 보여주고,
설치는 보이는 터미널에서, 파일 선택은 `omarchy-file-select` 로.

---

## 상태

| 항목 | 상태 |
|---|---|
| `manifest.json` | `omarchy plugin validate` 통과 |
| `core/vpn-ctl` | 전 상태 실기기 검증 (`missing-backend` → `missing-config` → `authenticating` → `connected`) |
| `core/vpn-up` | Arch 이식 완료. 가로채기 제거 + 자동 열기 억제. 프로파일 자동 발견 |
| `core/vpn-down` | 프로파일 자동 발견 |
| `Widget.qml` | 3단계 UI + URL 복사 버튼. 실기기 동작 확인 |
| 연결 전 구간 | **검증됨** — 설치 → import → 인증 → 연결 → 끊기 |

### 개발 중 리로드 방법 (중요)

**`./dev-reload.sh --watch` 를 띄워두고 `Widget.qml` 을 저장하면 바로 바뀐다.**
로그아웃·재부팅 불필요.

```bash
./dev-reload.sh           # 한 번 반영
./dev-reload.sh --watch   # 저장할 때마다 자동 반영
./dev-reload.sh --off     # 개발 모드 해제 (설치본을 git 상태로)
```

`core/` 는 repo 를 심볼릭 링크로 가리키므로 `vpn-ctl` 수정은 반영 없이 바로 먹는다.

#### 왜 그냥 덮어쓰면 안 먹는가 (2026-11-02 원인 확인)

셸은 파일 변경을 감지해 리로드하고 `Qt.clearComponentCache()` 도 부른다.
그런데 Qt 는 **같은 URL 의 컴파일 결과**와 **디렉터리 목록**을 계속 들고 있다.
실험 결과:

| 방법 | 결과 |
|---|---|
| 같은 경로에 덮어쓰기 | ❌ 옛 위젯 그대로 (로그의 `Widget.qml[273]` 줄번호가 옛 파일 기준) |
| 같은 폴더에 새 파일명 + manifest 수정 | ❌ `File name case mismatch` — 폴더 목록 캐시에 새 파일이 없다 |
| **새 디렉터리** + manifest 수정 | ✅ 새로 컴파일됨 (줄번호가 새 파일 기준) |
| 로그아웃 / 재부팅 | ✅ 확실하지만 느리다 |
| `omarchy restart shell` | 잠금화면까지 재시작 — 반복하면 잠금화면이 깨진다. 쓰지 말 것 |

예전에 의심했던 `pluginReloading` 플래그 고착은 원인이 아니었다 — 리로드는
매번 정상적으로 돌았고, 다시 로드한 결과가 캐시된 옛 컴파일본이었을 뿐이다.
`dev-reload.sh` 는 매번 `dev-<타임스탬프>/` 에 복사하고 manifest 의
`entryPoints.barWidget` 을 그쪽으로 돌려서 캐시를 피한다.

주의: 개발 모드는 **재부팅해도 풀리지 않는다** (설치본 파일을 바꾼 상태라서).
켜둔 채 두면 위젯은 마지막 반영본으로 잘 돌지만, 설치본의 `manifest.json` 이
바뀌어 있어 `plugin update`(= git pull) 가 충돌하고, 설치본 `core/` 가 이 repo 를
가리키므로 repo 를 옮기면 위젯이 깨진다.

**개발을 마칠 때는 이 순서로** — `--off` 만 하면 설치본이 마지막 pull 시점의
옛 버전으로 돌아간다:

```bash
git commit … && git push
./dev-reload.sh --off
omarchy plugin update io.github.cocobunnyfarm.rtst-vpn
#   또는 푸시 없이 로컬 repo 에서 바로:
#   git -C ~/.config/omarchy/plugins/io.github.cocobunnyfarm.rtst-vpn pull --ff-only "$PWD" master
```

`--off` 직후엔 같은 경로(`Widget.qml`)를 다시 쓰므로 캐시 때문에 로그아웃 전까지
화면에 옛 위젯이 보일 수 있다. 동작에는 지장 없다.

**확인은 화면으로.** "reloading" 로그는 반영의 증거가 아니다. 확실한 증거는
경고 로그에 찍히는 파일 경로·줄번호가 새 것인지:

```bash
journalctl --user --since -10s -o cat | grep rtst-vpn/dev-
```

`IpcHandler ... will not be used` 경고는 모니터가 2대라 위젯이 2개 떠서 나는 것으로 무해하다.

### 미결

- **openvpn3 프로파일이 왜 사라지는가.** `--persistent` 로 넣고
  `config-manage --show` 도 `Persistent config: Yes` 인데, 상태 디렉터리가
  비어 있다:

  ```
  /var/lib/openvpn3/configs   root:root 755   (파일 0개)
  configmgr 프로세스는 openvpn 유저로 실행
  ```

  쓰기 권한이 없어 보이지만, 부팅 로그엔
  `Parsed persistent configuration 'hansulee-hell'` 이 찍혀 있어 재부팅을
  넘긴 것도 사실이다 (로드 후 파일을 지우고 종료 시 다시 쓰는 방식일 수 있다).
  파고들려면 root 가 필요해 멈췄다.

  다만 보관소가 등록 여부의 근거이므로 **사라져도 사용자 눈에는 안 보인다** —
  `status` / `up` 이 조용히 다시 넣는다. 증상이 아니라 원인만 미결이다.
- `dimmed` 기반 아이콘 밝기: 연결 상태에서 밝아지는지 **육안 검증 안 됨**
- 브라우저 **선택**(억제가 아니라 특정 브라우저로 열기)은 미구현.
  같은 기법으로 가능하다 — 임시 `mimeapps.list` 에
  `x-scheme-handler/https=firefox.desktop` 한 줄. `XDG_DATA_DIRS` 를 건드리지 않으면
  `/usr/share/applications` 에서 해석된다

### 알려진 Arch 이식 이슈

1. `openvpn3` 는 AUR (`aur/openvpn3`). 원본의 `apt install` 은 해당 없음
2. **원본의 브라우저 강제 방식(`xdg-open` PATH 가로채기)은 통하지 않는다.**
   openvpn3 v27.1 은 GLib 의 기본앱 실행(`g_app_info_launch_default_for_uri` 계열)로
   `mimeapps.list` 핸들러를 직접 exec 한다. 실측으로 확인한 것:
   - `$BROWSER` → 무시 (센티넬 미호출)
   - PATH 의 가짜 `xdg-open` → 미호출
   - XDG Portal `OpenURI` → `dbus-monitor` 결과 **호출 0건**
   - `session-start` 에 자동 열기를 끄는 옵션 없음

   snap 분기도 당연히 무의미하다 (Arch 에 snap 없음). 가로채기 코드 전체를 제거하고,
   대신 `session-start` 호출에만 no-op 핸들러 환경을 씌워 자동 열기를 억제한다
3. `vpn-status` alias 는 `~/.bashrc` 에 한 줄만 추가하는 delta 로 관리
