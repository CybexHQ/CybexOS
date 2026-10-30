pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers
import "../Common/TablerGlyphs.js" as Tabler

// A category with its subcategory chips, Editor's choice and every app in
// it by popularity; also "Popular on Cybex OS" (the whole catalogue) and a
// collection's apps.
PageScroll {
    id: root

    property var entry: ({ kind: "category", id: "", sub: "" })
    readonly property string kind: entry.kind
    readonly property var category: kind === "category" ? Software.categoriesById[entry.id] || null : null
    readonly property var profile: kind === "collection" ? Software.profiles.find(item => item.id === entry.id) || null : null
    readonly property string sub: entry.sub || ""
    readonly property color tint: category && Helpers.parseHex(category.color) ? category.color : Theme.accent
    readonly property var collection: Helpers.collection(profile, Software.appsById)
    readonly property var apps: kind === "collection" ? collection.apps
        : Helpers.inCategory(Software.apps, category ? category.id : "", sub)
    readonly property var picks: category ? Helpers.editorsChoice(Software.apps, Software.catalogue.featured || [], category.id, sub, 3) : []
    readonly property string subName: {
        const value = category ? (category.subcategories || []).find(item => item.id === root.sub) : null;
        return value ? Software.label(value.name) : "";
    }

    objectName: "softwareCategoryPage"

    Row {
        spacing: Theme.scaled(14)
        Rectangle {
            width: Theme.scaled(48)
            height: width
            radius: Theme.chipRadius + 4
            color: root.category ? Qt.rgba(root.tint.r, root.tint.g, root.tint.b, Theme.dark ? 0.16 : 0.18) : Theme.accentAlpha(0.14)
            Sym {
                anchors.centerIn: parent
                name: root.category ? Helpers.glyph(root.category.icon, Tabler.has)
                    : root.profile ? Helpers.glyph(root.profile.icon, Tabler.has) : "star"
                size: Theme.scaled(26)
                color: root.category ? (Theme.dark ? root.tint : Qt.darker(root.tint, 1.45)) : Theme.accentText
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(2)
            Text {
                objectName: "softwareCategoryTitle"
                text: root.category ? Software.label(root.category.name)
                    : root.profile ? Software.label(root.profile.name) : I18n.tr("Popular on Cybex OS")
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.display
                font.weight: Theme.weightBold
                font.letterSpacing: -0.6
                textFormat: Text.PlainText
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Text {
                text: root.category ? Software.label(root.category.summary)
                    : root.profile ? (root.collection.apps.length === 1 ? I18n.tr("1 app")
                        : I18n.format("%1 apps", [root.collection.apps.length]))
                    : I18n.tr("Apps people install most, from Flathub's download counts")
                color: Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                textFormat: Text.PlainText
            }
        }
    }

    Flow {
        visible: root.category !== null
        width: parent.width
        spacing: Theme.scaled(6)
        Repeater {
            model: root.category ? [{ id: "", name: "" }].concat(root.category.subcategories || []) : []
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool selected: modelData.id === root.sub
                readonly property string label: modelData.id === "" ? I18n.tr("All") : Software.label(modelData.name)
                objectName: "softwareSubcategory"
                width: chipText.implicitWidth + Theme.scaled(24)
                height: Theme.scaled(30)
                radius: height / 2
                color: selected ? Theme.textHi : mouse.containsMouse ? Theme.hoverFill : "transparent"
                border.width: chip.activeFocus ? 2 : 1
                border.color: chip.activeFocus ? Theme.accentText : selected ? Theme.textHi : Theme.stroke
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: chip.label
                Accessible.checked: chip.selected
                Accessible.onPressAction: Software.setSubcategory(chip.modelData.id)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        Software.setSubcategory(chip.modelData.id);
                        event.accepted = true;
                    }
                }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.label
                    color: chip.selected ? Theme.background : Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    font.weight: chip.selected ? Theme.weightSemibold : Theme.weightMedium
                    textFormat: Text.PlainText
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Software.setSubcategory(chip.modelData.id)
                }
            }
        }
    }

    SoftwareButton {
        objectName: "softwareCollectionInstallAll"
        visible: root.profile !== null && root.collection.missing.length > 0
        big: true
        primary: true
        glyph: "plus"
        text: I18n.format("Install all %1", [root.collection.missing.length])
        onTriggered: Software.installAll(root.profile.id)
    }

    SectionTitle {
        width: parent.width
        visible: root.picks.length > 0
        text: I18n.tr("Editor's choice")
    }
    Grid {
        id: pickGrid
        width: parent.width
        visible: root.picks.length > 0
        columns: Math.min(3, Helpers.columns(width, Theme.scaled(240), Theme.scaled(10)))
        spacing: Theme.scaled(10)
        Repeater {
            model: root.picks.slice(0, pickGrid.columns)
            delegate: PickCard {
                required property var modelData
                width: (pickGrid.width - pickGrid.spacing * (pickGrid.columns - 1)) / pickGrid.columns
                app: modelData
            }
        }
    }

    SectionTitle {
        width: parent.width
        text: root.category ? (root.subName !== "" ? root.subName : I18n.format("All apps in %1", [Software.label(root.category.name)]))
            : root.profile ? I18n.tr("In this collection") : I18n.tr("All apps")
        detail: root.kind === "collection" ? "" : I18n.tr("Sorted by popularity")
    }
    Grid {
        id: grid
        width: parent.width
        columns: Helpers.columns(width, Theme.scaled(280), Theme.scaled(12))
        columnSpacing: Theme.scaled(12)
        rowSpacing: Theme.scaled(2)
        Repeater {
            model: root.apps
            delegate: AppRow {
                required property var modelData
                objectName: "softwareAppRow"
                width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
                app: modelData
            }
        }
    }
    Text {
        visible: root.apps.length === 0
        width: parent.width
        text: I18n.tr("No apps here yet.")
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.primary
        textFormat: Text.PlainText
    }
}
