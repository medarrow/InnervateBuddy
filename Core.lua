-- InnervateBuddy - Core
-- Written for the 1.12 client (Lua 5.0): uses this/arg1/event globals, table.getn, string.find.

InnervateBuddy = InnervateBuddy or {}
local IB = InnervateBuddy

IB.version = "1.2.0"

local INNERVATE       = "Innervate"
local INNERVATE_RANGE = 30
local TEX             = "Interface\\ChatFrame\\ChatFrameBackground"
local FONT            = "Fonts\\FRIZQT__.TTF"
local ROW_H, ROW_GAP, PAD, HEADER_H = 14, 1, 2, 14
local UPDATE_RATE     = 0.2
local DETECT_MIN      = 3                 -- weighted casts needed before a role is decided
local DETECT_EXPIRE   = 3 * 24 * 3600     -- forget detections older than 3 days

IB.CLASS_COLORS = {
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
}

IB.HEAL_CLASSES     = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
IB.DPS_MANA_CLASSES = { MAGE = true, WARLOCK = true, HUNTER = true }

-- spell name -> weight. Seen from a group member, these push them toward healer / dps.
IB.HEAL_SPELLS = {
    ["Heal"] = 1, ["Lesser Heal"] = 1, ["Greater Heal"] = 2, ["Flash Heal"] = 1,
    ["Renew"] = 1, ["Prayer of Healing"] = 2, ["Holy Nova"] = 1,
    ["Healing Touch"] = 1, ["Rejuvenation"] = 1, ["Regrowth"] = 1, ["Tranquility"] = 2,
    ["Swiftmend"] = 3,
    ["Healing Wave"] = 1, ["Lesser Healing Wave"] = 1, ["Chain Heal"] = 2,
    ["Holy Light"] = 1, ["Flash of Light"] = 1, ["Holy Shock"] = 2,
}
IB.DPS_SPELLS = {
    ["Mind Flay"] = 2, ["Mind Blast"] = 1, ["Shadowform"] = 10, ["Vampiric Embrace"] = 3,
    ["Starfire"] = 2, ["Wrath"] = 1, ["Insect Swarm"] = 2, ["Moonkin Form"] = 10,
    ["Shred"] = 2, ["Claw"] = 1, ["Rake"] = 1, ["Rip"] = 1, ["Ferocious Bite"] = 1,
    ["Maul"] = 1, ["Swipe"] = 1,
    ["Lightning Bolt"] = 1, ["Chain Lightning"] = 2, ["Stormstrike"] = 3,
    ["Seal of Command"] = 3, ["Crusader Strike"] = 2, ["Holy Strike"] = 2,
}

