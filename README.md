# WeirdLoot

WeirdLoot is a World of Warcraft 3.3.5a addon for end-of-raid loot processing.

## Features

- Server/client loot mechanism with the loot master as the authority
- Master roster, loot priority, and named-item priority imports
- Raid roster enrichment with configured class/spec/status metadata
- Loot-master bag scan for tradable epic items
- Client roll/pass selection with pass as the default
- Interpretable and explicit loot resolution with named, class/spec, and main/alt priority
- Result history with a detailed audit trail per item

## Files

- `weirdloot.toc`: addon manifest
- `Core.lua`: addon bootstrap, saved variables, slash commands, and events
- `Util.lua`: shared helpers
- `Config.lua`: import parsing and normalized configuration
- `Roster.lua`: raid roster, authority, and player profile lookup
- `Session.lua`: raid-session and bag-scan tracking
- `Comm.lua`: raid addon message transport and synchronization
- `Resolver.lua`: loot-priority resolution
- `UI.lua`: tabbed addon interface

## Manual validation

Install the addon on a 3.3.5a client and test with at least two raid members:

- Start a loot session and confirm the loot-master tab only unlocks for the loot master or raid leadership fallback.
- Import roster, loot priority, and named-item rules on the loot master client.
- Loot epic items after the session starts, scan bags, and broadcast the session.
- Confirm clients default each item to `Pass` and can switch to `Roll`.
- Process loot and verify the results tab and raid chat summary.

Made by and for `Weird Vibes`.