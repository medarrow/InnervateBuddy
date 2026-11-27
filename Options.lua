-- InnervateBuddy - Options window

local IB = InnervateBuddy
local TEX = "Interface\\ChatFrame\\ChatFrameBackground"
local LIST_ROWS = 8
local opt
local checks, sliders = {}, {}
local manualRows, healerRows = {}, {}
local manualOffset = 0
local modeButton, testButton, specStatus

local MODE_ORDER = { "BOTH", "AUTO", "MANUAL" }
local MODE_LABEL = { BOTH = "Detection: Auto + Manual", AUTO = "Detection: Auto only", MANUAL = "Detection: Manual only" }

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Divider(parent, y, title)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(TEX)
    t:SetVertexColor(1, 1, 1, 0.12)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
    if title then
        local l = Label(parent, title, "GameFontNormalSmall")
        l:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 2, 3)
    end
end

local function CheckBox(key, text, tip, x, y)
    local cb = CreateFrame("CheckButton", "InnervateBuddyOpt_" .. key, opt, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    cb:SetPoint("TOPLEFT", opt, "TOPLEFT", x, y)
    local tmpl = getglobal(cb:GetName() .. "Text")
    if tmpl then tmpl:SetText("") end
    cb.label = Label(cb, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetHitRectInsets(0, -150, 0, 0)
    cb:SetScript("OnClick", function()
        IB.db[key] = this:GetChecked() and true or false
        IB:ApplySettings()
        IB:Options_Refresh()
    end)
    cb:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1)
        GameTooltip:AddLine(tip, 1, 0.82, 0, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    checks[key] = cb
end

local function Slider(key, text, minv, maxv, step, x, y, fmt)
    local name = "InnervateBuddyOpt_" .. key
    local s = CreateFrame("Slider", name, opt, "OptionsSliderTemplate")
    s:SetWidth(170)
    s:SetHeight(16)
    s:SetPoint("TOPLEFT", opt, "TOPLEFT", x, y)
    s:SetMinMaxValues(minv, maxv)
    s:SetValueStep(step)
    getglobal(name .. "Low"):SetText("")
    getglobal(name .. "High"):SetText("")
    s:SetScript("OnValueChanged", function()
        local v = math.floor(this:GetValue() / step + 0.5) * step
        IB.db[key] = v
        getglobal(this:GetName() .. "Text"):SetText(text .. ":  |cffffffff" .. fmt(v) .. "|r")
        IB:ApplySettings()
    end)
    sliders[key] = s
end

local function Button(text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", opt, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- layout grid for the lower section: two 192px columns
local COL_L, COL_R, COL_W = 16, 232, 192
local ROW_STEP = 15

local function ListRow(x, y, withRemove)
    local r = CreateFrame("Frame", nil, opt)
    r:SetWidth(COL_W)
    r:SetHeight(ROW_STEP)
    r:SetPoint("TOPLEFT", opt, "TOPLEFT", x, y)
    r.text = Label(r, "")
    r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
    if withRemove then
        local rb = CreateFrame("Button", nil, r)
        rb:SetWidth(16)
        rb:SetHeight(ROW_STEP)
        rb:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        local fs = rb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", rb, "CENTER", 0, 1)
        fs:SetText("x")
        fs:SetTextColor(1, 0.3, 0.3)
        rb:SetScript("OnClick", function() if r.value then IB:RemoveManual(r.value) end end)
        rb:SetScript("OnEnter", function() fs:SetTextColor(1, 0.6, 0.6) end)
        rb:SetScript("OnLeave", function() fs:SetTextColor(1, 0.3, 0.3) end)
        r.remove = rb
    end
    return r
end

local function ListBackground(x, y, h)
    local bg = opt:CreateTexture(nil, "BORDER")
    bg:SetTexture(TEX)
    bg:SetVertexColor(1, 1, 1, 0.05)
    bg:SetWidth(COL_W)
    bg:SetHeight(h)
    bg:SetPoint("TOPLEFT", opt, "TOPLEFT", x, y)
end

local function pctFmt(v) return math.floor(v * 100 + 0.5) .. "%" end
local function intFmt(v) return tostring(math.floor(v + 0.5)) end
local function scaleFmt(v) return string.format("%.2f", v) end

local function CreateOptions()
    opt = CreateFrame("Frame", "InnervateBuddyOptions", UIParent)
    opt:SetWidth(440)
    opt:SetHeight(556)
    opt:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    opt:SetFrameStrata("DIALOG")
    opt:SetMovable(true)
    opt:EnableMouse(true)
    opt:RegisterForDrag("LeftButton")
    opt:SetScript("OnDragStart", function() this:StartMoving() end)
    opt:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    opt:SetBackdrop({
        bgFile = TEX, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    opt:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    opt:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    opt:Hide()
    table.insert(UISpecialFrames, "InnervateBuddyOptions")

    local title = Label(opt, "|cffff7d0aInnervate|rBuddy", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", opt, "TOPLEFT", 16, -14)
    local ver = Label(opt, "|cff777777v" .. IB.version .. "  -  /ib help|r")
    ver:SetPoint("LEFT", title, "RIGHT", 8, -1)

    local close = CreateFrame("Button", nil, opt, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", opt, "TOPRIGHT", -2, -2)

    -- display section
    Divider(opt, -52, "Display")
    local y, step = -60, -24
    CheckBox("locked", "Lock frame", "Prevents dragging. Unlock to move it.", 16, y)
    CheckBox("showDPS", "Show DPS mana classes", "Also list mages, warlocks, hunters and DPS-spec hybrids. Healers get a green edge.", 16, y + step)
    CheckBox("includeSelf", "Include yourself", "List yourself too (for self-Innervate).", 16, y + step * 2)
    CheckBox("hideSolo", "Hide when solo", "Hide the frame when not in a party or raid (while locked).", 16, y + step * 3)
    CheckBox("combatOnly", "Only show in combat", "Hide the frame out of combat (while locked).", 16, y + step * 4)
    CheckBox("showHeader", "Show header / cooldown", "Show the title bar with your Innervate cooldown.", 16, y + step * 5)
    CheckBox("clickCast", "Left-click casts Innervate", "Left-click a name to Innervate them. Otherwise left-click targets.", 16, y + step * 6)
    CheckBox("assumeHybrids", "Assume hybrids heal", "Treat druids, shamans and paladins as healers until their talents (or combat log) say otherwise. Priests are always assumed healers until detected as Shadow.", 16, y + step * 7)

    Slider("maxRows", "Units shown", 1, 40, 1, 240, -78, intFmt)
    Slider("threshold", "Show below mana", 10, 100, 5, 240, -120, function(v) return math.floor(v) .. "%" end)
    Slider("fadeAlpha", "Out of range alpha", 0, 1, 0.05, 240, -162, pctFmt)
    Slider("width", "Width", 100, 300, 10, 240, -204, intFmt)
    Slider("scale", "Scale", 0.5, 2, 0.05, 240, -246, scaleFmt)

    -- healers section
    Divider(opt, -280, "Healers")
    modeButton = Button("", COL_W, COL_L, -290, function()
        local cur = IB.db.detectMode
        for i = 1, 3 do
            if MODE_ORDER[i] == cur then
                IB.db.detectMode = MODE_ORDER[math.mod(i, 3) + 1]
                break
            end
        end
        IB:Refresh()
        IB:Options_Refresh()
    end)
    Button("Reset detected", 110, COL_R, -290, function() IB:ClearDetected() end)
    testButton = Button("Test", COL_W - 114, COL_R + 114, -290, function()
        IB.testMode = not IB.testMode
        IB:Refresh()
        IB:Options_Refresh()
    end)

    CheckBox("useTalents", "Inspect talents", "Auto-detect healers by inspecting group members' talent specs (Turtle WoW / 1.18 allows inspecting at any range). One request every 3s, paused in combat and while your Inspect window is open.", COL_L, -318)
    CheckBox("useCombatLog", "Use combat log", "Fallback: auto-detect healers from heals and DPS spells seen in the combat log. Useful if talent inspect doesn't work.", COL_R, -318)

    -- column headers
    local l1 = Label(opt, "|cffaaaaaaManual list|r")
    l1:SetPoint("TOPLEFT", opt, "TOPLEFT", COL_L + 2, -352)
    local l2 = Label(opt, "|cffaaaaaaHealers in group now|r")
    l2:SetPoint("TOPLEFT", opt, "TOPLEFT", COL_R + 2, -352)

    -- add row (left) / inspect status (right), same baseline
    local eb = CreateFrame("EditBox", "InnervateBuddyOptInput", opt, "InputBoxTemplate")
    eb:SetWidth(92)   -- template caps draw 5px outside the box
    eb:SetHeight(20)
    eb:SetPoint("TOPLEFT", opt, "TOPLEFT", COL_L + 6, -368)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(24)
    local function addFromBox()
        local t = eb:GetText()
        if t and t ~= "" then IB:AddManual(t) end
        eb:SetText("")
        eb:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", addFromBox)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    Button("Add", 44, COL_L + 102, -368, addFromBox)
    Button("Target", COL_W - 148, COL_L + 148, -368, function() IB:AddManual(nil) end)

    specStatus = Label(opt, "")
    specStatus:SetPoint("LEFT", opt, "TOPLEFT", COL_R + 2, -378)
    specStatus:SetWidth(COL_W)

    -- lists
    local listTop, listH = -396, LIST_ROWS * ROW_STEP + 6
    ListBackground(COL_L, listTop, listH)
    ListBackground(COL_R, listTop, listH)
    for i = 1, LIST_ROWS do
        manualRows[i] = ListRow(COL_L, listTop - 3 - (i - 1) * ROW_STEP, true)
        healerRows[i] = ListRow(COL_R, listTop - 3 - (i - 1) * ROW_STEP, false)
    end

    -- mouse wheel scrolls the manual list
    local wheel = CreateFrame("Frame", nil, opt)
    wheel:SetPoint("TOPLEFT", opt, "TOPLEFT", COL_L, listTop)
    wheel:SetWidth(COL_W)
    wheel:SetHeight(listH)
    wheel:EnableMouseWheel(true)
    wheel:SetScript("OnMouseWheel", function()
        manualOffset = manualOffset - arg1
        IB:Options_Refresh()
    end)
    wheel:SetFrameLevel(opt:GetFrameLevel() + 1)
    for i = 1, LIST_ROWS do manualRows[i]:SetFrameLevel(wheel:GetFrameLevel() + 1) end

    local foot = Label(opt, "|cff777777Click a name: Innervate  -  Right: target  -  Shift-Right: toggle healer list|r")
    foot:SetPoint("BOTTOM", opt, "BOTTOM", 0, 12)

    opt:SetScript("OnShow", function() IB:Options_Refresh() end)
end

function IB:Options_Refresh()
    if not opt or not opt:IsVisible() then return end
    local db = self.db
    for key, cb in pairs(checks) do cb:SetChecked(db[key] and 1 or nil) end
    for key, s in pairs(sliders) do s:SetValue(db[key]) end
    modeButton:SetText(MODE_LABEL[db.detectMode] or db.detectMode)
    testButton:SetText(self.testMode and "Test: on" or "Test")
    local known, total, ok = self:InspectStatus()
    if not db.useTalents then
        specStatus:SetText("|cff777777Talent inspect off|r")
    elseif total == 0 then
        specStatus:SetText("|cff777777No other healing classes in group|r")
    else
        specStatus:SetText(string.format("|cff777777Specs inspected: |cffffffff%d/%d|r%s", known, total,
            (ok == nil and known < total) and " |cff777777(waiting)|r" or ""))
    end

    local list = self:GetManualList()
    local n = table.getn(list)
    manualOffset = math.max(0, math.min(manualOffset, n - LIST_ROWS))
    for i = 1, LIST_ROWS do
        local r = manualRows[i]
        local name = list[i + manualOffset]
        r.value = name
        if name then
            r.text:SetText(name)
            r.remove:Show()
        elseif i == 1 and n == 0 then
            r.text:SetText("|cff666666(empty)|r")
            r.remove:Hide()
        else
            r.text:SetText("")
            r.remove:Hide()
        end
    end

    local healers = self:GetHealerSummary()
    for i = 1, LIST_ROWS do
        local r = healerRows[i]
        local h = healers[i]
        if h then
            local c = self.CLASS_COLORS[h.class] or { r = 1, g = 1, b = 1 }
            r.text:SetText(string.format("|cff%02x%02x%02x%s|r |cff777777%s|r",
                math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), h.name, h.reason or ""))
        elseif i == 1 then
            r.text:SetText("|cff666666(none)|r")
        else
            r.text:SetText("")
        end
    end
    if table.getn(healers) > LIST_ROWS then
        healerRows[LIST_ROWS].text:SetText("|cff777777+" .. (table.getn(healers) - LIST_ROWS + 1) .. " more|r")
    end
end

function IB:ToggleOptions()
    if not opt then CreateOptions() end
    if opt:IsVisible() then opt:Hide() else opt:Show() end
end
