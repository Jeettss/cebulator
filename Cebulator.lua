local MOBS = {
    ["Eversong Woods"] = { mobs = { "Gloomclaw" },               pin = { x = 0.4200, y = 0.7944 }, mapID = 2395 },
    ["Zul'Aman"]       = { mobs = { "Silverscale" },             pin = { x = 0.4741, y = 0.5370 }, mapID = 2437 },
    ["Harandar"]       = { mobs = { "Lumenfin" },                pin = { x = 0.6652, y = 0.4750 }, mapID = 2413 },
    ["Voidstorm"]      = { mobs = { "Umbrafang", "Netherscythe" }, pin = nil, pins = { Umbrafang = { x = 0.5544, y = 0.6527 }, Netherscythe = { x = 0.4330, y = 0.8266 } }, mapID = 2405 },
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
local DEFAULT_COIN_POS = { point = "CENTER", x = 200, y = 0 }
local LDB, LibDBIcon, CebulatorLDB
local lastKilledMob = nil
local coinBtn
local waypointSet = false

local function today()
    local utc     = time() + 2 * 3600
    local shifted = utc - 6 * 3600
    local t       = date("*t", shifted)
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function initDB()
    if not CebulatorDB then CebulatorDB = {} end
    if not CebulatorDB[today()] then CebulatorDB[today()] = {} end
    if not CebulatorDB.total   then CebulatorDB.total   = {} end
    if not CebulatorDB.minimap then CebulatorDB.minimap = {} end
    if not CebulatorDB.coinPos then
        CebulatorDB.coinPos = { point = DEFAULT_COIN_POS.point, x = DEFAULT_COIN_POS.x, y = DEFAULT_COIN_POS.y }
    end
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

local function applyCoinPos()
    local p = CebulatorDB.coinPos
    coinBtn:ClearAllPoints()
    coinBtn:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local function showReport()
    local day = getDayData()
    print("|cffffff00Cebulator v" .. C_AddOns.GetAddOnMetadata("Cebulator", "Version") .. " - Today:|r")
    local killed, notKilled = {}, {}
    for mobName in pairs(TRACKED_MOBS) do
        local data = day[mobName]
        if data and data.killed then
            killed[#killed+1] = mobName
        else
            notKilled[#notKilled+1] = mobName
        end
    end
    if #killed > 0 then
        print("|cff00ff00Killed today:|r")
        for _, mobName in ipairs(killed) do
            print("|cff00ff00  [" .. mobName .. "]|r")
        end
    end
    if #notKilled > 0 then
        print(" ")
        print("|cffaaaaaa Not killed today:|r")
        for _, mobName in ipairs(notKilled) do
            print("|cffaaaaaa  " .. mobName .. "|r")
        end
    end
    print(" ")
    print("|cffffff00Summary (daily account):|r")
    local loot = getDayLoot()
    for itemId, itemName in pairs(ITEMS) do
        print("  " .. itemName .. ": " .. (loot[itemId] or 0))
    end
    print(" ")
    print("|cffffff00Summary (total account):|r")
    local total = getTotalLoot()
    for itemId, itemName in pairs(ITEMS) do
        print("  " .. itemName .. ": " .. (total[itemId] or 0))
    end
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
    else
        print("|cffffff00Cebulator commands:|r")
        print("  /cebulator total reset - reset total account summary")
        print("  /cebulator daily reset - reset daily account summary")
        print("  /cebulator help - show this help")
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
            getMobData(targetName).killed = true
            lastKilledMob = targetName
            if targetName == "Umbrafang" then waypointSet = false end
        end
    elseif event == "LOOT_CLOSED" then
        lastKilledMob = nil
    end
end)