-- player's own spec from talents: which tabs count as healing
-- talent trees per class (by name, so tab order doesn't matter); true = healing tree
local CLASS_TREES = {
    DRUID   = { ["Balance"] = false, ["Feral Combat"] = false, ["Restoration"] = true },
    PRIEST  = { ["Discipline"] = true, ["Holy"] = true, ["Shadow"] = false },
    SHAMAN  = { ["Elemental"] = false, ["Enhancement"] = false, ["Restoration"] = true },
    PALADIN = { ["Holy"] = true, ["Protection"] = false, ["Retribution"] = false },
}

local INSPECT_INTERVAL = 3          -- seconds between talent requests
local INSPECT_TIMEOUT  = 10         -- give up waiting for a talent reply after this
local INSPECT_RETRY    = 90         -- wait before retrying someone whose inspect failed
local SPEC_REFRESH     = 30 * 60    -- re-inspect known specs after this (respecs)
local SPEC_EXPIRE      = 14 * 24 * 3600

local defaults = {
    enabled      = true,
    locked       = false,
    maxRows      = 5,
    showDPS      = false,
    detectMode   = "BOTH",      -- BOTH, AUTO, MANUAL
    useTalents   = true,        -- auto-detect by inspecting talents
    useCombatLog = false,       -- auto-detect from combat log heals (fallback)
    assumeHybrids = false,      -- treat undetected druids/shamans/paladins as healers
    includeSelf  = true,
    hideSolo     = true,
    combatOnly   = false,
    showHeader   = true,
    clickCast    = true,
    fadeAlpha    = 0.35,
    threshold    = 100,         -- only list units at or below this mana %
    scale        = 1,
    width        = 150,
    manual       = {},
    detected     = {},
    specs        = {},          -- name -> { class, h = heal pts, o = best other tree, pts = "a/b/c", t }
    point       = { "CENTER", "CENTER", 250, 0 },
}

local db
local driver = CreateFrame("Frame", "InnervateBuddyDriver", UIParent)
local main, headerText, headerCD
local rows = {}
local roster, rosterByName = {}, {}
local rosterDirty = true
local display = {}
local playerName
local innervateSlot
local selfHealer = true
IB.testMode = false

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
function IB:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0aInnervateBuddy|r: " .. tostring(msg))
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                CopyDefaults(v, dst[k])
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function Normalize(name)
    if not name then return nil end
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then return nil end
    return string.upper(string.sub(name, 1, 1)) .. string.lower(string.sub(name, 2))
end

local function NotifyOptions()
    if IB.Options_Refresh then IB:Options_Refresh() end
end

---------------------------------------------------------------------------
-- manual healer list
---------------------------------------------------------------------------
function IB:AddManual(name)
    if not name or name == "" then
        if UnitExists("target") and UnitIsPlayer("target") then
            name = UnitName("target")
        else
            self:Print("No name given and no player targeted.")
            return
        end
    end
    name = Normalize(name)
    if not name then return end
    db.manual[name] = true
    self:Print(name .. " added to the healer list.")
    self:Refresh()
    NotifyOptions()
end

function IB:RemoveManual(name)
    if not name or name == "" then
        if UnitExists("target") and UnitIsPlayer("target") then name = UnitName("target") end
    end
    name = Normalize(name)
    if not name then return end
    if db.manual[name] then
        db.manual[name] = nil
        self:Print(name .. " removed from the healer list.")
    else
        self:Print(name .. " is not on the healer list.")
    end
    self:Refresh()
    NotifyOptions()
end

function IB:ToggleManual(name)
    if db.manual[name] then self:RemoveManual(name) else self:AddManual(name) end
end

function IB:GetManualList()
    local t = {}
    for name in pairs(db.manual) do table.insert(t, name) end
    table.sort(t)
    return t
end

function IB:ClearManual()
    db.manual = {}
    self:Print("Healer list cleared.")
    self:Refresh()
    NotifyOptions()
end

function IB:ClearDetected()
    db.detected = {}
    db.specs = {}
    for i = 1, table.getn(roster) do roster[i].inspectFail = nil end
    self:Print("Auto-detected roles reset (talents will be re-inspected).")
    self:Refresh()
    NotifyOptions()
end

---------------------------------------------------------------------------
-- role logic
---------------------------------------------------------------------------
-- returns isHealer, reason
function IB:GetRole(name, class)
    local mode = db.detectMode
    if mode ~= "AUTO" and db.manual[name] then return true, "manual" end
    if mode == "MANUAL" then return false, nil end
    if not IB.HEAL_CLASSES[class] then return false, nil end
    if name == playerName then return selfHealer, "talents" end
    if db.useTalents then
        local s = db.specs[name]
        if s and s.class == class then
            return s.h >= s.o, "talents " .. s.pts
        end
    end
    if db.useCombatLog then
        local d = db.detected[name]
        if d then
            if d.h >= DETECT_MIN and d.h >= d.d then return true, "combat log" end
            if d.d >= DETECT_MIN then return false, "combat log" end
        end
    end
    if class == "PRIEST" or db.assumeHybrids then return true, "assumed" end
    return false, nil
end

local function IsEligible(e)
    local healer = IB:GetRole(e.name, e.class)
    if healer then return true, true end
    if db.showDPS and (IB.HEAL_CLASSES[e.class] or IB.DPS_MANA_CLASSES[e.class]) then
        return true, false
    end
    return false, false
end

function IB:GetHealerSummary()
    local t = {}
    for i = 1, table.getn(roster) do
        local e = roster[i]
        local healer, reason = self:GetRole(e.name, e.class)
        if healer then table.insert(t, { name = e.name, class = e.class, reason = reason }) end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

local function Record(name, spell)
    if not name or not spell or not rosterByName[name] then return end
    local kind, w
    if IB.HEAL_SPELLS[spell] then
        kind, w = "h", IB.HEAL_SPELLS[spell]
    elseif IB.DPS_SPELLS[spell] then
        kind, w = "d", IB.DPS_SPELLS[spell]
    else
        return
    end
    local d = db.detected[name]
    if not d then
        d = { h = 0, d = 0 }
        db.detected[name] = d
    end
    d[kind] = d[kind] + w
    if d[kind] > 40 then -- keep it biased toward recent behaviour (respecs)
        d.h = math.floor(d.h / 2)
        d.d = math.floor(d.d / 2)
    end
    d.t = time()
end

local PATTERNS = {
    "^(.-) begins to cast (.+)%.$",
    "^(.-) casts (.-) on ",
    " from (.-)'s (.-)%.$",
    "^(.-)'s (.-) critically heals ",
    "^(.-)'s (.-) heals ",
    "^(.-)'s (.-) crits ",
    "^(.-)'s (.-) hits ",
    "^(.-) gains (.-)%.$",
}

function IB:ParseCombat(msg)
    if not msg or not db.useCombatLog or db.detectMode == "MANUAL" then return end
    for i = 1, table.getn(PATTERNS) do
        local _, _, who, spell = string.find(msg, PATTERNS[i])
        if who then
            Record(who, spell)
            return
        end
    end
end

-- Reads the player's own talent tabs.
-- Returns heal points, best other tree, "a/b/c"; nil if the tabs don't belong to class.
local function ReadOwnTalents(class)
    local trees = CLASS_TREES[class]
    if not trees then return nil end
    local heal, other, parts = 0, 0, {}
    for i = 1, 3 do
        local tabName, _, pts = GetTalentTabInfo(i)
        if not tabName or trees[tabName] == nil then return nil end
        pts = pts or 0
        if trees[tabName] then heal = heal + pts else other = math.max(other, pts) end
        table.insert(parts, pts)
    end
    return heal, other, table.concat(parts, "/")
end

function IB:CheckSelfSpec()
    local _, class = UnitClass("player")
    local heal, other = ReadOwnTalents(class)
    selfHealer = heal ~= nil and heal >= other
end

---------------------------------------------------------------------------
-- talent inspection (Turtle WoW protocol)
--
-- Turtle doesn't use NotifyInspect for talents. Its own Inspect > Talents tab
-- whispers a hidden addon message "INSTalentShow" through the server, and the
-- other player's client (Turtle_General, always loaded) replies with:
--   INSTalentTabInfo;tree;treeName;...    (one per tree)
--   INSTalentInfo;tree;idx;name;tier;col;currRank;maxRank;...   (one per talent)
--   INSTalentEND;
-- Points per tree are summed from currRank, which doesn't depend on the
-- TabInfo field order (that has differed between client versions).
---------------------------------------------------------------------------
local TALENT_PREFIX = "TW_CHAT_MSG_WHISPER"
-- tree index fallback if tree names don't come through
local HEAL_TAB_INDEX = {
    DRUID = { [3] = true }, PRIEST = { [1] = true, [2] = true },
    SHAMAN = { [3] = true }, PALADIN = { [1] = true },
}

local pending          -- request in flight
local nextInspect = 0
local inspectSupported = nil   -- true once any talent reply has arrived
local stats = { sent = 0, answered = 0 }
IB.debug = false

local function Debug(msg)
    if IB.debug then DEFAULT_CHAT_FRAME:AddMessage("|cff888888[IB debug]|r " .. msg) end
end

-- the server prepends a tab (or other whitespace) to addon messages
local function Clean(msg)
    if not msg then return nil end
    return (string.gsub(msg, "^%s+", ""))
end

local function Split(msg)
    local t = {}
    for part in string.gfind(msg, "[^;]+") do table.insert(t, part) end
    return t
end

local function NeedsInspect(e, now)
    if not IB.HEAL_CLASSES[e.class] or e.name == playerName then return false end
    if e.inspectFail and now - e.inspectFail < INSPECT_RETRY then return false end
    local s = db.specs[e.name]
    if s and s.class == e.class and time() - s.t < SPEC_REFRESH then return false end
    return true
end

-- Turtle_General hands every INSTalent reply to Blizzard_InspectUI's
-- InspectTalentsFrame_HandleMessage, which stores it against whatever you have
-- targeted right now and may pop its talent frame (CanInspect("target")).
-- Background scans mixed another player's talents into the current target's
-- inspect state; changing target afterwards could hang the client. So replies to
-- our own requests are kept away from it, unless you're inspecting that player.
local recentAsk = {}            -- name -> GetTime() of our last request
local inspectHooked = false

local function IsOurReply(message, sender)
    message = Clean(message)
    if not (message and sender) then return false end
    if not string.find(message, "^INSTalent") or string.find(message, "^INSTalentShow") then return false end
    local t = recentAsk[sender]
    if not t or GetTime() - t > INSPECT_TIMEOUT + 10 then return false end
    if InspectFrame and InspectFrame:IsVisible() and UnitName("target") == sender then return false end
    return true
end

local function HookTurtleInspect()
    if inspectHooked then return true end
    -- load it now, so the hook is in place before the first reply arrives
    if type(InspectTalentsFrame_HandleMessage) ~= "function" then
        pcall(LoadAddOn, "Blizzard_InspectUI")
    end
    local orig = InspectTalentsFrame_HandleMessage
    if type(orig) ~= "function" then return false end
    InspectTalentsFrame_HandleMessage = function(message, sender)
        if IsOurReply(message, sender) then return end
        return orig(message, sender)
    end
    inspectHooked = true
    return true
end

local function BeginInspect(name, class, manual)
    if not HookTurtleInspect() then
        Debug("Turtle inspect UI not found, not sending requests")
        nextInspect = GetTime() + 60
        return
    end
    local now = GetTime()
    recentAsk[name] = now
    pending = { name = name, class = class, time = now, manual = manual,
                ranks = { 0, 0, 0 }, tabs = {}, infoLines = 0,
                tree = 0, nextIdx = 1 }   -- position in the reply; tree 0 = not started
    nextInspect = now + INSPECT_INTERVAL
    stats.sent = stats.sent + 1
    local ok, err = pcall(SendAddonMessage, TALENT_PREFIX .. "<" .. name .. ">", "INSTalentShow", "GUILD")
    Debug("-> INSTalentShow to " .. name .. (ok and "" or (" |cffff5555failed: " .. tostring(err) .. "|r")))
    if not ok then pending = nil end
end

local function FailInspect(p, why)
    local e = rosterByName[p.name]
    if e then e.inspectFail = GetTime() end
    Debug("x " .. p.name .. ": " .. why)
    if p.manual and not IB.debug then IB:Print(p.name .. ": " .. why) end
end

local function FinishInspect()
    local p = pending
    pending = nil
    stats.answered = stats.answered + 1
    inspectSupported = true

    local trees = CLASS_TREES[p.class]
    local byName = trees ~= nil
    for t = 1, 3 do
        local tab = p.tabs[t]
        if not tab or not trees or trees[tab] == nil then byName = false end
    end

    local heal, other, total, parts = 0, 0, 0, {}
    for t = 1, 3 do
        local pts = p.ranks[t]
        local isHeal
        if byName then
            isHeal = trees[p.tabs[t]]
        else
            isHeal = HEAL_TAB_INDEX[p.class] and HEAL_TAB_INDEX[p.class][t]
        end
        if isHeal then heal = heal + pts else other = math.max(other, pts) end
        total = total + pts
        table.insert(parts, pts)
    end
    local ptsStr = table.concat(parts, "/")
    Debug(string.format("<- END from %s: %d talent lines, trees %s, points %s",
        p.name, p.infoLines, byName and "by name" or "by index", ptsStr))

    if p.infoLines == 0 or total == 0 then
        FailInspect(p, "reply had no talent points")
        return
    end
    db.specs[p.name] = { class = p.class, h = heal, o = other, pts = ptsStr, t = time() }
    local e = rosterByName[p.name]
    if e then e.inspectFail = nil end
    local role = heal >= other and "|cff4cff66healer|r" or "|cffff6666dps|r"
    Debug(p.name .. " = " .. role)
    if p.manual and not IB.debug then IB:Print(p.name .. ": " .. ptsStr .. " - " .. role) end
    NotifyOptions()
end

-- Throw away what's been read and wait for the start of a fresh reply.
local function ResetReply(p, why)
    Debug("|cffff9933" .. p.name .. ": " .. why .. ", waiting for a full reply|r")
    p.ranks, p.tabs, p.infoLines, p.tree, p.nextIdx = { 0, 0, 0 }, {}, 0, 0, 1
end

-- A reply is TabInfo(1), Info(1,1..n), TabInfo(2), Info(2,1..n), TabInfo(3), ..., END.
-- Another addon (e.g. ChronicleCompanion) may have asked the same player just before
-- us, so the first lines we see can be the tail of the answer meant for it. Lines
-- before TabInfo for tree 1 are skipped, and anything out of order is discarded.
function IB:OnAddonMessage(prefix, msg, sender)
    if prefix ~= TALENT_PREFIX then return end
    msg = Clean(msg)
    if not msg or not string.find(msg, "^INSTalent") or string.find(msg, "^INSTalentShow") then return end
    local p = pending
    if not (p and sender == p.name) then
        if IB.debug and not string.find(msg, "^INSTalentInfo") then
            Debug("(ignored, not ours) " .. tostring(sender) .. ": " .. msg)
        end
        return
    end
    if string.find(msg, "^INSTalentEND") then
        if p.tree == 0 then
            Debug("(skipped end of an earlier reply from " .. sender .. ")")
        elseif p.tree ~= 3 then
            ResetReply(p, "reply ended after tree " .. p.tree)
        else
            FinishInspect()
        end
    elseif string.find(msg, "^INSTalentTabInfo") then
        local parts = Split(msg)
        local t = tonumber(parts[2])
        if t == 1 then
            if p.tree ~= 0 then ResetReply(p, "a new reply started mid-way") end
            p.tree, p.nextIdx = 1, 1
        elseif p.tree == 0 then
            return  -- tail of an earlier reply
        elseif t ~= p.tree + 1 then
            ResetReply(p, "tree " .. tostring(t) .. " arrived out of order")
            return
        else
            p.tree, p.nextIdx = t, 1
        end
        p.tabs[t] = parts[3]
        Debug("<- " .. msg)
    elseif string.find(msg, "^INSTalentInfo") then
        if p.tree == 0 then return end
        local parts = Split(msg)
        local t, idx, rank = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[7])
        if t ~= p.tree or idx ~= p.nextIdx or not rank then
            ResetReply(p, "talent line out of order")
            return
        end
        p.nextIdx = idx + 1
        p.ranks[t] = p.ranks[t] + rank
        p.infoLines = p.infoLines + 1
    end
