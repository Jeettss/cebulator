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
local showCalendar
local showGuild
local reportFrame, calendarFrame, guildFrame

local function today()
    local cest    = time() + 2 * 3600
    local shifted = cest - 6 * 3600
    local t       = date("*t", shifted)
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function thisWeek()
    local cest    = time() + 2 * 3600
    local shifted = cest - 6 * 3600
    local t       = date("*t", shifted)
    -- weekday: 1=Sunday, 4=Wednesday
    local dow = t.wday
    local daysFromWed = (dow - 4 + 7) % 7
    local weekStart = shifted - daysFromWed * 86400
    local ws = date("*t", weekStart)
    return string.format("%04d-W%02d-%02d-%02d", ws.year, ws.month, ws.day, t.wday >= 4 and 0 or 1)
end

-- ===== GUILD SYNC SYSTEM =====
local GUILD_PREFIX = "Cebulator"
local guildData = {}  -- guildData[btag] = { name=charName, kills={}, loot={}, badluck={}, weekBadluck={}, weekKills={}, weekLoot={} }
local lastGuildSync = 0
local GUILD_SYNC_COOLDOWN = 60

local function getPlayerBTag()
    local ok, _, tag = pcall(BNGetInfo)
    if ok and tag and type(tag) == "string" then
        return tag:match("^([^#]+)") or tag
    end
    return UnitName("player") or "Unknown"
end

