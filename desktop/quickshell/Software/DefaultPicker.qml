pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers
import "../Popovers" as Popovers

// One everyday job's picker, over Software: the apps Cybex OS has checked
// work with it, the others already on this computer, and, before anything
// happens, what choosing one does. Escape or a click outside closes it.
Rectangle {
    id: root

    readonly property string roleId: Software.picker
    readonly property var role: Software.rolesById[roleId] || null
    readonly property var roleState: Software.roleStates[roleId] || ({})
    readonly property var rows: role ? Software.roleChoices(roleId) : []
    readonly property var others: role ? Helpers.otherApps(role, roleState) : []
    readonly property string effective: roleState.effective || ""
    readonly property var card: Software.roleCard(roleId)
    // An option ID, or "other:" and an installed app's desktop entry ID.
    property string selected: ""
    property bool picked: false
    readonly property var chosenRow: rows.find(row => row.option.id === selected) || null
    readonly property var chosenOther: selected.indexOf("other:") === 0
        ? others.find(row => "other:" + row.value === selected) || null : null
    readonly property string chosenName: chosenRow ? chosenRow.option.name : chosenOther ? chosenOther.label : ""
    readonly property bool chosenCurrent: chosenRow ? Helpers.roleDesktops(chosenRow.option).includes(effective)
        : chosenOther !== null && chosenOther.value === effective
    readonly property bool chosenReady: chosenOther !== null || (chosenRow !== null && chosenRow.ready)

    function initial() {
        const current = Helpers.roleOptionFor(role, effective);
        if (current && rows.some(row => row.option.id === current.id))
            return current.id;
        if (others.some(row => row.value === effective))
            return "other:" + effective;
        return rows.length > 0 ? rows[0].option.id : "";
    }
    function pick(value) {
        selected = value;
        picked = true;
    }
    function joined(parts) { return parts.filter(part => part !== "").join(" "); }
    function message() {
        if (selected === "")
            return "";
        const noun = Software.roleWord(roleId, "noun");
        const carry = roleId === "browser"
            ? I18n.tr("Bookmarks and passwords stay where they are; most browsers offer to import them when they first start.")
            : roleId === "terminal" ? I18n.tr("Your shell and its settings come along unchanged.") : "";
        const keep = card.name !== "" && card.who !== "none" && card.who !== "switching"
            ? I18n.format("%1 stays installed, so you can switch back any time.", [card.name]) : "";
        if (chosenCurrent)
            return joined([I18n.format("%1 is your %2.", [chosenName, noun]), carry]);
        if (chosenOther || (chosenRow && chosenRow.source === "installed"))
            return joined([I18n.format("Switches to %1 right away.", [chosenName]), keep, carry]);
        switch (chosenRow ? chosenRow.source : "") {
        case "web":
            return I18n.format("Email links open a new message in %1, in your web browser. Nothing to install.", [chosenName]);
        case "nixos": {
            const size = Helpers.size(chosenRow.option.downloadBytes);
            return joined([size !== ""
                ? I18n.format("Installs %1 (≈ %2, prebuilt by NixOS), then switches to it. You confirm with your password; no restart.", [chosenName, size])
                : I18n.format("Installs %1, prebuilt by NixOS, then switches to it. You confirm with your password; no restart.", [chosenName]), keep]);
        }
        case "vendor":
            return joined([I18n.format("Downloads %1 from its maker, then switches to it. You confirm with your password; no restart.", [chosenName]), keep]);
        case "flathub":
            return joined([I18n.format("Installs %1 from Flathub for your account only, with no password and no restart. It runs in a sandbox and updates in the Updates tab.", [chosenName]), keep]);
        }
        return "";
    }
    function confirm() {
        if (chosenCurrent)
            return;
        if (chosenOther)
            Software.useOther(roleId, chosenOther.value);
        else if (chosenRow)
            Software.useDefault(roleId, chosenRow.option.id);
    }

    onRoleIdChanged: {
        picked = false;
        selected = role ? initial() : "";
        if (visible)
            list.contentY = 0;
    }
    // Status can arrive after the picker opens: select what is in use then.
    onEffectiveChanged: {
        if (role && !picked)
            selected = initial();
    }
    onRowsChanged: {
        if (role && !picked)
            selected = initial();
    }

    objectName: "softwareDefaultPicker"
    visible: role !== null
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0.08, 0.08, 0.14, 0.3)
    focus: visible
    Accessible.role: Accessible.Dialog
    Accessible.name: I18n.format("Choose your %1", [Software.roleWord(roleId, "noun")])
    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }
    Keys.onEscapePressed: Software.closePicker()

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.closePicker()
    }

    Rectangle {
        id: sheet
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.scaled(36)
        width: Math.min(parent.width - Theme.scaled(48), Theme.scaled(680))
        height: Math.min(parent.height - Theme.scaled(72), header.height + list.contentHeight + footer.height + Theme.scaled(18))
        radius: Theme.chipRadius + 8
        color: Theme.surfaceStrong
        border.width: 1
        border.color: Theme.hairline
        clip: true

        // Clicks inside the sheet stay in it.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header
            width: parent.width
            height: Math.max(badge.height, heading.implicitHeight) + Theme.scaled(32)
            Rectangle {
                id: badge
                x: Theme.scaled(18)
                y: Theme.scaled(16)
                width: Theme.scaled(42)
                height: width
                radius: Theme.chipRadius + 3
                color: Theme.accentAlpha(Theme.dark ? 0.16 : 0.13)
                Sym {
                    anchors.centerIn: parent
                    name: Helpers.ROLE_GLYPHS[root.roleId] || "apps"
                    size: Theme.iconLarge
                    color: Theme.accentText
                }
            }
            Column {
                id: heading
                anchors.left: badge.right
                anchors.leftMargin: Theme.scaled(14)
                anchors.right: close.left
                anchors.rightMargin: Theme.scaled(12)
                y: Theme.scaled(16)
                spacing: Theme.scaled(3)
                Text {
                    objectName: "softwareDefaultPickerTitle"
                    width: parent.width
                    text: I18n.format("Choose your %1", [Software.roleWord(root.roleId, "noun")])
                    color: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.title
                    font.weight: Theme.weightBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Text {
                    width: parent.width
                    text: Software.roleWord(root.roleId, "use")
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }
            SoftwareButton {
                id: close
                anchors.right: parent.right
                anchors.rightMargin: Theme.scaled(14)
                y: Theme.scaled(14)
                quiet: true
                glyph: "x"
                accessibleName: I18n.tr("Close")
                onTriggered: Software.closePicker()
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.hairlineSoft
            }
        }

        Flickable {
            id: list
            anchors.top: header.bottom
            anchors.bottom: footer.top
            width: parent.width
            contentHeight: options.implicitHeight + Theme.scaled(18)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: options
                x: Theme.scaled(10)
                y: Theme.scaled(8)
                width: list.width - Theme.scaled(20)
                spacing: Theme.scaled(2)
                Repeater {
                    model: root.rows
                    delegate: DefaultOption {
                        required property var modelData
                        width: options.width
                        row: modelData
                        selected: root.selected === modelData.option.id
                        current: Helpers.roleDesktops(modelData.option).includes(root.effective)
                        pick: !!root.roleState.system && Helpers.roleDesktops(modelData.option).includes(root.roleState.system)
                        onChosen: root.pick(modelData.option.id)
                        onConfirmed: root.confirm()
                    }
                }
                Item {
                    width: parent.width
                    height: group.implicitHeight
                    visible: root.others.length > 0
                    GroupLabel {
                        id: group
                        x: Theme.scaled(12)
                        width: parent.width - Theme.scaled(24)
                        text: I18n.tr("Also on this computer")
                    }
                }
                Repeater {
                    model: root.others
                    delegate: DefaultOption {
                        required property var modelData
                        width: options.width
                        row: ({ other: modelData })
                        selected: root.selected === "other:" + modelData.value
                        current: modelData.value === root.effective
                        pick: modelData.value === root.roleState.system
                        onChosen: root.pick("other:" + modelData.value)
                        onConfirmed: root.confirm()
                    }
                }
                Item {
                    width: parent.width
                    height: more.implicitHeight + Theme.scaled(16)
                    Sym {
                        id: find
                        x: Theme.scaled(14)
                        anchors.verticalCenter: more.verticalCenter
                        name: "search"
                        size: Theme.iconSmall
                        color: Theme.textDim
                    }
                    Popovers.LinkText {
                        id: more
                        anchors.left: find.right
                        anchors.leftMargin: Theme.scaled(8)
                        y: Theme.scaled(8)
                        text: I18n.format("Find another %1 in Software", [Software.roleWord(root.roleId, "noun")])
                        font.pixelSize: Theme.typography.secondary
                        onClicked: {
                            const terms = Software.roleWord(root.roleId, "search");
                            Software.closePicker();
                            Software.search(terms);
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(note.implicitHeight, buttons.implicitHeight) + Theme.scaled(28)
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairlineSoft
            }
            Text {
                id: note
                objectName: "softwareDefaultPickerNote"
                anchors.left: parent.left
                anchors.leftMargin: Theme.scaled(18)
                anchors.right: buttons.left
                anchors.rightMargin: Theme.scaled(16)
                anchors.verticalCenter: parent.verticalCenter
                text: root.message()
                color: Theme.textMid
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: Theme.scaled(16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.scaled(8)
                SoftwareButton {
                    big: true
                    text: I18n.tr("Cancel")
                    onTriggered: Software.closePicker()
                }
                SoftwareButton {
                    objectName: "softwareDefaultUse"
                    big: true
                    primary: true
                    enabled: root.selected !== "" && !root.chosenCurrent
                    text: root.chosenCurrent ? I18n.tr("In use")
                        : root.chosenReady ? I18n.format("Use %1", [root.chosenName]) : I18n.tr("Install and use")
                    onTriggered: root.confirm()
                }
            }
        }
    }
}
