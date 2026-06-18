# WeirdLoot

WeirdLoot is a World of Warcraft 3.3.5a addon for Wrath-era raid loot handling. It keeps the loot master as the authority, lets raiders register interest in items, resolves winners with explicit priority rules, and helps the loot master move items from boss drops to the correct players with less manual bookkeeping.

## What It Does

- Runs a synchronized loot session with the loot master as the source of truth.
- Imports and applies a master roster, per-item loot priority rules, and named-item priority rules.
- Supports both batch rolling and on-the-fly live rolling for newly collected items.
- Records detailed loot results with an audit trail for each item.
- Exports a simple winners list or a detailed resolver log.
- Helps the loot master deliver won items through guided whispers, trade targeting, and trade auto-fill.
- Auto-routes master-loot drops to the loot master or a designated disenchanter while a session is active.

## Main Features

### Loot sessions

- `Start Session` opens a new active loot session and snapshots the current raid attendees.
- `Scan Bags` refreshes the session item list from the loot master's bags.
- `Broadcast` pushes the current session, item list, locks, and results to the raid.
- Clients can request sync if they join late or reload.
- A raid-entry prompt can offer to start a session automatically when you zone in as the loot master.

### Rolling systems

- Batch rolling: `Roll Out the Loot` resolves every unlocked item in the session in one pass.
- Live rolling: newly collected loot can surface a pending popup to the loot master and be rolled immediately instead of waiting for a full batch.
- Right-clicking an item in the Loot tab can manually start a live roll.
- Live rolls and batch rolls feed the same resolver and result-record path, so they stay consistent.
- `Unlock Roll` clears item locks so previously resolved loot can be intentionally rerolled.

### Priority and resolution

- Raiders choose from `BiS`, `MS`, `MU`, `OS`, `TM`, or `Pass`.
- Resolution uses explicit bracket priority first, then named-item priority, then class/spec loot rules, then roster status, then rolls.
- Named-item rules can include hard priority chains and `LC` fallbacks for loot-council style handling.
- Result details are written in a human-readable form so you can see why an item resolved the way it did.

### Roster and raid visibility

- The Roster tab compares the configured master roster against the live raid roster.
- Players are shown with class, spec, status, and whether they came from the saved roster or only from the live raid.
- The addon tracks loot authority robustly across raid, party, master-loot, and leadership-fallback cases.

### Importing roster and named items

- The Loot Master tab includes `Import Roster` and `Import Named Items` buttons.
- Each button opens an editable paste window where the loot master can paste a full weekly list and save it directly into WeirdLoot.
- `Import Roster` expects one raider per line in the format `name, class spec, status`.
- `Import Named Items` expects one item per line in the format `item name, player > player / player > LC`.
- Saving an import updates the loot master's saved configuration immediately, including the normalized roster and named-item rule maps used by the resolver.
- For actual loot decisions, the loot master's imported config is the authoritative source of truth.

### Loot results and exports

- The Loot Results tab stores processed items, winners, and detailed reasoning.
- Selecting a result shows the full audit text for that item.
- `Export Winners` produces a simple item-to-winner list.
- `Export Log` produces a detailed resolver log suitable for raid records or review.

### Payout and trading

- Winners can be queued into a payout ledger automatically after loot is resolved.
- `Start Payout` whispers owed players and arms automatic trade filling.
- When an owed player opens trade with the loot master, WeirdLoot can fill the trade window with exactly the owed items.
- The final trade accept remains manual.
- The Results tab also supports a guided manual flow with `Target + Whisper`, `Trade Winner`, and `Fill Trade`.

### Auto-loot routing

- While a session is active and you are master looter, BoP items are routed to the loot master for rolling.
- Epic BoE items are routed to the loot master.
- Non-epic BoE items can be routed to a designated disenchanter set with `/wl deer <name>`.

### Quality-of-life behavior

- A login settle window avoids treating already-owned items as fresh drops during staged bag loading.
- Fresh copies of previously rolled items can reappear for rolling instead of being lost to stale state.
- Sessions, results, and payout state are resilient to reloads and relogs through saved variables.
- Test mode supports in-city validation by treating any bag item as session loot.

## Interface Overview

- `Loot` tab: current session loot, player responses, roller counts, sync actions, and manual live-roll entry by right-click.
- `Loot Results` tab: resolved winners, detailed reasoning, and payout/trade helper actions.
- `Roster` tab: configured roster versus live raid membership.
- `Loot Master` tab: session controls, exports, payout toggle, and session summary.

## Slash Commands

- `/weirdloot` or `/wl` opens the addon window.
- `/wl start` starts a loot session.
- `/wl end` ends and clears the current loot session.
- `/wl scan` refreshes session loot from bags.
- `/wl payout` turns payout mode on.
- `/wl payout stop` turns payout mode off.
- `/wl payout clear` clears the payout ledger.
- `/wl deer <name>` sets the designated disenchanter for non-epic BoE routing.
- `/wl autoroll` toggles automatic live-roll startup for new loot.
- `/wl test` toggles test mode for local/in-city validation.

## Files

- `WeirdLoot.toc`: addon manifest and load order.
- `Core.lua`: addon bootstrap, saved variables, slash commands, authority checks, and events.
- `Util.lua`: shared helpers and formatting utilities.
- `Config.lua`: roster import parsing, loot rules, named-item rules, and normalized config state.
- `Roster.lua`: live roster building, loot-master detection, and roster display data.
- `Session.lua`: raid-session state, bag scanning, item tracking, and lock management.
- `Comm.lua`: addon communication, session sync, result broadcast, and live-roll messaging.
- `Resolver.lua`: loot resolution engine and detailed result construction.
- `UI.lua`: tabbed interface, exports, loot controls, roster view, and result actions.
- `LiveRoll.lua`: on-the-fly live roll flow and pending popup handling.
- `Payout.lua`: bridge from resolved winners to the trade-delivery engine.
- `TradeDeliver.lua`: stack-correct, partner-initiated trade filling for payouts.
- `AutoLoot.lua`: master-loot routing for BoP, BoE, and disenchanter flows.
- `Libs/`: embedded communication and callback dependencies used by the addon.

## Manual Validation

Install the addon on a 3.3.5a client and test with at least two raid members:

- Confirm the Loot Master tab only unlocks for the actual loot master or leadership fallback.
- Import roster, loot priority, and named-item rules on the loot master client.
- Start a session, loot items, and verify that newly collected loot appears in the Loot tab.
- Test both batch rolling and live rolling, including right-click live-roll starts from the Loot tab.
- Confirm raiders can choose brackets and that the winner matches named/spec/status priority expectations.
- Verify results appear in the Loot Results tab with readable detailed reasoning.
- Verify `Export Winners` and `Export Log` contain the expected output.
- Test payout mode by having a winner open trade with the loot master and confirm the correct items auto-fill.
- Test auto-loot routing with master loot enabled and a designated disenchanter configured.
- Reload the UI during an active session and confirm session state, pending items, and results restore correctly.

Made by and for `Weird Vibes`.
