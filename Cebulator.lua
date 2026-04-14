local MOBS = {
    ["Eversong Woods"] = { mobs = { "Gloomclaw" },               pin = { x = 0.4200, y = 0.7944 }, mapID = 2395 },
    ["Zul'Aman"]       = { mobs = { "Silverscale" },             pin = { x = 0.4741, y = 0.5370 }, mapID = 2437 },
    ["Harandar"]       = { mobs = { "Lumenfin" },                pin = { x = 0.6652, y = 0.4750 }, mapID = 2413 },
    ["Voidstorm"]      = { mobs = { "Umbrafang", "Netherscythe" }, pin = nil, pins = { Umbrafang = { x = 0.5407, y = 0.6524 }, Netherscythe = { x = 0.4330, y = 0.8266 } }, mapID = 2405 },
}
local ZONE_ALIASES = {
    ["Atal'Aman"]       = "Zul'Aman",
    ["The Den"]         = "Harandar",
    ["Silvermoon City"] = "Eversong Woods",
    ["Masters' Perch"]  = "Voidstorm",
}
local function getZone()
    local zone = GetRealZoneText()
    return ZONE_ALIASES[zone] or zone
end
local ITEMS = {
    [238529] = "Majestic Hide",
    [238528] = "Majestic Claw",
    [238530] = "Majestic Fin",
}
local TRACKED_MOBS = {
    Gloomclaw = true, Silverscale = true, Lumenfin = true,
    Umbrafang = true, Netherscythe = true,
}
local MOB_DROPS = {
    Gloomclaw   = { [238529] = true, [238528] = true },
    Silverscale = { [238528] = true },
    Lumenfin    = { [238530] = true },
    Umbrafang   = { [238529] = true, [238528] = true },
    Netherscythe = { [238529] = true, [238528] = true, [238530] = true },
}
local DEFAULT_COIN_POS = { point = "CENTER", x = 200, y = 0 }
local LDB, LibDBIcon, CebulatorLDB
local lastKilledMob = nil
local lastLootedMob = nil
local lastLootedGUID = nil
local coinBtn
local waypointSet = false

local function today()
    local utc     = time() + 2 * 3600
    local shifted = utc - 6 * 3600
    local t       = date("*t", shifted)
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function thisWeek()
    local utc     = time() + 2 * 3600
    local shifted = utc - 6 * 3600
    local t       = date("*t", shifted)
    -- weekday: 1=Sunday, 4=Wednesday
    local dow = t.wday
    local daysFromWed = (dow - 4 + 7) % 7
    local weekStart = shifted - daysFromWed * 86400
    local ws = date("*t", weekStart)
    return string.format("%04d-W%02d-%02d-%02d", ws.year, ws.month, ws.day, t.wday >= 4 and 0 or 1)
end

local function initDB()
    if not CebulatorDB then CebulatorDB = {} end
    if not CebulatorDB[today()] then CebulatorDB[today()] = {} end
    if not CebulatorDB.total   then CebulatorDB.total   = {} end
    if not CebulatorDB.minimap then CebulatorDB.minimap = {} end
    if not CebulatorDB.coinPos then
        CebulatorDB.coinPos = { point = DEFAULT_COIN_POS.point, x = DEFAULT_COIN_POS.x, y = DEFAULT_COIN_POS.y }
    end
    if not CebulatorDB.streak then
        CebulatorDB.streak = { current = 0, best = 0, lastKillDay = nil }
    end
    if not CebulatorDB.kills then CebulatorDB.kills = 0 end
    if not CebulatorDB.lastSeenVersion then CebulatorDB.lastSeenVersion = "" end
    if CebulatorDB.reportPos == nil then CebulatorDB.reportPos = false end
    if not CebulatorDB.records then
        CebulatorDB.records = { daily = {}, weekly = {} }
    end
    if not CebulatorDB.badluck then
        CebulatorDB.badluck = { current = {}, best = {} }
        for itemId in pairs(ITEMS) do
            CebulatorDB.badluck.current[itemId] = 0
            CebulatorDB.badluck.best[itemId]    = 0
        end
    end
    -- inicjalizuj brakujące klucze w badluck
    for itemId in pairs(ITEMS) do
        if not CebulatorDB.badluck.current[itemId] then CebulatorDB.badluck.current[itemId] = 0 end
        if not CebulatorDB.badluck.best[itemId]    then CebulatorDB.badluck.best[itemId]    = 0 end
    end
    -- inicjalizuj rekordy tygodniowe/dzienne
    if not CebulatorDB.records.daily[today()]      then CebulatorDB.records.daily[today()]      = {} end
    if not CebulatorDB.records.weekly[thisWeek()]  then CebulatorDB.records.weekly[thisWeek()]  = {} end
    if not CebulatorCharDB then CebulatorCharDB = {} end
    if not CebulatorCharDB[today()] then CebulatorCharDB[today()] = {} end
