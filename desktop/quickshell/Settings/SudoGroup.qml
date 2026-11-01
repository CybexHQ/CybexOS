pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Sudo without password (docs/sudo.md): one root-owned sudoers rule for the
// primary user, added or removed by a narrow Polkit helper. It applies at
// once, with no rebuild or restart, and system prompts keep asking.
SettingsGroup {
    id: root
    readonly property SystemSettingsBackend service: SystemSettings.passwordlessSudo
    readonly property var sudoState: service.snapshot
    // A personal module that turns off every administrator's password wins;
    // the switch shows that instead of offering a choice it cannot make.
    readonly property bool declared: sudoState.passwordRequired === false
    title: "Sudo" // i18n: untranslated
    changeTag: "admin"

    Claim {
        active: root.visible && Settings.panelOpen
        onClaimed: root.service.acquire()
        onReleased: root.service.release()
    }
    SystemServiceStatus { width: parent.width; service: root.service }
    SwitchRow {
        width: parent.width
        label: I18n.tr("Sudo without password")
        dirty: false
        resetKeys: []
        checked: root.sudoState.enabled === true || root.declared
        description: checked
            ? I18n.tr("sudo no longer asks for your password, so apps and scripts you run can act as administrator. System prompts still ask.")
            : I18n.tr("Run sudo in a terminal without typing your password. System prompts still ask for it.")
        hintTone: checked ? "warning" : "info"
        disabledReason: !root.service.loaded ? I18n.tr("Checking…")
            : root.declared ? I18n.tr("Managed in /etc/nixos/local")
            : !root.sudoState.available ? I18n.tr("Unavailable")
            : root.service.busy ? I18n.tr("Applying…") : ""
        onToggled: value => root.service.run({action: "set-enabled", enabled: value})
    }
}
