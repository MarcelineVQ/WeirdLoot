-- Default roster entries: the curated list of raiders, classes, specs, and roster status
-- (main / designatedalt / nil). Loaded from Core.lua; consumed at PLAYER_LOGIN by the migration
-- logic that re-seeds a character's saved roster whenever the upstream default changes. Lives
-- on its own here so Core.lua doesn't carry a 72-line data table alongside its bootstrap.
--
-- Format: array of { name, className, specName, status }. Names are stored in the canonical
-- display form (the roster normalizer lowercases on read). Status is one of:
--   main           -- the player is the canonical holder of this spec/role pairing
--   designatedalt  -- the player's alt is also expected/accepted in this slot
--   nil            -- on the roster but not competing for loot (benched, social, etc.)
-- A "designatedalt" status still rolls for items their main is eligible for; the resolver
-- treats them as a fallback for slots the main doesn't fill.

local addon = WeirdLoot

addon.defaultRosterEntries = {
    { name = "achera", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "aest", className = "mage", specName = "fire", status = "main" },
    { name = "aldeberron", className = "mage", specName = "arcane", status = "main" },
    { name = "cfg", className = "warlock", specName = "demonology", status = "main" },
    { name = "dehumanizing", className = "warrior", specName = "fury", status = "main" },
    { name = "barnyard", className = "shaman", specName = "restoration", status = "main" },
    { name = "bisket", className = "warlock", specName = "affliction", status = "main" },
    { name = "friendhelper", className = "druid", specName = "balance", status = "main" },
    { name = "nitt", className = "rogue", specName = "combat", status = "main" },
    { name = "notdewbie", className = "rogue", specName = "assassination", status = "main" },
    { name = "valamas", className = "death knight", specName = "unholy", status = "main" },
    { name = "styrza", className = "warrior", specName = "fury", status = "main" },
    { name = "lexissa", className = "warlock", specName = "demonology", status = "main" },
    { name = "zaneran", className = "warrior", specName = "fury", status = "main" },
    { name = "heisthegoat", className = "warrior", specName = "fury", status = "designatedalt" },
    { name = "command", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "onaqui", className = "death knight", specName = "blood", status = "main" },
    { name = "seme", className = "druid", specName = "restoration", status = "designatedalt" },
    { name = "tumtum", className = "shaman", specName = "enhancement", status = "main" },
    { name = "scozetti", className = "druid", specName = "balance", status = "main" },
    { name = "fellera", className = "priest", specName = "discipline", status = "main" },
    { name = "sweetde", className = "paladin", specName = "retribution", status = "designatedalt" },
    { name = "zannahdee", className = "mage", specName = "arcane", status = "main" },
    { name = "welkin", className = "shaman", specName = "elemental", status = "nil" },
    { name = "nothara", className = "hunter", specName = "survival", status = "main" },
    { name = "owlation", className = "hunter", specName = "survival", status = "main" },
    { name = "dewbie", className = "paladin", specName = "retribution", status = "designatedalt" },
    { name = "uzragol", className = "shaman", specName = "elemental", status = "main" },
    { name = "helvi", className = "priest", specName = "shadow", status = "main" },
    { name = "zenkahi", className = "death knight", specName = "frost", status = "main" },
    { name = "sweezy", className = "death knight", specName = "unholy", status = "main" },
    { name = "runereaver", className = "death knight", specName = "frost", status = "main" },
    { name = "volckerr", className = "warlock", specName = "affliction", status = "main" },
    { name = "volckurr", className = "hunter", specName = "survival", status = "designatedalt" },
    { name = "illithris", className = "paladin", specName = "holy", status = "main" },
    { name = "stickboard", className = "paladin", specName = "holy", status = "main" },
    { name = "sticknight", className = "death knight", specName = "unholy", status = "designatedalt" },
    { name = "mitsuki", className = "paladin", specName = "retribution", status = "main" },
    { name = "yumie", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "scozette", className = "mage", specName = "arcane", status = "designatedalt" },
    { name = "thalamier", className = "druid", specName = "feral", status = "main" },
    { name = "hellhound", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "shapiffany", className = "paladin", specName = "holy", status = "main" },
    { name = "gromnash", className = "death knight", specName = "blood", status = "main" },
    { name = "scarletrage", className = "mage", specName = "arcane", status = "main" },
    { name = "lehran", className = "paladin", specName = "protection", status = "main" },
    { name = "dezmar", className = "warlock", specName = "affliction", status = "main" },
    { name = "ivala", className = "shaman", specName = "enhancement", status = "designatedalt" },
    { name = "iseut", className = "paladin", specName = "retribution", status = "main" },
    { name = "allannon", className = "paladin", specName = "protection", status = "main" },
    { name = "sayri", className = "mage", specName = "fire", status = "designatedalt" },
    { name = "halosylvan", className = "priest", specName = "discipline", status = "main" },
    { name = "kleedus", className = "druid", specName = "restoration", status = "main" },
    { name = "verdalax", className = "druid", specName = "balance", status = "designatedalt" },
    { name = "rigul", className = "rogue", specName = "assassination", status = "main" },
    { name = "naioraa", className = "priest", specName = "discipline", status = "main" },
    { name = "plainam", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "douchenasty", className = "rogue", specName = "combat", status = "main" },
    { name = "scartin", className = "warrior", specName = "fury", status = "main" },
    { name = "bospongi", className = "death knight", specName = "frost", status = "nil" },
    { name = "fischoeder", className = "druid", specName = "restoration", status = "designatedalt" },
    { name = "dlnero", className = "warlock", specName = "affliction", status = "main" },
    { name = "lawgiver", className = "paladin", specName = "protection", status = "designatedalt" },
    { name = "potatosmashr", className = "warrior", specName = "fury", status = "designatedalt" },
    { name = "tsea", className = "paladin", specName = "retribution", status = "designatedalt" },
    { name = "ironklad", className = "paladin", specName = "protection", status = "main" },
    { name = "lizal", className = "priest", specName = "discipline", status = "nil" },
    { name = "remos", className = "death knight", specName = "blood", status = "nil" },
    { name = "rigpal", className = "paladin", specName = "holy", status = "designatedalt" },
    { name = "scozotti", className = "paladin", specName = "holy", status = "nil" },
}
