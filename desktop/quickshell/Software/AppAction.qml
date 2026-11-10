import QtQuick
import "../Common"

// The one right action for a catalogue app wherever it appears: Add to
// queue, In queue (press again to take it out), Open (also when it was
// installed from Flathub instead), or why it can't be installed yet.
//
// One rule for the words: "Install" always starts installing now (the
// queue bar's "Install N apps", a Flathub app, "Install and use"), while a
// NixOS app only joins the queue, because the queued apps install together
// as one checked system change (docs/software-and-defaults.md).
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
        : app.installed || Software.viaFlathub(app) ? "open"
        : queuedAction === "install" ? "added"
        : app.unavailable ? "unavailable"
        : verdict && verdict.state === "compiles" ? "compiles"
        : "install"

    // Pressing it adds the app to the install queue.
    readonly property bool adds: mode === "install"

    visible: mode !== "none"
    text: mode === "open" ? I18n.tr("Open")
        : mode === "added" ? I18n.tr("In queue")
        : mode === "installing" ? I18n.tr("Installing…")
        : mode === "ready" ? I18n.tr("Ready to install")
        : mode === "unavailable" ? I18n.tr("Unavailable")
        : mode === "compiles" ? I18n.tr("Not ready yet")
        : I18n.tr("Add to queue")
    queued: mode === "added" || mode === "ready"
    glyph: queued ? "check" : adds ? "plus" : ""
    primary: prominent && mode === "install"
    busy: mode === "installing"
    enabled: mode === "install" || mode === "added" || (mode === "open" && Software.canOpenApp(app))
    accessibleName: !app ? "" : mode === "open" ? I18n.format("Open %1", [app.name])
        : mode === "added" ? I18n.format("Take %1 out of the install queue", [app.name])
        : mode === "install" ? I18n.format("Add %1 to the install queue", [app.name])
        : text
    onTriggered: {
        if (mode === "open")
            Software.openApplication(app);
        else if (mode === "install" || mode === "added")
            Software.toggleInstall(attribute);
    }
}