end

function IB:InspectTick()
    local now = GetTime()
    if pending then
        if now - pending.time > INSPECT_TIMEOUT then
            local p = pending
            pending = nil
            FailInspect(p, "no reply (their client didn't answer)")
        end
        return
    end
    if not db.useTalents or db.detectMode == "MANUAL" then return end
    if now < nextInspect then return end
    if UnitAffectingCombat("player") then return end
    -- replies also feed Turtle's own Inspect > Talents tab, so leave it alone while open
    if InspectFrame and InspectFrame:IsVisible() then return end
    for i = 1, table.getn(roster) do
        local e = roster[i]
        if NeedsInspect(e, now) and UnitIsConnected(e.unit) and UnitName(e.unit) == e.name then
            BeginInspect(e.name, e.class, false)
            return
        end
    end
end

-- /ib inspect [name]: ask one player now (target if no name)
function IB:InspectNow(name)
    if not name or name == "" then
        if not (UnitExists("target") and UnitIsPlayer("target")) then
            self:Print("Usage: /ib inspect <name>, or target a player.")
            return
        end
        name = UnitName("target")
    end
    name = Normalize(name)
    local e = rosterByName[name]
    local class = e and e.class
    if not class and UnitExists("target") and UnitName("target") == name then
        local _, c = UnitClass("target")
        class = c
    end
    if not class then
        self:Print(name .. " isn't in your group or targeted.")
        return
    end
    if name == playerName then
        self:Print("Your own spec is read from your talents: " .. (selfHealer and "healer" or "dps") .. ".")
        return
    end
    if pending then Debug("dropping request to " .. pending.name) end
    if not IB.debug then self:Print("Asking " .. name .. " for talents...") end
    BeginInspect(name, class, true)