end

local function getDayData()  return CebulatorCharDB[today()] end
local function getDayLoot()  return CebulatorDB[today()] end
local function getTotalLoot() return CebulatorDB.total end

local function getMobData(mobName)
    local day = getDayData()
    if not day[mobName] then day[mobName] = { killed = false } end
    return day[mobName]
end

local function getLootData(itemId)
    local day = getDayLoot()
    if not day[itemId] then day[itemId] = 0 end
    return day
end

local function accountKilledToday()
    local day = CebulatorDB[today()]
    if not day then return false end
    for mobName in pairs(TRACKED_MOBS) do
        if day[mobName] and day[mobName].killed then return true end
    end
    return false
end

local function charKilledToday()
    local day = getDayData()
    for mobName in pairs(TRACKED_MOBS) do
        if day[mobName] and day[mobName].killed then return true end
    end
    return false
end

local function updateStreak()
    local s = CebulatorDB.streak
    local t = today()
    if s.lastKillDay == nil then return end
    -- sprawdź czy poprzedni dzień był wczoraj lub dziś
    local lastTime = s.lastKillDay
    local todayTime = t
    -- jeśli lastKillDay to nie dziś i nie wczoraj - reset
    local function daysBetween(d1, d2)
        local function toSec(d)
            local y, m, day = d:match("(%d+)-(%d+)-(%d+)")
            return time({ year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = 6 })
        end
        return math.floor((toSec(d2) - toSec(d1)) / 86400)
    end
    local diff = daysBetween(lastTime, todayTime)
    if diff > 1 then
        s.current = 0
        s.lastKillDay = nil
    end
end

local function onMobKilled()
    local s = CebulatorDB.streak
    local t = today()
    if s.lastKillDay == t then return end  -- już dziś przedłużono
    s.lastKillDay = t
    s.current = s.current + 1
    if s.current > s.best then s.best = s.current end
    print(string.format("|cffffff00Cebulator:|r Good job on extending your hunting streak! Currently |cffFFD700%d|r day%s.", s.current, s.current == 1 and "" or "s"))
end

local function showStreakLogin()
    local s = CebulatorDB.streak
    local accountKilled = accountKilledToday()
    local charKilled = charKilledToday()
    if accountKilled and charKilled then
        print(string.format("|cffffff00Cebulator:|r You have a |cffFFD700%d|r day%s killing streak. Good job!", s.current, s.current == 1 and "" or "s"))
    elseif accountKilled and not charKilled then
        print(string.format("|cffffff00Cebulator:|r You have a |cffFFD700%d|r day%s killing streak, but you haven't hunted the Renowned Beasts on this character yet!", s.current, s.current == 1 and "" or "s"))
    else
        if s.current > 0 then
            print(string.format("|cffffff00Cebulator:|r You have a |cffFFD700%d|r day%s killing streak. Keep it up and remember to hunt the Renowned Beasts today!", s.current, s.current == 1 and "" or "s"))
        else
            print("|cffffff00Cebulator:|r Remember to hunt the Renowned Beasts today!")
        end
    end
end

