# Design

## Goal

Omarchy Switcher is intentionally a **window switcher**, not a workspace
overview, launcher, task manager, or window-management suite.

The complete interaction is:

```text
hold Super
  ↓
press Tab
  ↓
show one horizontal strip of window previews
  ↓
press Tab / Shift+Tab to move the selection
  ↓
release Super
  ↓
focus the selected window
```

That is the product.

The reference behavior is the directness of Windows Alt+Tab and macOS-style
visual switching, adapted to Omarchy/Hyprland and bound to `Super+Tab`.

## Non-goals

Do not add any of the following unless the product scope is explicitly changed:

- workspace overview or workspace switching;
- application launcher or search;
- multiple display modes such as grid / flip / icons;
- snap layouts or window arrangement;
- window grouping;
- persistent window history of our own;
- settings UI;
- a background daemon outside Omarchy Shell;
- screenshots written to disk;
- a native Hyprland plugin.

A feature being available in Orbit or Overview Workspaces is not, by itself, a
reason to add it here.

## UX contract

### Open

The first `Super+Tab` starts a switch session.

The overlay:

- appears centered on the focused monitor;
- contains exactly one horizontal row;
- never wraps;
- displays one card per eligible window;
- starts from Hyprland MRU order;
- selects the previous window on the first forward gesture.

### Cycle

While Super remains held:

- `Tab` moves forward;
- `Shift+Tab` moves backward;
- selection wraps at both ends;
- if the selected card leaves the viewport, the horizontal list scrolls enough
  to reveal it.

The list should feel like one track. It should not paginate into a grid or
create multiple rows.

### Commit

Releasing either Super key commits the current selection.

The overlay must close before focus is handed to the target window.

### Cancel

`Esc` cancels without changing focus.

A switch session that is still waiting for its initial window query must also
be cancellable. In particular, a quick `Super+Tab` followed immediately by
Super release must not cause a late overlay to appear after the modifier has
already been released.

## Window order

Hyprland is the source of truth.

At the beginning of each switch session we run:

```bash
hyprctl clients -j
```

Eligible clients are sorted by `focusHistoryID` ascending:

```text
0  current window
1  previous window
2  window used before that
...
```

For a normal forward invocation, one step is already pending when the query
finishes, so the initial selected index is `1`: the previously used window.

We deliberately do not maintain a second MRU database.

## Eligible windows

The switcher keeps clients that are:

- mapped;
- not hidden;
- on a regular positive workspace;
- addressable by Hyprland.

Special workspaces and non-window surfaces are excluded.

This policy should stay small. If local testing finds a concrete class of
ordinary windows that should be included or excluded, change the filter only
for that observed case.

## Preview model

The visual list is backed by Hyprland client metadata and Quickshell foreign
toplevel objects.

The implementation:

1. queries Hyprland clients for ordering and metadata;
2. matches each client address against `Hyprland.toplevels`;
3. uses the matched Wayland toplevel as the `ScreencopyView.captureSource`;
4. requests a single frame with `live: false`;
5. releases the preview when the switcher closes / delegate disappears.

No capture is written to disk.

If a preview cannot be obtained, the card must remain usable and show a simple
text fallback rather than disappearing.

## UI structure

The plugin is a single Omarchy `service` entry point:

```text
org.lsong.window-switcher
└── Switcher.qml
    ├── session state
    ├── hyprctl client query
    ├── runtime Hyprland bindings
    ├── Quickshell GlobalShortcuts
    └── PanelWindow
        └── centered BorderSurface
            └── ListView (Horizontal)
                └── window card
                    ├── ScreencopyView
                    └── title
```

There is intentionally no separate model daemon.

## Session state machine

The useful states are conceptual rather than separate QML objects:

```text
IDLE
  │ Super+Tab / Super+Shift+Tab
  ▼
QUERYING
  │ hyprctl clients result
  ├──────────── Super release / Esc ────────────► IDLE
  ▼
OPEN
  │ Tab / Shift+Tab
  │   └── update selectedIndex
  │
  ├── Esc ──────────────────────────────────────► IDLE
  │
  └── Super release
        ↓
      COMMIT
        ↓
      focus selected Hyprland address
        ↓
      IDLE
```

Current implementation variables map approximately to this:

- `opened` — OPEN;
- `queryWanted` — QUERYING still belongs to a live gesture;
- `pendingSteps` — Tab movements received before the client query finished;
- `windows` — immutable-enough session snapshot;
- `selectedIndex` — current cursor.

Avoid introducing more state unless it solves an observed race.

## Shortcut architecture

The plugin registers Quickshell global shortcuts:

```text
org.lsong.window-switcher:next
org.lsong.window-switcher:previous
org.lsong.window-switcher:commit
```

Runtime Hyprland bindings map:

