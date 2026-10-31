pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/Format.js" as Format
import "../Common/SoftwareHelpers.js" as Helpers

// One everyday job on Software's home: the app doing it and who chose it
// (Cybex OS or you), or the app on its way while it installs. The whole card
// opens the job's picker.
Rectangle {
    id: root

    property var role: ({})
    readonly property var card: Software.roleCard(role.id || "")
    readonly property var pending: card.pending
    readonly property bool inFlight: pending !== null && !!pending.attribute && Software.flowActive
        && Helpers.list(Software.flowChange.installs).includes(pending.attribute)
    readonly property bool fromFlathub: pending !== null && !!pending.flathub
        && Helpers.flathubRunning(Helpers.flathubTask(Software.flathubTask, pending.flathub))
    readonly property real fraction: inFlight && Software.phase === "preparing" ? Software.preparation.fraction : -1

    function status() {
        switch (card.who) {
        case "system":
            return I18n.tr("Cybex pick");
        case "you":
            return I18n.tr("Your choice");
        case "none":
            return I18n.tr("Nothing set yet");
        }
        if (fromFlathub)
            return I18n.tr("Installing for you…");
        if (inFlight) {
            switch (Software.phase) {
            case "checking":
                return I18n.tr("Checking…");
            case "authorizing":
                return I18n.tr("Waiting for your password");
            case "preparing":
                return fraction >= 0 ? I18n.format("Downloading · %1%", [Math.round(fraction * 100)]) : I18n.tr("Downloading…");
            case "ready":
                return I18n.tr("Ready · finish below");
            case "installing":
                return I18n.tr("Installing…");
            }
        }
        if (pending && pending.attribute && Software.queued(pending.attribute) === "install")
            return I18n.tr("On your install list");
        return I18n.tr("Waiting to install");
    }

    objectName: "softwareDefaultCard"
    implicitHeight: Theme.scaled(92)
    radius: Theme.chipRadius + 4
    color: Theme.cardFill
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Theme.accentText : card.who === "none" ? Theme.stroke : Theme.hairlineSoft
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: Software.roleWord(role.id, "label") + ": " + (card.name || I18n.tr("Choose an app"))
    Accessible.description: status()
    Accessible.onPressAction: Software.openPicker(role.id)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            Software.openPicker(root.role.id);
            event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        rippleEnabled: false
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.openPicker(root.role.id)
    }

    Row {
        id: heading
        x: Theme.scaled(12)
        y: Theme.scaled(11)
        width: parent.width - Theme.scaled(24)
        spacing: Theme.scaled(6)
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: Helpers.ROLE_GLYPHS[root.role.id] || "apps"
            size: Theme.iconSmall
            color: Theme.textDim
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.iconSmall - change.width - parent.spacing * 2
            text: Software.roleWord(root.role.id, "label").toUpperCase()
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightSemibold
            font.letterSpacing: 0.8
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Row {
            id: change
            anchors.verticalCenter: parent.verticalCenter
            visible: root.card.who !== "switching"
            spacing: Theme.scaled(2)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.card.who === "none" ? I18n.tr("Choose") : I18n.tr("Change")
                color: mouse.containsMouse ? Theme.accentText : Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                textFormat: Text.PlainText
            }
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-right"
                size: Theme.iconTiny
                color: mouse.containsMouse ? Theme.accentText : Theme.textDim
            }
        }
    }

    Item {
        anchors.left: parent.left
        anchors.leftMargin: Theme.scaled(12)
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(12)
        anchors.top: heading.bottom
        anchors.topMargin: Theme.scaled(10)
        height: Theme.scaled(36)

        RoleIcon {
            id: icon
            visible: root.card.who !== "none"
            opacity: root.card.who === "switching" ? 0.55 : 1
            option: root.card.option
            desktop: root.card.desktop
            size: Theme.scaled(36)
        }
        Rectangle {
            visible: root.card.who === "none"
            width: Theme.scaled(36)
            height: width
            radius: Math.round(width * 0.24)
            color: "transparent"
            border.width: 1
            border.color: Theme.stroke
            Sym {
                anchors.centerIn: parent
                name: Helpers.ROLE_GLYPHS[root.role.id] || "apps"
                size: Theme.iconMedium
                color: Theme.textDim
            }
        }
        Column {
            anchors.left: icon.right
            anchors.leftMargin: Theme.scaled(10)
            anchors.right: parent.right
            anchors.verticalCenter: icon.verticalCenter
            spacing: Theme.scaled(1)
            Text {
                objectName: "softwareDefaultName"
                width: parent.width
                text: root.card.name || I18n.tr("Choose an app")
                color: root.card.who === "none" ? Theme.accentText : Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Row {
                width: parent.width
                spacing: Theme.scaled(5)
                Spinner {
                    visible: root.card.who === "switching"
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.iconTiny
                    color: Theme.textMid
                }
                Rectangle {
                    visible: root.card.who === "you"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.scaled(6)
                    height: width
                    radius: width / 2
                    color: Theme.accent
                }
                Text {
                    objectName: "softwareDefaultStatus"
                    width: parent.width - Theme.iconTiny - parent.spacing
                    text: root.status()
                    color: root.card.who === "you" ? Theme.accentText : root.card.who === "switching" ? Theme.textMid : Theme.textDim
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }
    }

    // Download progress while the app's change is prepared.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: Theme.scaled(3)
        radius: height / 2
        visible: root.fraction >= 0
        color: Theme.chip
        Rectangle {
            width: parent.width * Format.clamp01(root.fraction)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }
}
