# Personal utilities

This page describes the current Hyper Caps and menu-bar hiding implementation. Physical-device acceptance is tracked separately in the [roadmap](../roadmap/README.md); implementation and passing tests do not establish observed hardware behavior.

## Application

XMT runs as an accessory application. Opening or reopening it presents Settings; closing the window leaves it running. General includes launch-at-login controls and Quit. Quit waits for Hyper mapping recovery and remains open if recovery fails. A process-lifetime lock prevents two app instances from owning the mapping concurrently. Window Mover retains its existing behavior and shortcut editor, visible even while disabled.

The default settings tabs are General, Window Mover, Hyper, and Menu Bar. Dictation is outside the default product; its older optional development source remains. Home-row settings are no longer exposed.

## Hyper Caps

Hyper is opt-in and targets the uniquely discovered built-in keyboard service. Caps taps Escape before the hold threshold; holding it forms Control–Option–Shift–Command for keyboard chords. Pressing another non-repeat key resolves Hyper immediately. The threshold defaults to 200 milliseconds and accepts 1 through 60,000. Apply saves the draft; status distinguishes active behavior, missing permission, interruption, and recovery failure.

The backend temporarily maps Caps to F18 using the targeted HID service, then consumes F18 through an active event tap. F18 is consequently reserved in the session, including when sent by another keyboard. Known F18 mappings are rejected during preparation. Hyperkey must be stopped before XMT starts transforming keys. Password fields using Secure Input may bypass the tap: Hyper/Escape are unavailable there and the underlying F18 mapping may remain until interruption is observed. XMT does not promise transparent Caps passthrough in those fields.

A journal records the previous mapping before activation. The tap and an independent recovery child become ready before the new mapping is installed. Disablement restores only XMT's still-owned Caps entry, preserving unrelated entries and newer external changes. The child detects parent pipe closure and attempts the same generation-scoped restoration after a crash; graceful shutdown explicitly disarms and joins it. HID commands, readiness handshakes, and child shutdown waits have finite deadlines. Recovery on next launch also handles a prepared but never installed mapping. Other remappers must remain stopped: hidutil does not offer an atomic cross-application compare-and-set operation.

Hyper preferences use `hyper.settings.v1` in UserDefaults. They are independent of the retained, inactive `keyboardCustomization` configuration used by the old feasibility models.

## Menu-bar hiding

The feature owns an arrow and separator, with saved status-item positions. Command-drag determines the group to hide. Before widening the separator, XMT verifies that it is positioned to the left of the recovery arrow. If placement is missing or reversed, XMT refuses to collapse, keeps both controls visible, and directs the user in Settings to Command-drag the separator immediately left of the arrow. Expanding or collapsing changes XMT's separator width; it does not individually move another app's icons. A one-shot timer collapses after 60 seconds by default and defers while the pointer occupies the menu bar or XMT's context menu is open. The delay is editable between 1 and 3,600 seconds.

Hidden Bar's saved delay is imported once if available. Separators are visible; there is no always-hidden group, global hiding shortcut, or full-menu-bar takeover. XMT hides its controls while Hidden Bar is running or the feature is disabled. Right-clicking the arrow opens Settings and Quit actions. Reopening the app remains the way to reach Settings when controls are hidden.
