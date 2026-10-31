pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// The Software app's content. Tabs stay alive underneath pages, so going back
// returns to where Explore or Installed was scrolled. Escape goes back, then
// closes; typing anywhere searches; Alt+Left and Ctrl+F work as elsewhere.
FocusScope {
    id: root

    objectName: "softwareView"
    readonly property string view: Software.view
    readonly property var page: Software.page

    function focusInitial() { header.field.forceActiveFocus(); }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (Software.viewer)
                Software.closeViewer();
            else if (!Software.back())
                Software.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
            Software.back();
            event.accepted = true;
        } else if ((event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) || event.key === Qt.Key_Slash) {
            header.focusSearch("");
            event.accepted = true;
        } else if (event.text.length === 1 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            header.focusSearch(event.text);
            event.accepted = true;
        }
    }

    HeaderBar {
        id: header
        width: parent.width
        z: 2
    }

    Item {
        id: content
        anchors.top: header.bottom
        anchors.bottom: bar.visible ? bar.top : parent.bottom
        width: parent.width

        // The tab roots, kept for their scroll positions.
        ExplorePage {
            anchors.fill: parent
            visible: root.view === "explore"
        }
        InstalledPage {
            anchors.fill: parent
            visible: root.view === "installed"
        }
        UpdatesPage {
            anchors.fill: parent
            visible: root.view === "updates"
        }
        Loader {
            id: pageLoader
            anchors.fill: parent
            active: root.view === "search" || root.page !== null
            visible: active
            // One instance per page entry; a new entry starts at the top.
            readonly property var entry: root.page
            readonly property string key: root.page ? root.page.kind + ":" + root.page.id + ":" + (root.page.sub || "") : root.view
            onKeyChanged: {
                if (!active)
                    return;
                sourceComponent = undefined;
                sourceComponent = pageLoader.component();
            }
            onActiveChanged: {
                if (active)
                    sourceComponent = pageLoader.component();
            }
            function component() {
                return root.page === null ? searchPage : root.page.kind === "app" ? appPage
                    : root.page.kind === "flathub" ? flathubPage : categoryPage;
            }
            onLoaded: fade.restart()
            NumberAnimation {
                id: fade
                target: pageLoader.item
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.popoutContentFadeDuration * 1.4
                easing.type: Easing.OutCubic
            }
        }
        Component {
            id: searchPage
            SearchPage {}
        }
        Component {
            id: appPage
            AppPage {
                app: Software.appsById[(pageLoader.entry || {}).id] || ({})
            }
        }
        Component {
            id: flathubPage
            FlathubPage {
                appId: (pageLoader.entry || {}).id || ""
            }
        }
        Component {
            id: categoryPage
            CategoryPage {
                entry: pageLoader.entry || ({ kind: "category", id: "", sub: "" })
            }
        }

        // First load, and a catalogue that could not be read.
        Rectangle {
            anchors.fill: parent
            visible: !Software.loaded
            color: Theme.panelSurface
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.scaled(48), Theme.scaled(460))
                spacing: Theme.scaled(10)
                Spinner {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Software.loadError === ""
                    size: Theme.iconHero
                    color: Theme.textDim
                }
                Sym {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Software.loadError !== ""
                    name: "alert-triangle"
                    size: Theme.iconHero
                    color: Theme.amber
                }
                Text {
                    width: parent.width
                    text: Software.loadError !== "" ? I18n.tr("Software couldn't load its catalogue")
                        : I18n.tr("Loading apps…")
                    color: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.title
                    font.weight: Theme.weightSemibold
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    visible: Software.loadError !== ""
                    text: Software.loadError
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                SoftwareButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Software.loadError !== ""
                    big: true
                    text: I18n.tr("Try Again")
                    onTriggered: Software.refresh()
                }
            }
        }
    }

    QueueBar {
        id: bar
        anchors.bottom: parent.bottom
        width: parent.width
        z: 2
    }

    ScreenshotViewer {
        anchors.fill: parent
        z: 5
    }
}