end

function IB:ToggleDebug()
    IB.debug = not IB.debug
    if IB.debug then
        self:Print("Inspect debug on - talent requests and replies print to chat. /ib debug again to stop.")
    else
        self:Print("Inspect debug off.")
    end
end

function IB:InspectStatus()
    local known, total = 0, 0
    for i = 1, table.getn(roster) do
        local e = roster[i]
        if IB.HEAL_CLASSES[e.class] and e.name ~= playerName then
            total = total + 1
            local s = db.specs[e.name]
            if s and s.class == e.class then known = known + 1 end
        end
    end
    return known, total, inspectSupported
end

function IB:PrintSpecs()
    local known, total = self:InspectStatus()
    self:Print(string.format("Talent specs known for %d/%d healing-class group members. This session: %d asked, %d answered.",
        known, total, stats.sent, stats.answered))
    local now = GetTime()
    for i = 1, table.getn(roster) do
        local e = roster[i]
        if IB.HEAL_CLASSES[e.class] and e.name ~= playerName then
            local s = db.specs[e.name]
            local line
            if s and s.class == e.class then
                line = s.pts .. " - " .. (s.h >= s.o and "|cff4cff66healer|r" or "|cffff6666dps|r")
            elseif pending and pending.name == e.name then
                line = "|cffaaaaaaasking...|r"
            elseif e.inspectFail then
                line = string.format("|cffff9933no answer|r |cff777777(retry in %ds)|r",
                    math.max(0, math.floor(INSPECT_RETRY - (now - e.inspectFail))))
            else
                line = "|cff777777queued|r"
            end
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (%s): %s", e.name, string.lower(e.class or "?"), line))
        end
    end