local PATCH_NOTES = {
    ["1.04"] = {
        "What's New in Cebulator!",
        " ",
        "v1.04",
        "- Killing streak system - tracks how many days in a row you hunted a Renowned Beast (account-wide)",
        "- Login reminder - on login you receive a message about your current streak and whether you still need to hunt today",
        "- Drop average tracker - total summary now shows average drops per kill",
        "  (for accurate data, run |cffffff00'/cebulator total reset'|r and |cffffff00'/cebulator daily reset'|r)",
        "- Waypoint now auto-clears after killing the last tracked beast in the zone",
        "- Personal records - announces new daily loot records in chat",
        "- Bad luck counter - tracks kills without a specific drop (visible in report)",
        "- Report is now a movable popup window instead of chat messages",
        " ",
        "Check |cffffff00'/cebulator help'|r for detailed commands.",
    },
}

local function showWhatsNew()
    local version = C_AddOns.GetAddOnMetadata("Cebulator", "Version")
    if CebulatorDB.lastSeenVersion == version then return end
    if not PATCH_NOTES[version] then
        CebulatorDB.lastSeenVersion = version
        return
    end

    local f = CreateFrame("Frame", "CebulatorWhatsNew", UIParent, "BackdropTemplate")
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local W = 390
    local PAD_TOP = 80
    local PAD_BOTTOM = 50

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\Cebulator\\cebulator")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    local iconMask = f:CreateMaskTexture()
    iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    iconMask:SetAllPoints(icon)
    icon:AddMaskTexture(iconMask)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    title:SetText("|cffffff00Cebulator|r")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("What's New?")

    local notes = PATCH_NOTES[version]
    local fontStrings = {}
    local totalH = 0
    local contentW = W - 52
    for i, line in ipairs(notes) do
        local font = i == 1 and "GameFontNormalLarge" or (line:sub(1,1) == "v" and "GameFontNormal" or "GameFontHighlight")
        local fs = f:CreateFontString(nil, "OVERLAY", font)
        fs:SetWidth(contentW)
        fs:SetJustifyH("LEFT")
        fs:SetText(line)
        fontStrings[i] = fs
        totalH = totalH + fs:GetStringHeight() + 4
    end

    local frameH = PAD_TOP + totalH + PAD_BOTTOM
    f:SetSize(W, frameH)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -PAD_TOP + 10)
    content:SetSize(contentW, totalH)

    local lastLine
    for i, fs in ipairs(fontStrings) do
        fs:SetParent(content)
        if i == 1 then
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        else
            fs:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT", 0, -4)
        end
        lastLine = fs
    end

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        CebulatorDB.lastSeenVersion = version
        f:Hide()
    end)

    f:Show()
end

local function onItemLooted(itemId, count)
    local r = CebulatorDB.records
    local d = today()
    local w = thisWeek()
    if not r.daily[d]   then r.daily[d]   = {} end
    if not r.weekly[w]  then r.weekly[w]  = {} end
    r.daily[d][itemId]  = (r.daily[d][itemId]  or 0) + count
    r.weekly[w][itemId] = (r.weekly[w][itemId] or 0) + count
    -- sprawdź rekord dzienny
    local bestDay = 0
    for _, dayData in pairs(r.daily) do
        if (dayData[itemId] or 0) > bestDay then bestDay = dayData[itemId] end
    end
    if r.daily[d][itemId] == bestDay and bestDay > 0 and r.daily[d][itemId] > (r.daily[d][itemId] - count) then
        local prevBest = 0
        for dk, dayData in pairs(r.daily) do
            if dk ~= d and (dayData[itemId] or 0) > prevBest then prevBest = dayData[itemId] end
        end
        if r.daily[d][itemId] > prevBest then
            print(string.format("|cffffff00Cebulator:|r New daily record! |cffFFD700%d|r %s in one day!", r.daily[d][itemId], ITEMS[itemId]))
        end
    end
    -- reset bad luck
    CebulatorDB.badluck.current[itemId] = 0
end

local function onMobKilledForBadLuck(mobName)
    local bl = CebulatorDB.badluck
    local drops = MOB_DROPS[mobName]
    if not drops then return end
    for itemId in pairs(drops) do
        bl.current[itemId] = (bl.current[itemId] or 0) + 1
        if bl.current[itemId] > (bl.best[itemId] or 0) then
            bl.best[itemId] = bl.current[itemId]
        end
    end
end