```text
Super+Tab         → next
Super+Shift+Tab   → previous
Super_L release   → commit
Super_R release   → commit
```

The focused overlay also handles the Super key release directly, so a release
delivered to its exclusive keyboard focus still commits the selection.

The service is `keepLoaded` so these shortcuts remain registered.

On a Hyprland config reload, bindings are installed again.

When the plugin unloads, it restores Omarchy's normal:

```text
Super+Tab         → next workspace
Super+Shift+Tab   → previous workspace
```

### Binding limitation

Hyprland runtime bindings do not carry plugin ownership metadata.

The plugin therefore keeps its own owner token to reduce the chance that an old
instance restores bindings after a newer instance has replaced it, but it
cannot perfectly preserve arbitrary user mappings that use the same chords.

Custom mappings on these chords are considered conflicting.

## Window activation

The switcher focuses the selected client by exact Hyprland address:

```bash
hyprctl eval 'hl.dispatch(hl.dsp.focus({ window = "address:0x..." }))'
```

Prefer an exact address over class/title matching because titles and classes are
not unique.

Do not add fullscreen handoff logic, resize covers, retries, or native compositor
bridges unless local testing proves that ordinary focus is unreliable for a
specific common case.

## Multi-monitor behavior

The overlay should appear on the monitor that was focused when the switch
session started.

The window list is currently global across regular workspaces. Selecting a
window on another workspace or monitor should let Hyprland focus that window in
place.

Local testing should verify:

- overlay appears on the expected monitor;
- switching to another monitor works;
- switching to another workspace works;
- no window is moved merely because it was selected.

## Performance principles

This interaction must feel instantaneous.

Keep the hot path simple:

- one `hyprctl clients -j` query per session;
- no periodic polling while the switcher is open;
- no persistent screenshot cache;
- no live video previews unless a demonstrated UX problem requires them;
- only instantiated ListView delegates create preview surfaces;
- release all session state when the overlay closes.

Optimize only after measuring an actual delay.

## Error handling

Failure should degrade to no-op rather than disturb the desktop.

Examples:

- malformed `hyprctl` JSON → log warning and abandon the session;
- fewer than two eligible windows → do not open the overlay;
- missing Wayland preview source → show text fallback;
- release before query completion → cancel query result logically;
- invalid selected index → cancel rather than focus an arbitrary window.

## Validation checklist

Validate behavior on a real Omarchy/Hyprland session before changing the
interaction model.

### Plugin lifecycle

```bash
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" Switcher.qml
omarchy restart shell
```

Confirm:

- plugin loads without QML errors;
- disabling/removing it restores normal Super+Tab workspace navigation;
- a Hyprland config reload does not permanently remove switcher bindings.

Useful diagnostics:

```bash
hyprctl binds -j | jq '.[] | select(.description | test("Switcher"))'
journalctl --user -u omarchy-shell.service -n 200 --no-pager
hyprctl clients -j | jq 'sort_by(.focusHistoryID) | map({title, class, address, focusHistoryID, workspace})'
```

### Core interaction

Test all of these:

1. With at least three windows, hold Super and press Tab once.
   - overlay opens;
   - previous MRU window is selected.
2. Keep holding Super and press Tab repeatedly.
   - selection advances exactly one card at a time;
   - wrapping works.
3. Use `Super+Shift+Tab`.
   - reverse selection works from both initial and open states.
4. Release Super.
   - overlay closes;
   - selected window gains focus.
5. Press Esc.
   - overlay closes;
   - original focus remains.
6. Very quickly press `Super+Tab` and release Super.
   - no delayed overlay appears.
7. Hold Tab long enough to trigger key repeat.
   - repeated movement remains deterministic.

### Preview behavior

Test a mixture of:

- native Wayland apps;
- Chromium/Electron;
- terminal;
- XWayland app if available;
- fullscreen/maximized window.

Confirm:

- preview appears where supported;
- unsupported capture does not break the card;
- preview preserves recognizable aspect/content;
- opening/closing the overlay repeatedly does not leave stale captures.

### Horizontal track

Open enough windows to exceed screen width.

Confirm:

- there is still only one row;
- cards never wrap;
- selected off-screen cards are brought into view;
- track remains centered and bounded by screen margins.

### Multi-workspace / multi-monitor

Confirm:

- windows from another normal workspace can be selected and focused;
- target workspace changes naturally through Hyprland focus;
- another monitor's window can be selected;
- overlay stays on the monitor focused at session start.

## Release criteria

A release is ready when the validation checklist passes reliably.

Do not treat visual polish as a blocker unless it affects readability or input
behavior.

Follow-up work should remain small and evidence driven, for example:

- better card aspect sizing;
- application icon fallback;
- subtle open/selection animation;
- replacement of shell subprocesses if Omarchy later exposes an equally simple
  supported API.

Those are optional refinements, not part of the core interaction contract.
