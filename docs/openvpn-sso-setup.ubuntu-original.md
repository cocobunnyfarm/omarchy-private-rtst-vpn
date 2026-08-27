# OpenVPN + Google SSO 셋업 가이드 (Ubuntu 22.04)

회사 VPN이 Google SSO를 쓰는 새 서버(예: `vpn.rtst.co.kr:1195`)로 전환됐을 때, 리눅스에서 붙는 방법.
기존 `apt install openvpn` + `systemctl openvpn@<name>` 방식은 SSO를 못 다루므로 **`openvpn3` 클라이언트로 갈아탄다.**

---

## 0. 전제 / 환경

- Ubuntu 22.04 (jammy), KDE 또는 GNOME 데스크톱 (브라우저 사용 가능해야 함)
- 발급받은 `.ovpn` 파일이 있음 (예: `hansulee-hell.ovpn`)
- 시스템에 `apt`, `curl`, `sudo` 사용 가능

---

## 1. openvpn3 설치

OpenVPN 공식 repo 등록 후 설치.

```bash
sudo apt update
sudo apt install -y apt-transport-https curl
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://swupdate.openvpn.net/repos/openvpn-repo-pkg-key.pub -o /etc/apt/keyrings/openvpn.asc
```

repo 등록은 **heredoc**으로 (긴 한 줄이 터미널에서 줄바꿈 사고 잘 남):

```bash
sudo tee /etc/apt/sources.list.d/openvpn3.list > /dev/null <<'EOF'
deb [signed-by=/etc/apt/keyrings/openvpn.asc] https://swupdate.openvpn.net/community/openvpn3/repos jammy main
EOF
```

설치:

```bash
sudo apt update
sudo apt install -y openvpn3
openvpn3 version
```

---

## 2. 기본 브라우저를 Firefox로 (선택)

SSO 인증 URL이 자동으로 열리는 브라우저는 OS 기본값(`xdg-open`)을 따름. Chrome 말고 Firefox 쓰고 싶으면:

```bash
xdg-settings set default-web-browser firefox.desktop
xdg-settings get default-web-browser   # 확인
```

snap firefox라 `firefox.desktop`이 안 먹으면:

```bash
ls /usr/share/applications/ | grep -i firefox
# 나오는 정확한 .desktop 이름으로 다시 set
```

---

## 3. conf 파일 위치

`.ovpn` → `.conf`로 확장자 바꿔서 `/etc/openvpn/`에 둔다 (관습; openvpn3는 어디 둬도 됨).

```bash
sudo cp ~/Downloads/hansulee-hell.ovpn /etc/openvpn/hansulee-hell.conf
sudo chmod 600 /etc/openvpn/hansulee-hell.conf
```

---

## 4. 기존 systemd OpenVPN 비활성화 (정리)

옛 `openvpn@<name>.service`가 떠 있으면 tun이 두 개 생기거나 충돌함. **반드시 정리.**

```bash
# 모든 openvpn@ 인스턴스 stop + disable
sudo systemctl stop 'openvpn@*' 2>/dev/null
for u in $(systemctl list-unit-files 'openvpn@*' --no-legend | awk '{print $1}'); do
  sudo systemctl disable "$u" 2>/dev/null
done

# AUTOSTART도 비움 (부팅 시 generator가 자동 인스턴스 안 만들도록)
sudo sed -i 's/^AUTOSTART=.*/AUTOSTART="none"/' /etc/default/openvpn

# 우산 서비스도 disable
sudo systemctl disable openvpn

# 확인
systemctl is-enabled openvpn 'openvpn@*' 2>&1
grep AUTOSTART /etc/default/openvpn
```

---

## 5. openvpn3에 conf import

```bash
openvpn3 config-import \
  --config /etc/openvpn/hansulee-hell.conf \
  --persistent \
  --name hell
```

- `--persistent` : 부팅 후에도 프로파일 유지
- `--name hell` : 이후 명령에서 쓰는 짧은 별칭 (원하는 이름)

목록 확인:

```bash
openvpn3 configs-list
```

---

## 6. 연결 (SSO 흐름)

```bash
openvpn3 session-start --config hell
```

출력 예:

```
Web based authentication required.
Session running, awaiting external authentication.
Opening in existing browser session.
```

기본 브라우저가 자동으로 떠서 Google SSO 페이지를 보여줌. **로그인 완료하면 터미널의 세션이 자동으로 connected 상태로 전환됨.**

브라우저가 자동으로 안 떠도 URL을 직접 다시 보고 싶으면:

```bash
openvpn3 session-auth
```

대기 중인 세션과 인증 URL이 출력됨 → 원하는 브라우저에 복붙.

---

## 7. 연결 검증

```bash
openvpn3 sessions-list             # Status: "Client connected" 확인
ip addr show tun0                  # tun0 + 10.x.x.x IP 확인
ip route                           # 10.0.0.0/10, 10.x.0.0/16 via tun0 확인
ping -c 3 git.rtst.co.kr           # 응답 옴
curl -sI https://git.rtst.co.kr/ | head -3   # HTTP 헤더 출력
```

브라우저에서 `https://git.rtst.co.kr/` 정상 접속되면 끝.

---

