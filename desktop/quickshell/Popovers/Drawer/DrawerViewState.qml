pragma Singleton
import QtQuick

// What the drawer remembers for the session: view state, not settings. It
// outlives a tab switch and the drawer closing (the popout host may release
// the drawer's view), and starts over when the shell does.
QtObject {
    // Overview's "Show details": the usage meters, the system facts and the
    // top processes behind the system summary. Collapsed at first, so the
    // everyday controls lead (2026-11 UI council).
    property bool overviewDetails: false
}
