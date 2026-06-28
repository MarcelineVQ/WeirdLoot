-- Aggregator for the blacklist-preset data files. This file is listed in WeirdLoot.toc BEFORE the
-- per-class files; it initializes addon.blacklistPresets and defines the builder they use. See
-- Data/BlacklistPresets/<Class>.lua for the per-class content.

local addon = WeirdLoot

addon.blacklistPresets = {}

-- Builder so each data file is pure data: a WoW class token ("DRUID"), a display name, and a flat
-- list of item names. The list is stored as-is (an array) -- the registry (Core.lua
-- GetBlacklistPresets) joins it into the newline string the editor consumes only at that boundary,
-- since a blacklist is matched item-by-item (LiveRoll parseItemList splits it straight back into a
-- name set), never as one blob. The class token gates the preset to its class: the blacklist is a
-- personal popup filter, so a Druid is only offered Druid presets, never another class's.
function addon:AddBlacklistPreset(class, name, items)
    table.insert(self.blacklistPresets, { class = class, name = name, items = items })
end