local function applyCoinPos()
    local p = CebulatorDB.coinPos
    coinBtn:ClearAllPoints()
    coinBtn:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local function showReport()
    local version = C_AddOns.GetAddOnMetadata("Cebulator", "Version")
    local day = getDayData()

    if CebulatorReportFrame and CebulatorReportFrame:IsShown() then
        CebulatorReportFrame:Hide()
        return
    end

    local W = 500
    local PAD_TOP = 70
    local PAD_BOTTOM = 50
    local contentW = W - 52

    local lines = {}
    local function addLine(text, font)
        lines[#lines+1] = { text = text, font = font or "GameFontHighlight" }
    end

    local s = CebulatorDB.streak
    addLine(string.format("|cffFFD700Killing Streak: %d day%s|r  |cff00cc00(best: %d)|r",
        s.current, s.current == 1 and "" or "s", s.best), "GameFontNormal")
    addLine(" ")

    local killed, notKilled = {}, {}
    for mobName in pairs(TRACKED_MOBS) do
        local data = day[mobName]
        if data and data.killed then killed[#killed+1] = mobName
        else notKilled[#notKilled+1] = mobName end
    end
    if #killed > 0 then
        addLine("|cff00cc00Killed today:|r", "GameFontNormal")
        for _, mobName in ipairs(killed) do
            addLine("|cff00cc00  - |r" .. mobName)
        end
    end
    if #notKilled > 0 then
        addLine(" ")
        addLine("|cffcc4444Not killed today:|r", "GameFontNormal")
        for _, mobName in ipairs(notKilled) do
            addLine("|cffcc4444  - |r|cffaaaaaa" .. mobName .. "|r")
        end
    end

    addLine(" ")
    addLine("|cffffff00Daily Loot|r", "GameFontNormal")
    local loot = getDayLoot()
    for itemId, itemName in pairs(ITEMS) do
        local count = loot[itemId] or 0
        local color = count > 0 and "|cffFFD700" or "|cffaaaaaa"
        local bestDay = 0
        for _, dayData in pairs(CebulatorDB.records.daily) do
            if (dayData[itemId] or 0) > bestDay then bestDay = dayData[itemId] end
        end
        if bestDay > 0 then
            addLine(string.format("  %s%s|r: %s%d|r |cff00cc00(best daily: %d)|r", color, itemName, color, count, bestDay), "GameFontHighlightSmall")
        else
            addLine(string.format("  %s%s|r: %s%d|r", color, itemName, color, count))
        end
    end

    addLine(" ")
    addLine("|cffffff00Total Loot|r", "GameFontNormal")
    local total = getTotalLoot()
    local kills = CebulatorDB.kills or 0
    for itemId, itemName in pairs(ITEMS) do
        local count = total[itemId] or 0
        if kills > 0 then
            addLine(string.format("  |cffFFD700%s|r: %d |cffaaaaaa(avg drop per kill: %.2g)|r", itemName, count, count / kills), "GameFontHighlightSmall")
        else
            addLine(string.format("  |cffFFD700%s|r: %d", itemName, count))
        end
    end

    addLine(" ")
    addLine("|cffffff00Bad Luck Counter|r", "GameFontNormal")
    local bl = CebulatorDB.badluck
    for itemId, itemName in pairs(ITEMS) do
        local cur = bl.current[itemId] or 0
        local best = bl.best[itemId] or 0
        local curColor = cur >= 5 and "|cffcc4444" or "|cffaaaaaa"
        addLine(string.format("  |cffFFD700%s|r: %s%d kills without drop|r |cffcc4444(longest: %d)|r",
            itemName, curColor, cur, best), "GameFontHighlightSmall")
    end

    -- build frame
    local f = CreateFrame("Frame", "CebulatorReportFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        CebulatorDB.reportPos = { point = point, x = x, y = y }
    end)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\Cebulator\\cebulator")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    local iconMask = f:CreateMaskTexture()
    iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    iconMask:SetAllPoints(icon)
    icon:AddMaskTexture(iconMask)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    title:SetText("|cffffff00Cebulator|r")
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("v" .. version .. " - Summary")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 46)
    hint:SetText("|cffaaaaaaCheck |cffffff00/cebulator help|r|cffaaaaaa for additional commands.|r")

    local fontStrings = {}
    local totalH = 0
    for i, line in ipairs(lines) do
        local fs = f:CreateFontString(nil, "OVERLAY", line.font)
        fs:SetWidth(contentW)
        fs:SetJustifyH("LEFT")
        fs:SetText(line.text)
        fontStrings[i] = fs
        totalH = totalH + fs:GetStringHeight() + 4
    end

    local frameH = PAD_TOP + totalH + PAD_BOTTOM
    f:SetSize(W, frameH)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -PAD_TOP + 10)
    content:SetSize(contentW, totalH)

    local lastLine
    for i, fs in ipairs(fontStrings) do
        fs:SetParent(content)
        if i == 1 then
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        else
            fs:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT", 0, -4)
        end
        lastLine = fs
    end

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        local point, _, _, x, y = f:GetPoint()
        CebulatorDB.reportPos = { point = point, x = x, y = y }
        f:Hide()
    end)

    local pos = CebulatorDB.reportPos
    if pos then
        f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        f:SetPoint("CENTER")
    end

    f:Show()
