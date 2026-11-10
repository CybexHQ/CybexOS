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
- Every switch track is at least 24 px tall at about 1.7:1 proportions
  (`Theme.switchPopover`, `switchRow`, `switchCompact`; plugins'
  `Ui/ToggleSwitch`), and its pointer target reaches at least 32 px both ways
  (`Theme.switchHitMin`), invisibly where the row is shorter.
- Disabled content uses one token, `Theme.textDisabled` (`barTextDisabled` on
  the menubar): dimmed, but about 3:1 over `copyReferenceBg`, so it reads as
  unavailable without becoming illegible. A disabled switch draws its track,
  border and knob in it instead of fading. The reason a control is disabled
  stays at full contrast and any recovery action stays enabled.

## Copy contrast and light-mode edges

- Every step of the copy ladder below `textHi` (`textMid`, `textLow`,
  `textDim`, `textFaint`, `icon`) clears 4.5:1 on every window and card
  surface, in the default palette in both modes and in every theme pack. In
  dark mode the reference (`copyReferenceBg`) is a resting card
  (`Theme.tile`, `darkCardAlpha`) on the raised panel surface, the lightest
  thing copy sits on; in light mode it is a hovered chip on the base.
  `tests/quickshell/state-tokens.test.cjs` and `typography.test.cjs` check it.
- Light mode gives every floating surface (popovers, the drawer, the
  launcher, toasts, bar tooltips) a 1 px ink edge (`Theme.surfaceEdge`, drawn
  through `surfaceBorderWidth`/`surfaceBorderColor`) while no border is
  chosen. Cards inside a window take `Theme.cardEdgeWidth` and
  `Theme.cardEdge`. Dark mode draws neither, and the menubar slab stays
  borderless.

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
  `region`). Workspace cells meet side by side, each 32 px wide
  (`WorkspaceMotion.CELL_WIDTH`), and the layout button beside them is one
  cell. Every icon-only target names itself in a tooltip.
- **Running out of room:** the right cluster outranks the clock, the clock
  the workspaces, and the workspaces the media chip. The media title first
  shortens so the chip ends 12 px short of the centre group, then goes, then
  the chip moves to **More** before the clock or the right cluster lose
  anything (`BarGeometry.fitMenubar` over `LayoutHelpers.fitBar`). Bar height,
  the Control Center icon and the media module's maximum width and title
  format stay the user's.
- **Workspaces:** every place is an 8 px pip. An occupied place is a filled
  dot (`barWsOccupied`), an empty one a dimmer 1.5 px ring (`barWsEmpty`), so
  the two differ in shape as well as tone. In the dots style the current
  workspace is a 20 × 8 px accent pill (`barWsCurrent`); the numbers style
  keeps its accent chip around the number and shows empty places as rings.
- **The Control Center button:** a chip (the status group's `barChip` fill)
  so the mark at the far right reads as a button that opens something, not a
  close button; while the drawer is open it lights (`barChipHover`) with a
  1 px `barAccent` edge. Its tooltip is "Control Center". The icon stays the
  owner's choice (`controlIcon`). The Cybex X is also two-tone at rest (the
  short stroke at 55 % of `barIcon`) and turns brand red on hover or while
  Control Center is open; every other bar mark keeps the shared ink.
- **Unavailable marks:** an offline network or an unconnected Bluetooth mark
  is drawn in `barTextDisabled` (about 3:1), not faded.

## Control Center

- **Pinned rows:** the tab strip and the session row stay put on every tab;
  only the body scrolls, with a fade while more is below.
- **Tabs:** every tab shows its icon with a short label under it
  (Overview, Sound, Network, Bluetooth, Power, Alerts; the tooltip and
  description keep "Notifications"). Tabs take their natural width plus an
  equal share of the rest; when the labels do not fit whole (a narrow drawer,
  a larger text size, a longer translation) the strip wraps onto more rows,
  label beside icon, rather than cutting one short
  (`DrawerFormat.tabLayout`).
- **Session row:** three labelled secondary buttons. **Lock** acts at once;
  **Power ▴** is a menu of Sleep, Restart…, Shut down… and Log out…; **More ▴**
  a menu of Settings, Keyboard shortcuts and Screenshot (`DrawerMenu`: Up and
  Down move, Esc closes it and returns to its button before it would close
  the drawer). Sleep acts at once. Log out, Restart and Shut down turn the
  row into a question with Cancel focused: Enter confirms, Esc cancels
  without closing the drawer.
- **Overview order:** quick toggles, sliders, now playing, a ready update,
  the system summary, then processes. That order is also what stays above
  the fold at every text size, and the Overview section switches in Settings
  still hide any of them.
- **Details:** the system summary shows the machine and one plain line of
  readings ("CPU 6% · Memory 34% · Disk 62%", amber or red when one needs
  attention). Its **Show details** reveals the usage meters, the system
  facts and the top processes, and the choice holds for the session
  (`DrawerViewState`). Collapsed, the process list does not sample at all.
- **Processes:** five rows, three when the body is short, named as people
  know them (".firefox-wrapped" reads "firefox"). The end button appears on
  hover or keyboard focus and opens the existing confirmation (name and PID,
  then Force quit if ignored).
- **Missing devices:** a slider without a device is faded and shows a
  full-contrast reason with a link ("No output device · Sound settings").
- **Empty tabs:** Sound, Network, Bluetooth and Power share one empty state
  (`DrawerEmptyState`): a quiet glyph, the cause in one plain line, a
  sentence on what it means, and at most one action. Missing hardware ("No
  Bluetooth adapter found"), something turned off ("Wi-Fi is off", with
  **Turn on**) and a service that is not running ("Sound service isn't
  running") read differently. The tab's other controls and its footer step
  aside while it shows; switches stay out of sight for hardware that is not
  there, and so do features that are not installed (Tailscale).

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
- **Welcome guide:** while the full-screen guide covers an output, an
  ordinary toast there goes quietly to the notification centre: it stays in
  history and counts as unread on the Notifications tab
  (`NotifPolicy.guideRoute`). A critical one still shows, below the guide's
  top bar or above its footer (`NotifPolicy.guideInset`). The drawer rule is
  unchanged.
- **Toast edge:** a toast floats over any window, so it always draws an
  edge: the panel border when one is set, otherwise a 1 px hairline, and a
  shadow while glass is off. Its × and the group buttons answer to a 32 px
  target around the drawn control.
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