end

---------------------------------------------------------------------------
-- roster / range / innervate
---------------------------------------------------------------------------
local function AddUnit(unit)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    if not name or name == UNKNOWNOBJECT then return end
    local _, class = UnitClass(unit)
    local e = { unit = unit, name = name, class = class }
    table.insert(roster, e)
    rosterByName[name] = e
end

function IB:BuildRoster()
    rosterDirty = false
    local old = rosterByName
    roster, rosterByName = {}, {}
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do AddUnit("raid" .. i) end
    else
        AddUnit("player")
        for i = 1, GetNumPartyMembers() do AddUnit("party" .. i) end
    end
    -- carry over last known mana (druids in forms)
    for name, e in pairs(rosterByName) do
        if old[name] then
            e.lastPct = old[name].lastPct
            e.inspectFail = old[name].inspectFail
        end
    end
    NotifyOptions()
end

function IB:GetDistance(unit)
    if UnitXP then
        local ok, d = pcall(UnitXP, "distanceBetween", "player", unit)
        if ok and type(d) == "number" then return d end
    end
    return nil
end

function IB:InRange(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not UnitIsVisible(unit) then return false end
    local d = self:GetDistance(unit)
    if d then return d <= INNERVATE_RANGE end
    return CheckInteractDistance(unit, 4) and true or false -- ~28 yards
end

function IB:FindInnervate()
    innervateSlot = nil
    local i = 1
    while true do
        local n = GetSpellName(i, "spell")
        if not n then break end
        if n == INNERVATE then innervateSlot = i end
        i = i + 1
    end
end

function IB:CastOn(unit)
    if not innervateSlot then
        self:Print("You don't know Innervate.")
        return
    end
    if SUPERWOW_VERSION then
        CastSpellByName(INNERVATE, unit)
        return
    end
    if UnitIsUnit(unit, "player") then
        CastSpellByName(INNERVATE, 1)
        return
    end
    if UnitIsUnit(unit, "target") then
        CastSpellByName(INNERVATE)
        return
    end
    local hadTarget = UnitExists("target")
    TargetUnit(unit)
    CastSpellByName(INNERVATE)
    if SpellIsTargeting() then SpellTargetUnit(unit) end
    if hadTarget then TargetLastTarget() else ClearTarget() end
end

---------------------------------------------------------------------------
-- display
---------------------------------------------------------------------------
local TEST_DATA = {
    { "Lightwell", "PRIEST", 0.12 }, { "Treehugger", "DRUID", 0.27 },
    { "Totemic", "SHAMAN", 0.41 }, { "Bubbles", "PALADIN", 0.58 },
    { "Frostbolt", "MAGE", 0.66 }, { "Lifetap", "WARLOCK", 0.08 },
    { "Aimshot", "HUNTER", 0.73 }, { "Holyshock", "PALADIN", 0.89 },
    { "Sunbeam", "PRIEST", 0.95 },
}
local testEntries = {}
for i = 1, table.getn(TEST_DATA) do
    local t = TEST_DATA[i]
    testEntries[i] = { name = t[1], class = t[2], pct = t[3], healer = IB.HEAL_CLASSES[t[2]],
                       inRange = math.mod(i, 3) ~= 0, test = true }
end

local function SortFn(a, b)
    if a.pct ~= b.pct then return a.pct < b.pct end
    return a.name < b.name
end

local function SetFont(fs, size)
    fs:SetFont(FONT, size)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end

local function Row_OnEnter()
    local e = this.entry
    if not e then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    local c = IB.CLASS_COLORS[e.class] or { r = 1, g = 1, b = 1 }
    GameTooltip:AddLine(e.name, c.r, c.g, c.b)
    if e.unit and UnitExists(e.unit) then
        GameTooltip:AddDoubleLine("Mana", UnitMana(e.unit) .. " / " .. UnitManaMax(e.unit), .7, .7, .7, 1, 1, 1)
        local d = IB:GetDistance(e.unit)
        if d then GameTooltip:AddDoubleLine("Distance", string.format("%.0f yd", d), .7, .7, .7, 1, 1, 1) end
    end
    if e.form then GameTooltip:AddLine("In shapeshift form - last known mana", .6, .6, .6) end
    if not e.inRange then GameTooltip:AddLine("Out of Innervate range", 1, .3, .3) end
    if not e.test then
        local healer, reason = IB:GetRole(e.name, e.class)
        GameTooltip:AddDoubleLine("Role", healer and ("Healer (" .. reason .. ")") or "DPS", .7, .7, .7, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if db.clickCast then GameTooltip:AddLine("Left-click: cast Innervate", .5, .8, 1) end
    GameTooltip:AddLine("Right-click: target", .5, .8, 1)
    GameTooltip:AddLine("Shift-right-click: toggle healer list", .5, .8, 1)
    GameTooltip:Show()
end

local function Row_OnClick()
    local e = this.entry
    if not e or e.test then return end
    if arg1 == "LeftButton" then
        if db.clickCast then IB:CastOn(e.unit) else TargetUnit(e.unit) end
    elseif arg1 == "RightButton" then
        if IsShiftKeyDown() then IB:ToggleManual(e.name) else TargetUnit(e.unit) end
    end
end

local function StartDrag()
    if not db.locked then main:StartMoving() end
end

local function StopDrag()
    main:StopMovingOrSizing()
    local p, _, rp, x, y = main:GetPoint()
    db.point = { p, rp, x, y }
end

local function CreateRow(i)
    local b = CreateFrame("Button", "InnervateBuddyRow" .. i, main)
    b:SetHeight(ROW_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", StartDrag)
    b:SetScript("OnDragStop", StopDrag)
    b:SetScript("OnClick", Row_OnClick)
    b:SetScript("OnEnter", Row_OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetTexture(TEX)

    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetAllPoints(b)
    b.bar:SetStatusBarTexture(TEX)
    b.bar:SetMinMaxValues(0, 1)

    b.role = b.bar:CreateTexture(nil, "OVERLAY")
    b.role:SetTexture(TEX)
    b.role:SetVertexColor(0.3, 1, 0.4, 1)
    b.role:SetWidth(2)
    b.role:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.role:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)

    b.pct = b.bar:CreateFontString(nil, "OVERLAY")
    SetFont(b.pct, 10)
    b.pct:SetPoint("RIGHT", b, "RIGHT", -3, 0)
    b.pct:SetJustifyH("RIGHT")

    b.name = b.bar:CreateFontString(nil, "OVERLAY")
    SetFont(b.name, 10)
    b.name:SetPoint("LEFT", b, "LEFT", 5, 0)
    b.name:SetPoint("RIGHT", b.pct, "LEFT", -2, 0)
    b.name:SetHeight(ROW_H)
    b.name:SetJustifyH("LEFT")

    rows[i] = b
    return b
end

local function CreateMain()
    main = CreateFrame("Frame", "InnervateBuddyFrame", UIParent)
    main:SetFrameStrata("MEDIUM")
    main:SetMovable(true)
    main:SetClampedToScreen(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", StartDrag)
    main:SetScript("OnDragStop", StopDrag)
    main:SetBackdrop({
        bgFile = TEX, edgeFile = TEX, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    main:SetBackdropColor(0, 0, 0, 0.55)
    main:SetBackdropBorderColor(0, 0, 0, 0.9)

    headerText = main:CreateFontString(nil, "OVERLAY")
    SetFont(headerText, 10)
    headerText:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + 3, -PAD - 2)
    headerText:SetTextColor(1, 0.49, 0.04)
    headerText:SetText("Innervate")

    headerCD = main:CreateFontString(nil, "OVERLAY")
    SetFont(headerCD, 10)
    headerCD:SetPoint("TOPRIGHT", main, "TOPRIGHT", -PAD - 3, -PAD - 2)
end

function IB:ApplySettings()
    if not main then return end
    main:SetScale(db.scale)
    main:SetWidth(db.width)
    main:ClearAllPoints()
    local p = db.point
    main:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    self:Refresh()
end

function IB:ResetPosition()
    db.point = { "CENTER", "CENTER", 250, 0 }
    self:ApplySettings()
end

local function UpdateCooldown()
    if not innervateSlot then
        headerCD:SetText("")
        return
    end
    local start, duration = GetSpellCooldown(innervateSlot, "spell")
    local remain = (start or 0) + (duration or 0) - GetTime()
    if start and start > 0 and duration > 1.5 and remain > 0 then
        local m = math.floor(remain / 60)
        local s = math.floor(math.mod(remain, 60))
        headerCD:SetText(string.format("%d:%02d", m, s))
        headerCD:SetTextColor(0.8, 0.8, 0.8)
    else
        headerCD:SetText("Ready")
        headerCD:SetTextColor(0.3, 1, 0.4)
    end
end

function IB:Refresh()
    if not main or not db then return end
    if rosterDirty then self:BuildRoster() end

    -- visibility
    local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
    local show = db.enabled
    if show and db.locked and not self.testMode then
        if db.hideSolo and not inGroup then show = false end
        if db.combatOnly and not UnitAffectingCombat("player") then show = false end
    end
    if not show then
        main:Hide()
        return
    end

    -- collect
    for i = table.getn(display), 1, -1 do table.remove(display, i) end
    if self.testMode then
        for i = 1, table.getn(testEntries) do
            local e = testEntries[i]
            if (e.healer or db.showDPS) and e.pct * 100 <= db.threshold then
                table.insert(display, e)
            end
        end
    else
        for i = 1, table.getn(roster) do
            local e = roster[i]
            local u = e.unit
            if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
               and (db.includeSelf or not UnitIsUnit(u, "player")) then
                if not e.class then local _, c = UnitClass(u); e.class = c end
                local ok, healer = IsEligible(e)
                if ok then
                    local pct
                    if UnitPowerType(u) == 0 then
                        local max = UnitManaMax(u)
                        if max and max > 0 then
                            pct = UnitMana(u) / max
                            e.lastPct = pct
                        end
                        e.form = nil
                    else
                        pct = e.lastPct
                        e.form = true
                    end
                    if pct and pct * 100 <= db.threshold then
                        e.pct = pct
                        e.healer = healer
                        e.inRange = self:InRange(u)
                        table.insert(display, e)
                    end
                end
            end
        end
    end
    table.sort(display, SortFn)

    -- layout
    local count = math.min(table.getn(display), db.maxRows)
    local showHeader = db.showHeader or not db.locked
    local y = -PAD
    if showHeader then
        headerText:Show()
        headerCD:Show()
        headerText:SetText(db.locked and "Innervate" or "Innervate |cff888888(unlocked)|r")
        UpdateCooldown()
        y = y - HEADER_H - ROW_GAP
    else
        headerText:Hide()
        headerCD:Hide()
    end

    for i = 1, count do
        local e = display[i]
        local r = rows[i] or CreateRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", main, "TOPLEFT", PAD, y)
        r:SetPoint("TOPRIGHT", main, "TOPRIGHT", -PAD, y)
        y = y - ROW_H - ROW_GAP
        r.entry = e

        local c = IB.CLASS_COLORS[e.class] or { r = .6, g = .6, b = .6 }
        r.bar:SetStatusBarColor(c.r * 0.8, c.g * 0.8, c.b * 0.8, 0.85)
        r.bg:SetVertexColor(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.9)
        r.bar:SetValue(e.pct)
        r.name:SetText(e.name)

        local p = math.floor(e.pct * 100 + 0.5)
        if e.form then
            r.pct:SetText("~" .. p .. "%")
            r.pct:SetTextColor(0.6, 0.6, 0.6)
        elseif p < 20 then
            r.pct:SetText(p .. "%"); r.pct:SetTextColor(1, 0.3, 0.3)
        elseif p < 40 then
            r.pct:SetText(p .. "%"); r.pct:SetTextColor(1, 0.75, 0.3)
        else
            r.pct:SetText(p .. "%"); r.pct:SetTextColor(1, 1, 1)
        end

        if db.showDPS and e.healer then r.role:Show() else r.role:Hide() end
        r:SetAlpha(e.inRange and 1 or db.fadeAlpha)
        r:Show()
    end
    for i = count + 1, table.getn(rows) do
        rows[i].entry = nil
        rows[i]:Hide()
    end

    if count == 0 and not showHeader then
        main:Hide()
        return
    end
    local h = -y + PAD - ROW_GAP
    if count == 0 then h = PAD * 2 + HEADER_H end
    main:SetHeight(h)
    main:Show()
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local COMBAT_EVENTS = {
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF", "CHAT_MSG_SPELL_PARTY_BUFF",
    "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
    "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
}
local isCombatEvent = {}
for i = 1, table.getn(COMBAT_EVENTS) do isCombatEvent[COMBAT_EVENTS[i]] = true end

local function OnLoad()
    InnervateBuddyDB = InnervateBuddyDB or {}
    db = InnervateBuddyDB
    CopyDefaults(defaults, db)
    IB.db = db
    local now = time()
    for name, d in pairs(db.detected) do
        if type(d) ~= "table" or not d.t or now - d.t > DETECT_EXPIRE then db.detected[name] = nil end
    end
    for name, s in pairs(db.specs) do
        if type(s) ~= "table" or not s.t or now - s.t > SPEC_EXPIRE then db.specs[name] = nil end
    end
    playerName = UnitName("player")
    CreateMain()
    IB:ApplySettings()
    local _, class = UnitClass("player")
    if class ~= "DRUID" then
        IB:Print("You are not a Druid - Innervate casting is disabled, but the list still works.")
    end
end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("RAID_ROSTER_UPDATE")
driver:RegisterEvent("PARTY_MEMBERS_CHANGED")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("LEARNED_SPELL_IN_TAB")
driver:RegisterEvent("CHARACTER_POINTS_CHANGED")
if SUPERWOW_VERSION then driver:RegisterEvent("UNIT_CASTEVENT") end
driver:RegisterEvent("CHAT_MSG_ADDON")
for i = 1, table.getn(COMBAT_EVENTS) do driver:RegisterEvent(COMBAT_EVENTS[i]) end

driver:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == "InnervateBuddy" then OnLoad() end
        return
    end
    if not db then return end
    if isCombatEvent[event] then
        IB:ParseCombat(arg1)
    elseif event == "CHAT_MSG_ADDON" then
        IB:OnAddonMessage(arg1, arg2, arg4)
    elseif event == "UNIT_CASTEVENT" then
        if (arg3 == "CAST" or arg3 == "CHANNEL") and SpellInfo and db.useCombatLog and db.detectMode ~= "MANUAL" then
            local ok, name = pcall(UnitName, arg1)
            local spell = SpellInfo(arg4)
            if ok then Record(name, spell) end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerName = UnitName("player")
        rosterDirty = true
        IB:FindInnervate()
        IB:CheckSelfSpec()
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        rosterDirty = true
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        IB:FindInnervate()
    elseif event == "CHARACTER_POINTS_CHANGED" then
        IB:CheckSelfSpec()
    end
end)

local elapsed = 0
driver:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < UPDATE_RATE then return end
    elapsed = 0
    IB:Refresh()
    IB:InspectTick()
end)

---------------------------------------------------------------------------
-- slash commands
---------------------------------------------------------------------------
local function Help()
    IB:Print("v" .. IB.version .. " commands (/ib or /innervatebuddy):")
    local c = "|cffffd100"
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib|r - open options")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib lock|unlock|r - lock or unlock the frame")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib dps|r - toggle showing DPS mana classes")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib rows <n>|r - number of units shown")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib mode auto|manual|both|r - healer detection mode")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib add|remove [name]|r - edit healer list (no name = target)")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib list|r, |cffffd100/ib clear|r - show / clear healer list")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib talents [on|off]|r - detect healers by inspecting talents (default on)")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib combatlog [on|off]|r - detect healers from combat log heals (default off)")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib specs|r - show inspected talent specs in your group")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib inspect [name]|r - ask one player for talents now (no name = target)")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib debug|r - print talent requests and replies to chat")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib rescan|r - forget detected roles and re-inspect")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib test|r - toggle preview with fake data")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib toggle|r - enable / disable the frame")
    DEFAULT_CHAT_FRAME:AddMessage(c .. "  /ib reset|r - reset frame position")
