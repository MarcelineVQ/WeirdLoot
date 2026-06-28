-- Aggregator for the blacklist-preset data files. This file is listed in WeirdLoot.toc
-- BEFORE the per-class files; it initializes addon.blacklistPresets to an empty table.
-- Each Data/BlacklistPresets/<Class>.lua then pushes its preset entries into that table.
-- See Data/BlacklistPresets/<Class>.lua for the per-class content.

local addon = WeirdLoot

addon.blacklistPresets = {}