end

local function resetCoinPos()
    CebulatorDB.coinPos = { point = DEFAULT_COIN_POS.point, x = DEFAULT_COIN_POS.x, y = DEFAULT_COIN_POS.y }
    applyCoinPos()
end

local MACRO_NAME = "CebTarget"

local function getPinForMob(zoneData, mobName)
    if zoneData.pins and zoneData.pins[mobName] then return zoneData.pins[mobName] end
    if zoneData.pin then return zoneData.pin end
    return nil
end

local function setWaypoint()
    local zone = getZone()
    local zoneData = MOBS[zone]
    if not zoneData then
        C_Map.ClearUserWaypoint()
        return
    end

    -- sprawdź czy wszystkie moby zabite
    local allKilled = true
    for _, mob in ipairs(zoneData.mobs or {}) do
        if not getMobData(mob).killed then allKilled = false; break end
    end
    if allKilled then
        for _, mob in ipairs(zoneData.mobs or {}) do
            local pin = getPinForMob(zoneData, mob)
            if pin then
                print(string.format("|cffaaaaaa[Cebulator] %s (%s, %.2f, %.2f) already killed today.|r", mob, zone, pin.x * 100, pin.y * 100))
            else
                print(string.format("|cffaaaaaa[Cebulator] %s (%s) already killed today.|r", mob, zone))
            end
        end
        return
    end

    if waypointSet then return end
    local mapID = zoneData.mapID
    if not mapID then return end
    local pin = zoneData.pin
    local targetMob = zoneData.mobs and zoneData.mobs[1]
    if zoneData.pins then
        local umbrafangKilled = getMobData("Umbrafang").killed
        if umbrafangKilled then
            pin = zoneData.pins.Netherscythe
            targetMob = "Netherscythe"
        else
            pin = zoneData.pins.Umbrafang
            targetMob = "Umbrafang"
        end
    end
    if not pin then return end
    local point = UiMapPoint.CreateFromCoordinates(mapID, pin.x, pin.y)
    C_Map.SetUserWaypoint(point)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    waypointSet = true
    print(string.format("|cffffff00Cebulator:|r Setting waypoint to %s (%s, %.2f, %.2f)", targetMob or "?", zone, pin.x * 100, pin.y * 100))
end

local function updateTargetMacro()
    local zone = getZone()
    local zoneData = MOBS[zone]
    local mobs = zoneData and zoneData.mobs
    local body = ""
    if mobs then
        local filteredMobs = mobs
        if zone == "Voidstorm" then
            local umbrafangKilled = getMobData("Umbrafang").killed
            filteredMobs = { umbrafangKilled and "Netherscythe" or "Umbrafang" }
        end
        for _, mob in ipairs(filteredMobs) do body = body .. "/target " .. mob .. "\n" end
    end
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx == 0 then
        CreateMacro(MACRO_NAME, "INV_Misc_QuestionMark", body, false)
    else
        EditMacro(idx, MACRO_NAME, nil, body)
    end
    if not InCombatLockdown() then
        coinBtn:SetAttribute("macrotext1", body)
    end
