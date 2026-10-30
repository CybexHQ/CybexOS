pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/UpdatesHelpers.js" as Helpers

// Important changes: the components people recognise, each old → new, as
// an update's review highlights list them (UpdatesHelpers.summary).
Rectangle {
    id: root

    property var components: []
    readonly property var nixos: components.find(row => row.id === "nixos") || null
    readonly property string nixosRelease: nixos ? Helpers.versionParts("nixos", nixos.after).text : ""

    visible: components.length > 0
    height: list.implicitHeight
    radius: Theme.chipRadius + 3
    color: Theme.cardFill
    border.width: 1
    border.color: Theme.hairlineSoft

    Column {
        id: list
        width: parent.width
        Repeater {
            model: root.components
            delegate: ChangeRow {
                required property var modelData
                required property int index
                readonly property var info: Helpers.component(modelData.id)
                // Within one NixOS release only the build date moves; the
                // title names the release and the versions read as dates.
                readonly property bool sameRelease: modelData.id === "nixos"
                    && Helpers.versionParts("nixos", modelData.before).text === root.nixosRelease
                objectName: "updateComponent"
                width: list.width
                divider: index > 0
                glyph: info.glyph
                title: sameRelease ? I18n.format("NixOS %1", [root.nixosRelease]) : I18n.tr(info.label)
                detail: I18n.tr(info.detail)
                component: sameRelease ? "date" : modelData.id
                before: sameRelease ? Helpers.versionParts("nixos", modelData.before).date.replace(/-/g, "") : modelData.before
                after: sameRelease ? Helpers.versionParts("nixos", modelData.after).date.replace(/-/g, "") : modelData.after
            }
        }
    }
}