## 8. 끊기 / 상태 / 자주 쓰는 명령

```bash
# 상태
openvpn3 sessions-list

# 끊기
openvpn3 session-manage --config hell --disconnect

# 다시 연결
openvpn3 session-start --config hell

# 로그 (실시간)
openvpn3 log --config hell

# 죽은(failed) 세션 정리
openvpn3 sessions-list                                      # path 확인
openvpn3 session-manage --session-path <PATH> --disconnect

# 프로파일 삭제
openvpn3 config-remove --config hell
```

---

## 9. 편의 스크립트 / alias

이 폴더의 `vpn-up`, `vpn-down` 스크립트를 `~/.local/bin/`에 복사하고 `chmod +x`:

```bash
cp ./vpn-up ./vpn-down ~/.local/bin/
chmod +x ~/.local/bin/vpn-up ~/.local/bin/vpn-down
```

- `vpn-up`  : 좀비 세션 정리 → 새 세션 시작 → Auth URL 터미널 출력 + Firefox로 자동 오픈
  - `vpn-up myconf` : 다른 config 이름
  - `vpn-up -u` : URL만 출력, 브라우저는 안 띄움 (직접 복붙해서 쓰고 싶을 때)
  - `vpn-up -h` : 도움말
  - 내부적으로 `xdg-open`을 PATH로 가로채서 Firefox로 강제 라우팅함
    (시스템 기본 브라우저가 Chrome으로 잡혀 있어도 Firefox가 뜸)
- `vpn-down`: 해당 config의 모든 세션 disconnect (동일 이름 세션이 여러 개여도 안전하게)

**주의: 같은 이름의 alias를 `~/.bashrc`에 만들면 안 됨.** alias가 PATH보다 우선이라
스크립트가 가려져버리고, 특히 `alias vpn-down='openvpn3 session-manage --config hell --disconnect'`은
세션이 여러 개일 때 "More than one session ..." 에러로 실패함.

추가로 status 정도만 alias로:

```bash
alias vpn-status='openvpn3 sessions-list'
alias vpn-log='openvpn3 log --config hell'
```

---

## 10. 트러블슈팅 빠른표

| 증상 | 원인 / 처치 |
|---|---|
| `AUTH: ... AUTH_FAILED` (community openvpn에서) | SSO 서버는 community CLI 미지원. **openvpn3로 가야 함.** |
| `session-start` 후 브라우저가 안 뜸 | `xdg-settings get default-web-browser` 확인. 또는 `openvpn3 session-auth`로 URL 수동 확인. |
| 인증 후에도 ping 안 됨 (`Destination Net Prohibited`) | 서버 push 라우트가 로컬망과 충돌. conf 끝에 예외 추가 후 `config-import` 다시 (아래 11번 참조). |
| tun이 두 개 뜸 | 옛 `openvpn@xxx` 서비스가 살아있음. 4번 정리 다시 수행. |
| `WARNING: 'tun-mtu' is used inconsistently` | 서버가 push하는 MTU와 클라 기본값 불일치. conf에 `tun-mtu 1420`, `mssfix 1380` 명시. |
| 어제 됐는데 오늘 안 됨 | SSO 세션 만료. 그냥 다시 `vpn-up`. |
| `openvpn3-autoload --enable hell` 같은 거 통하면 좋겠는데 | autoload는 디렉터리 스캔 방식이고, **SSO에선 매번 브라우저 인증이 필요**해서 자동시작 의미가 없음. 수동이 정공법. |

---

## 11. 라우팅 / MTU 픽스 (필요 시 conf에 추가)

서버 push 라우트가 로컬망(예: `10.6.x.x`)을 삼키거나 VPN 서버 자체 트래픽이 터널로 들어가서 ping-restart 루프가 도는 경우. `.conf` 끝에 다음 추가:

```
# 로컬망은 VPN 안 타게
route 10.6.0.0 255.255.0.0 net_gateway

# VPN 서버 IP 자체는 원래 랜선으로 (자기잠식 방지)
route 221.158.185.6 255.255.255.255 net_gateway

# (선택) 특정 호스트만 강제로 VPN으로
route 10.10.0.14 255.255.255.255 vpn_gateway

# MTU 최적화
tun-mtu 1420
mssfix 1380
```

수정 후 재import:

```bash
openvpn3 config-remove --config hell
openvpn3 config-import --config /etc/openvpn/hansulee-hell.conf --persistent --name hell
openvpn3 session-start --config hell
```

`net_gateway`는 "VPN 직전의 원래 기본 게이트웨이"를 가리키는 키워드라, 사무실/집/카페 어디서든 자동으로 잡힌다 (portable).

---

## 12. 핵심 요약 (한 장)

```
설치:    apt repo 등록 → apt install openvpn3
브라우저: xdg-settings set default-web-browser firefox.desktop
정리:    systemctl stop/disable openvpn@*, AUTOSTART="none"
import:  openvpn3 config-import --config <path> --persistent --name hell
연결:    openvpn3 session-start --config hell  → 브라우저 SSO
검증:    openvpn3 sessions-list, ip addr show tun0, ping git.rtst.co.kr
끊기:    openvpn3 session-manage --config hell --disconnect
```
