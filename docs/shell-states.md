# Shell states, actions and formats

The 2026-11 UI review (a two-round design council over real-engine
screenshots) settled one vocabulary for how the shell shows where you are,
where the keyboard is, what is on, and what to do next. Every native surface
— the menubar, the Control Center, notifications, Settings, Software,
Software Update and the welcome guide — uses it. Plugins keep their own API
(`Ui/`, `Style`) unchanged.

## Selected, hovered and focused

| State | Treatment | Token |
| --- | --- | --- |
| Hover | Neutral chip fill | `Theme.chip` / `chipHover` |
| Selected (rail, list) | Accent tint + 3 px accent edge on the inline-start side + accent icon + `textHi` label | `selectedFill`, `selectedMark`, `selectedEdgeWidth` |
| Selected (tile) | Accent tint + 2 px accent border | `selectedFill`, `selectedMark`, `selectedBorderWidth` |
| Selected (theme card) | 2 px `textHi` border + accent check badge | `textHi`, `accent` |
| Selected (segmented control) | The neutral raised segment, no accent | `segmentSelected` |
| Keyboard focus | 2 px ring, never a fill | `focusRing`, `Theme.focusWidth(activeFocus)` |

Hover and selection used to share `chip`, which is why a hovered or focused
row could look selected. `selectedFill` is an accent tint instead.

`selectedMark` and `focusRing` are the accent lifted to 3:1 over
`copyReferenceBg`, the least favourable backdrop copy sits on
(`SettingsHelpers.stateTokens`). `tests/quickshell/state-tokens.test.cjs`
checks them in the default palette in both modes and in every bundled theme
pack.

### Focus rings and keyboard modality

A focus ring promises where the next key will act, so it shows only while the
person drives the shell from the keyboard. `Common/FocusModality` holds that
state. Each window ends with a `FocusModalityObserver`:

- It sees every pointer press and declines it, so the press still reaches the
  control underneath, and it hides rings.
- Focus that moves without a press just before it reveals rings.
- A window that opens or regains activation starts without a ring, so the
  first Tab always shows where focus went.

Rings are `Rectangle` borders, which Qt Quick paints inside the item. A
clipping parent therefore cannot cut them off, and they land on whole pixels
at fractional scales. Write `border.width: Theme.focusWidth(activeFocus)` with
`border.color: Theme.focusRing`. Text fields keep showing focus after a click,
because the caret is not enough on its own. `StateLayer` raises its focus
layer only for keyboard modality.

### Switches and disabled controls

- An off switch has a quiet track (`switchOffTrack`), and a border and knob in
  `textMid`, which carry the 3:1 boundary. An on switch has an accent track.
- A disabled control fades. Its reason stays at full contrast and any
  recovery action stays enabled.

## Action tiers

- **Primary:** accent fill. At most one per group: the next step.
- **Secondary:** chip fill and hairline.
- **Tertiary:** text with an icon, still with a 32 px hit box.

A status pill (dot and label) sits beside its action.

## Formats

- **Storage:** decimal units everywhere: `SysInfoHelpers.formatStorageBytes`
  ("412 GB free of 1 TB").
- **Memory:** binary units, labelled as such: `SysInfoHelpers.formatIecBytes`
  ("31 GiB").
- **Percentages and times:** follow the locale and the clock's 12/24-hour
  setting.

## Menubar

- **Pointer targets:** every bar target takes the bar's full height and at
  least 32 px of width (`Bar/BarIcon.qml`, `Bar/BarChip.qml`). The hover fill
  keeps its inset; the target reaches half the gap towards each neighbour, so
  a narrow icon is laid out a little wider rather than overlapping the one
  beside it, and hover lights wherever a click would land (`PointerCheck`'s
  `region`). Workspace cells already meet side by side and keep their 22 px.
- **Running out of room:** the right cluster outranks the clock, the clock
  the workspaces, and the workspaces the media chip. The media title first
  shortens so the chip ends 12 px short of the centre group, then goes, then
  the chip moves to **More** before the clock or the right cluster lose
  anything (`BarGeometry.fitMenubar` over `LayoutHelpers.fitBar`). Bar height,
  the Control Center icon and the media module's maximum width and title
  format stay the user's.
- **Workspaces, dots style:** the current workspace is an 18 × 6 px accent
  pill (`barWsCurrent`), occupied dots `barWsOccupied`, empty dots
  `barWsEmpty`. The numbers style is unchanged.
- **The Cybex X:** two-tone at rest (the short stroke at 55 % of `barIcon`)
  so it does not read as a close button, the brand red on hover or while
  Control Center is open; every other bar mark keeps the shared ink.

## Control Center

- **Pinned rows:** the tab strip and the session row stay put on every tab;
  only the body scrolls, with a fade while more is below. Lock and Suspend act
  at once. Log out, Restart and Shut down turn the row into a question with
  Cancel focused: Enter confirms, Esc cancels without closing the drawer.
- **Overview order:** quick toggles, sliders, now playing, a ready update,
  the system summary, then processes. That order is also what stays above
  the fold at every text size, and the Overview section switches in Settings
  still hide any of them.
- **Processes:** five rows, three when the body is short. The end button
  appears on hover or keyboard focus and opens the existing confirmation
  (name and PID, then Force quit if ignored).
- **Missing devices:** a slider without a device is faded and shows a
  full-contrast reason with a link ("No output device · Sound settings").

## Notifications

- **Card:** the same card in toasts and the drawer list:
  - an app icon, or a monogram when there is none;
  - the app name and time on one line, then the title on its own line;
  - the body, two lines when the card has buttons;
  - up to two action buttons, the rest under **More**.

  Clicking the body runs the default action and dismisses the card. Toasts
  never take keyboard focus; the keyboard path is the drawer's Notifications
  tab.
- **Collision rule:** when the drawer is open on the output and side where
  toasts appear, and the Notifications tab is enabled, a new arrival does not
  toast (`NotifPolicy.drawerRoute`):
  - The tab keeps an unread count until it is viewed.
  - A one-line strip appears under the tabs for 5 s.
  - A critical arrival instead pins a banner until it is handled.

  Focus, quiet hours, snoozes and placement are applied first, and nothing
  replays when the drawer closes.
- **Focus:** one name everywhere for silencing pop-ups ("Do Not Disturb"
  before 2026-11): the Overview tile, the Notifications tab's switch,
  Settings, the bar and the launcher.

## Settings

- **Rail:** the current page has the selected tint and edge, and keyboard
  focus is only the ring.
- **Narrow windows:** below the scaled 860 px breakpoint the rail collapses
  to 58 px, with page names as tooltips on hover and keyboard focus. A tip,
  "Press / to search pages", appears once per session.
- **Narrow content:** below about 560 px of content, Home's summary becomes
  2×2, values wrap instead of eliding, and status-plus-action rows stack.
- **Rows:** Settings turns off `StateLayer`'s focus tint on rows, tiles and
  switches: a ring, never a fill.