end

local function setup()
    coinBtn = CreateFrame("Button", "CebulatorCoinBtn", UIParent, "SecureActionButtonTemplate")
    coinBtn:SetSize(48, 48)
    coinBtn:SetMovable(true)
    coinBtn:SetClampedToScreen(true)
    coinBtn:RegisterForClicks("AnyUp", "AnyDown")
    coinBtn:RegisterForDrag("LeftButton")
    coinBtn:SetAttribute("type1", "macro")
    coinBtn:SetAttribute("macrotext1", "")
    coinBtn:Hide()

    local coinIcon = coinBtn:CreateTexture(nil, "ARTWORK")
    coinIcon:SetTexture("Interface\\AddOns\\Cebulator\\cebulator")
    coinIcon:SetAllPoints()
    local coinMask = coinBtn:CreateMaskTexture()
    coinMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    coinMask:SetAllPoints(coinIcon)
    coinIcon:AddMaskTexture(coinMask)

    local hl = coinBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\AddOns\\Cebulator\\cebulator")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1, 0.3)
    hl:SetAllPoints()
    local hlMask = coinBtn:CreateMaskTexture()
    hlMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    hlMask:SetAllPoints(hl)
    hl:AddMaskTexture(hlMask)

    local ring = coinBtn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\AddOns\\Cebulator\\cebulator")
    ring:SetVertexColor(1, 1, 1, 0.9)
    ring:SetPoint("TOPLEFT", coinBtn, "TOPLEFT", -3, 3)
    ring:SetPoint("BOTTOMRIGHT", coinBtn, "BOTTOMRIGHT", 3, -3)
    local ringMask = coinBtn:CreateMaskTexture()
    ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    ringMask:SetPoint("TOPLEFT", ring, "TOPLEFT")
    ringMask:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT")
    ring:AddMaskTexture(ringMask)
    ring:Hide()

    coinBtn:SetScript("OnEnter", function(self)
        ring:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Cebulator")
        GameTooltip:AddLine(" ")
        local zone = getZone()
        local zoneData = MOBS[zone]
        local mobs = zoneData and zoneData.mobs
        if mobs then
            GameTooltip:AddLine("|cffeda55fLMB|r Target: " .. table.concat(mobs, ", "))
        else
            GameTooltip:AddLine("|cffeda55fLMB|r Target (no mobs in this zone)")
        end
        if zoneData and zoneData.pin then
            GameTooltip:AddLine("|cffeda55fLMB|r also sets map waypoint")
        end
        GameTooltip:AddLine("|cffeda55fRMB|r Show report")
        GameTooltip:Show()
    end)
    coinBtn:SetScript("OnLeave", function(self)
        ring:Hide()
        GameTooltip:Hide()
    end)
    coinBtn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    coinBtn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        CebulatorDB.coinPos = { point = point, x = x, y = y }
    end)
    coinBtn:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then showReport() end
        if button == "LeftButton" then setWaypoint() end
    end)

    LDB = LibStub("LibDataBroker-1.1")
    LibDBIcon = LibStub("LibDBIcon-1.0")
    CebulatorLDB = LDB:NewDataObject("Cebulator", {
        type = "data source",
        text = "Cebulator",
        icon = "Interface\\AddOns\\Cebulator\\cebulator_minimap",
        OnClick = function(self, button)
            if IsShiftKeyDown() and IsAltKeyDown() then
                resetCoinPos()
            else
                if coinBtn:IsShown() then
                    coinBtn:Hide()
                else
                    coinBtn:Show()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Cebulator")
            tooltip:AddLine(" ")
            tooltip:AddLine("|cffeda55fLMB|r Toggle Tracker")
            tooltip:AddLine("|cffeda55fShift+Alt+LMB|r Reset Tracker position")
        end,
    })
    LibDBIcon:Register("Cebulator", CebulatorLDB, CebulatorDB.minimap)
    LibDBIcon:Show("Cebulator")

    applyCoinPos()
    updateTargetMacro()
end

