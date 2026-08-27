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
vpn-ctl up [config]        # 연결 시작 (SSO URL 브라우저 오픈)
vpn-ctl down [config]      # 끊기 + 좀비 세션 정리
```

### `status --json` 응답

```json
{
  "state": "ready",
  "detail": "connected to hell",
  "config": "hell",
  "actionable": null
}
```

| `state` | 뜻 | 위젯 표현 |
|---|---|---|
| `missing-backend` | `openvpn3` 미설치 | 회색. 클릭 시 설치 안내 |
| `missing-config` | 설치됐으나 프로파일 미 import | 회색. 클릭 시 import 안내 |
| `disconnected` | 준비됐고 미연결 | 평상시 색. 클릭 시 연결 |
| `authenticating` | SSO 인증 대기 | 점멸/강조 |
| `connected` | 연결됨 | 활성 색 |
| `error` | 그 외 | 경고색 + `detail` |

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

### `.ovpn` import 는 애초에 자동화 대상이 아니다

사내 자산 파일이라 사람이 받아와야 한다. → `private/README.md`

---

## 셋업

`docs/openvpn-sso-setup.md` 참고 (Arch/Omarchy 기준).
원본 우분투 가이드는 `docs/openvpn-sso-setup.ubuntu-original.md` 로 보존.

요약:

1. `omarchy pkg aur add openvpn3`
2. 회사 `.ovpn` 을 `private/` 에 둔다
3. `openvpn3 config-import --config private/<파일>.ovpn --persistent --name hell`
4. `./install-core.sh` (CLI 용) 또는 `omarchy plugin add ...` (위젯 용)

---

## 상태

| 항목 | 상태 |
|---|---|
| `manifest.json` | 작성됨, `omarchy plugin validate` 통과 |
| `core/vpn-up`, `core/vpn-down` | 원본에서 가져옴. **Arch 수정 미적용** |
| `core/vpn-ctl` | **미작성** — 계약만 확정 |
| `Widget.qml` | **골격만.** 검증 전 |
| Arch 실기기 검증 | **미수행** — `openvpn3` 미설치 |

### 알려진 Arch 이식 이슈

1. `openvpn3` 는 AUR (`aur/openvpn3`). 원본의 `apt install` 은 해당 없음
2. **snap 이 없다** → `vpn-up` 의 `/snap/bin/firefox` 분기는 절대 안 탄다.
   `/usr/bin/firefox` 네이티브라 두 번째 분기로 가서 수정 없이 동작한다.
   원본 README 의 "snap firefox 심볼릭 링크 함정" 항목도 해당 없음
3. `vpn-status` alias 는 `~/.bashrc` 에 한 줄만 추가하는 delta 로 관리
