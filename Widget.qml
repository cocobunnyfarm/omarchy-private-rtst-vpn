import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// ─────────────────────────────────────────────────────────────────────────
// RTST VPN 바 위젯 — 골격 (아직 실기기 검증 전)
//
// 이 위젯은 openvpn3 도 RTST 도 모른다. `ctlCommand` 가 가리키는 CLI 를
// `Process` 로 호출해 JSON 을 받아 그리기만 한다. 계약은 README 참조.
//
// 검증 상태: openvpn3 미설치로 실동작 미확인. core/vpn-ctl 검증 후
//            팝업 UI 를 채운다.
// ─────────────────────────────────────────────────────────────────────────
BarWidget {
  id: root
  moduleName: "io.github.cocobunnyfarm.rtst-vpn"

  readonly property int refreshSec: setting("refreshIntervalSec", 15)
  readonly property string ctlCommand: setting("ctlCommand", "vpn-ctl")
  readonly property string configName: setting("configName", "hell")

  // vpn-ctl status --json 의 파싱 결과
  property string state: "unknown"
  property string detail: ""
  property string actionable: ""

  readonly property bool ready: state === "connected" || state === "disconnected"
                                || state === "authenticating"

  // 상태별 글리프
  readonly property string glyph: {
    switch (state) {
      case "connected":       return "󰦝"   // shield-check
      case "authenticating":  return "󰦛"   // shield-half
      case "disconnected":    return "󰦞"   // shield-off
      case "missing-backend":
      case "missing-config":  return "󰦝"
      default:                return "󰦞"
    }
  }

  // ── 상태 조회 ─────────────────────────────────────────────────────────
  Process {
    id: statusProc
    command: [root.ctlCommand, "status", "--json"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        // 명령 자체가 없으면 백엔드 미설치로 간주
        root.state = "missing-backend"
        root.detail = root.ctlCommand + " 를 찾을 수 없음"
        root.actionable = ""
        return
      }
      try {
        var d = JSON.parse(statusOut.text)
        root.state = d.state || "unknown"
        root.detail = d.detail || ""
        root.actionable = d.actionable || ""
      } catch (e) {
        root.state = "error"
        root.detail = "status JSON 파싱 실패"
        root.actionable = ""
      }
    }
  }

  function refreshNow() {
    if (!statusProc.running) statusProc.running = true
  }

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
    onExited: root.refreshNow()
  }

  function connect() {
    if (actionProc.running) return
    actionProc.command = [root.ctlCommand, "up", root.configName]
    actionProc.running = true
  }

  function disconnect() {
    if (actionProc.running) return
    actionProc.command = [root.ctlCommand, "down", root.configName]
    actionProc.running = true
  }

  // 의존성 미충족 시 — 자동 설치하지 않는다. 보이는 터미널을 띄운다.
  // (AUR 은 yay 가 sudo 를 직접 물어보고 makepkg 가 root 를 거부하므로
  //  위젯에서의 자동 설치는 기계적으로 불가능. README 참조)
  Process { id: termProc }

  function runInTerminal(cmd) {
    if (termProc.running || !cmd) return
    termProc.command = ["omarchy-launch-floating-terminal-with-presentation", cmd]
    termProc.running = true
  }

  // ── 팝업 라우팅 계약 ──────────────────────────────────────────────────
  property bool panelOpen: false
  readonly property bool opened: panelOpen
  function open() { panelOpen = true; refreshNow() }
  function close() { panelOpen = false }
  function togglePanel() { panelOpen ? close() : open() }

  IpcHandler {
    target: "io.github.cocobunnyfarm.rtst-vpn"

    function refresh(): void { root.refreshNow() }
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

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refreshNow()
      else root.togglePanel()
    }
  }

  // ── 팝업 (골격 — 검증 후 확장) ────────────────────────────────────────
  readonly property real pad: Style.space(14)

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.panelOpen
    contentWidth: panel.fittedContentWidth(Style.space(280))
    contentHeight: panel.fittedContentHeight(col.implicitHeight + root.pad * 2)

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: col
        x: root.pad
        y: root.pad
        width: parent.width - root.pad * 2
        spacing: Style.space(8)

        Text {
          text: "RTST VPN"
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          text: root.state
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body * 1.2
          font.bold: true
        }

        Text {
          visible: root.detail !== ""
          text: root.detail
          width: parent.width
          wrapMode: Text.WordWrap
          color: Qt.darker(Color.foreground, 1.2)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
