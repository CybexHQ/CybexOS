pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Back, search, and the three tabs. Updates carries a count of installed
// apps a prepared system update changes, or a dot while updates wait.
Rectangle {
    id: root

    readonly property alias field: input
    readonly property var tabs: [
        { id: "explore", label: I18n.tr("Explore") },
        { id: "installed", label: I18n.tr("Installed") },
        { id: "updates", label: I18n.tr("Updates") }
    ]

    // When the search's minimum width, the tabs and the buttons no longer fit
    // side by side, the search folds to an icon button. Activating it, typing,
    // / or Ctrl+F opens the field over the tabs; Escape or leaving the field
    // folds it again. The query stays, and with it the results.
    readonly property real searchMinimum: Theme.scaled(180)
    readonly property bool searchFolded: back.x + back.width + Theme.scaled(10)
        + searchMinimum + Theme.scaled(12) > tabTrack.x
    property bool searchOpen: false
    readonly property bool searchCovering: searchFolded && searchOpen
    readonly property bool fieldShown: !searchFolded || searchOpen

    function openSearch() {
        searchOpen = true;
        input.forceActiveFocus();
    }

    // SoftwareView reports every press in the window: one outside the open
    // field folds it, as leaving it by keyboard does.
    function pressedAt(scenePoint) {
        if (!searchCovering)
            return;
        const local = search.mapFromItem(null, scenePoint.x, scenePoint.y);
        if (local.x < 0 || local.y < 0 || local.x > search.width || local.y > search.height)
            searchOpen = false;
    }

    function focusSearch(text) {
        openSearch();
        if (text) {
            input.insert(input.cursorPosition, text);
            Software.search(input.text);
        }
    }

    implicitHeight: Theme.scaled(58)
    color: Theme.surfaceStrong

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }

    SoftwareButton {
        id: back
        objectName: "softwareBack"
        x: Theme.scaled(14)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.scaled(34)
        height: Theme.scaled(34)
        quiet: true
        glyph: "chevron-left"
        opacity: Software.canGoBack ? 1 : 0
        enabled: Software.canGoBack
        accessibleName: I18n.tr("Back")
        onTriggered: Software.back()
    }

    Rectangle {
        id: search
        objectName: "softwareSearchBox"
        anchors.left: back.right
        anchors.leftMargin: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        // Over the tabs it reaches the refresh button.
        width: !root.searchFolded
            ? Math.min(Theme.scaled(290), Math.max(root.searchMinimum, (root.width - tabTrack.width) / 2 - Theme.scaled(70)))
            : root.searchOpen ? refresh.x - Theme.scaled(10) - x : Theme.scaled(36)
        height: Theme.scaled(34)
        z: root.searchCovering ? 1 : 0
        radius: Theme.chipRadius + 1
        color: Theme.chip
        // The field shows focus after a click too; the folded button shows
        // the keyboard ring.
        border.width: input.activeFocus ? 2 : activeFocus ? Theme.focusWidth(activeFocus) : 1
        border.color: input.activeFocus ? Theme.accentText : activeFocus ? Theme.focusRing : Theme.hairlineSoft
        activeFocusOnTab: !root.fieldShown
        Accessible.role: root.fieldShown ? Accessible.Grouping : Accessible.Button
        Accessible.name: I18n.tr("Search apps and packages")
        Accessible.onPressAction: root.openSearch()
        Keys.onPressed: event => {
            if (!root.fieldShown && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space)) {
                root.openSearch();
                event.accepted = true;
            }
        }

        Behavior on width {
            enabled: root.searchFolded && !Theme.reducedMotion
            NumberAnimation {
                duration: Theme.chipFadeDuration
                easing.type: Easing.OutCubic
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            visible: !root.fieldShown
            hovered: foldedMouse.containsMouse
            pressed: foldedMouse.pressed
            tint: Theme.textHi
            pressPoint: Qt.point(foldedMouse.mouseX, foldedMouse.mouseY)
        }
        MouseArea {
            id: foldedMouse
            anchors.fill: parent
            enabled: !root.fieldShown
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openSearch()
        }

        Sym {
            id: glass
            x: root.fieldShown ? Theme.scaled(10) : (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: Theme.iconMedium
            color: Theme.textDim
        }
        TextInput {
            id: input
            objectName: "softwareSearch"
            visible: root.fieldShown
            anchors.left: glass.right
            anchors.leftMargin: Theme.scaled(8)
            anchors.right: clear.visible ? clear.left : parent.right
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            text: Software.query
            color: Theme.textHi
            selectionColor: Theme.accentAlpha(0.4)
            selectedTextColor: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            clip: true
            maximumLength: 200
            activeFocusOnTab: true
            Accessible.role: Accessible.EditableText
            Accessible.name: I18n.tr("Search apps and packages")
            onTextEdited: Software.search(text)
            onActiveFocusChanged: {
                if (!activeFocus)
                    root.searchOpen = false;
            }
            Keys.onDownPressed: event => { event.accepted = false; }
            // Folded, Escape first folds the field back over the tabs and
            // returns focus to the search button; with a query it also goes
            // on to leave the search, as it does unfolded.
            Keys.onEscapePressed: event => {
                const folding = root.searchCovering;
                if (folding) {
                    root.searchOpen = false;
                    search.forceActiveFocus();
                }
                event.accepted = folding && input.text === "";
            }
            Text {
                anchors.fill: parent
                visible: input.text === ""
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr("Search apps")
                color: Theme.textFaint
                font: input.font
                elide: Text.ElideRight
            }
        }
        Sym {
            id: clear
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.fieldShown && input.text !== ""
            name: "x"
            size: Theme.iconSmall
            color: clearMouse.containsMouse ? Theme.textHi : Theme.textDim
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("Clear search")
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                anchors.margins: -Theme.scaled(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Software.search("");
                    input.forceActiveFocus();
                }
            }
        }
    }

    Rectangle {
        id: tabTrack
        anchors.centerIn: parent
        // Covered by the open search, and out of the Tab order meanwhile.
        visible: !root.searchCovering
        width: tabRow.implicitWidth + Theme.scaled(6)
        height: Theme.scaled(36)
        radius: Theme.chipRadius + 2
        color: Theme.chip
        border.width: 1
        border.color: Theme.hairlineSoft
        Accessible.role: Accessible.PageTabList

        Row {
            id: tabRow
            anchors.centerIn: parent
            spacing: Theme.scaled(2)
            Repeater {
                id: tabRepeater
                model: root.tabs
                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool selected: Software.tab === modelData.id
                    readonly property int badge: modelData.id === "updates" ? Software.updates.length : 0
                    readonly property bool dot: modelData.id === "updates" && badge === 0 && Updates.hasUpdates
                    objectName: "softwareTab-" + modelData.id
                    width: label.implicitWidth + (badge > 0 ? badgeChip.width + Theme.scaled(7) : dot ? Theme.scaled(13) : 0) + Theme.scaled(30)
                    height: Theme.scaled(30)
                    radius: Theme.chipRadius
                    color: selected ? Theme.segmentSelected : tabMouse.containsMouse ? Theme.hoverFill : "transparent"
                    border.width: tab.activeFocus ? 2 : selected ? 1 : 0
                    border.color: tab.activeFocus ? Theme.accentText : Theme.stroke
                    activeFocusOnTab: selected
                    Accessible.role: Accessible.PageTab
                    Accessible.name: tab.badge > 0 ? I18n.format("%1, %2 apps with updates", [tab.modelData.label, tab.badge]) : tab.modelData.label
                    Accessible.selected: tab.selected
                    Accessible.onPressAction: Software.selectTab(tab.modelData.id)
                    Keys.onPressed: event => {
                        const step = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0;
                        if (step !== 0 && !(event.modifiers & Qt.AltModifier)) {
                            const next = root.tabs[Math.max(0, Math.min(root.tabs.length - 1, tab.index + step))];
                            Software.selectTab(next.id);
                            Qt.callLater(() => {
                                const item = tabRepeater.itemAt(root.tabs.indexOf(next));
                                if (item)
                                    item.forceActiveFocus();
                            });
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            Software.selectTab(tab.modelData.id);
                            event.accepted = true;
                        }
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.scaled(7)
                        Text {
                            id: label
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.modelData.label
                            color: tab.selected ? Theme.textHi : Theme.textMid
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.navigation
                            font.weight: tab.selected ? Theme.weightSemibold : Theme.weightMedium
                            textFormat: Text.PlainText
                        }
                        Rectangle {
                            id: badgeChip
                            objectName: "softwareUpdatesBadge"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tab.badge > 0
                            width: Math.max(height, count.implicitWidth + Theme.scaled(10))
                            height: Theme.scaled(18)
                            radius: height / 2
                            color: Theme.accent
                            Text {
                                id: count
                                anchors.centerIn: parent
                                text: String(tab.badge)
                                color: Theme.textOnAccent
                                font.family: Theme.fontNumeric
                                font.pixelSize: Theme.typography.metadata
                                font.weight: Theme.weightBold
                                textFormat: Text.PlainText
                            }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tab.dot
                            width: Theme.scaled(6)
                            height: width
                            radius: width / 2
                            color: Theme.accent
                        }
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Software.selectTab(tab.modelData.id)
                    }
                }
            }
        }
    }

    SoftwareButton {
        id: refresh
        objectName: "softwareRefresh"
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(14)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.scaled(34)
        height: Theme.scaled(34)
        quiet: true
        busy: Software.loading
        glyph: "refresh"
        enabled: !Software.loading
        accessibleName: I18n.tr("Refresh")
        onTriggered: Software.refresh()
    }
}
