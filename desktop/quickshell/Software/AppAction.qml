import QtQuick
import "../Common"

// The one right action for a catalogue app wherever it appears: Install,
// Added (on the list; press again to take it off), Open, or why it can't be
// installed yet.
SoftwareButton {
    id: root

    property var app: null
    // An accent-filled Install, for the one main action of a surface.
    property bool prominent: false

    readonly property string attribute: app && app.attribute ? app.attribute : ""
    readonly property string queuedAction: Software.queued(attribute)
    readonly property var verdict: attribute !== "" ? Software.checks[attribute] || null : null
    readonly property bool inFlight: attribute !== "" && !app.installed
        && ["checking", "authorizing", "preparing", "ready", "installing"].includes(Software.phase)
        && Software.flowChange.installs.includes(attribute)
    readonly property string mode: !app ? "none"
        : inFlight ? (Software.phase === "ready" ? "ready" : "installing")
        : app.installed ? "open"
        : queuedAction === "install" ? "added"
        : app.unavailable ? "unavailable"
        : verdict && verdict.state === "compiles" ? "compiles"
        : "install"

    visible: mode !== "none"
    text: mode === "open" ? I18n.tr("Open")
        : mode === "added" ? I18n.tr("Added")
        : mode === "installing" ? I18n.tr("Installing…")
        : mode === "ready" ? I18n.tr("Ready to install")
        : mode === "unavailable" ? I18n.tr("Unavailable")
        : mode === "compiles" ? I18n.tr("Not ready yet")
        : I18n.tr("Install")
    queued: mode === "added" || mode === "ready"
    glyph: queued ? "check" : ""
    primary: prominent && mode === "install"
    busy: mode === "installing"
    enabled: mode === "install" || mode === "added" || (mode === "open" && Software.canOpenApp(app))
    accessibleName: !app ? "" : mode === "open" ? I18n.format("Open %1", [app.name])
        : mode === "added" ? I18n.format("Take %1 off the install list", [app.name])
        : mode === "install" ? I18n.format("Install %1", [app.name])
        : text
    onTriggered: {
        if (mode === "open")
            Software.openApplication(app);
        else if (mode === "install" || mode === "added")
            Software.toggleInstall(attribute);
    }
}
