import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// ─────────────────────────────────────────────────────────────────────────
// RTST VPN 바 위젯
//
// 이 위젯은 openvpn3 도 RTST 도 모른다. core/vpn-ctl 을 Process 로 호출해
// JSON 을 받아 그리기만 한다. 계약은 README 참조.
//
// 화면은 준비 상태에 따라 단계적으로 바뀐다:
//   missing-backend → openvpn3 설치 안내만 보여준다 (그 전엔 나머지가 무의미)
//   missing-config  → .ovpn 파일 선택 UI. 사용자가 아직 아무 파일도 고르지
//                      않은 상태이므로 연결 버튼은 아예 나오지 않는다
//   그 외           → 정상 연결/끊기 UI + 끊긴 상태에서만 프로파일 관리
// ─────────────────────────────────────────────────────────────────────────
BarWidget {
  id: root
  moduleName: "io.github.cocobunnyfarm.rtst-vpn"

  // 플러그인 폴더 기준 절대경로. PATH 에 의존하면 안 된다 —
  // core/ 는 플러그인과 함께 배포되므로 self-contained 로 해석한다.
  readonly property string backendCommand:
    String(Qt.resolvedUrl("core/vpn-ctl")).replace(/^file:\/\//, "")

  readonly property int refreshSec: setting("refreshIntervalSec", 15)

  // vpn-ctl status --json 파싱 결과
  // 프로파일 이름은 코어가 정한다. UI 는 status 가 알려준 것을 받아 보여줄 뿐,
  // 어떤 명령에도 이름을 넘기지 않는다 — 넘기는 순간 코어의 자동 발견/복구와
  // 어긋나서, 복구된 프로파일에 대고 없는 이름으로 연결을 시도하게 된다.
  property string activeConfig: ""

  // 보관된 .ovpn 목록: [{ name, file, active }, …]
  // 코어의 보관소($XDG_CONFIG_HOME/rtst-vpn)가 유일한 근거다. status 가
  // 매번 함께 실어 주므로 따로 조회하지 않는다 — 목록과 상태가 어긋날 수 없다.
  property var profiles: []
  readonly property bool hasProfile: profiles.length > 0

  // 삭제 2단계 확인. 패널 안에서 끝내려고 ConfirmDialog 대신 버튼 자체가
  // "정말?" 로 바뀌는 방식을 쓴다.
  property string pendingForget: ""

  property string vpnState: "loading"
  property string detail: ""
  property string actionable: ""
  property string lastError: ""
  property string authUrl: ""
  property bool urlCopied: false

  readonly property bool busy: statusProc.running || actionProc.running
                               || pickProc.running || importProc.running

  // 아이콘은 두 종류만 쓴다 — 바에 위젯이 여러 개라 종류가 많으면 헷갈린다.
  //   󰦝 온전한 쉴드  : 쓸 준비가 된 상태 (연결됨 / 미연결 / 인증 중)
  //   󰦞 금간 쉴드    : 쓸 수 없는 상태 (백엔드·프로파일 없음 / 오류)
  // backend-busy / loading 은 "프로파일 없음" 이 아니라 "아직 모름" 이다.
  // 금간 쉴드를 보여주면 사용자가 뭔가 깨진 줄 알게 되므로 온전한 쉴드로 둔다.
  readonly property bool usable: vpnState === "connected"
                                 || vpnState === "disconnected"
                                 || vpnState === "authenticating"
                                 || vpnState === "backend-busy"
                                 || vpnState === "loading"

  readonly property string glyph: usable ? "󰦝" : "󰦞"

  // 밝기로 구분한다. 색을 직접 지정하지 않고 WidgetButton 의 dimmed 를 쓴다 —
  // 바의 기본 전경색(bar.barForeground)을 그대로 쓰면서 opacity 만 45% 로
  // 떨어뜨리므로 테마가 바뀌어도 어긋나지 않는다.
  //   연결됨   → 100% (밝은 흰색)
  //   그 외    → 45%  (회색으로 보임)
  readonly property bool connected: vpnState === "connected"

  // 사람이 읽는 제목
  readonly property string headline: {
    switch (vpnState) {
      case "loading":            return "확인 중…"
      case "backend-busy":       return "확인 중…"
      case "missing-backend":    return "openvpn3 설치 필요"
      case "missing-config":     return ".ovpn 파일 등록 필요"
      case "disconnected":    return "연결 안 됨"
      case "authenticating":  return "브라우저에서 로그인 대기"
      case "connected":       return "연결됨"
      case "backend-failed":  return "vpn-ctl 실행 실패"
      default:                return "오류"
    }
  }

  // ── 상태 조회 ─────────────────────────────────────────────────────────
  Process {
    id: statusProc
    command: [root.backendCommand, "status", "--json"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // vpn-ctl 자체가 실행되지 않은 경우 — 경로 문제 등
        root.vpnState = "backend-failed"
        root.detail = statusErr.text.trim() || (root.backendCommand + " 실행 실패")
        root.actionable = ""
        return
      }
      try {
        var d = JSON.parse(statusOut.text)
        root.vpnState = d.state || "error"
        root.activeConfig = d.config || ""
        root.profiles = d.profiles || []
        root.detail = d.detail || ""
        root.actionable = d.actionable || ""
      } catch (e) {
        root.vpnState = "backend-failed"
        root.detail = "status JSON 파싱 실패: " + statusOut.text.trim().slice(0, 120)
        root.actionable = ""
        root.profiles = []
      }
    }
  }

  function refreshNow() { if (!statusProc.running) statusProc.running = true }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  // ── 연결 / 끊기 ───────────────────────────────────────────────────────
  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.lastError = actionErr.text.trim()
      root.refreshNow()
    }
  }

  function runAction(args) {
    if (actionProc.running) return
    root.lastError = ""
    actionProc.command = [root.backendCommand].concat(args)
    actionProc.running = true
  }

  function connectVpn()    { runAction(["up"]) }
  function disconnectVpn() { runAction(["down"]) }

  // ── .ovpn 파일 선택 → import ──────────────────────────────────────────
  // Omarchy 공식 파일 선택기. 종료코드 1 = 아무것도 안 고름(정상),
  // 2 = 선택기가 뜨지 않음(실패). 둘을 구분해 처리한다.
  Process {
    id: pickProc
    command: ["omarchy-file-select", "--title", "회사 .ovpn 파일 선택",
              "--extensions", "ovpn conf"]
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        var path = pickOut.text.trim().split("\n")[0]
        if (path.length > 0) root.importConfig(path)
      } else if (code === 2) {
        root.lastError = "파일 선택기를 열 수 없습니다"
      }
      // code === 1 은 사용자가 취소한 것 — 조용히 넘어간다
    }
  }

  Process {
    id: importProc
    stderr: StdioCollector { id: importErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.lastError = importErr.text.trim() || "import 실패"
      root.refreshNow()
    }
  }

  function pickConfig() { if (!pickProc.running) pickProc.running = true }

  // ── 프로파일 관리 ────────────────────────────────────────────────────
  // 활성 전환·삭제는 코어에 그대로 넘긴다. UI 는 어느 파일이 활성인지도
  // 스스로 기억하지 않는다 — 다음 status 가 알려 준다.
  function useProfile(name) {
    root.pendingForget = ""
    runAction(["use", name])
  }

  function forgetProfile(name) {
    root.pendingForget = ""
    runAction(["forget", name])
  }

  // 첫 클릭은 확인을 요청하고, 같은 항목을 다시 누르면 실제로 지운다.
  function requestForget(name) {
    if (root.pendingForget === name) { root.forgetProfile(name); return }
    root.pendingForget = name
    forgetReset.restart()
  }

  Timer { id: forgetReset; interval: 4000; onTriggered: root.pendingForget = "" }

  function importConfig(path) {
    if (importProc.running) return
    root.lastError = ""
    importProc.command = [root.backendCommand, "import", path]
    importProc.running = true
  }

  // ── 인증 URL 복사 ─────────────────────────────────────────────────────
  // openvpn3 는 인증 URL 을 XDG Desktop Portal 로 넘겨 시스템 기본 브라우저에
  // 띄운다. 그걸 바꿀 방법이 없다 ($BROWSER 무시, xdg-open 미호출, 끄는 옵션
  // 없음). 전역 기본 브라우저를 바꾸는 건 VPN 인증 하나를 위해 치를 대가가
  // 아니므로, 대신 URL 을 복사해 원하는 브라우저에서 열게 한다.
  // URL 은 세션에 묶여 있어 어디서 로그인해도 그 세션이 연결된다.
  Process {
    id: urlProc
    command: [root.backendCommand, "auth-url"]
    stdout: StdioCollector { id: urlOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { root.lastError = "인증 URL 을 가져오지 못했습니다"; return }
      root.authUrl = urlOut.text.trim()
      if (root.authUrl.length > 0) {
        copyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", root.authUrl]
        copyProc.running = true
      }
    }
  }

  Process {
    id: copyProc
    onExited: function(code) {
      root.urlCopied = (code === 0)
      if (code !== 0) root.lastError = "클립보드 복사 실패"
      copiedReset.restart()
    }
  }

  Timer { id: copiedReset; interval: 2500; onTriggered: root.urlCopied = false }

  function copyAuthUrl() {
    if (urlProc.running || copyProc.running) return
    root.lastError = ""
    urlProc.running = true
  }

  // ── 설치 안내 (자동 설치하지 않는다 — README 참조) ────────────────────
  Process { id: termProc }

  function openInstallTerminal() {
    if (termProc.running || root.actionable.length === 0) return
    termProc.command = ["omarchy-launch-floating-terminal-with-presentation",
                        root.actionable]
    termProc.running = true
  }

  Process { id: menuProc }

  // Omarchy 의 AUR 설치기(fzf 검색)를 바로 띄운다. openvpn3 는 공식 저장소가
  // 아니라 AUR 이므로 Install > Package 가 아니라 Install > AUR 로 보낸다.
  function openAurMenu() {
    if (menuProc.running) return
    menuProc.command = ["omarchy", "menu", "summon", "install.aur"]
    menuProc.running = true
  }

  // ── 팝업 라우팅 계약 ──────────────────────────────────────────────────
  property bool panelOpen: false
  readonly property bool opened: panelOpen
  function open() { panelOpen = true; urlCopied = false; pendingForget = ""; refreshNow() }
  function close() { panelOpen = false }
  function togglePanel() { panelOpen ? close() : open() }

  IpcHandler {
    target: "io.github.cocobunnyfarm.rtst-vpn"
    function refresh(): void { root.refreshNow() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ── 바 표시 ───────────────────────────────────────────────────────────
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    dimmed: !root.connected

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refreshNow()
      else root.togglePanel()
    }
  }

  // ── 팝업 ──────────────────────────────────────────────────────────────
  readonly property real pad: Style.space(14)

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.panelOpen
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(col.implicitHeight + root.pad * 2)

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: col
        x: root.pad
        y: root.pad
        width: parent.width - root.pad * 2
        spacing: Style.space(10)

        PanelSectionHeader { text: "RTST VPN" }

        Text {
          text: root.headline
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body * 1.15
          font.bold: true
        }

        // 어느 프로파일로 연결됐는지. 연결/인증 중에는 프로파일 관리 목록이
        // 숨겨지므로, 이게 없으면 "무엇으로 붙었는지" 를 볼 방법이 없다.
        Text {
          visible: root.activeConfig.length > 0
                   && root.vpnState !== "missing-backend"
                   && root.vpnState !== "missing-config"
          text: "󰦝  " + root.activeConfig
          color: Qt.darker(Color.foreground, 1.2)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.detail.length > 0 && root.vpnState !== "missing-backend"
                   && root.vpnState !== "missing-config"
          text: root.detail
          width: parent.width
          wrapMode: Text.WordWrap
          color: Qt.darker(Color.foreground, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // ── 1단계: openvpn3 미설치 ──────────────────────────────────────
        // 이게 없으면 나머지가 전부 무의미하므로 이 화면만 보여준다.
        Column {
          visible: root.vpnState === "missing-backend"
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator { width: parent.width }

          Text {
            text: "openvpn3 패키지를 설치해주세요."
            width: parent.width
            wrapMode: Text.WordWrap
            color: Qt.darker(Color.foreground, 1.2)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: "AUR 설치 메뉴"
              bordered: true
              onClicked: root.openAurMenu()
            }

            Button {
              text: "터미널에서 실행"
              bordered: true
              onClicked: root.openInstallTerminal()
            }
          }
        }

        // ── 2단계: 프로파일 없음 (최초 설정) ────────────────────────────
        // 보관본이 있으면 코어가 조용히 복원하므로 이 화면은 정말 처음일 때만
        // 나온다. "복구할까요?" 를 묻지 않는다 — 이미 한 결정을 다시 묻는 것이므로.
        Column {
          visible: root.vpnState === "missing-config"
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { width: parent.width }

          Text {
            text: "회사에서 받은 .ovpn 파일을 선택하세요."
            width: parent.width
            wrapMode: Text.WordWrap
            color: Qt.darker(Color.foreground, 1.2)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Button {
            text: root.busy ? "처리 중…" : ".ovpn 파일 선택"
            bordered: true
            enabled: !root.busy
            onClicked: root.pickConfig()
          }
        }

        // ── 3단계: 정상 동작 ────────────────────────────────────────────
        Column {
          visible: root.usable
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { width: parent.width }

          // 등록된 .ovpn 이 없으면 누를 수 없다. disconnected 자체가 이미
          // "활성 프로파일이 있다" 는 뜻이지만, 상태와 목록이 어긋나는 순간이
          // 있더라도 연결을 시도하지 않도록 hasProfile 을 함께 본다.
          Button {
            visible: root.vpnState === "disconnected"
            text: root.busy ? "연결 중…" : "연결"
            bordered: true
            enabled: !root.busy && root.hasProfile
            onClicked: root.connectVpn()
          }

          Button {
            visible: root.vpnState === "connected"
                     || root.vpnState === "authenticating"
            text: root.busy ? "처리 중…" : "끊기"
            bordered: true
            enabled: !root.busy
            onClicked: root.disconnectVpn()
          }

          Text {
            visible: root.vpnState === "authenticating"
            text: "브라우저에서 Google 로그인을 완료하면 연결됩니다."
            width: parent.width
            wrapMode: Text.WordWrap
            color: Qt.darker(Color.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // 인증은 시스템 기본 브라우저로 열린다. 다른 브라우저에서 하려면
          // URL 을 복사해 직접 연다.
          Button {
            visible: root.vpnState === "authenticating"
            text: root.urlCopied ? "복사됨" : "인증 URL 복사"
            bordered: true
            enabled: !urlProc.running && !copyProc.running
            onClicked: root.copyAuthUrl()
          }

          // 프로파일 관리는 연결이 끊긴 상태에서만 노출한다 — 연결 중에
          // 프로파일을 갈아치우면 살아 있는 세션과 어긋난다.
          Column {
            visible: root.vpnState === "disconnected"
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { width: parent.width }

            PanelSectionHeader { text: "프로파일" }

            // 한 줄에 하나. 이름을 누르면 활성 전환, 오른쪽 버튼으로 삭제.
            // 보통 1개뿐이라 드롭다운보다 목록이 낫다 — 몇 개가 있고 어느
            // 것이 활성인지 펼치지 않고 바로 보인다.
            Repeater {
              model: root.profiles

              delegate: Row {
                id: profileRow
                // Repeater 가 넘겨주는 항목. 자식에서 맨몸의 modelData 를 쓰면
                // 델리게이트 컨텍스트에 암묵적으로 의존하게 되므로 명시한다.
                required property var modelData

                width: parent.width
                spacing: Style.space(6)

                readonly property bool isActive: profileRow.modelData.active === true
                readonly property string profileName: String(profileRow.modelData.name)

                Button {
                  width: profileRow.width - delBtn.width - Style.space(6)
                  leftAlign: true
                  bordered: profileRow.isActive
                  selected: profileRow.isActive
                  text: (profileRow.isActive ? "󰄬  " : "     ") + profileRow.profileName
                  tooltipText: profileRow.isActive ? "활성 프로파일" : "이 프로파일로 전환"
                  enabled: !root.busy && !profileRow.isActive
                  onClicked: root.useProfile(profileRow.profileName)
                }

                Button {
                  id: delBtn
                  bordered: true
                  text: root.pendingForget === profileRow.profileName ? "정말?" : "삭제"
                  tooltipText: root.pendingForget === profileRow.profileName
                               ? "다시 누르면 보관본까지 삭제됩니다"
                               : "보관된 .ovpn 을 삭제"
                  enabled: !root.busy
                  onClicked: root.requestForget(profileRow.profileName)
                }
              }
            }

            Button {
              text: root.busy ? "처리 중…" : ".ovpn 추가"
              bordered: true
              enabled: !root.busy
              onClicked: root.pickConfig()
            }

            Text {
              text: "보관 위치: ~/.config/rtst-vpn"
              width: parent.width
              wrapMode: Text.WordWrap
              color: Qt.darker(Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ── 오류 표시 ───────────────────────────────────────────────────
        Column {
          visible: root.lastError.length > 0
          width: parent.width
          spacing: Style.space(4)

          PanelSeparator { width: parent.width }

          Text {
            text: root.lastError
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.bar && root.bar.urgent ? root.bar.urgent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
