import QtQuick
import QtQuick.Shapes
import "../Common"

// Product geometry presented as menubar furniture. BrandIcon keeps canonical
// paint for content identities elsewhere; this boundary makes every service
// and shell identity in the bar follow the same resting and hover ink as the
// generic Tabler glyphs beside it. Starting from the white paint variant
// prevents MultiEffect from scaling the tint by each brand's source luminance.
//
// One mark differs: the Cybex X. In one ink, at the bar's far end, it reads as
// a window's close ✕, so it is drawn two-tone (docs/shell-states.md): at rest
// the short stroke takes 55 % of the shared ink; on hover, or while its panel
// is open, the long stroke takes the hover ink and the short one the brand
// red. MultiEffect can only tint a whole image (and scaled the red stroke by
// its luminance, to about a third), so the X is drawn from its own two paths.
Item {
    id: root

    property string name: ""
    property bool highlighted: false
    readonly property bool twoTone: name === "cybexos"

    implicitWidth: Theme.iconMedium
    implicitHeight: Theme.iconMedium
    // Every use sits inside a named control, as with BrandIcon.
    Accessible.ignored: true

    BrandIcon {
        anchors.fill: parent
        visible: !root.twoTone
        name: root.twoTone ? "" : root.name
        highlighted: root.highlighted
        colorized: true
        tint: Theme.barIcon
        normalizeTintSource: true
    }

    // assets/cybexos.svg, its 44-unit viewBox fitted like
    // Image.PreserveAspectFit (bar-cybex-mark.test.cjs keeps the paths equal).
    Item {
        id: mark

        readonly property real unit: Math.min(root.width, root.height) / 44
        // The mark's own red, from the same SVG.
        readonly property color brandRed: "#DC1E37"
        property color longInk: root.highlighted ? Theme.barTextHi : Theme.barIcon
        property color shortInk: root.highlighted ? brandRed
            : Qt.rgba(Theme.barIcon.r, Theme.barIcon.g, Theme.barIcon.b, 0.55)

        visible: root.twoTone
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: 44 * unit
        height: 44 * unit

        Behavior on longInk {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        Behavior on shortInk {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        Shape {
            x: -147 * mark.unit
            y: -3 * mark.unit
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                objectName: "cybexMarkShort"
                scale: Qt.size(mark.unit, mark.unit)
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: mark.shortInk
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    path: "m171.53,16.96l7.55-6.73c.19-.17.34-.34.53-.43.19-.1.46-.14.82-.14h5.42c.45,0,.71.15.79.46.08.3,0,.6-.26.84l-10.71,9.81-4.13-3.8Z"
                }
            }

            ShapePath {
                objectName: "cybexMarkLong"
                scale: Qt.size(mark.unit, mark.unit)
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: mark.longInk
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    path: "m158.54,9.65c.35,0,.62.05.82.14.19.1.37.25.58.43l26.83,24.52c.25.23.3.53.24.82-.06.29-.32.43-.77.43h-6.09c-.35,0-.63-.05-.84-.14-.21-.1-.39-.22-.55-.38l-10.17-9.31-10.46,9.31c-.16.16-.34.29-.53.38-.19.1-.46.14-.82.14h-5.42c-.45,0-.71-.14-.79-.43-.08-.29,0-.56.26-.82l13.53-12.43-12.38-11.37c-.26-.26-.35-.54-.29-.84.06-.3.32-.46.77-.46h6.09Z"
                }
            }
        }
    }
}