end

local MODE_NAMES = { BOTH = "auto + manual", AUTO = "auto only", MANUAL = "manual only" }
IB.MODE_NAMES = MODE_NAMES

SLASH_INNERVATEBUDDY1 = "/ib"
SLASH_INNERVATEBUDDY2 = "/innervatebuddy"
SlashCmdList["INNERVATEBUDDY"] = function(msg)
    if not db then return end
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "" or cmd == "config" or cmd == "options" then
        IB:ToggleOptions()
    elseif cmd == "help" then
        Help()
    elseif cmd == "lock" then
        db.locked = true; IB:Print("Frame locked."); IB:Refresh(); NotifyOptions()
    elseif cmd == "unlock" then
        db.locked = false; IB:Print("Frame unlocked - drag to move."); IB:Refresh(); NotifyOptions()
    elseif cmd == "dps" then
        db.showDPS = not db.showDPS
        IB:Print("DPS mana classes " .. (db.showDPS and "shown." or "hidden."))
        IB:Refresh(); NotifyOptions()
    elseif cmd == "rows" then
        local n = tonumber(rest)
        if n and n >= 1 and n <= 40 then
            db.maxRows = math.floor(n); IB:Print("Showing up to " .. db.maxRows .. " units.")
            IB:Refresh(); NotifyOptions()
        else
            IB:Print("Usage: /ib rows <1-40>")
        end
    elseif cmd == "mode" then
        local m = string.upper(rest or "")
        if MODE_NAMES[m] then
            db.detectMode = m; IB:Print("Healer detection: " .. MODE_NAMES[m] .. ".")
            IB:Refresh(); NotifyOptions()
        else
            IB:Print("Usage: /ib mode auto|manual|both")
        end
    elseif cmd == "add" then
        IB:AddManual(rest)
    elseif cmd == "remove" or cmd == "del" then
        IB:RemoveManual(rest)
    elseif cmd == "list" then
        local t = IB:GetManualList()
        if table.getn(t) == 0 then IB:Print("Healer list is empty.")
        else IB:Print("Healer list: " .. table.concat(t, ", ")) end
    elseif cmd == "clear" then
        IB:ClearManual()
    elseif cmd == "resetdetect" or cmd == "rescan" then
        IB:ClearDetected()
    elseif cmd == "talents" or cmd == "combatlog" then
        local key = (cmd == "talents") and "useTalents" or "useCombatLog"
        local v = string.lower(rest or "")
        if v == "on" then db[key] = true elseif v == "off" then db[key] = false else db[key] = not db[key] end
        IB:Print((cmd == "talents" and "Talent inspect" or "Combat log") .. " detection " .. (db[key] and "on." or "off."))
        IB:Refresh(); NotifyOptions()
    elseif cmd == "specs" then
        IB:PrintSpecs()
    elseif cmd == "inspect" then
        IB:InspectNow(rest)
    elseif cmd == "debug" then
        IB:ToggleDebug()
    elseif cmd == "test" then
        IB.testMode = not IB.testMode
        IB:Print("Test mode " .. (IB.testMode and "on." or "off."))
        IB:Refresh(); NotifyOptions()
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
        IB:Print(db.enabled and "Enabled." or "Disabled.")
        IB:Refresh(); NotifyOptions()
    elseif cmd == "reset" then
        IB:ResetPosition(); IB:Print("Position reset.")
    else
        Help()
    end
end