local function guildEncode()
    local d = today()
    local w = thisWeek()
    local btag = getPlayerBTag()
    local charName = UnitName("player")
    local parts = {}

    -- part 0: btag~charName
    parts[1] = btag .. "~" .. charName

    local dk = CebulatorDB.dailyKills[d]
    local killParts = {}
    if dk then
        for mob, cnt in pairs(dk) do
            killParts[#killParts+1] = mob .. "=" .. cnt
        end
    end
    parts[2] = table.concat(killParts, ",")

    local dl = CebulatorDB[d]
    local lootParts = {}
    if dl then
        for itemId in pairs(ITEMS) do
            if (dl[itemId] or 0) > 0 then
                lootParts[#lootParts+1] = itemId .. "=" .. dl[itemId]
            end
        end
    end
    parts[3] = table.concat(lootParts, ",")

    local bl = CebulatorDB.badluck
    local blParts = {}
    for itemId in pairs(ITEMS) do
        local cur = bl.current[itemId] or 0
        if cur > 0 then
            blParts[#blParts+1] = itemId .. "=" .. cur
        end
    end
    parts[4] = table.concat(blParts, ",")

    -- weekly kills
    local wk = {}
    local cestNow = time() + 2 * 3600
    local shiftedNow = cestNow - 6 * 3600
    local tNow = date("*t", shiftedNow)
    local dowNow = tNow.wday
    local daysFromWedNow = (dowNow - 4 + 7) % 7
    local weekStartSec = shiftedNow - daysFromWedNow * 86400
    local wsDate = date("*t", weekStartSec)
    local weekStartStr = string.format("%04d-%02d-%02d", wsDate.year, wsDate.month, wsDate.day)
    for dateStr, mobs in pairs(CebulatorDB.dailyKills) do
        if dateStr >= weekStartStr and dateStr <= d then
            for mob, cnt in pairs(mobs) do
                wk[mob] = (wk[mob] or 0) + cnt
            end
        end
    end
    local wkParts = {}
    for mob, cnt in pairs(wk) do
        wkParts[#wkParts+1] = mob .. "=" .. cnt
    end
    parts[5] = table.concat(wkParts, ",")

    -- weekly loot
    local wr = CebulatorDB.records and CebulatorDB.records.weekly and CebulatorDB.records.weekly[w]
    local wlParts = {}
    if wr then
        for itemId in pairs(ITEMS) do
            if (wr[itemId] or 0) > 0 then
                wlParts[#wlParts+1] = itemId .. "=" .. wr[itemId]
            end
        end
    end
    parts[6] = table.concat(wlParts, ",")

    -- weekly bad luck
    local wblParts = {}
    local wbl = CebulatorDB.badluck.weekCurrent
    for itemId in pairs(ITEMS) do
        local cur = wbl[itemId] or 0
        if cur > 0 then
            wblParts[#wblParts+1] = itemId .. "=" .. cur
        end
    end
    parts[7] = table.concat(wblParts, ",")

    return "DATA|" .. table.concat(parts, "|")
end

local function guildDecode(payload)
    local segments = { strsplit("|", payload) }
    local tag = segments[1]
    if tag ~= "DATA" then return end

    local function parseKV(str)
        local t = {}
        if str and str ~= "" then
            for pair in str:gmatch("[^,]+") do
                local k, v = pair:match("(.+)=(%d+)")
                if k and v then t[k] = tonumber(v) end
            end
        end
        return t
    end

    local identStr = segments[2] or ""
    local btag, charName = identStr:match("^(.+)~(.+)$")
    if not btag then return end

    guildData[btag] = {
        name = charName,
        kills = parseKV(segments[3] or ""),
        loot = parseKV(segments[4] or ""),
        badluck = parseKV(segments[5] or ""),
        weekKills = parseKV(segments[6] or ""),
        weekLoot = parseKV(segments[7] or ""),
        weekBadluck = parseKV(segments[8] or ""),
    }

    return btag
end

local function guildEncodeRelay()
    -- encode all cached guildData entries as RELAY messages
    local msgs = {}
    local myBtag = getPlayerBTag()
    for btag, data in pairs(guildData) do
        if btag ~= myBtag then
            local parts = {}
            parts[1] = btag .. "~" .. (data.name or "?")

            local killParts = {}
            for k, v in pairs(data.kills or {}) do killParts[#killParts+1] = k .. "=" .. v end
            parts[2] = table.concat(killParts, ",")

            local lootParts = {}
            for k, v in pairs(data.loot or {}) do lootParts[#lootParts+1] = k .. "=" .. v end
            parts[3] = table.concat(lootParts, ",")

            local blParts = {}
            for k, v in pairs(data.badluck or {}) do blParts[#blParts+1] = k .. "=" .. v end
            parts[4] = table.concat(blParts, ",")

            local wkParts = {}
            for k, v in pairs(data.weekKills or {}) do wkParts[#wkParts+1] = k .. "=" .. v end
            parts[5] = table.concat(wkParts, ",")

            local wlParts = {}
            for k, v in pairs(data.weekLoot or {}) do wlParts[#wlParts+1] = k .. "=" .. v end
            parts[6] = table.concat(wlParts, ",")

            local wblParts = {}
            for k, v in pairs(data.weekBadluck or {}) do wblParts[#wblParts+1] = k .. "=" .. v end
            parts[7] = table.concat(wblParts, ",")

            msgs[#msgs+1] = "DATA|" .. table.concat(parts, "|")
        end
    end
    return msgs
end

local function sendGuildData()
    if not IsInGuild() then return end
    local msg = guildEncode()
    C_ChatInfo.SendAddonMessage(GUILD_PREFIX, msg, "GUILD")
end

local function sendGuildRelay()
    if not IsInGuild() then return end
    local msgs = guildEncodeRelay()
    for _, msg in ipairs(msgs) do
        C_ChatInfo.SendAddonMessage(GUILD_PREFIX, msg, "GUILD")
    end
end

local function requestGuildSync()
    if not IsInGuild() then return end
    local now = time()
    if now - lastGuildSync < GUILD_SYNC_COOLDOWN then return false end
    lastGuildSync = now
    -- include own data
    guildDecode(guildEncode())
    C_ChatInfo.SendAddonMessage(GUILD_PREFIX, "REQ", "GUILD")
    sendGuildData()
    return true
end

local function initDB()
    if not CebulatorDB then CebulatorDB = {} end
    if not CebulatorDB[today()] then CebulatorDB[today()] = {} end
    if not CebulatorDB.total   then CebulatorDB.total   = {} end
    if not CebulatorDB.minimap then CebulatorDB.minimap = {} end
    if not CebulatorDB.guildData then CebulatorDB.guildData = {} end
    guildData = CebulatorDB.guildData
    if not CebulatorDB.coinPos then
        CebulatorDB.coinPos = { point = DEFAULT_COIN_POS.point, x = DEFAULT_COIN_POS.x, y = DEFAULT_COIN_POS.y }
    end
    if not CebulatorDB.streak then
        CebulatorDB.streak = { current = 0, best = 0, lastKillDay = nil }
    end
    if not CebulatorDB.kills then CebulatorDB.kills = 0 end
    if not CebulatorDB.dailyKills then CebulatorDB.dailyKills = {} end
    if not CebulatorDB.lastSeenVersion then CebulatorDB.lastSeenVersion = "" end
    if CebulatorDB.reportPos == nil then CebulatorDB.reportPos = false end
    if not CebulatorDB.records then
        CebulatorDB.records = { daily = {}, weekly = {} }
    end
    if not CebulatorDB.badluck then
        CebulatorDB.badluck = { current = {}, best = {}, weekCurrent = {}, weekKey = thisWeek() }
        for itemId in pairs(ITEMS) do
            CebulatorDB.badluck.current[itemId] = 0
            CebulatorDB.badluck.best[itemId]    = 0
            CebulatorDB.badluck.weekCurrent[itemId] = 0
        end
    end
    -- initialize missing badluck keys
    if not CebulatorDB.badluck.weekCurrent then CebulatorDB.badluck.weekCurrent = {} end
    if not CebulatorDB.badluck.weekKey then CebulatorDB.badluck.weekKey = thisWeek() end
    for itemId in pairs(ITEMS) do
        if not CebulatorDB.badluck.current[itemId] then CebulatorDB.badluck.current[itemId] = 0 end
        if not CebulatorDB.badluck.best[itemId]    then CebulatorDB.badluck.best[itemId]    = 0 end
        if not CebulatorDB.badluck.weekCurrent[itemId] then CebulatorDB.badluck.weekCurrent[itemId] = 0 end
    end
    -- reset weekly bad luck on new week
    if CebulatorDB.badluck.weekKey ~= thisWeek() then
        CebulatorDB.badluck.weekKey = thisWeek()
        for itemId in pairs(ITEMS) do
            CebulatorDB.badluck.weekCurrent[itemId] = 0
        end
    end
    -- initialize daily/weekly records
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
    -- check if last kill day was yesterday or today
    local lastTime = s.lastKillDay
    local todayTime = t
    -- if lastKillDay is neither today nor yesterday - reset
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
    if s.lastKillDay == t then return end  -- already extended today
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
    ["1.05.2"] = {
        "What's New in Cebulator!",
        " ",
        "v1.05.2",
        "- Fixed report, calendar and guild windows opening multiple times",
        "  - they now toggle properly on repeated clicks",
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
    -- check daily record
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
    CebulatorDB.badluck.weekCurrent[itemId] = 0
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
        bl.weekCurrent[itemId] = (bl.weekCurrent[itemId] or 0) + 1
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

    if reportFrame and reportFrame:IsShown() then
        reportFrame:Hide()
        return
    end
    if reportFrame then reportFrame:Hide() end

    local W = 500
    local PAD_TOP = 70
    local PAD_BOTTOM = 76
    local contentW = W - 52

    local lines = {}
    local function addLine(text, font)
        lines[#lines+1] = { text = text, font = font or "GameFontHighlight" }
    end

    local s = CebulatorDB.streak
    addLine(string.format("|cffFFD700Account Killing Streak: %d day%s|r  |cff00cc00(best: %d)|r",
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
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    reportFrame = f
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
    hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 62)
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

    -- bottom menu
    local guildBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    guildBtn:SetSize(100, 22)
    guildBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -120, 36)
    guildBtn:SetText("Guild")
    guildBtn:SetScript("OnClick", function()
        local point,_,_,x,y = f:GetPoint()
        CebulatorDB.reportPos = {point=point,x=x,y=y}
        f:Hide()
        showGuild()
    end)

    local calBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    calBtn:SetSize(100, 22)
    calBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 36)
    calBtn:SetText("Calendar")
    calBtn:SetScript("OnClick", function()
        local point,_,_,x,y = f:GetPoint()
        CebulatorDB.reportPos = {point=point,x=x,y=y}
        f:Hide()
        showCalendar()
    end)

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

local MONTH_NAMES = { "January","February","March","April","May","June","July","August","September","October","November","December" }
local DAY_NAMES   = { "Mon","Tue","Wed","Thu","Fri","Sat","Sun" }

local function daysInMonth(y, m)
    if m == 2 then return (y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28 end
    if m==4 or m==6 or m==9 or m==11 then return 30 end
    return 31
end

local function firstWeekday(y, m) -- 1=Mon..7=Sun
    local t = date("*t", time({year=y,month=m,day=1,hour=12}))
    return t.wday == 1 and 7 or t.wday - 1
end

showCalendar = function(anchorFrame)
    if calendarFrame and calendarFrame:IsShown() then
        calendarFrame:Hide()
        return
    end
    if calendarFrame then calendarFrame:Hide() end

    local utc     = time() + 2*3600
    local shifted = utc - 6*3600
    local tnow    = date("*t", shifted)
    local curYear, curMonth = tnow.year, tnow.month
    local todayStr = today()

    local CELL = 52
    local COLS = 7
    local W    = CELL * COLS + 40
    local calViewYear, calViewMonth = curYear, curMonth

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    calendarFrame = f
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point,_,_,x,y = self:GetPoint()
        CebulatorDB.reportPos = { point=point, x=x, y=y }
    end)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=11,right=12,top=12,bottom=11},
    })

    -- header icon + title
    local icon = f:CreateTexture(nil,"ARTWORK")
    icon:SetTexture("Interface\\AddOns\\Cebulator\\cebulator")
    icon:SetSize(40,40)
    icon:SetPoint("TOPLEFT",f,"TOPLEFT",18,-16)
    local iconMask = f:CreateMaskTexture()
    iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    iconMask:SetAllPoints(icon)
    icon:AddMaskTexture(iconMask)
    local titleFs = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleFs:SetPoint("TOPLEFT",icon,"TOPRIGHT",10,0)
    titleFs:SetText("|cffffff00Cebulator|r")
    local subtitleFs = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    subtitleFs:SetPoint("TOPLEFT",titleFs,"BOTTOMLEFT",0,-2)
    subtitleFs:SetText("Calendar")

    -- month nav
    local monthLabel = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    monthLabel:SetPoint("TOP",f,"TOP",0,-68)

    local prevBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    prevBtn:SetSize(24,22)
    prevBtn:SetPoint("RIGHT",monthLabel,"LEFT",-6,0)
    prevBtn:SetText("<")

    local nextBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    nextBtn:SetSize(24,22)
    nextBtn:SetPoint("LEFT",monthLabel,"RIGHT",6,0)
    nextBtn:SetText(">")

    -- day headers
    local headerY = -95
    for i,dn in ipairs(DAY_NAMES) do
        local fs = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fs:SetSize(CELL,16)
        fs:SetPoint("TOPLEFT",f,"TOPLEFT", 20+(i-1)*CELL, headerY)
        fs:SetJustifyH("CENTER")
        fs:SetText("|cffaaaaaa"..dn.."|r")
    end

    -- cell pool
    local cells = {}
    for row=0,5 do
        for col=0,6 do
            local btn = CreateFrame("Button",nil,f)
            btn:SetSize(CELL-2, CELL-2)
            btn:SetPoint("TOPLEFT",f,"TOPLEFT", 20+col*CELL, headerY-20-row*(CELL))
            local bg = btn:CreateTexture(nil,"BACKGROUND")
            bg:SetAllPoints()
            btn.bg = bg
            local numFs = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            numFs:SetPoint("TOPLEFT",btn,"TOPLEFT",4,-2)
            btn.numFs = numFs
            local killFs = btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            killFs:SetPoint("CENTER",btn,"CENTER",0,-4)
            btn.killFs = killFs
            btn:SetScript("OnEnter", function(self)
                if not self.dateStr then return end
                local dk = CebulatorDB.dailyKills[self.dateStr]
                local dl = CebulatorDB[self.dateStr]
                if not dk and not dl then return end
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine("|cffffff00"..self.dateStr.."|r")
                GameTooltip:AddLine(" ")
                if dk then
                    GameTooltip:AddLine("|cffaaaaaa-- Kills --|r")
                    for mob,cnt in pairs(dk) do
                        GameTooltip:AddLine(string.format("  %s: %d", mob, cnt))
                    end
                end
                if dl then
                    local hasLoot = false
                    for itemId,itemName in pairs(ITEMS) do
                        if (dl[itemId] or 0) > 0 then hasLoot = true end
                    end
                    if hasLoot then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cffaaaaaa-- Loot --|r")
                        for itemId,itemName in pairs(ITEMS) do
                            local cnt = dl[itemId] or 0
                            if cnt > 0 then
                                GameTooltip:AddLine(string.format("  %s: %d", itemName, cnt))
                            end
                        end
                    end
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cells[row*7+col+1] = btn
        end
    end

    local function renderMonth()
        local dim = daysInMonth(calViewYear, calViewMonth)
        local startWd = firstWeekday(calViewYear, calViewMonth)
        monthLabel:SetText(string.format("|cffffff00%s %d|r", MONTH_NAMES[calViewMonth], calViewYear))

        -- disable nav beyond limits
        local minYear, minMonth = curYear, curMonth - 3
        if minMonth <= 0 then minYear = curYear-1; minMonth = minMonth+12 end
        local maxYear, maxMonth = curYear, curMonth + 2
        if maxMonth > 12 then maxYear = curYear+1; maxMonth = maxMonth-12 end
        prevBtn:SetEnabled(not (calViewYear==minYear and calViewMonth==minMonth))
        nextBtn:SetEnabled(not (calViewYear==maxYear and calViewMonth==maxMonth))

        for i=1,42 do
            local cell = cells[i]
            local dayNum = i - startWd + 1
            if dayNum < 1 or dayNum > dim then
                cell:Hide()
            else
                cell:Show()
                local ds = string.format("%04d-%02d-%02d", calViewYear, calViewMonth, dayNum)
                cell.dateStr = ds
                cell.numFs:SetText("|cffaaaaaa"..dayNum.."|r")

                -- total kills that day
                local dk = CebulatorDB.dailyKills[ds]
                local totalKills = 0
                if dk then for _,v in pairs(dk) do totalKills = totalKills + v end end

                -- color gradient: 0=gray, 1-3=light green, 4-6=medium, 7+=bright
                local r,g,b,a
                if ds == todayStr then
                    r,g,b,a = 0.2,0.2,0.5,0.6  -- today highlight blue
                elseif totalKills == 0 then
                    r,g,b,a = 0.15,0.15,0.15,0.8
                elseif totalKills <= 3 then
                    r,g,b,a = 0.1,0.3,0.1,0.9
                elseif totalKills <= 6 then
                    r,g,b,a = 0.1,0.5,0.1,0.9
                else
                    r,g,b,a = 0.1,0.75,0.1,0.9
                end
                cell.bg:SetColorTexture(r,g,b,a)

                if totalKills > 0 then
                    cell.killFs:SetText("|cff00ff00"..totalKills.."|r")
                else
                    cell.killFs:SetText("")
                end
            end
        end

        -- frame height based on rows needed
        local rows = math.ceil((startWd - 1 + dim) / 7)
        f:SetSize(W, 120 + 20 + rows * CELL + 76)
    end

    prevBtn:SetScript("OnClick", function()
        calViewMonth = calViewMonth - 1
        if calViewMonth < 1 then calViewMonth = 12; calViewYear = calViewYear - 1 end
        renderMonth()
    end)
    nextBtn:SetScript("OnClick", function()
        calViewMonth = calViewMonth + 1
        if calViewMonth > 12 then calViewMonth = 1; calViewYear = calViewYear + 1 end
        renderMonth()
    end)


    -- bottom menu
    local guildBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    guildBtn:SetSize(100,22)
    guildBtn:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-120,36)
    guildBtn:SetText("Guild")
    guildBtn:SetScript("OnClick", function()
        local point,_,_,x,y = f:GetPoint()
        CebulatorDB.reportPos = {point=point,x=x,y=y}
        f:Hide()
        showGuild()
    end)

    local summaryBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    summaryBtn:SetSize(100,22)
    summaryBtn:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-16,36)
    summaryBtn:SetText("Summary")
    summaryBtn:SetScript("OnClick", function()
        local point,_,_,x,y = f:GetPoint()
        CebulatorDB.reportPos = {point=point,x=x,y=y}
        f:Hide()
        showReport()
    end)

    local closeBtn = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    closeBtn:SetSize(80,22)
    closeBtn:SetPoint("BOTTOM",f,"BOTTOM",0,10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        local point,_,_,x,y = f:GetPoint()
        CebulatorDB.reportPos = {point=point,x=x,y=y}
        f:Hide()
    end)

    local pos = CebulatorDB.reportPos
    if pos then
        f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        f:SetPoint("CENTER")
    end

    renderMonth()
    f:Show()
end

showGuild = function()
    if guildFrame and guildFrame:IsShown() then
        guildFrame:Hide()
        return
    end
    if guildFrame then guildFrame:Hide() end

    local W = 620
    local PAD_TOP = 70
    local PAD_BOTTOM = 76
    local COL_W = (W - 52) / 2
    local MAX_RANK = 5

    local function rankColor(i)
        if i == 1 then return "|cffFFD700"
        elseif i == 2 then return "|cffc0c0c0"
        elseif i == 3 then return "|cffcd7f32"
        else return "|cffaaaaaa" end
    end

    local function buildRankKills(dataKey)
        local rank = {}
        for btag, data in pairs(guildData) do
            local total = 0
            for _, cnt in pairs(data[dataKey] or {}) do total = total + cnt end
            if total > 0 then rank[#rank+1] = { name = data.name or btag, count = total } end
        end
        table.sort(rank, function(a, b) return a.count > b.count end)
        return rank
    end

    local function buildRankLootItem(dataKey, itemId)
        local rank = {}
        for btag, data in pairs(guildData) do
            local cnt = (data[dataKey] or {})[tostring(itemId)] or 0
            if cnt > 0 then rank[#rank+1] = { name = data.name or btag, count = cnt } end
        end
        table.sort(rank, function(a, b) return a.count > b.count end)
        return rank
    end

    local function buildRankBadLuck(itemId)
        local rank = {}
        for btag, data in pairs(guildData) do
            local cur = (data.badluck or {})[tostring(itemId)] or 0
            if cur > 0 then rank[#rank+1] = { name = data.name or btag, count = cur } end
        end
        table.sort(rank, function(a, b) return a.count > b.count end)
        return rank
    end

    local function buildRankWeekBadLuck(itemId)
        local rank = {}
        for btag, data in pairs(guildData) do
            local cur = (data.weekBadluck or {})[tostring(itemId)] or 0
            if cur > 0 then rank[#rank+1] = { name = data.name or btag, count = cur } end
        end
        table.sort(rank, function(a, b) return a.count > b.count end)
        return rank
    end

    -- build frame
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    guildFrame = f
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

    local titleFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFs:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    titleFs:SetText("|cffffff00Cebulator|r")
    local subtitleFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitleFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
    subtitleFs:SetText("Guild")

    if not IsInGuild() then
        local noGuild = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noGuild:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -PAD_TOP + 10)
        noGuild:SetText("|cffcc4444Sorry, you have no guild.|r")
        f:SetSize(W, PAD_TOP + 30 + PAD_BOTTOM)
    else
        guildDecode(guildEncode())

        local function makeLabel(parent, x, y, text, font, width)
            local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
            fs:SetWidth(width or COL_W)
            fs:SetJustifyH("LEFT")
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            fs:SetText(text)
            return fs, fs:GetStringHeight()
        end

        local function drawRankEntries(parent, x, y, rank, maxEntries, formatFn)
            local h = 0
            if #rank == 0 then
                local _, lh = makeLabel(parent, x, y, "  |cffaaaaaano data yet|r", "GameFontHighlightSmall", COL_W)
                return lh + 2
            end
            for i = 1, math.min(#rank, maxEntries) do
                local text = formatFn(i, rank[i])
                local _, lh = makeLabel(parent, x, y - h, text, "GameFontHighlightSmall", COL_W)
                h = h + lh + 2
            end
            return h
        end

        local function drawHLine(parent, x, y, width)
            local line = parent:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(0.4, 0.4, 0.4, 0.5)
            line:SetSize(width, 1)
            line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        end

        local content = CreateFrame("Frame", nil, f)
        content:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -PAD_TOP + 10)

        local leftX = 0
        local rightX = COL_W + 10
        local leftY = 0
        local rightY = 0
        local fullW = COL_W * 2 + 10

        -- === BIG HEADERS ===
        local _, lh = makeLabel(content, leftX, leftY, "|cffffff00Daily|r", "GameFontNormalHuge", COL_W)
        makeLabel(content, rightX, rightY, "|cffffff00Weekly|r", "GameFontNormalHuge", COL_W)
        leftY = leftY - lh - 6
        rightY = rightY - lh - 6

        -- horizontal line under headers
        drawHLine(content, leftX, leftY, COL_W - 5)
        drawHLine(content, rightX, rightY, COL_W - 5)
        leftY = leftY - 6
        rightY = rightY - 6

        -- === RENOWNED BEAST KILLS ===
        _, lh = makeLabel(content, leftX, leftY, "|cffffff00Renowned Beast Kills|r", "GameFontNormal", COL_W)
        makeLabel(content, rightX, rightY, "|cffffff00Renowned Beast Kills|r", "GameFontNormal", COL_W)
        leftY = leftY - lh - 4
        rightY = rightY - lh - 4

        local dailyKillRank = buildRankKills("kills")
        local h = drawRankEntries(content, leftX, leftY, dailyKillRank, MAX_RANK, function(i, e)
            return string.format("  %s%d. %s|r - |cff00ff00%d|r", rankColor(i), i, e.name, e.count)
        end)
        leftY = leftY - h - 6

        local weeklyKillRank = buildRankKills("weekKills")
        h = drawRankEntries(content, rightX, rightY, weeklyKillRank, MAX_RANK, function(i, e)
            return string.format("  %s%d. %s|r - |cff00ff00%d|r", rankColor(i), i, e.name, e.count)
        end)
        rightY = rightY - h - 6

        -- horizontal line between kills and loot
        local killsBottom = math.min(leftY, rightY)
        drawHLine(content, leftX, killsBottom, COL_W - 5)
        drawHLine(content, rightX, killsBottom, COL_W - 5)
        leftY = killsBottom - 6
        rightY = killsBottom - 6

        -- === LOOT AMOUNT ===
        _, lh = makeLabel(content, leftX, leftY, "|cffffff00Loot Amount|r", "GameFontNormal", COL_W)
        makeLabel(content, rightX, rightY, "|cffffff00Loot Amount|r", "GameFontNormal", COL_W)
        leftY = leftY - lh - 4
        rightY = rightY - lh - 4

        for itemId, itemName in pairs(ITEMS) do
            _, lh = makeLabel(content, leftX, leftY, "  |cffFFD700" .. itemName .. "|r:", "GameFontNormal", COL_W)
            makeLabel(content, rightX, rightY, "  |cffFFD700" .. itemName .. "|r:", "GameFontNormal", COL_W)
            leftY = leftY - lh - 2
            rightY = rightY - lh - 2

            local dailyItemRank = buildRankLootItem("loot", itemId)
            h = drawRankEntries(content, leftX, leftY, dailyItemRank, MAX_RANK, function(i, e)
                return string.format("    %s%d. %s|r - %s%d|r", rankColor(i), i, e.name, rankColor(i), e.count)
            end)
            leftY = leftY - h - 4

            local weeklyItemRank = buildRankLootItem("weekLoot", itemId)
            h = drawRankEntries(content, rightX, rightY, weeklyItemRank, MAX_RANK, function(i, e)
                return string.format("    %s%d. %s|r - %s%d|r", rankColor(i), i, e.name, rankColor(i), e.count)
            end)
            rightY = rightY - h - 4
        end

        -- columns divider line (vertical)
        local colBottom = math.min(leftY, rightY)
        local divider = content:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(0.4, 0.4, 0.4, 0.5)
        divider:SetSize(1, math.abs(colBottom) + 4)
        divider:SetPoint("TOPLEFT", content, "TOPLEFT", COL_W + 5, 2)

        -- horizontal line before bad luck
        drawHLine(content, leftX, colBottom - 6, fullW)

        -- === BOTTOM: BAD LUCK ===
        local bottomY = colBottom - 18
        _, lh = makeLabel(content, leftX, bottomY, "|cffffff00Guild Bad Luck Ranking|r", "GameFontNormalHuge", fullW)
        bottomY = bottomY - lh - 4
        drawHLine(content, leftX, bottomY, fullW)
        bottomY = bottomY - 6

        -- two-column headers: Total | Weekly
        _, lh = makeLabel(content, leftX, bottomY, "|cffffff00Total|r", "GameFontNormal", COL_W)
        makeLabel(content, rightX, bottomY, "|cffffff00Weekly|r", "GameFontNormal", COL_W)
        bottomY = bottomY - lh - 4

        local blLeftY = bottomY
        local blRightY = bottomY

        for itemId, itemName in pairs(ITEMS) do
            _, lh = makeLabel(content, leftX, blLeftY, "  |cffFFD700" .. itemName .. "|r:", "GameFontNormal", COL_W)
            makeLabel(content, rightX, blRightY, "  |cffFFD700" .. itemName .. "|r:", "GameFontNormal", COL_W)
            blLeftY = blLeftY - lh - 2
            blRightY = blRightY - lh - 2

            local blRank = buildRankBadLuck(itemId)
            h = drawRankEntries(content, leftX, blLeftY, blRank, MAX_RANK, function(i, e)
                local color = i == 1 and "|cffcc4444" or "|cffaaaaaa"
                return string.format("    %s%d. %s|r - %s%d|r kills w/o drop", color, i, e.name, color, e.count)
            end)
            blLeftY = blLeftY - h - 4

            local wblRank = buildRankWeekBadLuck(itemId)
            h = drawRankEntries(content, rightX, blRightY, wblRank, MAX_RANK, function(i, e)
                local color = i == 1 and "|cffcc4444" or "|cffaaaaaa"
                return string.format("    %s%d. %s|r - %s%d|r kills w/o drop", color, i, e.name, color, e.count)
            end)
            blRightY = blRightY - h - 4
        end

        -- vertical divider for bad luck section
        local blBottom = math.min(blLeftY, blRightY)
        local blDivider = content:CreateTexture(nil, "ARTWORK")
        blDivider:SetColorTexture(0.4, 0.4, 0.4, 0.5)
        blDivider:SetSize(1, math.abs(blBottom - bottomY) + 4)
        blDivider:SetPoint("TOPLEFT", content, "TOPLEFT", COL_W + 5, bottomY + 2)

        local totalH = math.abs(blBottom)
        content:SetSize(fullW, totalH)
        f:SetSize(W, PAD_TOP + totalH + PAD_BOTTOM)
    end

    -- bottom menu
    local guildHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    guildHint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 62)
    guildHint:SetText("|cffaaaaaaThis section is currently in experimental mode.|r")

    local syncBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    syncBtn:SetSize(120, 22)
    syncBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 36)
    syncBtn:SetText("Sync with guild")
    syncBtn:SetScript("OnClick", function()
        if not IsInGuild() then
            print("|cffffff00Cebulator:|r You are not in a guild.")
            return
        end
        local ok = requestGuildSync()
        if ok then
            print("|cffffff00Cebulator:|r Guild sync requested. Refreshing in a moment...")
            C_Timer.After(2, function()
                local point,_,_,x,y = f:GetPoint()
                CebulatorDB.reportPos = {point=point,x=x,y=y}
                f:Hide()
                showGuild()
            end)
        else
            local remaining = GUILD_SYNC_COOLDOWN - (time() - lastGuildSync)
            print(string.format("|cffffff00Cebulator:|r Sync on cooldown. Try again in |cffFFD700%d|r sec.", remaining))
        end
    end)

    local summaryBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    summaryBtn:SetSize(100, 22)
    summaryBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 36)
    summaryBtn:SetText("Summary")
    summaryBtn:SetScript("OnClick", function()
        local point,_,_,x,y = f:GetPoint()
        CebulatorDB.reportPos = {point=point,x=x,y=y}
        f:Hide()
        showReport()
    end)

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

    -- check if all mobs are killed
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
        if reportFrame then reportFrame:SetPoint("CENTER") end
        print("|cffffff00Cebulator:|r Report position reset.")
    elseif cmd == "whatsnew" then
        CebulatorDB.lastSeenVersion = ""
        showWhatsNew()
    else
        print("|cffffff00Cebulator commands:|r")
        print("  /cebulator total reset - reset total account summary")
        print("  /cebulator daily reset - reset daily account summary")
        print("  /cebulator streak - show killing streak")
        print("  /cebulator position reset - reset report window position")
        print("  /cebulator whatsnew - show patch notes")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "Cebulator" then
        initDB()
        C_ChatInfo.RegisterAddonMessagePrefix(GUILD_PREFIX)
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
        -- auto sync guild data on login
        C_Timer.After(5, function()
            if IsInGuild() then
                lastGuildSync = time()
                guildDecode(guildEncode())
                C_ChatInfo.SendAddonMessage(GUILD_PREFIX, "REQ", "GUILD")
                sendGuildData()
            end
        end)
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
                local dk = CebulatorDB.dailyKills
                local d = today()
                if not dk[d] then dk[d] = {} end
                dk[d][targetName] = (dk[d][targetName] or 0) + 1
                onMobKilled()
            end
            if targetName == "Umbrafang" then waypointSet = false end
            -- check if all mobs in this zone are killed
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
    elseif event == "CHAT_MSG_ADDON" then
        local prefix = arg1
        if prefix ~= GUILD_PREFIX then return end
        local msg2, channel, sender = ...
        if not msg2 then return end
        if msg2 == "REQ" then
            sendGuildData()
            -- relay cached data from other players
            sendGuildRelay()
        elseif msg2:sub(1, 4) == "DATA" then
            guildDecode(msg2)
        end
    end
end)
