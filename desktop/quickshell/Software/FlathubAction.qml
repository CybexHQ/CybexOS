import QtQuick
import "../Common"

// The one right action for a Flathub app wherever it appears: Install (right
// away, for this account), Open, the change on its way, or Unavailable.
SoftwareButton {
    id: root

    // A Flathub search result, or an app page's details: {id, name, …}.
    property var entry: null
    // An accent-filled Install, for the one main action of a surface.
    property bool prominent: false

    readonly property string mode: Software.flathubMode(entry)

    visible: mode !== "none"
    text: mode === "open" ? I18n.tr("Open")
        : mode === "installing" ? I18n.tr("Installing…")
        : mode === "removing" ? I18n.tr("Removing…")
        : mode === "updating" ? I18n.tr("Updating…")
        : mode === "install" ? I18n.tr("Install")
        : I18n.tr("Unavailable")
    busy: ["installing", "removing", "updating"].includes(mode)
    primary: prominent && mode === "install"
    // One Flathub change at a time; the worker refuses a second one.
    enabled: (mode === "install" && !Software.flathubBusy) || mode === "open"
    accessibleName: !entry ? "" : mode === "open" ? I18n.format("Open %1", [entry.name || entry.id])
        : mode === "install" ? I18n.format("Install %1 from Flathub", [entry.name || entry.id])
        : text
    onTriggered: {
        if (mode === "open")
            Software.launchFlathub(entry.id, entry.name || "");
        else if (mode === "install")
            Software.installFlathub(entry.id, entry.name || "");
    }
}
