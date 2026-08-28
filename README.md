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

`core/` 도 함께 클론되므로 별도 설치 없이 self-contained 로 돈다.

### B. 그냥 CLI 로 (Omarchy 아닌 환경)

```bash
git clone git@github.com:cocobunnyfarm/omarchy-private-rtst-vpn.git
cd omarchy-private-rtst-vpn
./install-core.sh          # core/* -> ~/.local/bin/
vpn-up                     # 연결
vpn-down                   # 끊기
vpn-ctl status --json      # 상태 (JSON)
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
vpn-ctl import <file>      # .ovpn 보관 + import. 프로파일 이름은 파일명에서 유도
```

config 인자를 생략하면 `openvpn3 configs-list` 에서 첫 프로파일을 발견한다 —
매직 상수(`hell` 같은 것)를 두지 않는다.

```
```

### `status --json` 응답

```json
{
  "state": "disconnected",
  "detail": "세션 없음",
  "config": "hansulee-hell",
  "actionable": null
}
```

| `state` | 뜻 | 위젯 표현 |
|---|---|---|
| `missing-backend` | `openvpn3` 미설치 | 금간 쉴드. 클릭 시 설치 안내 |
| `backend-busy` | openvpn3 서비스 응답 없음 (부팅 직후 등) | 금간 쉴드. "확인 중…" — **프로파일 없다고 단정하지 않는다** |
| `missing-config` | 프로파일도 보관본도 없음 (최초 1회) | 금간 쉴드. `.ovpn` 선택 버튼 |
| `disconnected` | 준비됐고 미연결 | 쉴드 (흐림). 연결 / `.ovpn` 변경 |
| `authenticating` | SSO 인증 대기 | 쉴드 (흐림). 인증 URL 복사 버튼 |
| `connected` | 연결됨 | 쉴드 (밝게) |
| `error` | 그 외 | 금간 쉴드 + `detail` |

`actionable` 은 사용자가 실행해야 하는 명령 문자열(또는 `null`).
**위젯은 이걸 자동 실행하지 않는다** — 아래 참조.

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

QML 을 고친 뒤 반영하는 방법은 **플러그인만 껐다 켜는 것**이다:

```bash
omarchy plugin disable io.github.cocobunnyfarm.rtst-vpn
omarchy plugin enable  io.github.cocobunnyfarm.rtst-vpn right
```

| 방법 | 결과 |
|---|---|
| 파일 저장 (핫리로드) | ❌ 안 먹음 |
| `omarchy-shell shell rescanPlugins` | ❌ 안 먹음 |
| **`plugin disable` → `enable`** | ✅ **됨. 우리 플러그인만 영향** |
| `omarchy restart shell` | ✅ 되지만 바·알림·배경·**잠금화면**까지 재시작 — 쓰지 말 것 |

`omarchy restart shell` 은 `omarchy.lock`(잠금화면)이 같은 프로세스의 플러그인이라
반복하면 잠금화면이 깨진다. 실제로 겪었다.

### 미결

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