function Cebulator_OnCombatLog(msg)
    if not msg then return end
    for mobName in pairs(TRACKED_MOBS) do
        if msg:find(mobName, 1, true) then
            getMobData(mobName).killed = true
            lastKilledMob = mobName
        end
    end
end

SLASH_CEBULATOR1 = "/cebulator"
SlashCmdList["CEBULATOR"] = function(msg)
    local cmd = msg:lower()
    if cmd == "total reset" then
        CebulatorDB.total = {}
        print("|cffffff00Cebulator:|r Total account summary reset.")
    elseif cmd == "daily reset" then
        CebulatorDB[today()] = {}
        print("|cffffff00Cebulator:|r Daily account summary reset.")
    elseif cmd == "streak" then
        local s = CebulatorDB.streak
        print(string.format("|cffffff00Cebulator:|r Current streak: |cffFFD700%d|r day%s. Personal best: |cffFFD700%d|r day%s.",
            s.current, s.current == 1 and "" or "s",
            s.best, s.best == 1 and "" or "s"))
    elseif cmd == "position reset" then
        CebulatorDB.reportPos = false
        if CebulatorReportFrame then CebulatorReportFrame:SetPoint("CENTER") end
        print("|cffffff00Cebulator:|r Report position reset.")
    else
        print("|cffffff00Cebulator commands:|r")
        print("  /cebulator total reset - reset total account summary")
        print("  /cebulator daily reset - reset daily account summary")
        print("  /cebulator streak - show killing streak")
        print("  /cebulator position reset - reset report window position")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Cebulator" then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        setup()
        updateStreak()
        showStreakLogin()
        showWhatsNew()
        local zone = getZone()
        local zoneData = MOBS[zone]
        if zoneData and not zoneData.mapID then
            zoneData.mapID = C_Map.GetBestMapForUnit("player")
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        waypointSet = false
        if coinBtn then updateTargetMacro() end
        local zone = getZone()
        local zoneData = MOBS[zone]
        if zoneData and not zoneData.mapID then
            zoneData.mapID = C_Map.GetBestMapForUnit("player")
        end
    elseif event == "CHAT_MSG_LOOT" then
        if not lastKilledMob then return end
        for itemId in pairs(ITEMS) do
            local itemStr = "item:" .. itemId
            local s, e = arg1:find(itemStr)
            if s then
                local count = tonumber(arg1:match("x(%d+)", e)) or 1
                local loot = getDayLoot()
                loot[itemId] = (loot[itemId] or 0) + count
                local total = getTotalLoot()
                total[itemId] = (total[itemId] or 0) + count
                onItemLooted(itemId, count)
                local mobName = lastKilledMob
                if not mobName then
                    local targetName = UnitName("target")
                    if targetName and TRACKED_MOBS[targetName] then mobName = targetName end
                end
                if mobName then
                    getMobData(mobName).killed = true
                end
            end
        end
    elseif event == "LOOT_OPENED" then
        local targetName = UnitName("target")
        if targetName and TRACKED_MOBS[targetName] then
            local guid = GetLootSourceInfo(1)
            getMobData(targetName).killed = true
            local dayAccount = CebulatorDB[today()]
            if not dayAccount[targetName] then dayAccount[targetName] = {} end
            dayAccount[targetName].killed = true
            lastKilledMob = targetName
            if guid ~= lastLootedGUID then
                lastLootedGUID = guid
                lastLootedMob = targetName
                onMobKilledForBadLuck(targetName)
                CebulatorDB.kills = CebulatorDB.kills + 1
                onMobKilled()
            end
            if targetName == "Umbrafang" then waypointSet = false end
            -- sprawdź czy wszystkie moby na tej mapie zabite
            local zone = getZone()
            local zoneData = MOBS[zone]
            if zoneData then
                local allKilled = true
                for _, mob in ipairs(zoneData.mobs or {}) do
                    if not getMobData(mob).killed then allKilled = false; break end
                end
                if allKilled then
                    C_Map.ClearUserWaypoint()
                    waypointSet = false
                end
            end
        end
    elseif event == "LOOT_CLOSED" then
        lastKilledMob = nil
    end
end)
