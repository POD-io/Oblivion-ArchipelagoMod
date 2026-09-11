--[[
    Archipelago Integration Mod for Oblivion Remastered
    
    Integrates Oblivion Remastered with the Archipelago multiworld randomizer.
    Handles receiving items from other players and sending completion status back.
    

--]]

local UEHelpers = require("UEHelpers")
local config = require("ArchipelagoConfig")
local console = require("OBRConsole")


local function runPathDebug()
    local function safePrint(s)
        print(tostring(s):gsub("[^\32-\126]", "?"))
    end
    print("========================================")
    print("ARCHIPELAGO PATH DEBUG START")
    print("========================================")
    local ap_userprofile = os.getenv("USERPROFILE")
    safePrint("USERPROFILE = " .. tostring(ap_userprofile))
    local ap_default_dir = tostring(ap_userprofile) .. "\\Documents\\My Games\\Oblivion Remastered\\Saved\\Archipelago"
    safePrint("DEFAULT_ARCHIPELAGO_DIR = " .. ap_default_dir)
    local ap_test_connection = ap_default_dir .. "\\current_connection.txt"
    local ap_test_override = ap_default_dir .. "\\path_override.txt"
    print("Checking current_connection.txt")
    safePrint("PATH = " .. ap_test_connection)
    local f = io.open(ap_test_connection, "r")
    if f then
        print("RESULT = FOUND")
        f:close()
    else
        print("RESULT = NOT FOUND")
    end
    print("Checking path_override.txt")
    safePrint("PATH = " .. ap_test_override)
    f = io.open(ap_test_override, "r")
    if f then
        print("RESULT = FOUND")
        local line = f:read("*line")
        safePrint("CONTENTS = " .. tostring(line))
        f:close()
    else
        print("RESULT = NOT FOUND")
    end
    print("========================================")
    print("ARCHIPELAGO PATH DEBUG END")
    print("========================================")
end
runPathDebug()

-- ActorDetection module
local ActorDetection = nil
local killTrackingEnabled = false
local hasDungeonKillChecks = false
local hasOverworldKillChecks = false
local dungeonKillsPerCheck = 1
local overworldKillsPerCheck = 1
local killProgress = { dungeon = 0, overworld = 0, oblivion = 0 }
local killProgressLoaded = false
local pendingWarpMarker = nil
local WARP_FALLBACK_MARKER = "ICPrisonSewerMapMarker"
local skillXpApplied = false

-- Periodic tracking state
local nirnrootTrackingEnabled = false
local bossChestTrackingEnabled = false
local lastTrackingUpdate = 0
local lastBossChestMessage = 0
local lastNirnrootMessage = 0
local TRACKING_INTERVAL = 5.0  -- seconds
local BOSS_CHEST_MESSAGE_INTERVAL = 15.0  -- seconds
local NIRNROOT_MESSAGE_INTERVAL = 20.0  -- seconds
-- Quest marker (APXMarker) last-set position; nil means the marker is currently inactive.
-- Used to suppress when location has not changed
local lastMarkerX = nil
local lastMarkerY = nil
local lastMarkerZ = nil
local MARKER_MOVE_THRESHOLD = 50
local pendingTrackingToggle = false
local pendingIcarianFlight = false
local pendingMarkerClear = false
local pendingCellLookup = false
local pendingAutoTrack = nil
local pendingNirnrootRedetect = false
local state = {
    unstableSeconds = 0.5,
    unstableUntil = 0,
    travelling = false,
    fenceLimit = 0,
    fadeWorldSetup = false,
    apSyncOnStable = false,
    firstInit = false,
    periodMs = 250,
    nextPeriodAt = 0,
    nextSessionAt = 0,
    started = false,
    cellPending = false,
    loggedSkip = false,
    kills = {},
    gameStarted = false,
    notificationHookRegistered = false,
    allowAPSync = false,
    probeStartedForSession = false,
    pinsNeedRestore = true,
    pinsRestoreArmed = false,
    bountyProgressReady = false,
    hasOblivionKillChecks = false,
    oblivionKills = 0,
    oblivionKillsPerCheck = 2,
    oblivionKillsPerGate = 0,
    gateCount = 0,
    lastGateKillWarnKey = "",
    weaponLock = false,
    weaponLicenses = {},
    tutorialWidget = nil,
}
-- When the player manually F11s to OFF, ALL auto-track is turned off until F11 cycles back.
local autoTrackManualOff = false
-- Set by APAutoTrackNirnOff message
local nirnrootManualOff = false
-- if no nirnroot in seed, we will not auto-track nirnroot
local nirnrootInSeed = false
-- if no Dungeons in seed, we will not auto-track boss chests
local chestInSeed = false

-- Base directory for all Archipelago files
local DEFAULT_ARCHIPELAGO_DIR = os.getenv("USERPROFILE") .. "\\Documents\\My Games\\Oblivion Remastered\\Saved\\Archipelago"
local ARCHIPELAGO_BASE_DIR = DEFAULT_ARCHIPELAGO_DIR

-- Check for path override file at startup
local pathOverrideStatus = nil  -- nil = no file, "success" = loaded, "error" = found but invalid

local function loadPathOverride()
    local overridePath = DEFAULT_ARCHIPELAGO_DIR .. "\\path_override.txt"
    local file = io.open(overridePath, "r")
    if not file then
        return false  -- No override file, use default
    end
    
    local customPath = file:read("*line")
    file:close()
    
    if not customPath or customPath == "" then
        pathOverrideStatus = "error"
        return false
    end
    
    -- Normalize the path
    customPath = customPath:match("^%s*(.-)%s*$")
    customPath = customPath:gsub("/", "\\")
    customPath = customPath:gsub("[\\]+$", "")
    
    -- Validate the path
    if customPath == "" or not customPath:match("\\") then
        pathOverrideStatus = "error"
        return false
    end
    
    -- Accept the path
    ARCHIPELAGO_BASE_DIR = customPath
    pathOverrideStatus = "success"
    return true
end

-- Load path override before anything else
local pathOverrideLoaded = loadPathOverride()

-- Encumbrance scaling constants (match to .esp value)
local ENCUMBRANCE_MULT = 500
local ENCUMBRANCE_SETTINGS_OBJ = "/Script/UE5AltarPairing.Default__VOblivionInitialSettings"

-- Quality-of-life settings
local archipelagoSettings = {
    free_offerings = true,  -- Automatically add shrine offerings when receiving shrine tokens
    dungeon_marker_mode = "reveal_and_fast_travel", -- or "reveal_only"
    dungeon_warp = "off", -- "off", "on", "item", or "early_item"
    auto_tracking = false,      -- Automatically switch compass tracking on cell transitions
    silent_auto_tracking = false, -- do not show "Message" notifications for tracking
    ap_tips = true,
    skill_xp_multiplier = 1,
}

-- Queue for displaying messages when multiple items are processed
local messageboxQueue = {}
local BULK_ITEM_THRESHOLD = 30
local bulkItemGrantInProgress = false
local loggedInventoryNotifyDefault = false

-- Path + logging helpers
local function getArchipelagoPath(filename)
    return ARCHIPELAGO_BASE_DIR .. "\\" .. filename
end

local function getScriptDirectory()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1,1) == "@" then
        return info.source:match("^@(.+)\\[^\\]+$") or ""
    end
    return ""
end

-- Cached session ID for log lines; updated whenever getCurrentFilePrefix() is called
local currentSessionId = "NO_SESSION"

local function writeLog(message, level)
    level = level or "INFO"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logMessage = string.format("[%s] [%s] [%s] %s", timestamp, currentSessionId, level, message)
    local logPath = getArchipelagoPath("archipelago_debug.log")
    local file = io.open(logPath, "a")
    if file then
        file:write(logMessage .. "\n")
        file:close()
    end
end

local init = {
    shopStock = false,
    arena = false,
    shrines = false,
    sidequests = false,
    gates = false,
    doomstones = false,
    gateVision = false,
    fastTravel = false,
    classSystem = false,
    dungeonCounters = false,
    bounties = false,
    weaponLicenses = false,
    modFully = false,
    encumbrance = false,
    needsShopStock = false,
    needsArena = false,
    needsShrines = false,
    needsSidequests = false,
    needsGates = false,
    needsDoomstones = false,
    needsGateVision = false,
    needsFastTravel = false,
    needsClassSystem = false,
    needsDungeonCounters = false,
    needsBounties = false,
    needsWeaponLicenses = false,
    initializationCompleteTime = 0,
    itemProcessingEnabled = false,
}

-- apply Encumbrance fix once per session
local function applyEncumbranceScaling()
    if init.encumbrance then return true end
    local ok, result = pcall(function()
        local obj = StaticFindObject(ENCUMBRANCE_SETTINGS_OBJ)
        if obj and obj:IsValid() then
            obj.DefaultStrengthEncumbranceMult = ENCUMBRANCE_MULT
            return true
        end
        return false
    end)
    if ok and result then
        init.encumbrance = true
        writeLog(string.format("Encumbrance scaling applied: DefaultStrengthEncumbranceMult = %d", ENCUMBRANCE_MULT))
        return true
    end
    return false
end

-- read back the live value and reapply if the game has reset it.
local lastEncumbranceValidation = 0
local ENCUMBRANCE_VALIDATION_INTERVAL = 120  -- seconds between validation checks
local function validateEncumbranceScaling()
    if not init.encumbrance then return end  -- not applied yet; retry path handles this
    local ok, currentValue = pcall(function()
        local obj = StaticFindObject(ENCUMBRANCE_SETTINGS_OBJ)
        if obj and obj:IsValid() then
            return obj.DefaultStrengthEncumbranceMult
        end
        return nil
    end)
    if ok and currentValue ~= nil then
        if currentValue ~= ENCUMBRANCE_MULT then
            writeLog(string.format("Encumbrance validation failed (current=%s, expected=%d) — reapplying",
                tostring(currentValue), ENCUMBRANCE_MULT), "WARNING")
            init.encumbrance = false
            applyEncumbranceScaling()
        end
    end
end

pcall(applyEncumbranceScaling)

local hasShownNoSettingsMessage = false
-- Track if we showed the "no connection file" message and if a connection follow-up was shown
local hadNoConnectionMessage = false
local hasShownConnectionEstablished = false


-- Current goal from settings file
local currentGoal = ""
local goalRequired = 0

-- AP Class system settings
local selectedClass = ""

-- Class to integer mapping
local classToIntegerMapping = {
    ["Acrobat"] = 1,
    ["Agent"] = 2,
    ["Archer"] = 3,
    ["Assassin"] = 4,
    ["Barbarian"] = 5,
    ["Bard"] = 6,
    ["Battlemage"] = 7,
    ["Crusader"] = 8,
    ["Healer"] = 9,
    ["Knight"] = 10,
    ["Mage"] = 11,
    ["Monk"] = 12,
    ["Nightblade"] = 13,
    ["Pilgrim"] = 14,
    ["Rogue"] = 15,
    ["Scout"] = 16,
    ["Sorcerer"] = 17,
    ["Spellsword"] = 18,
    ["Thief"] = 19,
    ["Warrior"] = 20,
    ["Witchhunter"] = 21
}



local function queueMessagebox(message)
    table.insert(messageboxQueue, message)
end

local function processMessageboxQueue()
    if #messageboxQueue == 0 then return end
    if state.travelling or state.isWorldUnstable() then
        return
    end
    local message = table.remove(messageboxQueue, 1)
    console.ExecuteConsole("MessageBox \"" .. message .. "\"")
end

-- fetch APAppliedCount via console GetGS markers and then emit Message "AP_SYNC COUNT <n>".
-- this is used to track the number of items received from the multiworld
-- and to ensure that LUA and game are in sync

-- probe variables
local getBridgeStatusAPCount
local getCurrentFilePrefix
local truncateBridgeStatusTail
local apProbe = {
    console = nil,
    lastCount = 0,
    awaiting = false,
    circularBufferMode = false,
    circularBufferCheckCount = 0,
    inApsyncBlock = false,
    pendingValue = nil,
}
local menuCheckProbe = {
    awaiting = false,
    lastCount = 0,
    inBlock = false,
    gameHour = nil,
    cellFormID = nil,
}
local pendingMenuReinitCheck = false

local cellLookupProbe = {
    awaiting = false,
    lastCount = 0,
    foundFormID = nil,
    startedAt = nil,
    blockStartedAt = nil,
    circularBufferMode = false,
}
local currentCellName = nil
local currentCellEditorID = nil  -- EditorID from CSV lookup (used to detect Oblivion interiors)
local currentCellIsOblivion = false  -- True when in any Oblivion plane (worldspace or interior)
local cellNameRequestPending = false

pcall(function()
    PropertyTypes.ArrayProperty.Size = 0x10
    RegisterCustomProperty({ Name = "OutputBuffer", Type = PropertyTypes.ArrayProperty, BelongsToClass = "/Script/Engine.Console", OffsetInternal = 0x50, ArrayProperty = { Type = PropertyTypes.StrProperty } })
    RegisterCustomProperty({ Name = "OutputBufferSize", Type = PropertyTypes.IntProperty, BelongsToClass = "/Script/Engine.Console", OffsetInternal = 0x58 })
end)

local function apFindConsole()
    local cachedOk = false
    pcall(function()
        if apProbe.console and apProbe.console:IsValid() then
            cachedOk = true
        end
    end)
    if cachedOk then return apProbe.console end
    apProbe.console = nil
    local inst = FindFirstOf("Console")
    local valid = false
    pcall(function()
        if inst and inst:IsValid() then valid = true end
    end)
    if valid then
        apProbe.console = inst
    end
    return apProbe.console
end

local function apProbeResetBlock()
    apProbe.inApsyncBlock = false
    apProbe.pendingValue = nil
end

local function apProbeFeedLine(line)
    if line:find("Start {ID:APSYNC}", 1, true) then
        apProbe.inApsyncBlock = true
        apProbe.pendingValue = nil
        return false
    end
    if not apProbe.inApsyncBlock then return false end

    local v = line:match("^GetGlobalValue >>%s*(%d+%.?%d*)")
    if v then
        apProbe.pendingValue = math.floor(tonumber(v))
    end

    if line:find("GameSetting End", 1, true) then
        apProbe.inApsyncBlock = false
        return true
    end
    return false
end

-- When APAppliedCount reads 0 on an initialized session, verify GameHour/cell
-- before asking for new save reinit - this detects if player exited to main menu.
local function menuCheckInProgress()
    return pendingMenuReinitCheck or menuCheckProbe.awaiting
end

local function menuCheckFeedLine(line)
    if line:find("Start {ID:APMENU}", 1, true) then
        menuCheckProbe.inBlock = true
        menuCheckProbe.gameHour = nil
        menuCheckProbe.cellFormID = nil
        return false
    end
    if not menuCheckProbe.inBlock then return false end

    local hour = line:match("^GetGlobalValue >>%s*(%d+%.?%d*)")
    if hour then
        menuCheckProbe.gameHour = tonumber(hour)
    end

    local cell = line:match("Cell:%s*(%x+)")
    if cell then
        menuCheckProbe.cellFormID = cell:upper()
    end

    if line:find("GameSetting End", 1, true) then
        menuCheckProbe.inBlock = false
        return true
    end
    return false
end

local function startMenuCheckProbe()
    apFindConsole()
    local inst = apProbe.console
    if not inst then
        pendingMenuReinitCheck = false
        writeLog("Menu check aborted: console unavailable", "WARN")
        return
    end

    menuCheckProbe.awaiting = true
    menuCheckProbe.lastCount = inst.OutputBufferSize
    menuCheckProbe.inBlock = false
    menuCheckProbe.gameHour = nil
    menuCheckProbe.cellFormID = nil

    pcall(function()
        console.ExecuteConsole('GetGS "Start {ID:APMENU}"')
        console.ExecuteConsole("GetGlobalValue GameHour")
        console.ExecuteConsole("player.getparentcell")
        console.ExecuteConsole('GetGS "End"')
    end)
end

local function readMenuCheckConsole()
    if not menuCheckProbe.awaiting then return false end

    local inst = apFindConsole()
    if not inst then return false end

    local newCount = inst.OutputBufferSize
    if newCount <= menuCheckProbe.lastCount then return false end

    local blockComplete = false
    for i = menuCheckProbe.lastCount, newCount - 1 do
        local line = inst.OutputBuffer[i + 1]:ToString()
        if menuCheckFeedLine(line) then
            blockComplete = true
        end
    end
    menuCheckProbe.lastCount = newCount

    if blockComplete then
        menuCheckProbe.awaiting = false
        return true
    end
    return false
end

local function isMainMenuFalsePositive(gameHour, cellFormID)
    if gameHour == nil or math.abs(gameHour - 1.0) >= 0.01 then
        return false
    end
    if cellFormID and cellFormID:match("^%x+$") then
        return false
    end
    return true
end

local function processPendingMenuReinitCheck()
    if not pendingMenuReinitCheck then return end
    if not readMenuCheckConsole() then return end

    pendingMenuReinitCheck = false
    local hour = menuCheckProbe.gameHour
    local cell = menuCheckProbe.cellFormID

    if isMainMenuFalsePositive(hour, cell) then
        writeLog("Ignoring APAppliedCount=0: main menu (GameHour=1.00, no cell)")
        state.pinsNeedRestore = true
        state.pinsRestoreArmed = false
        skillXpApplied = false
        if reinitPending then
            writeLog("Clearing stale reinitPending: player returned to main menu")
            reinitPending = false
        end
        probeFinished = true
        return
    end

    writeLog("Probe zero confirmed in-game (GameHour=" .. tostring(hour) .. ", cell=" .. tostring(cell) .. "); continuing reinit flow")
    if reinitPending then
        writeLog("Clearing stale reinitPending before new-save reinit")
        reinitPending = false
    end
    pcall(function()
        console.ExecuteConsole('Message "AP_SYNC COUNT 0"')
    end)
end

local function apProbeEmitCount(value)
    if menuCheckInProgress() then
        return
    end

    local countStr = tostring(value)
    if not probeFinished then
        local ingameCount = value
        local diskCount = getBridgeStatusAPCount()
        local diff = diskCount - ingameCount
        if diff ~= 0 then
            writeLog("AP sync: in-game=" .. countStr .. ", bridge=" .. tostring(diskCount) .. ", diff=" .. tostring(diff))
        end

        if ingameCount == 0 and init.modFully and not suppressReinitOnNextZero then
            pendingMenuReinitCheck = true
            startMenuCheckProbe()
            if menuCheckInProgress() then
                apProbe.awaiting = false
                apProbe.circularBufferMode = false
                apProbe.circularBufferCheckCount = 0
                apProbeResetBlock()
                local inst = apFindConsole()
                if inst then
                    apProbe.lastCount = inst.OutputBufferSize
                end
                return
            end
        end

        if ingameCount ~= 0 then
            if ingameCount > diskCount then
                -- No match, show notification messagebox with prompt
            elseif diff > 0 and diff <= 20 then
                local removed = truncateBridgeStatusTail(diff)
                pcall(function()
                    console.ExecuteConsole("Message \"APSync: requesting resend of " .. tostring(removed) .. " items\"")
                end)
                probeFinished = true
                probeAttemptCount = 0
            elseif diff > 20 then
                pcall(function()
                    console.ExecuteConsole("set APSyncRequest to 1")
                end)
            else
                probeFinished = true
                probeAttemptCount = 0
            end
        end
    end
    pcall(function()
        console.ExecuteConsole('Message "AP_SYNC COUNT ' .. countStr .. '"')
    end)
    apProbe.awaiting = false
    apProbe.circularBufferMode = false
    apProbe.circularBufferCheckCount = 0
    apProbeResetBlock()
end

local function apReadConsoleAndEmitCount()
    local inst = apFindConsole()
    if not inst then return end

    local newCount = inst.OutputBufferSize
    local bufferAtMax = newCount >= 1024

    if apProbe.awaiting then
        local blockComplete = false
        local startIdx, endIdx

        if apProbe.circularBufferMode and bufferAtMax and newCount == apProbe.lastCount then
            apProbe.circularBufferCheckCount = apProbe.circularBufferCheckCount + 1
            if apProbe.circularBufferCheckCount < 60 then
                apProbe.lastCount = newCount
                return
            end
            startIdx = math.max(0, newCount - 40)
            endIdx = newCount - 1
            apProbeResetBlock()
        elseif newCount > apProbe.lastCount then
            startIdx = apProbe.lastCount
            endIdx = newCount - 1
        else
            apProbe.lastCount = newCount
            return
        end

        for i = startIdx, endIdx do
            local line = inst.OutputBuffer[i+1]:ToString()
            if apProbeFeedLine(line) then
                blockComplete = true
            end
        end

        if blockComplete then
            if apProbe.pendingValue ~= nil then
                apProbeEmitCount(apProbe.pendingValue)
            else
                writeLog("APSYNC block ended but GetGlobalValue >> line not found", "WARN")
                apProbeResetBlock()
            end
        end
    end
    apProbe.lastCount = newCount
end

local function startAPSyncProbe()
    apFindConsole()
    local currentBufferSize = apProbe.console and apProbe.console.OutputBufferSize or 0

    if currentBufferSize >= 1024 then
        apProbe.circularBufferMode = true
        apProbe.circularBufferCheckCount = 0
    else
        apProbe.circularBufferMode = false
    end

    apProbe.awaiting = true
    apProbe.lastCount = currentBufferSize
    apProbeResetBlock()
    probeFinished = false
    probeAttemptCount = 0
    probeStuckMessageShown = false

    local success, err = pcall(function()
        console.ExecuteConsole('GetGS "Start {ID:APSYNC}"')
        console.ExecuteConsole('GetGlobalValue APAppliedCount')
        console.ExecuteConsole('GetGS "End"')
    end)

    if not success then
        writeLog("Probe failed to execute console commands: " .. tostring(err), "ERROR")
        apProbe.awaiting = false
    end
end

local lookupCellNameByFormID

local shouldAutoTrack
local disableAllAutoTrack
local enableBossChestTracking
local enableNirnrootTracking
local clearAPXMarker
local tryEnableChestTrackingForCurrentCell

-- Random-gate Sigillum Sanguis only. Side towers (Sorrow/Anguish *LeftLord/*RightLord) are switches, not the close.
local function isRandomGateSigillum(editorID)
    editorID = editorID or ""
    if editorID:find("^OblivionRD") == nil or editorID:find("Lord") == nil then
        return false
    end
    if editorID:find("LeftLord") or editorID:find("RightLord") then
        return false
    end
    return true
end

function state.maybeWarnLastAccessibleGate(editorID)
    editorID = editorID or ""
    if not isRandomGateSigillum(editorID) then
        state.lastGateKillWarnKey = ""
        return
    end
    if (state.oblivionKills or 0) <= 0 or (state.gateCount or 0) <= 0 then
        return
    end
    local filePrefix = getCurrentFilePrefix and getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    local keysHeld = 0
    local statusFile = io.open(getArchipelagoPath(filePrefix .. "_bridge_status.txt"), "r")
    if statusFile then
        local content = statusFile:read("*a") or ""
        statusFile:close()
        for token in content:gmatch("([^,]+)") do
            if (token:match("^%s*(.-)%s*$") or "") == "Oblivion Gate Key" then
                keysHeld = keysHeld + 1
            end
        end
    end
    if keysHeld <= 0 then
        return
    end
    local closed = 0
    local oblivionChecked = 0
    local completedFile = io.open(getArchipelagoPath(filePrefix .. "_completed.txt"), "r")
    if completedFile then
        for line in completedFile:lines() do
            local stored = (line or ""):gsub("\r", ""):match("^%s*(.-)%s*$") or ""
            if stored == "Oblivion Gate Closed" then
                closed = closed + 1
            elseif stored == "Oblivion Kill" or stored:match("^Oblivion Kill %d+$") then
                oblivionChecked = oblivionChecked + 1
            end
        end
        completedFile:close()
    end
    if (closed + 1) < keysHeld then
        return
    end
    local perGate = state.oblivionKillsPerGate or 0
    local remainingInLogic = 0
    for i = 1, state.oblivionKills do
        local required = 1
        if perGate > 0 then
            required = math.ceil(i / perGate)
        end
        if required <= keysHeld and i > oblivionChecked then
            remainingInLogic = remainingInLogic + 1
        end
    end
    if remainingInLogic <= 0 then
        return
    end
    local warnKey = editorID .. "|" .. tostring(keysHeld) .. "|" .. tostring(closed)
    if state.lastGateKillWarnKey == warnKey then
        return
    end
    state.lastGateKillWarnKey = warnKey
    queueMessagebox("Beware, you are about to close the last accessible Gate and you still have Oblivion kill checks remaining. ")
end

-- Cell lookup: console player.getparentcell prints Cell: <hex>.
-- CSV maps that FormID to the TES cell name. UE world names are not TES cells.
function state.applyResolvedCellFormID(formID)
    cellLookupProbe.foundFormID = formID:upper()
    cellLookupProbe.awaiting = false
    cellLookupProbe.startedAt = nil
    cellLookupProbe.blockStartedAt = nil
    cellLookupProbe.circularBufferMode = false
    cellNameRequestPending = false
    pendingCellLookup = false

    local cellName, cellEditorID = lookupCellNameByFormID(cellLookupProbe.foundFormID)
    if cellName then
        currentCellName = cellName
        currentCellEditorID = cellEditorID or ""
        currentCellIsOblivion = currentCellEditorID:find("Oblivion") ~= nil
        if currentCellIsOblivion then
            writeLog("Cell resolved as Oblivion interior: " .. cellName .. " (" .. currentCellEditorID .. ")")
            if shouldAutoTrack() then
                disableAllAutoTrack()
                if apProbe.awaiting then
                    pendingMarkerClear = true
                else
                    clearAPXMarker()
                end
            end
        else
            writeLog("Cell resolved: " .. cellName .. " (" .. tostring(currentCellEditorID) .. ")")
            if shouldAutoTrack() and chestInSeed then
                if apProbe.awaiting then
                    pendingAutoTrack = "boss"
                else
                    tryEnableChestTrackingForCurrentCell()
                end
            end
        end
    else
        local worldFull = ""
        pcall(function()
            local ply = UEHelpers:GetPlayer()
            if ply and ply:IsValid() then
                worldFull = ply:GetWorld():GetFullName() or ""
            end
        end)
        if worldFull:lower():find("oblivion") then
            local mapName = worldFull:match("/([^/]+)%.") or worldFull:match("/([^/]+)$") or "Oblivion Plane"
            currentCellName = mapName
            currentCellEditorID = ""
            currentCellIsOblivion = true
            writeLog("Cell not in CSV but world name indicates Oblivion: " .. mapName .. " (FormID: " .. cellLookupProbe.foundFormID .. ")")
        elseif state.matchCityWorld(worldFull) then
            currentCellName = state.matchCityWorld(worldFull)
            currentCellEditorID = ""
            currentCellIsOblivion = false
            writeLog("City world (FormID not in CSV): " .. currentCellName .. " (" .. cellLookupProbe.foundFormID .. ")")
        else
            currentCellName = "Unknown Cell (FormID: " .. cellLookupProbe.foundFormID .. ")"
            currentCellEditorID = ""
            currentCellIsOblivion = false
            writeLog("Cell FormID not in oblivion_cell_database.csv: " .. cellLookupProbe.foundFormID .. " world='" .. worldFull .. "' — add this row to the CSV. Using fallback name.", "WARNING")
        end
    end
    state.cellPending = false
    state.flushPendingKills()
    state.maybeWarnLastAccessibleGate(currentCellEditorID)
end

function state.readCellLookupConsole()
    local inst = apFindConsole()
    if not inst or not cellLookupProbe.awaiting then return end

    local newCount = inst.OutputBufferSize or 0
    local startIdx, endIdx
    if newCount > cellLookupProbe.lastCount then
        startIdx = cellLookupProbe.lastCount
        endIdx = newCount - 1
    elseif newCount < cellLookupProbe.lastCount then
        startIdx = 0
        endIdx = newCount - 1
    elseif cellLookupProbe.circularBufferMode and newCount >= 1024 then
        startIdx = math.max(0, newCount - 20)
        endIdx = newCount - 1
    else
        return
    end

    for i = startIdx, endIdx do
        local line = nil
        pcall(function()
            line = inst.OutputBuffer[i + 1]:ToString()
        end)
        if line then
            local formID = line:match("Cell:%s*(%x+)")
            if formID then
                state.applyResolvedCellFormID(formID)
                cellLookupProbe.lastCount = newCount
                return
            end
        end
    end

    cellLookupProbe.lastCount = newCount
end

function state.startCellLookup()
    apFindConsole()
    local inst = apProbe.console
    if not inst then
        writeLog("Cell lookup waiting: console unavailable")
        pendingCellLookup = true
        if not cellLookupProbe.blockStartedAt then
            cellLookupProbe.blockStartedAt = os.clock()
        end
        return
    end
    cellLookupProbe.awaiting = true
    cellLookupProbe.startedAt = os.clock()
    cellLookupProbe.blockStartedAt = nil
    cellLookupProbe.lastCount = inst.OutputBufferSize or 0
    cellLookupProbe.circularBufferMode = cellLookupProbe.lastCount >= 1024
    cellLookupProbe.foundFormID = nil
    cellNameRequestPending = true
    pendingCellLookup = false
    writeLog("Cell lookup: player.getparentcell")
    local ok, err = pcall(function()
        console.ExecuteConsole("player.getparentcell")
    end)
    if not ok then
        writeLog("player.getparentcell failed: " .. tostring(err), "ERROR")
        cellLookupProbe.awaiting = false
        cellNameRequestPending = false
        pendingCellLookup = true
    end
end

function state.currentWorldFullName()
    local worldName = ""
    pcall(function()
        local player = UEHelpers:GetPlayer()
        if not player or not player:IsValid() then return end
        local world = player:GetWorld()
        if not world or not world:IsValid() then return end
        worldName = world:GetFullName() or ""
    end)
    return worldName
end

function state.matchCityWorld(worldName)
    if not worldName or worldName == "" then
        return nil
    end
    local cities = state.cityWorlds
    if not cities then
        cities = {
            { "ICImperialPalaceMQ16", "Imperial City" },
            { "ICTempleDistrictMQ16", "Imperial City" },
            { "ICTheArcaneUniversity", "Imperial City" },
            { "ICImperialPrisonDistrict", "Imperial City" },
            { "ICElvenGardensDistrict", "Imperial City" },
            { "ICArboretumDistrict", "Imperial City" },
            { "ICTalosPlazaDistrict", "Imperial City" },
            { "ICImperialPalace", "Imperial City" },
            { "ICMarketDistrict", "Imperial City" },
            { "ICTempleDistrict", "Imperial City" },
            { "ICArenaDistrict", "Imperial City" },
            { "CheydinhalWorld", "Cheydinhal" },
            { "LeyawiinWorld", "Leyawiin" },
            { "SkingradWorld", "Skingrad" },
            { "KvatchEntrance", "Kvatch" },
            { "ChorrolWorld", "Chorrol" },
            { "BravilWorld", "Bravil" },
            { "KvatchPlaza", "Kvatch" },
            { "KvatchEast", "Kvatch" },
            { "AnvilWorld", "Anvil" },
            { "BrumaWorld", "Bruma" },
        }
        state.cityWorlds = cities
    end
    for _, row in ipairs(cities) do
        if worldName:find(row[1], 1, true) then
            return row[2]
        end
    end
    return nil
end


function state.finishCellLookup(cellName, editorID, isOblivion, reason)
    currentCellName = cellName
    currentCellEditorID = editorID or ""
    currentCellIsOblivion = isOblivion and true or false
    cellLookupProbe.awaiting = false
    cellLookupProbe.startedAt = nil
    cellLookupProbe.blockStartedAt = nil
    cellLookupProbe.foundFormID = nil
    cellNameRequestPending = false
    pendingCellLookup = false
    state.cellPending = false
    writeLog(reason, "WARNING")
    if state.flushPendingKills then
        state.flushPendingKills()
    end
end

function state.expireCellLookupIfStuck()
    local waiting = cellLookupProbe.awaiting or cellNameRequestPending or pendingCellLookup or state.cellPending
    if not waiting then
        cellLookupProbe.blockStartedAt = nil
        return
    end
    local started = cellLookupProbe.startedAt or cellLookupProbe.blockStartedAt
    if not started then
        cellLookupProbe.blockStartedAt = os.clock()
        return
    end
    if (os.clock() - started) < 3.0 then
        return
    end
    local world = state.currentWorldFullName()
    local formId = cellLookupProbe.foundFormID or "(none)"
    if world:find("Tamriel") then
        state.finishCellLookup("Tamriel", "", false,
            "Cell lookup timed out after " .. tostring(3.0) .. "s. world='" .. world .. "' formID=" .. tostring(formId) .. " — falling back to Tamriel")
    elseif world:lower():find("oblivion") then
        local mapName = world:match("/([^/]+)%.") or world:match("/([^/]+)$") or "Oblivion Plane"
        state.finishCellLookup(mapName, "", true,
            "Cell lookup timed out. world='" .. world .. "' formID=" .. tostring(formId) .. " — Oblivion fallback")
    elseif state.matchCityWorld(world) then
        local cityName = state.matchCityWorld(world)
        state.finishCellLookup(cityName, "", false,
            "Cell lookup timed out. world='" .. world .. "' formID=" .. tostring(formId) .. " — city/town")
    else
        local mapName = world:match("/([^/]+)%.") or world:match("/([^/]+)$") or "Unknown Cell"
        state.finishCellLookup(mapName, "", false,
            "Cell lookup timed out. world='" .. world .. "' formID=" .. tostring(formId) .. " — treating as dungeon. If this FormID is missing from oblivion_cell_database.csv, add it.")
    end
end

-- Sync tracking and helpers
local probeFinished = false
local probeAttemptCount = 0
local probeStuckMessageShown = false

-- Initialization probe and reinit confirmation state
local reinitPending = false

-- This function resets the settings file by removing any *_initialized flags
-- This should only be called if a player starts an additional session after already having initialized once previously this session
-- In case the player made an error during character creation or just wanted to start over, this handles mod reinitialization
local suppressReinitOnNextZero = false

-- Forward declarations
local loadSettings
local handleInitialization


local function resetSettings()
    -- strip *_initialized and mod_fully_initialized from settings
    local prefix = getCurrentFilePrefix()
    if not prefix then
        writeLog("Reinit requested but no current file prefix found", "ERROR")
        return
    end

    local settingsPath = getArchipelagoPath(prefix .. "_settings.txt")
    local src = io.open(settingsPath, "r")
    if not src then
        writeLog("Reinit: settings file missing; nothing to clean", "WARNING")
    else
        local kept = {}
        for line in src:lines() do
            local key = line:match("^(.-)=") or ""
            -- Drop any *_initialized flags and mod_fully_initialized
            if key ~= "mod_fully_initialized"
               and not key:match("_initialized$") then
                table.insert(kept, line)
            end
        end
        src:close()
        local out = io.open(settingsPath, "w")
        if out then
            out:write(table.concat(kept, "\n"))
            if #kept > 0 then out:write("\n") end
            out:close()
            writeLog("Reinit: stripped initialized flags from settings")
        else
            writeLog("Reinit: failed to rewrite settings file", "ERROR")
        end
    end

    -- Do not clear bridge status or queue; probe will reconcile based on APAppliedCount vs receipts
    -- Reset local state so init will run again
    init.shopStock = false
    init.arena = false
    init.shrines = false
    init.sidequests = false
    init.gates = false
    init.doomstones = false
    init.gateVision = false
    init.fastTravel = false
    init.classSystem = false
    init.dungeonCounters = false
    init.bounties = false
    init.weaponLicenses = false
    init.encumbrance = false  -- allow reapplication for the new session
    init.needsShopStock = false
    init.needsArena = false
    init.needsShrines = false
    init.needsSidequests = false
    init.needsGates = false
    init.needsDoomstones = false
    init.needsGateVision = false
    init.needsFastTravel = false
    init.needsClassSystem = false
    init.needsDungeonCounters = false
    init.needsBounties = false
    init.needsWeaponLicenses = false
    init.modFully = false
    probeFinished = false

    -- Proactively reload settings and run init now so user doesn't have to wait
    loadSettings()
    handleInitialization()

    -- Kick off a fresh APSync probe after initialization so resend happens post-init
    writeLog("Reinit: starting APSync probe to reconcile items after fresh init")
    if not probeFinished and not apProbe.awaiting then
        startAPSyncProbe()
        state.probeStartedForSession = true -- prevents false positive on APAppliedCount = 0 at startup
    end

    -- One-shot: skip reinit check on the very next 0 so catch-up can proceed
    suppressReinitOnNextZero = true

    writeLog("Reinit: files reset; initialization re-run for this save")
end
-- Remember the last in-game APAppliedCount seen by the probe so we can compute
-- the true diff when the player responds
local lastIngameAPAppliedCount = nil

-- Count total entries (comma-separated) in bridge status
function getBridgeStatusAPCount()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return 0 end
    local statusPath = getArchipelagoPath(filePrefix .. "_bridge_status.txt")
    local file = io.open(statusPath, "r")
    if not file then
        -- First run or no items processed yet; treat as zero without warning
        writeLog("Bridge status file not found; assuming 0 previously applied items")
        return 0
    end
    local content = file:read("*all") or ""
    file:close()
    local count = 0
    for token in string.gmatch(content, "([^,]+)") do
        if token and token:match("%S") then count = count + 1 end
    end
    return count
end

-- Remove last N entries from bridge status to request client resend
function truncateBridgeStatusTail(n)
    if not n or n <= 0 then return 0 end
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return 0 end
    local statusPath = getArchipelagoPath(filePrefix .. "_bridge_status.txt")
    local file = io.open(statusPath, "r")
    if not file then return 0 end
    local content = file:read("*all") or ""
    file:close()

    -- Parse existing receipt items
    local items = {}
    for item in content:gmatch("([^,]+)") do
        table.insert(items, item)
    end
    local itemsToRemove = math.min(n, #items)
    if itemsToRemove <= 0 then
        return 0
    end

    -- Capture the removed items (oldest of the removed first)
    local removedItems = {}
    local startIndex = #items - itemsToRemove + 1
    for i = startIndex, #items do
        table.insert(removedItems, items[i])
    end

    -- Truncate the bridge status tail
    for i = 1, itemsToRemove do
        table.remove(items) -- remove from end
    end
    file = io.open(statusPath, "w")
    if file then
        if #items > 0 then
            file:write(table.concat(items, ",") .. ",")
        end
        file:close()
    end

    -- Prepend removed items back into the items queue for reprocessing
    local queuePath = getArchipelagoPath(filePrefix .. "_items.txt")
    local existingLines = {}
    local q = io.open(queuePath, "r")
    if q then
        for line in q:lines() do
            table.insert(existingLines, line)
        end
        q:close()
    end
    -- Rewrite queue: removedItems first (one per line), then the previous contents
    q = io.open(queuePath, "w")
    if q then
        for _, name in ipairs(removedItems) do
            q:write(name .. "\n")
        end
        for _, line in ipairs(existingLines) do
            if line and line:match("%S") then
                q:write(line .. "\n")
            end
        end
        q:close()
    end

    writeLog("AP sync: requeue " .. tostring(itemsToRemove) .. " items")
    return itemsToRemove
end


-- Get current connection file prefix
function getCurrentFilePrefix()
    local connectionPath = getArchipelagoPath("current_connection.txt")
    local file = io.open(connectionPath, "r")
    if not file then
        currentSessionId = "NO_SESSION"
        return nil  -- No connection file exists
    end
    
    for line in file:lines() do
        local prefix = line:match("^file_prefix=(.+)$")
        if prefix then
            file:close()
            currentSessionId = prefix
            return prefix
        end
    end
    file:close()
    currentSessionId = "NO_SESSION"
    return nil  -- No valid prefix found in connection file
end

-- Check if there are items waiting in the queue
local function hasItemsInQueue()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return false end  -- No valid session
    
    local queuePath = getArchipelagoPath(filePrefix .. "_items.txt")
    local file = io.open(queuePath, "r")
    if not file then return false end
    
    for line in file:lines() do
        if line and line:match("%S") then
            file:close()
            return true
        end
    end
    file:close()
    return false
end

local cachedFreezeSubsystem = nil

local function FindByName(class, name)
    local objs = FindAllOf(class)
    if not objs then return nil end
    for _, obj in ipairs(objs) do
        local ok, fullName = pcall(function()
            if not obj or not obj:IsValid() then return nil end
            return obj:GetFullName()
        end)
        if ok and fullName and fullName:match(name) then
            return obj
        end
    end
    return nil
end

local function getTutorialWidget()
    local cached = state.tutorialWidget
    if cached and cached.IsValid and cached:IsValid() then
        return cached
    end
    local found = FindByName("WBP_ModernTutorialDisplay_C", "WBP_PrimaryGameLayout_C")
    state.tutorialWidget = found
    return found
end

function state.isWorldUnstable()
    return state.travelling or os.clock() < state.unstableUntil
end

function state.clearCachedUObjects()
    apProbe.console = nil
    cachedFreezeSubsystem = nil
    state.tutorialWidget = nil
end

function state.beginWorldUnstable()
    state.unstableUntil = os.clock() + state.unstableSeconds
    state.clearCachedUObjects()
    apProbe.awaiting = false
    cellLookupProbe.awaiting = false
    cellLookupProbe.startedAt = nil
    cellLookupProbe.blockStartedAt = nil
    cellLookupProbe.circularBufferMode = false
    cellNameRequestPending = false
end

function state.markTravelling(reason)
    local widget = getTutorialWidget()
    CloseTutorialByTimeSqueeze(widget)
    HardHideTutorialWidget(widget)
    if lastAPTutorialMessage ~= "" then
        if #tutorialQueue == 0 or tutorialQueue[1] ~= lastAPTutorialMessage then
            table.insert(tutorialQueue, 1, lastAPTutorialMessage)
        end
    end
    lastAPTutorialMessage = ""
    lastAPCheckMessage = ""
    lastAPTutorialAt = 0
    nextTutorialAt = 0
    local already = state.travelling
    state.travelling = true
    if ActorDetection then
        pcall(function() ActorDetection.SetTravelling(true) end)
    end
    if not already then
        writeLog("Transition start: " .. reason)
    end
end

function state.markArrived(reason)
    writeLog("Transition end: " .. reason)
    state.travelling = false
    if ActorDetection then
        pcall(function() ActorDetection.SetTravelling(false) end)
    end
    state.beginWorldUnstable()
    if state.pinsNeedRestore then
        state.pinsRestoreArmed = true
    end
end

function state.tryRegisterHook(path, callback, label)
    local ok, err = pcall(function()
        RegisterHook(path, callback)
    end)
    if ok then
        writeLog("Hooked " .. label)
    else
        writeLog("Failed to hook " .. label .. ": " .. tostring(err), "WARN")
    end
end

local InterceptTutorial = false
local interceptApplied = false
local QueuedArchipelagoMessage = ""
local lastAPTutorialMessage = ""
local lastAPCheckMessage = ""
local lastAPTutorialAt = 0
local tutorialQueue = {}
local nextTutorialAt = 0
local replayTutorialDuration = nil

local AP_TUTORIAL_DEFAULT_TIME = 4.0
local AP_TUTORIAL_FAST_TIME = 1.0
local AP_TUTORIAL_FAST_BACKLOG = 25
local AP_TUTORIAL_SUMMARY_BACKLOG = 50
local lastTutorialShowDuration = AP_TUTORIAL_DEFAULT_TIME

-- Drop stored tutorial text after the HUD duration so a later zone does not
-- replay a check that already faded minutes ago.
function state.expireAPTutorialFallbackIfNeeded()
    if state.travelling or state.isWorldUnstable() then
        return
    end
    if lastAPTutorialAt <= 0 then
        return
    end
    if (os.clock() - lastAPTutorialAt) >= lastTutorialShowDuration then
        lastAPTutorialMessage = ""
        lastAPCheckMessage = ""
        lastAPTutorialAt = 0
    end
end

local setupNewDisplayHooked = false
local setMenuModeHooked = false
local settingsDetailsLogged = false

local function CloseTutorialByTimeSqueeze(widget)
    local target = widget
    if (not target) or (not target.IsValid) or (not target:IsValid()) then
        target = getTutorialWidget()
    end
    if not target or not target.IsValid or not target:IsValid() then return false end
    pcall(function()
        target.CurrentDisplayTime = 0.001
        if target.ManageCurrentDisplay then target:ManageCurrentDisplay() end
        if target.ManageDisplay then target:ManageDisplay() end
        if target.LaunchClosingAnimation then target:LaunchClosingAnimation() end
        if target.FinishAnimation then target:FinishAnimation() end
    end)
    return true
end

local function HardHideTutorialWidget(widget)
    local target = widget
    if (not target) or (not target.IsValid) or (not target:IsValid()) then
        target = getTutorialWidget()
    end
    if not target or not target.IsValid or not target:IsValid() then return false end
    pcall(function()
        if target.SetVisibility then target:SetVisibility(1) end -- Collapsed
        if target.SetRenderOpacity then target:SetRenderOpacity(0.0) end
        target.CurrentDisplayTime = 0.0
        if target.ManageCurrentDisplay then target:ManageCurrentDisplay() end
        if target.ManageDisplay then target:ManageDisplay() end
        if target.FinishAnimation then target:FinishAnimation() end
        if target.OnFadeEnded then target:OnFadeEnded() end
        if target.ClearDisplay then target:ClearDisplay() end
        if target.ClearTutorial then target:ClearTutorial() end
    end)
    return true
end

local function escapeForConsole(str)
    if not str then return "" end
    -- Escape double quotes for console Message command
    return tostring(str):gsub('"', '\\"')
end

local function IsPlayerInMenu()
    local menu = FindFirstOf("VLegacyPlayerMenu")
    
    if not menu then
        return false
    elseif not menu.GetViewModelRef then
        return false
    else
        local ok, vm = pcall(function() return menu:GetViewModelRef() end)
        if not ok or not vm then return false end
        local visible = false
        pcall(function()
            if vm.IsVisible then visible = vm:IsVisible() end
        end)
        return visible
    end
end

local function getFreezeSubsystem()
    if cachedFreezeSubsystem and cachedFreezeSubsystem:IsValid() then
        return cachedFreezeSubsystem
    end
    local ok, sub = pcall(function()
        return FindFirstOf("VFreezeInMenuSubsystem")
    end)
    if ok and sub and sub:IsValid() then
        cachedFreezeSubsystem = sub
        return cachedFreezeSubsystem
    end
    return nil
end

local function isGameFreezing()
    local sub = getFreezeSubsystem()
    if not sub then
        return false
    end
    local ok, freezing = pcall(function()
        return sub:IsFreezing()
    end)
    if ok and type(freezing) == "boolean" then
        return freezing
    end
    return false
end

function BroadcastArchipelagoMessage(message)
    if not message or message == "" then
        return false
    end
    local HudModel = getTutorialWidget()
    if not HudModel or not HudModel:IsValid() then
        return false
    end

    interceptApplied = false
    QueuedArchipelagoMessage = message
    InterceptTutorial = true
    if lastAPTutorialMessage ~= "" then
        CloseTutorialByTimeSqueeze(HudModel)
    end
    HudModel:SetupNewDisplay()
    return interceptApplied
end


local lastFreezeState = false

local function InterceptTutorialDisplay(Context)
    if InterceptTutorial then
        local tutorialMessage = Context:get()
        if tutorialMessage and QueuedArchipelagoMessage ~= "" then
            local KismetTextLibrary = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
            if KismetTextLibrary and KismetTextLibrary:IsValid() then
                local fText = KismetTextLibrary:Conv_StringToText(QueuedArchipelagoMessage)
                tutorialMessage.ControllerText = fText
                tutorialMessage.MouseKeyboardText = fText
                lastAPTutorialMessage = QueuedArchipelagoMessage or ""
                lastAPCheckMessage = lastAPTutorialMessage
                lastAPTutorialAt = os.clock()
                local duration = AP_TUTORIAL_DEFAULT_TIME
                if replayTutorialDuration and replayTutorialDuration > 0 then
                    duration = replayTutorialDuration
                end
                replayTutorialDuration = nil

                tutorialMessage.DefaultDisplayTime = duration
                tutorialMessage.CurrentDisplayTime = duration
                pcall(function()
                    if tutorialMessage.ManageInputMethodeChange then
                        tutorialMessage:ManageInputMethodeChange(1)
                    end
                end)

                pcall(function()
                    if tutorialMessage.SetVisibility then tutorialMessage:SetVisibility(0) end
                    if tutorialMessage.SetRenderOpacity then tutorialMessage:SetRenderOpacity(1.0) end
                    if tutorialMessage.ResetAnimation then tutorialMessage:ResetAnimation() end
                    if tutorialMessage.LaunchOpenningAnimation then tutorialMessage:LaunchOpenningAnimation() end
                end)

                interceptApplied = true
                local okF, fr = pcall(isGameFreezing)
                lastFreezeState = okF and fr or false
            end
        end
        InterceptTutorial = false
        QueuedArchipelagoMessage = ""
    end
end




function state.emitTutorialNow(message)
    lastAPCheckMessage = message or lastAPCheckMessage
    local inMenuNow = false
    local okMenu, resMenu = pcall(IsPlayerInMenu)
    if okMenu then inMenuNow = resMenu end
    local duration = AP_TUTORIAL_DEFAULT_TIME
    if #tutorialQueue >= AP_TUTORIAL_FAST_BACKLOG then
        duration = AP_TUTORIAL_FAST_TIME
    end
    if isGameFreezing() or inMenuNow then
        pcall(function()
            console.ExecuteConsole("Message \"" .. tostring(message) .. "\"")
        end)
        lastAPTutorialAt = os.clock()
        lastTutorialShowDuration = duration
        nextTutorialAt = os.clock() + duration + 0.6
        return true
    end
    if state.travelling or state.isWorldUnstable() then
        return false
    end

    replayTutorialDuration = duration
    local shown = false
    pcall(function()
        shown = BroadcastArchipelagoMessage(message) and true or false
    end)
    if not shown then
        replayTutorialDuration = nil
        nextTutorialAt = os.clock() + 0.25
        return false
    end
    lastAPTutorialMessage = message
    lastAPTutorialAt = os.clock()
    lastTutorialShowDuration = duration
    nextTutorialAt = os.clock() + duration + 0.6
    return true
end

local function ShowArchipelagoNotification(message)
    table.insert(tutorialQueue, message)
end

local function collapseTutorialQueueIfHuge()
    local n = #tutorialQueue
    if n < AP_TUTORIAL_SUMMARY_BACKLOG then
        return
    end
    tutorialQueue = {}
    queueMessagebox(n .. " checks received, check client for full list")
end

function state.processTutorialQueue()
    if #tutorialQueue == 0 then
        return
    end
    if os.clock() < nextTutorialAt then
        return
    end
    if state.travelling or state.isWorldUnstable() then
        return
    end
    collapseTutorialQueueIfHuge()
    if #tutorialQueue == 0 then
        return
    end
    local msg = tutorialQueue[1]
    if state.emitTutorialNow(msg) then
        table.remove(tutorialQueue, 1)
    end
end

-- Process item events file and display messages to player
local function processItemEvents()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return end

    local livePath = getArchipelagoPath(filePrefix .. "_item_events.txt")
    local takePath = getArchipelagoPath(filePrefix .. "_item_events_reading.txt")
    local live = io.open(livePath, "r")
    if live then
        live:close()
        pcall(function()
            os.rename(livePath, takePath)
        end)
    end

    local function ingest(path)
        local file = io.open(path, "r")
        if not file then return end
        for line in file:lines() do
            if line and line:match("%S") then
                local eventType, itemName, target = line:match("^([^|]+)|([^|]+)|(.+)$")
                if eventType and itemName and target then
                    local message = ""
                    if eventType == "found" then
                        message = "You found your " .. itemName .. " (" .. target .. ")"
                    elseif eventType == "sent" then
                        local player, location = target:match("^(.-)|(.*)$")
                        if player and location and location ~= "" then
                            message = "You sent '" .. itemName .. "' to '" .. player .. "' (" .. location .. ")"
                        else
                            message = "You sent '" .. itemName .. "' to '" .. target .. "'"
                        end
                    elseif eventType == "received" then
                        local player, location = target:match("^(.-)|(.*)$")
                        if player and location and location ~= "" then
                            message = player .. " found your " .. itemName .. " (" .. location .. ")"
                        else
                            message = target .. " found your " .. itemName
                        end
                    end
                    if message ~= "" then
                        ShowArchipelagoNotification(message)
                    end
                end
            end
        end
        file:close()
        os.remove(path)
    end

    ingest(takePath)
    ingest(livePath)
    collapseTutorialQueueIfHuge()
end

-- Detect messages generated by processItemEvents that may appear via console Message
-- We must ignore these in the completion hook to avoid false positives (e.g., skill increases)
local function isAPItemEventNotification(text)
    if not text or text == "" then return false end
    -- You found your <item> (<location>)
    if text:match("^You found your .- %(.+%)$") then return true end
    -- You sent '<item>' to '<player>' (no location)
    if text:match("^You sent%s*'.-'%s*to%s*'.-'$") then return true end
    -- You sent '<item>' to '<player>' (<location>)
    if text:match("^You sent%s*'.-'%s*to%s*'.-'%s*%(.+%)$") then return true end
    -- <player> found your <item> (no location)
    if text:match("^.+%s+found your%s+.-$") then return true end
    -- <player> found your <item> (<location>)
    if text:match("^.+%s+found your%s+.-%s*%(.+%)$") then return true end
    return false
end

-- Initialize progressive shop stock items
local function initializeShopsanity()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local initialized = false
    local hasProgressiveShopStockSettings = false
    
    -- Read all settings and check if already initialized
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "progressive_shop_stock_initialized" and value == "True" then
                initialized = true
            elseif key == "progressive_shop_stock" and value == "True" then
                hasProgressiveShopStockSettings = true
            end
        end
    end
    file:close()
    
    if initialized or not hasProgressiveShopStockSettings then 
        return 
    end
    
    -- Add the initial shop check items to all merchant chests
    local initialShopItems = {
        "APShopCheckValue1",
        "APShopCheckValue10",
        "APShopCheckValue100"
    }
    
    for _, shopItem in ipairs(initialShopItems) do
        writeLog("Adding " .. shopItem .. " to all merchant chests...")
        for _, chestRef in ipairs(config.merchantChests) do
            local command = chestRef .. ".AddItem " .. shopItem .. " 1"
            pcall(function() console.ExecuteConsole(command) end)
        end
        writeLog("Shop check item " .. shopItem .. " added to all merchant chests")
    end
    
    writeLog("Progressive shop stock initialization complete")
    
    -- Mark as initialized by appending to settings file
    file = io.open(settingsPath, "a")
    if file then
        file:write("progressive_shop_stock_initialized=True\n")
        file:close()
        writeLog("Marked progressive shop stock as initialized in settings file")
    else
        writeLog("Failed to write progressive_shop_stock_initialized to settings file", "ERROR")
    end
end

-- Load mod settings from the settings file
function loadSettings()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        writeLog("No valid Archipelago session found - no connection file or prefix")
        return false  -- No valid session
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    writeLog("Loading settings from: " .. settingsPath)
    local file = io.open(settingsPath, "r")
    
    if not file then
        writeLog("Settings file not found")
        return false  -- No valid settings file
    end
    
    local hasProgressiveShopStockSettings = false
    local hasArenaSettings = false
    local hasShrineSettings = false
    local hasSidequestSettings = false
    local hasGateVisionSettings = false
    local hasFastTravelSettings = false
    local hasClassSystemSettings = false
    local hasDungeonSettings = false
    local hasBountySettings = false
    local selectedDungeonNames = {}

    -- File flags are the source of truth. RAM from a prior seed/session must not skip inits.
    init.shopStock = false
    init.arena = false
    init.shrines = false
    init.sidequests = false
    init.gates = false
    init.doomstones = false
    init.gateVision = false
    init.fastTravel = false
    init.classSystem = false
    init.dungeonCounters = false
    init.bounties = false
    init.weaponLicenses = false
    init.modFully = false
    
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            local function foundLog(msg)
                if not settingsDetailsLogged then
                    writeLog(msg)
                end
            end
            if key == "free_offerings" then
                archipelagoSettings.free_offerings = (value == "True")
            elseif key == "goal" then
                currentGoal = value
                foundLog("Found goal: " .. value)
                if value == "nirnsanity" then nirnrootInSeed = true end
            elseif key == "goal_required" then
                goalRequired = tonumber(value) or 0
                foundLog("Found goal_required: " .. tostring(goalRequired))
            elseif key == "mod_fully_initialized" and value == "True" then
                init.modFully = true
            elseif key == "progressive_shop_stock_initialized" and value == "True" then
                init.shopStock = true
                foundLog("Found progressive shop stock already initialized from previous session")
            elseif key == "progressive_shop_stock" and value == "True" then
                hasProgressiveShopStockSettings = true
                foundLog("Found progressive_shop_stock=True in settings file")
            elseif key == "arena_initialized" and value == "True" then
                init.arena = true
                foundLog("Found arena already initialized from previous session")
            elseif key == "enable_arena" and value == "True" then
                hasArenaSettings = true
                foundLog("Found enable_arena=True in settings file")
            elseif key == "shrines_initialized" and value == "True" then
                init.shrines = true
                foundLog("Found shrines already initialized from previous session")

            elseif key == "active_shrines" and value ~= "" then
                hasShrineSettings = true
                foundLog("Found active_shrines=" .. value .. " in settings file")
            elseif key == "sidequests_initialized" and value == "True" then
                init.sidequests = true
                foundLog("Found sidequests already initialized from previous session")
            elseif key == "selected_sidequests" and value ~= "" then
                hasSidequestSettings = true
                foundLog("Found selected_sidequests in settings file")
            elseif key == "gates_initialized" and value == "True" then
                init.gates = true
                foundLog("Found gates already initialized from previous session")
            elseif key == "doomstones_initialized" and value == "True" then
                init.doomstones = true
                foundLog("Found doomstones already initialized from previous session")
            elseif key == "gate_vision" and value == "on" then
                hasGateVisionSettings = true
                foundLog("Found gate_vision=on in settings file")
            elseif key == "gate_vision_initialized" and value == "True" then
                init.gateVision = true
                foundLog("Found gate vision already initialized from previous session")
            elseif key == "fast_travel_initialized" and value == "True" then
                init.fastTravel = true
                foundLog("Found fast travel already initialized from previous session")
            elseif key == "fast_travel_item" and value:lower() == "true" then
                hasFastTravelSettings = true
                foundLog("Found fast_travel_item=True in settings file")
            elseif key == "class_system_enabled" and value == "True" then
                hasClassSystemSettings = true
                foundLog("Found class_system_enabled=True in settings file")
            elseif key == "class_system_initialized" and value == "True" then
                init.classSystem = true
                foundLog("Found class system already initialized from previous session")
            elseif key == "selected_regions" and value ~= "" then
                hasDungeonSettings = true
                foundLog("Found selected_regions in settings")
            elseif key == "dungeon_marker_mode" then
                local v = value:lower()
                if v == "reveal_only" then
                    archipelagoSettings.dungeon_marker_mode = "reveal_only"
                else
                    archipelagoSettings.dungeon_marker_mode = "reveal_and_fast_travel"
                end
                foundLog("Found dungeon_marker_mode=" .. archipelagoSettings.dungeon_marker_mode)
            elseif key == "dungeon_warp" then
                local v = value:lower()
                if v == "on" or v == "item" or v == "early_item" or v == "off" then
                    archipelagoSettings.dungeon_warp = v
                    foundLog("Found dungeon_warp=" .. v)
                    -- If dungeon_warp is "on", enable it immediately
                    if v == "on" then
                        local okSet, errSet = pcall(function()
                            console.ExecuteConsole("set APWarpEnabled to 1")
                        end)
                        if okSet then
                            writeLog("Set APWarpEnabled to 1 (dungeon_warp=on)")
                        else
                            writeLog("Failed to set APWarpEnabled: " .. tostring(errSet), "ERROR")
                        end
                    end
                end
            elseif key == "selected_class" then
                selectedClass = value
                foundLog("Found selected_class: " .. value)
            elseif key == "track_kills" and value == "True" then
                killTrackingEnabled = true
                foundLog("Found track_kills=True in settings file")
            elseif key == "dungeon_kills" then
                hasDungeonKillChecks = (tonumber(value) or 0) > 0
            elseif key == "overworld_kills" then
                hasOverworldKillChecks = (tonumber(value) or 0) > 0
            elseif key == "dungeon_kills_per_check" then
                dungeonKillsPerCheck = math.max(1, math.min(10, tonumber(value) or 1))
                foundLog("Found dungeon_kills_per_check=" .. tostring(dungeonKillsPerCheck))
            elseif key == "overworld_kills_per_check" then
                overworldKillsPerCheck = math.max(1, math.min(10, tonumber(value) or 1))
                foundLog("Found overworld_kills_per_check=" .. tostring(overworldKillsPerCheck))
            elseif key == "oblivion_kills" then
                state.oblivionKills = tonumber(value) or 0
                state.hasOblivionKillChecks = state.oblivionKills > 0
            elseif key == "oblivion_kills_per_gate" then
                state.oblivionKillsPerGate = tonumber(value) or 0
                foundLog("Found oblivion_kills_per_gate=" .. tostring(state.oblivionKillsPerGate))
            elseif key == "gate_count" then
                state.gateCount = tonumber(value) or 0
            elseif key == "oblivion_kills_per_check" then
                state.oblivionKillsPerCheck = math.max(1, math.min(10, tonumber(value) or 2))
                foundLog("Found oblivion_kills_per_check=" .. tostring(state.oblivionKillsPerCheck))
            elseif key == "weapon_lock" then
                state.weaponLock = (value == "True" or value == "true")
                foundLog("Found weapon_lock=" .. tostring(state.weaponLock))
            elseif key == "weapon_licenses_initialized" and value == "True" then
                init.weaponLicenses = true
            elseif key == "skill_xp_multiplier" then
                archipelagoSettings.skill_xp_multiplier = math.max(1, math.min(8, tonumber(value) or 1))
                foundLog("Found skill_xp_multiplier=" .. tostring(archipelagoSettings.skill_xp_multiplier))
            elseif key == "auto_tracking" then
                archipelagoSettings.auto_tracking = (value == "True")
                foundLog("Found auto_tracking=" .. tostring(archipelagoSettings.auto_tracking))
                pcall(function()
                    local val = archipelagoSettings.auto_tracking and 1 or 0
                    console.ExecuteConsole("set APAutoTrackEnabled to " .. val)
                end)
            elseif key == "silent_auto_tracking" then
                archipelagoSettings.silent_auto_tracking = (value == "True")
                foundLog("Found silent_auto_tracking=" .. tostring(archipelagoSettings.silent_auto_tracking))
            elseif key == "ap_tips" then
                archipelagoSettings.ap_tips = (value == "True")
                foundLog("Found ap_tips=" .. tostring(archipelagoSettings.ap_tips))
            elseif key == "nirnroot_count" then
                if (tonumber(value) or 0) > 0 then nirnrootInSeed = true end
            elseif key == "dungeon_selected_count" then
                chestInSeed = (tonumber(value) or 0) > 0
            elseif key == "bounty_initialized" and value == "True" then
                init.bounties = true
            elseif key == "bounty_count" then
                hasBountySettings = (tonumber(value) or 0) > 0
            elseif key == "fence_limit" then
                state.fenceLimit = tonumber(value) or 0
                if state.fenceLimit > 0 then
                    pcall(function()
                        console.ExecuteConsole("set APFenceLimit to " .. tostring(state.fenceLimit))
                    end)
                end
            elseif key:match("^region_.+_dungeons$") then
                for name in value:gmatch("([^,]+)") do
                    local trimmed = name:match("^%s*(.-)%s*$")
                    if trimmed ~= "" then
                        table.insert(selectedDungeonNames, trimmed)
                    end
                end
            end
        end
    end
    file:close()
    
    -- Set flags if we have settings but haven't initialized yet (using session flags)
    init.needsShopStock = hasProgressiveShopStockSettings and not init.shopStock
    init.needsArena = hasArenaSettings and not init.arena
    init.needsShrines = hasShrineSettings and not init.shrines
    init.needsSidequests = hasSidequestSettings and not init.sidequests
    init.needsGates = not init.gates
    init.needsDoomstones = not init.doomstones
    init.needsGateVision = hasGateVisionSettings and not init.gateVision
    init.needsFastTravel = hasFastTravelSettings and not init.fastTravel
    init.needsClassSystem = hasClassSystemSettings and not init.classSystem
    init.needsDungeonCounters = hasDungeonSettings and not init.dungeonCounters
    init.needsBounties = hasBountySettings and not init.bounties
    init.needsWeaponLicenses = state.weaponLock and not init.weaponLicenses
    
    writeLog("Settings loaded - init.needsShopStock: " .. tostring(init.needsShopStock) .. ", init.needsArena: " .. tostring(init.needsArena) .. ", init.needsShrines: " .. tostring(init.needsShrines) .. ", init.needsSidequests: " .. tostring(init.needsSidequests) .. ", init.needsGates: " .. tostring(init.needsGates) .. ", init.needsDoomstones: " .. tostring(init.needsDoomstones) .. ", init.needsGateVision: " .. tostring(init.needsGateVision) .. ", init.needsFastTravel: " .. tostring(init.needsFastTravel) .. ", init.needsClassSystem: " .. tostring(init.needsClassSystem))
    settingsDetailsLogged = true
    require("MapPins").setSelectedDungeons(selectedDungeonNames)
    return true  -- Settings loaded successfully
end



local function initializeArena()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local initialized = false
    local fastArenaEnabled = false
    
    -- Check if already initialized and read fast_arena setting
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "arena_initialized" and value == "True" then
                initialized = true
            elseif key == "fast_arena" and value == "true" then
                fastArenaEnabled = true
            end
        end
    end
    file:close()
    
    if initialized then 
        return 
    end
    
    -- Set APArenaRank to 0 to block arena progression until unlocks are received
    console.ExecuteConsole("set APArenaRank to 0")
    writeLog("Arena initialization complete - APArenaRank set to 0")
    
    -- Set APFastArena to 1 if fast arena mode is enabled
    if fastArenaEnabled then
        console.ExecuteConsole("set APFastArena to 1")
        writeLog("Set APFastArena to 1 - fast arena mode enabled")
    end
    
    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("arena_initialized=True\n")
        file:close()
        writeLog("Marked arena as initialized in settings file")
    else
        writeLog("Failed to write arena_initialized to settings file", "ERROR")
    end
end

local function initializeShrines()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local initialized = false
    local activeShrines = ""
    
    -- Read settings and check if already initialized
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "shrines_initialized" and value == "True" then
                initialized = true
                break
            elseif key == "active_shrines" then
                activeShrines = value
            end
        end
    end
    file:close()
    
    if initialized then 
        return 
    end
    
    -- Parse active shrines and set lock variables to 1
    if activeShrines ~= "" then
        -- Split comma-separated shrine names
        for shrineName in activeShrines:gmatch("([^,]+)") do
            -- Trim whitespace
            shrineName = shrineName:match("^%s*(.-)%s*$")
            
            -- Get corresponding lock variable
            local lockVariable = config.shrineLockMapping[shrineName]
            if lockVariable then
                console.ExecuteConsole("set " .. lockVariable .. " to 1")
                writeLog("Locked shrine: " .. shrineName .. " (" .. lockVariable .. " = 1)")
            else
                writeLog("Unknown shrine name in settings: " .. shrineName, "WARNING")
            end
        end
    end
    
    writeLog("Shrine initialization complete")
    
    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("shrines_initialized=True\n")
        file:close()
        writeLog("Marked shrines as initialized in settings file")
    else
        writeLog("Failed to write shrines_initialized to settings file", "ERROR")
    end
end

local function initializeSidequests()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local initialized = false
    local selectedSidequestsRaw = ""
    
    -- Read settings and check if already initialized
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "sidequests_initialized" and value == "True" then
                initialized = true
                break
            elseif key == "selected_sidequests" then
                selectedSidequestsRaw = value
            end
        end
    end
    file:close()
    
    if initialized then 
        return 
    end
    
    -- Parse selected sidequests and enable their flags
    if selectedSidequestsRaw ~= "" then
        -- Split by commas and trim whitespace
        for sidequestName in selectedSidequestsRaw:gmatch("([^,]+)") do
            -- Trim whitespace
            sidequestName = sidequestName:match("^%s*(.-)%s*$")
            
            -- Look up the variable name in config
            local sidequestVariable = config.sidequestMappings[sidequestName]
            if sidequestVariable then
                console.ExecuteConsole("set " .. sidequestVariable .. " to 1")
                writeLog("Enabled sidequest: " .. sidequestName .. " (" .. sidequestVariable .. " = 1)")
            else
                writeLog("Unknown sidequest name in settings: " .. sidequestName, "WARNING")
            end
        end
    else
        writeLog("No sidequests found in settings (selected_sidequests is empty or missing)")
    end
    
    writeLog("Sidequest initialization complete")
    
    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("sidequests_initialized=True\n")
        file:close()
        writeLog("Marked sidequests as initialized in settings file")
    else
        writeLog("Failed to write sidequests_initialized to settings file", "ERROR")
    end
end

local function initializeGates()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    -- Check if already initialized
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value and key == "gates_initialized" and value == "True" then
            file:close()
            return  -- Already initialized
        end
    end
    file:close()
    
    -- Read gate_count / oblivion_kills from settings file
    local gateCount = 0
    local oblivionKills = 0
    file = io.open(settingsPath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(.-)=(.*)$")
            if key and value then
                if key == "gate_count" then
                    gateCount = tonumber(value) or 0
                elseif key == "oblivion_kills" then
                    oblivionKills = tonumber(value) or 0
                end
            end
        end
        file:close()
    end
    
    -- Enable random gates for Closed checks, or for LTD Oblivion kill farming
    if gateCount > 0 or oblivionKills > 0 then
        -- Set APGatesEnabled to 1 to enable Oblivion Gates
        console.ExecuteConsole("set APGatesEnabled to 1")
        writeLog("Gates initialization complete - APGatesEnabled set to 1 (gate_count: " .. tostring(gateCount) .. ", oblivion_kills: " .. tostring(oblivionKills) .. ")")
    else
        writeLog("Gates initialization skipped - gate_count is 0 and no Oblivion kill checks")
    end
    
    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("gates_initialized=True\n")
        file:close()
        writeLog("Marked gates as initialized in settings file")
    else
        writeLog("Failed to write gates_initialized to settings file", "ERROR")
    end
end

local function initializeDoomstones()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end

    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then
        return
    end

    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value and key == "doomstones_initialized" and value == "True" then
            file:close()
            return
        end
    end
    file:close()

    local doomstoneChecksEnabled = true
    file = io.open(settingsPath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(.-)=(.*)$")
            if key and value and key == "doomstone_checks" then
                doomstoneChecksEnabled = (value == "True")
                break
            end
        end
        file:close()
    end

    local enabledVal = doomstoneChecksEnabled and 1 or 0
    console.ExecuteConsole("set APDoomstoneChecksEnabled to " .. tostring(enabledVal))
    writeLog("Doomstones initialization complete - APDoomstoneChecksEnabled set to " .. tostring(enabledVal) .. " (doomstone_checks=" .. tostring(doomstoneChecksEnabled) .. ")")

    file = io.open(settingsPath, "a")
    if file then
        file:write("doomstones_initialized=True\n")
        file:close()
        writeLog("Marked doomstones as initialized in settings file")
    else
        writeLog("Failed to write doomstones_initialized to settings file", "ERROR")
    end
end

local function initializeGateVision()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local hasGateVisionSettings = false
    
    -- Check if gate_vision setting is on
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value and key == "gate_vision" and value == "on" then
            hasGateVisionSettings = true
            break
        end
    end
    file:close()
    
    if not hasGateVisionSettings then 
        return 
    end
    
    -- Check if already initialized
    file = io.open(settingsPath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(.-)=(.*)$")
            if key and value and key == "gate_vision_initialized" and value == "True" then
                file:close()
                return  -- Already initialized
            end
        end
        file:close()
    end
    
    -- Set APGateMarkersVisible to 1 to enable gate vision
    console.ExecuteConsole("set APGateMarkersVisible to 1")
    writeLog("Gate vision initialization complete - APGateMarkersVisible set to 1")
    -- Mark as initialized by appending to settings file
    file = io.open(settingsPath, "a")
    if file then
        file:write("gate_vision_initialized=True\n")
        file:close()
        writeLog("Marked gate vision as initialized in settings file")
    else
        writeLog("Failed to write gate_vision_initialized to settings file", "ERROR")
    end
end

local function initializeClassSystem()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local initialized = false
    local classSystemEnabled = false
    
    -- Read settings and check flags
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "class_system_initialized" and value == "True" then
                initialized = true
                break
            elseif key == "class_system_enabled" and value == "True" then
                classSystemEnabled = true
            end
        end
    end
    file:close()
    
    if initialized then 
        return 
    end
    
    if not classSystemEnabled then
        writeLog("Class system not enabled")
        return
    end

    if selectedClass == "" then
        writeLog("No selected_class found for class system")
        return
    end
    
    -- Get the integer value for the selected class
    local classInteger = nil
    for className, integer in pairs(classToIntegerMapping) do
        if className:lower() == selectedClass:lower() then
            classInteger = integer
            break
        end
    end
    
    if not classInteger then
        writeLog("Unknown class: " .. selectedClass, "ERROR")
        return
    end
    
    -- Set APClassEnabled to 1
    console.ExecuteConsole("set APClassEnabled to 1")
    writeLog("Class system enabled - APClassEnabled set to 1")
    
    -- Set APClassType to the selected class
    console.ExecuteConsole("set APClassType to " .. tostring(classInteger))
    writeLog("Class system initialized - APClassType set to " .. tostring(classInteger) .. " (" .. selectedClass .. ")")
    
    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("class_system_initialized=True\n")
        file:close()
        writeLog("Marked class system as initialized in settings file")
    else
        writeLog("Failed to write class_system_initialized to settings file", "ERROR")
    end
end

local function initializeFastTravel()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then 
        return 
    end
    
    local initialized = false
    local fastTravelItemEnabled = false
    
    -- Read settings and check if already initialized
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "fast_travel_initialized" and value == "True" then
                initialized = true
                break
            elseif key == "fast_travel_item" and value:lower() == "true" then
                fastTravelItemEnabled = true
            end
        end
    end
    file:close()
    
    if initialized then 
        return 
    end
    
    -- Only disable fast travel if the setting is enabled
    if fastTravelItemEnabled then
        console.ExecuteConsole("EnableFastTravel 0")
        writeLog("Fast travel disabled - EnableFastTravel 0")
    else
        writeLog("Fast travel item not enabled - leaving fast travel enabled")
    end
    
    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("fast_travel_initialized=True\n")
        file:close()
        writeLog("Marked fast travel as initialized in settings file")
    else
        writeLog("Failed to write fast_travel_initialized to settings file", "ERROR")
    end
end

-- Add shrine offerings to queue if enabled
local function addShrineOfferings(itemName, queuePath)
    local offerings = config.shrineOfferings[itemName]
    if not offerings or not archipelagoSettings.free_offerings then
        return
    end
    
    local file = io.open(queuePath, "a")
    if file then
        for _, offering in ipairs(offerings) do
            file:write(offering[1] .. "\n")
        end
        file:close()
    end
end

-- Read the selected dungeons for a given region from the current settings file
local function getSelectedRegionDungeons(regionName)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return {}
    end
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then
        writeLog("Settings file not found while processing region access for '" .. tostring(regionName) .. "'", "WARNING")
        return {}
    end
    local keyName = "region_" .. regionName .. "_dungeons"
    local value = nil
    for line in file:lines() do
        local key, val = line:match("^(.-)=(.*)$")
        if key and val and key == keyName then
            value = val
            break
        end
    end
    file:close()
    local dungeons = {}
    if value and value ~= "" then
        for name in value:gmatch("([^,]+)") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                table.insert(dungeons, trimmed)
            end
        end
    end
    return dungeons
end

-- Reveal map markers for the selected dungeons in a region
local function revealDungeonMarkersForRegion(regionName)
    local dungeons = getSelectedRegionDungeons(regionName)
    if #dungeons == 0 then
        writeLog("No dungeons found in settings for region '" .. tostring(regionName) .. "'", "WARNING")
        return 0
    end
    local revealed = 0
    for _, dungeonName in ipairs(dungeons) do
        local markerId = config.dungeonMapMarkers[dungeonName]
        if markerId then
            local allowFastTravel = archipelagoSettings.dungeon_marker_mode ~= "reveal_only"
            local command
            if allowFastTravel then
                command = "ShowMap " .. markerId .. ", 1"
            else
                command = "ShowMap " .. markerId
            end
            local ok, err = pcall(function()
                console.ExecuteConsole(command)
            end)
            if ok then
                revealed = revealed + 1
                writeLog("Revealed map marker for dungeon '" .. dungeonName .. "' (" .. markerId .. ") mode=" .. archipelagoSettings.dungeon_marker_mode)
            else
                writeLog("Failed to reveal marker for dungeon '" .. dungeonName .. "': " .. tostring(err), "ERROR")
            end
        else
            writeLog("No map marker mapping found for dungeon '" .. dungeonName .. "'", "WARNING")
        end
    end
    require("MapPins").placeRegionDungeonPins(regionName)
    return revealed
end

-- Read selected_regions from settings file
local function getSelectedRegions()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return {} end
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then return {} end
    local regionsValue = nil
    for line in file:lines() do
        local key, val = line:match("^(.-)=(.*)$")
        if key == "selected_regions" then regionsValue = val; break end
    end
    file:close()
    local regions = {}
    if regionsValue and regionsValue ~= "" then
        for name in regionsValue:gmatch("([^,]+)") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(regions, trimmed) end
        end
    end
    return regions
end

local function areRegionsDisabled()
    -- Region gating considered disabled if settings define no selected regions
    local regions = getSelectedRegions()
    if #regions == 0 then return true end
    return false
end

-- Prevent dungeon cleared completions for locked dungeons
local function isRegionUnlockedViaReceipts(regionName)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return false end
    local statusPath = getArchipelagoPath(filePrefix .. "_bridge_status.txt")
    local file = io.open(statusPath, "r")
    if not file then return false end
    local content = file:read("*a") or ""
    file:close()
    if content == "" then return false end
    local token = tostring(regionName) .. " Access"

    if content:find(token .. ",", 1, true) then
        return true
    end
    return false
end

-- Read region_<Region>_dungeon_count from settings file
local function getRegionDungeonCountFromSettings(regionName)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return 0 end
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then return 0 end
    local keyName = "region_" .. regionName .. "_dungeon_count"
    local count = 0
    for line in file:lines() do
        local key, val = line:match("^(.-)=(.*)$")
        if key and key == keyName then
            local n = tonumber(val)
            if n then count = n end
            break
        end
    end
    file:close()
    return count
end

-- Find which selected region a dungeon belongs to by reading settings
local function findRegionForDungeon(dungeonName)
    local regions = getSelectedRegions()
    local target = (dungeonName or ""):match("^%s*(.-)%s*$")
    for _, regionName in ipairs(regions) do
        local list = getSelectedRegionDungeons(regionName)
        for _, name in ipairs(list) do
            if name == target then
                return regionName
            end
        end
    end
    return nil
end

-- Initialize AP<Region>DungeonCount for all selected regions (one-time per seed)
local function initializeDungeonCounters()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return end
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then return end

    local already = false
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value and key == "dungeon_counters_initialized" and value == "True" then
            already = true
            break
        end
    end
    file:close()
    if already then return end

    local regions = getSelectedRegions()
    for _, regionName in ipairs(regions) do
        local regionTag = regionName:gsub("%W", "")

        local count = getRegionDungeonCountFromSettings(regionName) or 0
        local regionVar = "AP" .. regionTag .. "DungeonCount"
        local okSet, errSet = pcall(function()
            console.ExecuteConsole("set " .. regionVar .. " to " .. tostring(count))
        end)
        if okSet then
            writeLog("Initialized " .. regionVar .. " to " .. tostring(count))
        else
            writeLog("Failed to set " .. regionVar .. ": " .. tostring(errSet), "ERROR")
        end

        local includedVar = "AP" .. regionTag .. "Included"
        local okInc, errInc = pcall(function()
            console.ExecuteConsole("set " .. includedVar .. " to 1")
        end)
        if okInc then
            writeLog("Initialized " .. includedVar .. " to 1")
        else
            writeLog("Failed to set " .. includedVar .. ": " .. tostring(errInc), "ERROR")
        end
    end

    -- Dungeon Delver global goal is initialized in the goal-globals section only.

    -- Mark as initialized
    file = io.open(settingsPath, "a")
    if file then
        file:write("dungeon_counters_initialized=True\n")
        file:close()
        writeLog("Marked dungeon counters as initialized in settings file")
    else
        writeLog("Failed to write dungeon_counters_initialized to settings file", "ERROR")
    end
end

-- Write processed items to bridge status file as a receipt
-- Build a cached set of offering item names to filter from receipts
local offeringItemNameSet = nil
local function ensureOfferingItemNameSet()
    if offeringItemNameSet then return offeringItemNameSet end
    offeringItemNameSet = {}
    if config and config.shrineOfferings then
        for _, offerings in pairs(config.shrineOfferings) do
            if type(offerings) == "table" then
                for _, entry in ipairs(offerings) do
                    local name = entry[1]
                    if type(name) == "string" then
                        offeringItemNameSet[name] = true
                    end
                end
            end
        end
    end
    return offeringItemNameSet
end

local function updateBridgeStatus(processedItems)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local statusPath = getArchipelagoPath(filePrefix .. "_bridge_status.txt")
    local offeringsSet = ensureOfferingItemNameSet()

    -- Filter out offering-only names before writing receipts
    local receiptItems = {}
    for _, name in ipairs(processedItems) do
        if not offeringsSet[name] then
            table.insert(receiptItems, name)
        end
    end

    if #receiptItems > 0 then
        local itemsString = table.concat(receiptItems, ",")
        local file = io.open(statusPath, "a")
        if file then
            file:write(itemsString .. ",")
            file:close()
        end
        -- Increment APAppliedCount once per batch by number of receipt items
        local increment = tostring(#receiptItems)
        pcall(function()
            console.ExecuteConsole("set APAppliedCount to APAppliedCount + " .. increment)
        end)
    end
end

-- Process the item queue file and give items to the player
-- This is the main function that handles items received from the multiworld
local function processItemQueue()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local queuePath = getArchipelagoPath(filePrefix .. "_items.txt")
    local file = io.open(queuePath, "r")
    
    if not file then
        writeLog("No item queue file found at: " .. queuePath, "WARNING")
        return
    end
    
    local itemsToProcess = {}
    
    -- Read all items from the queue and add shrine offerings if applicable
    for line in file:lines() do
        if line and line ~= "" then
            local itemName = line:match("^(.-)%s*$")
            writeLog("Found item in queue: '" .. itemName .. "'")
            table.insert(itemsToProcess, itemName)
            addShrineOfferings(itemName, queuePath)
        end
    end
    file:close()
    
    if #itemsToProcess > 0 then
        writeLog("Found " .. #itemsToProcess .. " items in queue to process")
    end
    
    -- Re-read the file if shrine offerings were added
    if #itemsToProcess > 0 then
        itemsToProcess = {}
        file = io.open(queuePath, "r")
        if file then
            for line in file:lines() do
                if line and line ~= "" then
                    table.insert(itemsToProcess, line:match("^(.-)%s*$"))
                end
            end
            file:close()
        end
    end
    
    local processedItems = {}
    bulkItemGrantInProgress = #itemsToProcess >= BULK_ITEM_THRESHOLD
    if bulkItemGrantInProgress then
        writeLog("Bulk item grant starting (" .. #itemsToProcess .. " items). Inventory notifications will be shortened.")
        queueMessagebox("A large number of items are being added. Outgoing checks may be delayed until this finishes.")
        processMessageboxQueue()
    end
    
    -- Give each item to the player using console commands
    for _, itemName in ipairs(itemsToProcess) do
        
        -- Handle Region Access items (e.g., "West Weald Access"): reveal only selected dungeons' markers
        local regionAccess = itemName:match("^(.*) Access$")
        local licenseCat = itemName:match("^(%a+) License$")
        if licenseCat and (licenseCat == "Blade" or licenseCat == "Blunt" or licenseCat == "Bow"
                or licenseCat == "Staff" or licenseCat == "Spell" or licenseCat == "Unarmed") then
            state.loadKillProgress()
            state.weaponLicenses = state.weaponLicenses or {}
            state.weaponLicenses[licenseCat:lower()] = true
            state.saveKillProgress()
            local blockedGlobal = "APWeaponLicense" .. licenseCat .. "Blocked"
            pcall(function()
                console.ExecuteConsole("set " .. blockedGlobal .. " to 2")
            end)
            writeLog("Weapon license granted: " .. licenseCat:lower() .. " (" .. blockedGlobal .. " = 2)")
            table.insert(processedItems, itemName)
        elseif itemName == "Black Market Access" then
            writeLog("Processing Black Market Access - setting APBlackMarketAccess to 1")
            local ok, err = pcall(function()
                console.ExecuteConsole("set APBlackMarketAccess to 1")
                if state.fenceLimit > 0 then
                    console.ExecuteConsole("set APFenceLimit to " .. tostring(state.fenceLimit))
                end
            end)
            if ok then
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to set Black Market Access: " .. tostring(err), "ERROR")
            end
        elseif itemName == "Progressive Bounty Contract" then
            writeLog("Processing Progressive Bounty Contract")
            require("BountyTracking").grantContract()
            table.insert(processedItems, itemName)
        elseif regionAccess then
            if regionAccess == "Paradise" then
                writeLog("Processing Paradise Access")
                local okAccess, errAccess = pcall(function()
                    console.ExecuteConsole("set APParadiseAccess to 1")
                end)
                if not okAccess then
                    writeLog("Failed to set APParadiseAccess: " .. tostring(errAccess), "ERROR")
                end
                table.insert(processedItems, itemName)
            else
                writeLog("Processing Region Access: " .. regionAccess)
                -- Reveal selected dungeon markers for this region
                local count = revealDungeonMarkersForRegion(regionAccess)
                if count == 0 then
                    writeLog("Region Access had no markers to reveal for '" .. regionAccess .. "'", "WARNING")
                end

                -- Set Region Unlocked global
                -- Example: "Blackwood" -> set APBlackwoodUnlocked to 1
                local regionVar = "AP" .. regionAccess:gsub("%W", "") .. "Unlocked"
                local ok, err = pcall(function()
                    console.ExecuteConsole("set " .. regionVar .. " to 1")
                end)
                if ok then
                    writeLog("Set " .. regionVar .. " to 1")
                else
                    writeLog("Failed to set " .. regionVar .. ": " .. tostring(err), "ERROR")
                end

                table.insert(processedItems, itemName)
            end
        
        -- Handle shop check items - add to merchant chests
        elseif itemName:match("^APShopCheckValue%d+$") then
            writeLog("Adding " .. itemName .. " to all merchant chests")
            for _, chestRef in ipairs(config.merchantChests) do
                local command = chestRef .. ".AddItem " .. itemName .. " 1"
                local success, result = pcall(function()
                    console.ExecuteConsole(command)
                end)
                
                if not success then
                    writeLog("Failed to add " .. itemName .. " to " .. chestRef .. ": " .. tostring(result), "ERROR")
                end
            end
            writeLog("Successfully added " .. itemName .. " to all merchant chests")
            
            -- Set flag for in-game quest to detect new shop stock
            console.ExecuteConsole("set APNewShopStock to 1")
            writeLog("Set APNewShopStock to 1 - in-game quest will notify player of new stock")
            
            table.insert(processedItems, itemName)
        -- Handle Oblivion Gate Vision - set console variable
        elseif itemName == "Oblivion Gate Vision" then
            writeLog("Processing Oblivion Gate Vision - setting APGateMarkersVisible to 1")
            local success, result = pcall(function()
                console.ExecuteConsole("set APGateMarkersVisible to 1")
            end)
            
            if success then
                writeLog("Successfully set APGateMarkersVisible to 1")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to set APGateMarkersVisible: " .. tostring(result), "ERROR")
            end
        -- Handle Arena unlock items
        elseif itemName:match("^APArena.*Unlock$") then
            writeLog("Processing Arena unlock item: " .. itemName)
            local edid = config.itemMappings[itemName]
            if edid then
                local addItemCommand = "player.additem " .. edid .. " 1"
                local success, result = pcall(function()
                    console.ExecuteConsole(addItemCommand)
                end)
                
                if success then
                    writeLog("Added Arena unlock item: " .. itemName)
                    
                    -- Set flag for in-game quest to detect new arena matches
                    console.ExecuteConsole("set APNewArenaMatches to 1")
                    writeLog("Set APNewArenaMatches to 1 - in-game quest will notify player of new matches")
                    
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to add Arena unlock item: " .. itemName .. " - Error: " .. tostring(result), "ERROR")
                end
            else
                writeLog("Unknown Arena unlock item: " .. itemName, "WARNING")
            end
        -- Handle Progressive Armor Tier items
        elseif itemName:match("^APArmorTier%d+$") then
            local tierNumber = tonumber(itemName:match("APArmorTier(%d+)"))
            if tierNumber then
                local success, result = pcall(function()
                    console.ExecuteConsole("set APProgressiveArmorLevel to " .. tostring(tierNumber))
                end)
                
                if success then
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to set APProgressiveArmorLevel: " .. tostring(result), "ERROR")
                end
            else
                writeLog("Invalid armor tier item: " .. itemName, "ERROR")
            end
        -- Handle Progressive Class Level items (APClassLevelX format)
        elseif itemName:match("^APClassLevel%d+$") then
            local levelNumber = tonumber(itemName:match("APClassLevel(%d+)"))
            if levelNumber then
                writeLog("Processing Progressive Class Level " .. levelNumber .. " - incrementing APClassLevel")
                local success, result = pcall(function()
                    -- Use +1 increment to handle multiple items in queue
                    console.ExecuteConsole("set APClassLevel to APClassLevel + 1")
                end)
                
                if success then
                    writeLog("Successfully incremented APClassLevel")
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to increment APClassLevel: " .. tostring(result), "ERROR")
                end
            else
                writeLog("Invalid class level item: " .. itemName, "ERROR")
            end
        -- Handle Nirnroot Satchel items
        elseif itemName:match("^APNirnrootSatchel%d+$") then
            local satchelNumber = tonumber(itemName:match("APNirnrootSatchel(%d+)"))
            if satchelNumber and satchelNumber >= 1 and satchelNumber <= 5 then
                local globalNames = {
                    "APNirnrootNoviceSatchelReceived",
                    "APNirnrootApprenticeSatchelReceived",
                    "APNirnrootJourneymanSatchelReceived",
                    "APNirnrootExpertSatchelReceived",
                    "APNirnrootMasterSatchelReceived"
                }
                local globalName = globalNames[satchelNumber]
                writeLog("Processing Nirnroot Satchel " .. satchelNumber .. " - setting " .. globalName .. " to 1")
                local success, result = pcall(function()
                    console.ExecuteConsole("set " .. globalName .. " to 1")
                end)
                
                if success then
                    writeLog("Successfully set " .. globalName .. " to 1")
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to set " .. globalName .. ": " .. tostring(result), "ERROR")
                end
            else
                writeLog("Invalid Nirnroot Satchel number: " .. tostring(satchelNumber), "ERROR")
            end
        -- Handle Septim Satchel items
        elseif itemName:match("^APSeptimSatchel%d+$") then
            local satchelNumber = tonumber(itemName:match("APSeptimSatchel(%d+)"))
            if satchelNumber and satchelNumber >= 1 and satchelNumber <= 5 then
                local globalNames = {
                    "APSeptimNoviceSatchelReceived",
                    "APSeptimApprenticeSatchelReceived",
                    "APSeptimJourneymanSatchelReceived",
                    "APSeptimExpertSatchelReceived",
                    "APSeptimMasterSatchelReceived"
                }
                local globalName = globalNames[satchelNumber]
                writeLog("Processing Septim Satchel " .. satchelNumber .. " - setting " .. globalName .. " to 1")
                local success, result = pcall(function()
                    console.ExecuteConsole("set " .. globalName .. " to 1")
                end)

                if success then
                    writeLog("Successfully set " .. globalName .. " to 1")
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to set " .. globalName .. ": " .. tostring(result), "ERROR")
                end
            else
                writeLog("Invalid Septim Satchel number: " .. tostring(satchelNumber), "ERROR")
            end
        -- Handle individual Nirnroot item
        elseif itemName == "Nirnroot" then
            writeLog("Processing Nirnroot - adding MS39Nirnroot to player inventory and incrementing APNirnrootCount")
            local success, result = pcall(function()
                console.ExecuteConsole("player.additem MS39Nirnroot 1")
                console.ExecuteConsole("set APNirnrootCount to APNirnrootCount + 1")
            end)
            
            if success then
                writeLog("Added Nirnroot (MS39Nirnroot) and incremented APNirnrootCount")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to add Nirnroot: " .. tostring(result), "ERROR")
            end
        -- Handle Fast Travel item
        elseif itemName == "Fast Travel" then
            writeLog("Processing Fast Travel item - enabling fast travel")
            local success, result = pcall(function()
                console.ExecuteConsole("EnableFastTravel 1")
            end)
            
            if success then
                writeLog("Successfully enabled fast travel")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to enable fast travel: " .. tostring(result), "ERROR")
            end
        -- Handle Dungeon Warp item
        elseif itemName == "Dungeon Warp" then
            writeLog("Processing Dungeon Warp item - enabling dungeon warp functionality")
            local success, result = pcall(function()
                console.ExecuteConsole("set APWarpEnabled to 1")
            end)
            
            if success then
                writeLog("Successfully enabled dungeon warp (APWarpEnabled = 1)")
                -- Update local setting so it takes effect immediately
                archipelagoSettings.dungeon_warp = "item"
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to enable dungeon warp: " .. tostring(result), "ERROR")
            end
        -- Handle Birth Sign item
        elseif itemName == "Birth Sign" then
            writeLog("Processing Birth Sign item - showing birth sign menu and setting APBirthSignSet")
            local success, result = pcall(function()
                console.ExecuteConsole("set APBirthSign to 1")
            end)
            
            if success then
                writeLog("Birth sign menu shown; APBirthSignSet = 1")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to process Birth Sign item: " .. tostring(result), "ERROR")
            end
        -- Handle Sidequest License items
        elseif itemName == "Wealth Sidequest License" then
            writeLog("Processing Wealth Sidequest License - setting wealth variable to 1")
            local success, result = pcall(function()
                console.ExecuteConsole("set APSidequestWealthLicense to 1")
            end)
            if success then
                writeLog("Successfully set wealth variable to 1")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to set wealth variable: " .. tostring(result), "ERROR")
            end
        elseif itemName == "Exploration Sidequest License" then
            writeLog("Processing Exploration Sidequest License - setting exploration variable to 1")
            local success, result = pcall(function()
                console.ExecuteConsole("set APSidequestExplorationLicense to 1")
            end)
            if success then
                writeLog("Successfully set exploration variable to 1")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to set exploration variable: " .. tostring(result), "ERROR")
            end
        -- Handle Lockpick Set item
        elseif itemName == "Lockpick Set" then
            writeLog("Processing Lockpick Set - adding 30 lockpicks")
            local success, result = pcall(function()
                console.ExecuteConsole("player.additem 0000000A 30")
            end)
            if success then
                writeLog("Added 30 lockpicks from Lockpick Set")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to add Lockpick Set: " .. tostring(result), "ERROR")
            end
        -- Handle Horse item
        elseif itemName == "Horse" then
            writeLog("Processing Horse - setting APHorseGranted to 1")
            local success, result = pcall(function()
                console.ExecuteConsole("set APHorseGranted to 1")
            end)
            if success then
                writeLog("Horse granted (APHorseGranted = 1)")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to grant Horse: " .. tostring(result), "ERROR")
            end
        -- Handle Dagon Shrine Passphrase: set known flag
        elseif itemName == "Dagon Shrine Passphrase" then
            writeLog("Processing Dagon Shrine Passphrase - setting APDagonShrinePassphraseKnown to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APDagonShrinePassphraseKnown to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APDagonShrinePassphraseKnown: " .. tostring(err), "ERROR") end
        -- Handle Encrypted Scroll of the Blades: set Global flag
        elseif itemName == "Encrypted Scroll of the Blades" then
            writeLog("Processing Encrypted Scroll of the Blades - setting APEncryptedScrolloftheBlades to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APEncryptedScrolloftheBlades to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APEncryptedScrolloftheBlades: " .. tostring(err), "ERROR") end
        elseif itemName == "Blades' Report: Strangers at Dusk" then
            writeLog("Processing Blades' Report: Strangers at Dusk - setting APStrangersAtDusk to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APStrangersAtDusk to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APStrangersAtDusk: " .. tostring(err), "ERROR") end
        -- Handle Decoded Page of the Xarxes: set corresponding Global flag
        elseif itemName == "Decoded Page of the Xarxes: Divine" then
            writeLog("Processing Decoded Page of the Xarxes: Divine - setting APDecodedPageoftheXarxesDivine to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APDecodedPageoftheXarxesDivine to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APDecodedPageoftheXarxesDivine: " .. tostring(err), "ERROR") end
        elseif itemName == "Decoded Page of the Xarxes: Daedric" then
            writeLog("Processing Decoded Page of the Xarxes: Daedric - setting APDecodedPageoftheXarxesDaedric to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APDecodedPageoftheXarxesDaedric to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APDecodedPageoftheXarxesDaedric: " .. tostring(err), "ERROR") end
        elseif itemName == "Decoded Page of the Xarxes: Ayleid" then
            writeLog("Processing Decoded Page of the Xarxes: Ayleid - setting APDecodedPageoftheXarxesAyleid to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APDecodedPageoftheXarxesAyleid to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APDecodedPageoftheXarxesAyleid: " .. tostring(err), "ERROR") end
          elseif itemName == "Decoded Page of the Xarxes: Sigillum" then
            writeLog("Processing Decoded Page of the Xarxes: Sigillum - setting APDecodedPageoftheXarxesSigillum to 1")
            local ok, err = pcall(function() console.ExecuteConsole("set APDecodedPageoftheXarxesSigillum to 1") end)
            if ok then table.insert(processedItems, itemName) else writeLog("Failed to set APDecodedPageoftheXarxesSigillum: " .. tostring(err), "ERROR") end
        -- Handle Amulet of Kings key item
        elseif itemName == "Amulet of Kings" then
            writeLog("Processing Amulet of Kings - adding AmuletofKings to player inventory")
            local success, result = pcall(function()
                console.ExecuteConsole("player.additem AmuletofKings 1")
            end)
            if success then
                writeLog("Added Amulet of Kings (AmuletofKings)")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to add Amulet of Kings: " .. tostring(result), "ERROR")
            end
        -- Handle Kvatch Gate Key item: add APKvatchGateKey to inventory
        elseif itemName == "Kvatch Gate Key" then
            writeLog("Processing Kvatch Gate Key - adding APKvatchGateKey to player inventory")
            local success, result = pcall(function()
                console.ExecuteConsole("player.additem APKvatchGateKey 1")
            end)
            if success then
                writeLog("Added Kvatch Gate Key (APKvatchGateKey)")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to add Kvatch Gate Key: " .. tostring(result), "ERROR")
            end
        -- Handle Fort Sutch Gate Key item: add APFortSutchGateKey to inventory
        elseif itemName == "Fort Sutch Gate Key" then
            writeLog("Processing Fort Sutch Gate Key - adding APFortSutchGateKey to player inventory")
            local success, result = pcall(function()
                console.ExecuteConsole("player.additem APFortSutchGateKey 1")
            end)
            if success then
                writeLog("Added Fort Sutch Gate Key (APFortSutchGateKey)")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to add Fort Sutch Gate Key: " .. tostring(result), "ERROR")
            end
        -- Handle Bruma Gate Key item: add APBrumaGateKey to inventory
        elseif itemName == "Bruma Gate Key" then
            writeLog("Processing Bruma Gate Key - adding APBrumaGateKey to player inventory")
            local success, result = pcall(function()
                console.ExecuteConsole("player.additem APBrumaGateKey 1")
            end)
            if success then
                writeLog("Added Bruma Gate Key (APBrumaGateKey)")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to add Bruma Gate Key: " .. tostring(result), "ERROR")
            end
        -- Handle Fortify Attribute items: set global flags for in-game processing
        elseif itemName:match("^Fortify .+") then
            local attributeName = itemName:match("^Fortify (.+)$") or ""
            local allowedAttributes = {
                Strength = "APFortifyStrength",
                Intelligence = "APFortifyIntelligence",
                Willpower = "APFortifyWillpower",
                Agility = "APFortifyAgility",
                Speed = "APFortifySpeed",
                Endurance = "APFortifyEndurance",
                Personality = "APFortifyPersonality",
                Luck = "APFortifyLuck"
            }
            local globalVar = allowedAttributes[attributeName]
            if globalVar then
                writeLog("Processing Fortify Attribute item: " .. itemName .. " (set " .. globalVar .. " = 1)")
                local success, result = pcall(function()
                    console.ExecuteConsole("set " .. globalVar .. " to 1")
                end)
                if success then
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to set global flag " .. globalVar .. ": " .. tostring(result), "ERROR")
                end
            else
                writeLog("Unknown attribute for Fortify item: '" .. attributeName .. "' from '" .. itemName .. "'", "WARNING")
            end
        else
            local edid = config.itemMappings[itemName]
            if type(edid) == "table" then
                edid = edid[math.random(#edid)]
            end
            if edid then
                -- Set quantity based on item type
                local quantity = 1
                if itemName:find("Potion") or itemName == "Skooma" then
                    quantity = 3
                elseif itemName == "Steel Arrows" then
                    quantity = 5
                elseif itemName == "Special Arrow Bundle" then
                    quantity = 100
                elseif itemName == "Poisoned Apples" then
                    quantity = 3
                elseif itemName == "Gold (10)" then
                    quantity = 10
                elseif itemName == "Gold" or itemName == "Clavicus Gold" then
                    quantity = 500
                elseif itemName == "Greater Soulgem Package" then
                    quantity = 5
                elseif itemName == "Legendary Detect Life Scroll Bundle" then
                    quantity = 5
                end
                
                local addItemCommand = "player.additem " .. edid .. " " .. quantity
                local success, result = pcall(function()
                    console.ExecuteConsole(addItemCommand)
                end)
                
                if success then
                    table.insert(processedItems, itemName)
                else
                    writeLog("Failed to add item: " .. itemName .. " - Error: " .. tostring(result), "ERROR")
                end
            else
                writeLog("Unknown item: " .. itemName, "WARNING")
            end
        end
    end
    
    -- Write receipt to bridge status and clean up queue
    if #itemsToProcess > 0 then
        updateBridgeStatus(processedItems)
        os.remove(queuePath)
        writeLog("Processed " .. #processedItems .. " items")
        bulkItemGrantInProgress = false
    end
end

local function DoIcarianFlightTrap()
    pendingIcarianFlight = true
end

local function executeIcarianLaunch()
    local player = UEHelpers:GetPlayer()
    if not player or not player:IsValid() then return end

    local movement = player.CharacterMovement
    if not movement or not movement:IsValid() then return end

    local yawRad = math.rad(player:K2_GetActorRotation().Yaw)
    movement.MovementMode = 3
    movement.Velocity = {
        X = math.cos(yawRad) * 3500.0,
        Y = math.sin(yawRad) * 3500.0,
        Z = 6500.0,
    }
    pcall(function() console.ExecuteConsole("player.playsound AMBFemaleScream") end)
    writeLog("IcarianFlight: launched")
end

local trapHandlers = {
    APMovementTrapReceived = function()
        console.ExecuteConsole("set APMovementTrapReceived to 1")
        writeLog("Trap triggered: APMovementTrapReceived")
    end,
    APStormTrapReceived = function()
        console.ExecuteConsole("set APStormTrapReceived to 1")
        writeLog("Trap triggered: APStormTrapReceived")
    end,
    APSpawnTrapReceived = function()
        console.ExecuteConsole("set APSpawnTrapReceived to 1")
        writeLog("Trap triggered: APSpawnTrapReceived")
    end,
    APWantedTrapReceived = function()
        console.ExecuteConsole("set APWantedTrapReceived to 1")
        writeLog("Trap triggered: APWantedTrapReceived")
    end,
}

local function processTrapQueue()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return end

    local trapsPath = getArchipelagoPath(filePrefix .. "_traps.txt")
    local file = io.open(trapsPath, "r")
    if not file then return end

    local trapCodes = {}
    for line in file:lines() do
        local code = line:match("^%s*(.-)%s*$")
        if code and code ~= "" then
            table.insert(trapCodes, code)
        end
    end
    file:close()

    if #trapCodes == 0 then
        os.remove(trapsPath)
        return
    end

    for _, code in ipairs(trapCodes) do
        local handler = trapHandlers[code]
        if handler then
            local ok, err = pcall(handler)
            if not ok then
                writeLog("Trap '" .. code .. "' failed: " .. tostring(err), "ERROR")
            end
        else
            writeLog("Unknown trap code: '" .. code .. "'", "WARNING")
        end
    end

    os.remove(trapsPath)
end

local function processDeathlinkSignal()
    -- Inbound deathlink: read {prefix}_deathlink.txt from AP client.
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return end

    local deathlinkPath = getArchipelagoPath(filePrefix .. "_deathlink.txt")
    local file = io.open(deathlinkPath, "r")
    if not file then return end
    file:close()

    writeLog("Deathlink signal received - setting APDeathlink global")
    local success, result = pcall(function()
        console.ExecuteConsole("set APDeathlink to 1")
    end)
    if success then
        writeLog("APDeathlink set to 1; in-game script will handle kill when safe")
    else
        writeLog("Failed to set APDeathlink: " .. tostring(result), "ERROR")
    end

    os.remove(deathlinkPath)
end

-- Check if a completion is already in *_completed.txt (same-session duplicate HUD).
local function isCompletionAlreadyRecorded(completionTokenEdid)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return false end
    completionTokenEdid = (completionTokenEdid or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
    if completionTokenEdid == "" then return false end

    local statusPath = getArchipelagoPath(filePrefix .. "_completed.txt")
    local file = io.open(statusPath, "r")
    if not file then return false end

    for line in file:lines() do
        local stored = (line or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
        if stored == completionTokenEdid then
            file:close()
            return true
        end
    end
    file:close()
    return false
end

-- Write quest completion status to file for the Archipelago client
local function writeCompletionStatus(completionTokenEdid)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end

    local statusPath = getArchipelagoPath(filePrefix .. "_completed.txt")
    local file = io.open(statusPath, "a")
    if file then
        file:write(completionTokenEdid .. "\n")
        file:close()
        writeLog("Completion recorded: " .. completionTokenEdid)
    end
end

-- Check for valid Archipelago session (connection file + settings)
local function checkValidSession()
    -- If path override failed, show that error instead of connection errors
    if pathOverrideStatus == "error" then
        if not hasShownNoSettingsMessage then
            local success = pcall(function()
                console.ExecuteConsole("MessageBox \"path_override.txt found but path is invalid.\"")
            end)
            if success then
                hasShownNoSettingsMessage = true
                writeLog("WARNING: path_override.txt found but invalid. Using default path.", "WARNING")
            end
        end
        pathOverrideStatus = nil  -- Clear status to avoid repeated messages
        -- Continue checking for connection file with default path
    end
    
    local connectionPath = getArchipelagoPath("current_connection.txt")
    local connectionFile = io.open(connectionPath, "r")
    if not connectionFile then
        -- No connection file found
        if not hasShownNoSettingsMessage then
            -- Customize message if using path override
            -- This helps users who set a custom path forget to update their AP client
            local message
            if pathOverrideLoaded then
                message = "No connection file found. Did you run /set_save_path in your AP client to match: " .. ARCHIPELAGO_BASE_DIR .. "?"
                writeLog("Path override active - suggesting /set_save_path to user: " .. ARCHIPELAGO_BASE_DIR)
            else
                message = "No connection file found, is your AP client connected?"
            end
            
            local success = pcall(function()
                console.ExecuteConsole("MessageBox \"" .. message .. "\"")
            end)
            if success then
                hasShownNoSettingsMessage = true
                hadNoConnectionMessage = true
                hasShownConnectionEstablished = false
            else
                writeLog("Failed to display 'no connection file' message", "ERROR")
            end
        end
        return false  -- No valid session
    end
    connectionFile:close()
    
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        -- Connection file exists but no valid prefix
        if not hasShownNoSettingsMessage then
            local success = pcall(function()
                console.ExecuteConsole("MessageBox \"Settings file not found, is your AP client connected?\"")
            end)
            if success then
                hasShownNoSettingsMessage = true
                hadNoConnectionMessage = true
                hasShownConnectionEstablished = false
            else
                writeLog("Failed to display 'no settings file' message", "ERROR")
            end
        end
        return false  -- No valid session
    end
    
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then
        -- Connection file exists but no settings file
        if not hasShownNoSettingsMessage then
            local success = pcall(function()
                console.ExecuteConsole("MessageBox \"Settings file not found, is your AP client connected?\"")
            end)
            if success then
                hasShownNoSettingsMessage = true
                hadNoConnectionMessage = true
                hasShownConnectionEstablished = false
            else
                writeLog("Failed to display 'no settings file' message", "ERROR")
            end
        end
        return false  -- No valid session
    end
    file:close()
    
    -- If we previously showed the no-connection message and now have a valid session, notify once
    if hadNoConnectionMessage and not hasShownConnectionEstablished then
        local ok = pcall(function()
            console.ExecuteConsole("MessageBox \"Archipelago connection established.\"")
        end)
        if ok then
            hasShownConnectionEstablished = true
            -- Force a settings reload path on reconnect: treat as not initialized
            -- This ensures we re-read the new session's settings and won't prompt
            -- for reinit when a fresh initialization is actually required.
            init.modFully = false
            writeLog("Reconnect detected; forcing settings reload by clearing init.modFully")
        else
            writeLog("Failed to display 'connection established' message", "ERROR")
        end
    end
    -- Reset the disconnect gate so future disconnects can alert again
    hasShownNoSettingsMessage = false
    
    return true  -- Valid session found
end

-- Get current cell/location name for kill tracking
local cellDbByForm = nil

function state.normalizeFormId(formID)
    if not formID then return nil end
    formID = formID:upper():gsub("^0X", "")
    if #formID < 8 then
        formID = string.rep("0", 8 - #formID) .. formID
    end
    return formID
end

function state.ensureCellDatabase()
    if cellDbByForm then
        return true
    end
    local file = nil
    local scriptDir = getScriptDirectory()
    if scriptDir and scriptDir ~= "" then
        file = io.open(scriptDir .. "\\oblivion_cell_database.csv", "r")
    end
    if not file then
        file = io.open("oblivion_cell_database.csv", "r")
    end
    if not file then
        file = io.open(getArchipelagoPath("oblivion_cell_database.csv"), "r")
    end
    if not file then
        writeLog("Cell lookup file not found (oblivion_cell_database.csv)", "WARN")
        return false
    end
    cellDbByForm = {}
    for line in file:lines() do
        if not line:match("^%s*$") then
            local parts = {}
            for part in line:gmatch("([^,]+)") do
                table.insert(parts, part:match("^%s*(.-)%s*$"))
            end
            if #parts >= 2 then
                local form = state.normalizeFormId(parts[2])
                local editor = parts[3] or ""
                local name = parts[1]
                if form then
                    cellDbByForm[form] = { name = name, editor = editor, category = parts[4] or "" }
                end
            end
        end
    end
    file:close()
    return true
end

lookupCellNameByFormID = function(formID)
    if not formID or not state.ensureCellDatabase() then
        return nil
    end
    local row = cellDbByForm[state.normalizeFormId(formID)]
    if not row then
        return nil
    end
    return row.name, row.editor, row.category
end

local function getCurrentCellName()
    if currentCellName then
        return currentCellName
    end

    local player = UEHelpers:GetPlayer()
    if not player or not player:IsValid() then return "Unknown Location" end

    local worldFullName = ""
    pcall(function()
        worldFullName = player:GetWorld():GetFullName() or ""
    end)

    if worldFullName:find("Tamriel") then
        currentCellName = "Tamriel"
        return "Tamriel"
    end

    if worldFullName:lower():find("oblivion") then
        local mapName = worldFullName:match("/([^/]+)%.") or worldFullName:match("/([^/]+)$") or "Oblivion Plane"
        currentCellName = mapName
        currentCellIsOblivion = true
        return mapName
    end

    local cityName = state.matchCityWorld(worldFullName)
    if cityName then
        currentCellName = cityName
        currentCellIsOblivion = false
        return cityName
    end

    if not cellNameRequestPending and not cellLookupProbe.awaiting then
        state.startCellLookup()
    end
    return "Unknown Location"
end

-- Returns "overworld", "oblivion", "town", or "dungeon".
local function getCellKillType()
    local worldName = state.currentWorldFullName()
    if state.matchCityWorld(worldName) then
        return "town"
    end
    local cellName = getCurrentCellName()
    if cellName:find("Tamriel") then
        return "overworld"
    end
    -- Check all three Oblivion indicators:
    -- 1. currentCellIsOblivion flag set during CSV lookup or worldspace detection
    -- 2. Fallback cell name contains "oblivion" (Oblivion worldspace map name)
    -- 3. currentCellEditorID directly
    local editorID = currentCellEditorID or ""
    if currentCellIsOblivion
       or cellName:lower():find("oblivion")
       or (editorID ~= "" and editorID:find("Oblivion")) then
        return "oblivion"
    end
    return "dungeon"
end

-- UE5 cm → Oblivion unit conversion.
-- Scale: 1 Oblivion unit ≈ 1/0.7 UE5 cm
-- Y axis: negated between the two coordinate systems
local function updateAPXMarker(x, y, z)
    local UE5_TO_OBL = 0.7
    if lastMarkerX then
        local dx = math.abs(x - lastMarkerX)
        local dy = math.abs(y - lastMarkerY)
        local dz = math.abs(z - lastMarkerZ)
        if dx <= MARKER_MOVE_THRESHOLD and dy <= MARKER_MOVE_THRESHOLD and dz <= MARKER_MOVE_THRESHOLD then
            return  -- Same target
        end
    end
    -- Convert UE5 cm to Oblivion units (Y is negated)
    local ox = x * UE5_TO_OBL
    local oy = -y * UE5_TO_OBL
    local oz = z * UE5_TO_OBL
    pcall(function()
        console.ExecuteConsole(string.format("APXMarkerRef.setpos x %.2f", ox))
        console.ExecuteConsole(string.format("APXMarkerRef.setpos y %.2f", oy))
        console.ExecuteConsole(string.format("APXMarkerRef.setpos z %.2f", oz))
        console.ExecuteConsole("set APAutoTrackValid to 1")
    end)
    lastMarkerX = x
    lastMarkerY = y
    lastMarkerZ = z
end

clearAPXMarker = function()
    if not lastMarkerX then return end
    pcall(function()
        console.ExecuteConsole("set APAutoTrackValid to 0")
    end)
    lastMarkerX = nil
    lastMarkerY = nil
    lastMarkerZ = nil
end

enableBossChestTracking = function()
    nirnrootTrackingEnabled = false
    bossChestTrackingEnabled = true
    lastBossChestMessage = os.clock()
    lastTrackingUpdate = os.clock()
end

tryEnableChestTrackingForCurrentCell = function()
    if not shouldAutoTrack() or not chestInSeed then
        disableAllAutoTrack()
        return
    end
    local cellName = currentCellName or ""
    if cellName == "" or currentCellIsOblivion then
        disableAllAutoTrack()
        return
    end
    local dungeon = require("MapPins").selectedDungeonForCell(cellName)
    if dungeon and not isCompletionAlreadyRecorded(dungeon .. " Dungeon Cleared") then
        enableBossChestTracking()
        writeLog("Boss chest tracking for selected dungeon: " .. dungeon)
    else
        disableAllAutoTrack()
    end
end

enableNirnrootTracking = function()
    bossChestTrackingEnabled = false
    nirnrootTrackingEnabled = true
    lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
    lastTrackingUpdate = os.clock()
end

disableAllAutoTrack = function()
    nirnrootTrackingEnabled = false
    bossChestTrackingEnabled = false
end

shouldAutoTrack = function()
    return archipelagoSettings.auto_tracking and not autoTrackManualOff
end

function state.runDeferredFadeWorldSetup()
    if not (killTrackingEnabled or archipelagoSettings.auto_tracking) then
        return
    end

    currentCellName = nil
    currentCellEditorID = nil
    currentCellIsOblivion = false
    cellNameRequestPending = false

    local worldName = state.currentWorldFullName()

    if worldName:find("Tamriel") then
        currentCellName = "Tamriel"
        currentCellIsOblivion = false
        state.cellPending = false
        writeLog("Cell set to Tamriel from world name")
        pendingMarkerClear = true
        if shouldAutoTrack() then
            if nirnrootInSeed and not nirnrootManualOff then
                pendingAutoTrack = "nirn"
            else
                pendingAutoTrack = "off"
            end
        else
            pendingAutoTrack = "off"
        end
    elseif worldName:lower():find("oblivion") then
        local mapName = worldName:match("/([^/]+)%.") or worldName:match("/([^/]+)$") or "Oblivion Plane"
        currentCellName = mapName
        currentCellIsOblivion = true
        state.cellPending = false
        writeLog("Cell set to Oblivion worldspace: " .. mapName)
        if shouldAutoTrack() then
            pendingAutoTrack = "off"
            pendingMarkerClear = true
        end
    elseif state.matchCityWorld(worldName) then
        currentCellName = state.matchCityWorld(worldName)
        currentCellIsOblivion = false
        state.cellPending = false
        writeLog("Cell set to city world: " .. currentCellName)
        pendingMarkerClear = true
        pendingAutoTrack = "off"
    elseif worldName ~= "" then
        pendingCellLookup = true
    else
        state.fadeWorldSetup = true
    end
end

function state.tryRestoreQuestPins()
    if not state.pinsNeedRestore then
        return
    end
    if not state.pinsRestoreArmed then
        return
    end
    if state.travelling or state.isWorldUnstable() then
        return
    end
    if state.cellPending or pendingCellLookup or cellNameRequestPending or cellLookupProbe.awaiting then
        return
    end
    local cell = currentCellName or ""
    if cell ~= "Tamriel" then
        return
    end
    state.pinsNeedRestore = false
    state.pinsRestoreArmed = false
    local ok, err = pcall(function()
        require("MapPins").restoreRegionPins()
        require("BountyTracking").restoreBountyPins()
    end)
    if ok then
        writeLog("Restored quest pins in '" .. cell .. "'")
    else
        state.pinsNeedRestore = true
        writeLog("Quest pin restore failed: " .. tostring(err), "ERROR")
    end
end

function state.processPendingFadeActions()
    if state.firstInit then
        state.firstInit = false
        if not init.modFully then
            writeLog("No init flags in memory. Reading settings file.")
            handleInitialization()
        end
    end

    if state.fadeWorldSetup then
        state.fadeWorldSetup = false
        state.runDeferredFadeWorldSetup()
    end

    if state.fadeWorldSetup then return end

    -- Interiors: always start getparentcell here. Do not wait on AP sync.
    if pendingCellLookup and not cellLookupProbe.awaiting then
        state.startCellLookup()
    end

    if pendingCellLookup or cellLookupProbe.awaiting or state.cellPending then
        return
    end

    -- Same two moments as quest pins: first in-game fade, and load after main menu.
    if state.pinsNeedRestore and state.pinsRestoreArmed then
        state.applySkillXpMultiplier()
    end
    state.tryRestoreQuestPins()

    if apProbe.awaiting then
        return
    end

    if state.apSyncOnStable then
        state.apSyncOnStable = false
        state.allowAPSync = checkValidSession()
        if state.allowAPSync then
            if not probeFinished and not apProbe.awaiting and not menuCheckInProgress() then
                startAPSyncProbe()
                state.probeStartedForSession = true
            end
        else
            writeLog("Skipping APSync probe - no valid Archipelago session")
        end
    end

    if pendingMarkerClear then
        pendingMarkerClear = false
        clearAPXMarker()
    end

    if pendingAutoTrack == "boss" then
        tryEnableChestTrackingForCurrentCell()
        pendingAutoTrack = nil
    elseif pendingAutoTrack == "nirn" then
        enableNirnrootTracking()
        pendingAutoTrack = nil
    elseif pendingAutoTrack == "off" then
        disableAllAutoTrack()
        pendingAutoTrack = nil
    end

    state.flushPendingKills()
end

-- Scan visible Nirnroot plants and update the compass marker.
-- Harvested plants are bHidden and skipped.
function state.scanNearestNirnroot(player, excludeX, excludeY, excludeZ)
    if not player or not player:IsValid() then return nil, nil end

    local playerLoc = player:K2_GetActorLocation()
    local instances = FindAllOf("BP_NirnrootPlant_C")
    local nearestDist = 99999999
    local nearestDir = "?"
    local nearestDistMeters = nil
    local nearestLoc = nil
    local excludeRadius = 200

    pcall(function()
        if not instances then return end
        for _, obj in ipairs(instances) do
            if obj and obj:IsValid() and obj.bHidden ~= true then
                local loc = obj:K2_GetActorLocation()
                local excluded = excludeX
                    and math.abs(loc.X - excludeX) <= excludeRadius
                    and math.abs(loc.Y - excludeY) <= excludeRadius
                    and math.abs(loc.Z - excludeZ) <= excludeRadius
                if not excluded then
                    local dist = math.sqrt(
                        (loc.X - playerLoc.X)^2 +
                        (loc.Y - playerLoc.Y)^2 +
                        (loc.Z - playerLoc.Z)^2
                    )
                    if dist < nearestDist then
                        nearestDist = dist
                        nearestDistMeters = math.floor(dist / 100)
                        nearestLoc = loc
                        local angle = math.atan(-(loc.Y - playerLoc.Y), loc.X - playerLoc.X) * (180 / math.pi)
                        if angle < 0 then angle = angle + 360 end
                        local dirs = {"E","NE","N","NW","W","SW","S","SE"}
                        nearestDir = dirs[math.floor((angle + 22.5) / 45) % 8 + 1]
                    end
                end
            end
        end
    end)

    if nearestDistMeters and nearestLoc then
        updateAPXMarker(nearestLoc.X, nearestLoc.Y, nearestLoc.Z)
        if not archipelagoSettings.silent_auto_tracking then
            pcall(function()
                console.ExecuteConsole(string.format('Message "Nirnroot %s %dm"', nearestDir, nearestDistMeters))
            end)
        end
        return nearestDir, nearestDistMeters
    end
    clearAPXMarker()
    return nil, nil
end

function state.redetectNirnrootAfterHarvest()
    if not nirnrootTrackingEnabled then
        writeLog("Nirnroot harvest redetect skipped (tracking not active)")
        return
    end
    pendingNirnrootRedetect = true
    writeLog("Nirnroot harvest redetect queued")
end

function state.runQueuedNirnrootRedetect()
    if not pendingNirnrootRedetect then return end
    pendingNirnrootRedetect = false
    if not nirnrootTrackingEnabled then
        writeLog("Nirnroot harvest redetect skipped (tracking not active)")
        return
    end
    local player = UEHelpers:GetPlayer()
    if not player or not player:IsValid() then
        writeLog("Nirnroot harvest redetect skipped (no player)")
        return
    end
    lastNirnrootMessage = os.clock()
    lastTrackingUpdate = os.clock()
    local dir, meters = state.scanNearestNirnroot(player, lastMarkerX, lastMarkerY, lastMarkerZ)
    if dir and meters then
        writeLog(string.format("Nirnroot harvest redetect: %s %dm", dir, meters))
    else
        writeLog("Nirnroot harvest redetect: no other plant found")
    end
end

-- Periodic tracking update function
local function updatePeriodicTracking()
    if not nirnrootTrackingEnabled and not bossChestTrackingEnabled then
        return
    end
    
    local currentTime = os.clock()
    
    -- Check if enough time has passed
    if currentTime - lastTrackingUpdate < TRACKING_INTERVAL then
        return
    end
    
    lastTrackingUpdate = currentTime
    
    -- load ActorDetection only when boss chest tracking needs it
    if bossChestTrackingEnabled and not ActorDetection then
        local success, module = pcall(function() return require("ActorDetection") end)
        if not success then
            writeLog("Failed to load ActorDetection module", "ERROR")
            return
        end
        ActorDetection = module
    end
    
    local player = UEHelpers:GetPlayer()
    if not player or not player:IsValid() then
        return
    end
    
    -- Track Nirnroot
    if nirnrootTrackingEnabled and currentTime - lastNirnrootMessage >= NIRNROOT_MESSAGE_INTERVAL then
        lastNirnrootMessage = currentTime
        state.scanNearestNirnroot(player)
    end

    -- Track Boss Chests
    if bossChestTrackingEnabled and currentTime - lastBossChestMessage >= BOSS_CHEST_MESSAGE_INTERVAL then
        lastBossChestMessage = currentTime

        local containers = ActorDetection.DetectNearbyContainers(5000)
        local playerLoc = player:K2_GetActorLocation()

        -- Collect boss containers with distances
        local bossContainers = {}
        for formID, data in pairs(containers) do
            local fn = data.fullName or ""
            if fn:find("MythEnemyChest", 1, true) and not fn:find("BossChest", 1, true) then
            elseif data.fullName:lower():match("boss") or data.name:lower():match("boss") or
               data.fullName:match("BattlehornChest") or data.fullName:match("DinningHallChest") then
                local distance = math.sqrt(
                    (data.location.X - playerLoc.X)^2 +
                    (data.location.Y - playerLoc.Y)^2 +
                    (data.location.Z - playerLoc.Z)^2
                )
                table.insert(bossContainers, {
                    name = data.name,
                    fullName = data.fullName,
                    formID = formID,
                    location = data.location,
                    distance = math.floor(distance / 100)
                })
            end
        end

        if #bossContainers > 0 then
            -- Find nearest boss chest
            local nearestChest = bossContainers[1]
            for _, chest in ipairs(bossContainers) do
                if chest.distance < nearestChest.distance then
                    nearestChest = chest
                end
            end

            updateAPXMarker(nearestChest.location.X, nearestChest.location.Y, nearestChest.location.Z)

            local suppressChestMessage = require("BountyTracking").shouldSuppressBossChestMessage()
            if not archipelagoSettings.silent_auto_tracking and not suppressChestMessage then
                local chestDir = "?"
                pcall(function()
                    local angle = math.atan(
                        -(nearestChest.location.Y - playerLoc.Y),
                        nearestChest.location.X - playerLoc.X
                    ) * (180 / math.pi)
                    if angle < 0 then angle = angle + 360 end
                    local dirs = {"E","NE","N","NW","W","SW","S","SE"}
                    chestDir = dirs[math.floor((angle + 22.5) / 45) % 8 + 1]
                end)
                pcall(function()
                    console.ExecuteConsole(string.format('Message "Boss chest %s %dm"', chestDir, nearestChest.distance))
                end)
            end
        else
            clearAPXMarker()
        end
    end
end

function state.killsPath()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return nil
    end
    return getArchipelagoPath(filePrefix .. "_kills.txt")
end

function state.splitKillsFile(contents)
    local dungeon, overworld, oblivion = nil, nil, nil
    local log = {}
    local bounty = {}
    local licenses = {}
    for raw in ((contents or "") .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("\r", "")
        local site, n = line:match("^cull:(.+)=(%d+)$")
        if site then
            bounty[site] = tonumber(n) or 0
        elseif line:match("^licenses=") then
            local rest = line:match("^licenses=(.*)$") or ""
            for cat in rest:gmatch("([^,]+)") do
                local trimmed = (cat:match("^%s*(.-)%s*$") or ""):lower()
                if trimmed ~= "" then
                    licenses[trimmed] = true
                end
            end
        else
            local kind, count = line:match("^(%a+)=(%d+)$")
            if kind == "dungeon" then
                dungeon = tonumber(count) or 0
            elseif kind == "overworld" then
                overworld = tonumber(count) or 0
            elseif kind == "oblivion" then
                oblivion = tonumber(count) or 0
            else
                table.insert(log, line)
            end
        end
    end
    while log[1] == "" do
        table.remove(log, 1)
    end
    while log[#log] == "" do
        log[#log] = nil
    end
    return dungeon, overworld, log, bounty, oblivion, licenses
end

function state.importLegacyBountyFile(bounty)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return bounty end
    if bounty and next(bounty) then return bounty end
    local path = getArchipelagoPath(filePrefix .. "_bounty.txt")
    local file = io.open(path, "r")
    if not file then return bounty or {} end
    bounty = bounty or {}
    for line in file:lines() do
        local site, n = line:match("^cull:(.+)=(%d+)$")
        if site and n then
            bounty[site] = tonumber(n) or 0
        end
    end
    file:close()
    return bounty
end

function state.getBountyProgress()
    return killProgress.bounty or {}
end

function state.currentBountyProgress()
    if state.bountyProgressReady then
        local ok, progress = pcall(function()
            return require("BountyTracking").bountyProgress()
        end)
        if ok and type(progress) == "table" then
            return progress
        end
    end
    return killProgress.bounty or {}
end

function state.loadKillProgress()
    if killProgressLoaded then return end
    killProgress.dungeon = 0
    killProgress.overworld = 0
    killProgress.oblivion = 0
    killProgress.bounty = {}
    state.weaponLicenses = state.weaponLicenses or {}
    local path = state.killsPath()
    if path then
        local file = io.open(path, "r")
        if file then
            local dungeon, overworld, _, bounty, oblivion, licenses = state.splitKillsFile(file:read("*a") or "")
            file:close()
            if dungeon then killProgress.dungeon = dungeon end
            if overworld then killProgress.overworld = overworld end
            if oblivion then killProgress.oblivion = oblivion end
            killProgress.bounty = bounty or {}
            if licenses then
                for cat, on in pairs(licenses) do
                    if on then state.weaponLicenses[cat] = true end
                end
            end
        end
    end
    killProgress.bounty = state.importLegacyBountyFile(killProgress.bounty)
    local filePrefix = getCurrentFilePrefix()
    if filePrefix and killProgress.dungeon == 0 and killProgress.overworld == 0 then
        local legacy = getArchipelagoPath(filePrefix .. "_kill_progress.txt")
        local file = io.open(legacy, "r")
        if file then
            for line in file:lines() do
                local kind, count = line:match("^(%a+)=(%d+)$")
                if (kind == "dungeon" or kind == "overworld" or kind == "oblivion") and count then
                    killProgress[kind] = tonumber(count) or 0
                end
            end
            file:close()
        end
    end
    killProgressLoaded = true
    writeLog(string.format("Loaded kill progress: dungeon=%d overworld=%d oblivion=%d",
        killProgress.dungeon or 0, killProgress.overworld or 0, killProgress.oblivion or 0))
end

function state.writeKillsFile(newLogLine)
    local path = state.killsPath()
    if not path then return end
    local log = {}
    local file = io.open(path, "r")
    if file then
        local _, _, existing = state.splitKillsFile(file:read("*a") or "")
        file:close()
        log = existing
    end
    if newLogLine and newLogLine ~= "" then
        table.insert(log, newLogLine)
    end
    local bounty = state.currentBountyProgress()
    killProgress.bounty = bounty
    file = io.open(path, "w")
    if not file then return end
    file:write(string.format("dungeon=%d\n", killProgress.dungeon or 0))
    file:write(string.format("overworld=%d\n", killProgress.overworld or 0))
    file:write(string.format("oblivion=%d\n", killProgress.oblivion or 0))
    local licenseKeys = {}
    for cat, on in pairs(state.weaponLicenses or {}) do
        if on then table.insert(licenseKeys, cat) end
    end
    table.sort(licenseKeys)
    if #licenseKeys > 0 then
        file:write("licenses=" .. table.concat(licenseKeys, ",") .. "\n")
    end
    local keys = {}
    for site in pairs(bounty) do
        table.insert(keys, site)
    end
    table.sort(keys)
    for _, site in ipairs(keys) do
        file:write(string.format("cull:%s=%d\n", site, bounty[site] or 0))
    end
    for i = 1, #log do
        file:write(log[i])
        file:write("\n")
    end
    file:close()
    local filePrefix = getCurrentFilePrefix()
    if filePrefix then
        pcall(os.remove, getArchipelagoPath(filePrefix .. "_kill_progress.txt"))
        pcall(os.remove, getArchipelagoPath(filePrefix .. "_bounty.txt"))
    end
end

function state.saveKillProgress()
    state.writeKillsFile(nil)
end

function state.lastClearedDungeonFromCompletions()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return nil end
    local path = getArchipelagoPath(filePrefix .. "_completed.txt")
    local file = io.open(path, "r")
    if not file then return nil end
    local lastName = nil
    for line in file:lines() do
        local name = line:match("^(.+)%s+Dungeon Cleared$")
        if name then
            lastName = name:match("^%s*(.-)%s*$")
        end
    end
    file:close()
    return lastName
end

function state.resolveWarpMarker(dungeonName)
    local markerId = dungeonName and config.dungeonMapMarkers[dungeonName]
    if markerId and markerId ~= "" then
        return markerId, false
    end
    return WARP_FALLBACK_MARKER, true
end

function state.offerDungeonWarp(clearedName)
    local markerId, usedFallback = state.resolveWarpMarker(clearedName)
    pendingWarpMarker = markerId
    if usedFallback then
        writeLog("No map marker for dungeon '" .. tostring(clearedName) .. "'; warp fallback " .. markerId, "WARNING")
    end
    local okWarp, errWarp = pcall(function()
        console.ExecuteConsole("set APOfferWarp to 1")
    end)
    if okWarp then
        writeLog("Set APOfferWarp to 1 for dungeon clear: " .. tostring(clearedName) .. " (" .. markerId .. ")")
    else
        writeLog("Failed to set APOfferWarp: " .. tostring(errWarp), "ERROR")
    end
end

function state.applyPlayerKill(enemyData, killerName)
    require("BountyTracking").onKill(enemyData)
    local cellName = getCurrentCellName()
    local cellKillType = getCellKillType()
    local killToken
    if cellKillType == "overworld" then
        killToken = "Overworld Kill"
    elseif cellKillType == "oblivion" then
        killToken = "Oblivion Kill"
    elseif cellKillType == "town" then
        killToken = "Town Kill"
    else
        killToken = "Dungeon Kill"
    end
    local killTypeEnabled = (cellKillType == "overworld" and hasOverworldKillChecks)
                         or (cellKillType == "dungeon" and hasDungeonKillChecks)
                         or (cellKillType == "oblivion" and state.hasOblivionKillChecks)

    local filePrefix = getCurrentFilePrefix()
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local levelStr = enemyData.level and (" Lv" .. enemyData.level) or ""
    local loc = enemyData.location
    local locationStr = ""
    if loc then
        locationStr = string.format(" at %.0f,%.0f,%.0f", loc.X, loc.Y, loc.Z)
    end
    local logLine = string.format("[%s] [%s] %s%s (FormID: %s) killed by %s with %s in %s%s",
        timestamp, killToken, enemyData.name, levelStr, enemyData.formID,
        killerName, enemyData.weaponType or "unknown", cellName, locationStr)

    state.loadKillProgress()
    local credited = true
    if state.weaponLock and (cellKillType == "overworld" or cellKillType == "dungeon" or cellKillType == "oblivion") then
        local category = "unknown"
        if ActorDetection and ActorDetection.WeaponCategory then
            category = ActorDetection.WeaponCategory(enemyData.weaponType)
        end
        if category == "unknown" or not (state.weaponLicenses and state.weaponLicenses[category]) then
            credited = false
            writeLog(string.format(
                "Weapon lock skipped %s kill credit: %s with %s (category=%s)",
                cellKillType, enemyData.name, tostring(enemyData.weaponType), category))
        end
    end
    if killTrackingEnabled and killTypeEnabled and filePrefix and credited then
        local kind = cellKillType
        if kind ~= "overworld" and kind ~= "oblivion" then kind = "dungeon" end
        local need
        if kind == "overworld" then
            need = overworldKillsPerCheck
        elseif kind == "oblivion" then
            need = state.oblivionKillsPerCheck or 2
        else
            need = dungeonKillsPerCheck
        end
        if need < 1 then need = 1 end
        killProgress[kind] = (killProgress[kind] or 0) + 1
        local awarded = 0
        while killProgress[kind] >= need do
            writeCompletionStatus(killToken)
            killProgress[kind] = killProgress[kind] - need
            awarded = awarded + 1
        end
        if awarded > 0 then
            writeLog(string.format(
                "Kill check written (%dx): %s in %s (%s) remainder=%d need=%d",
                awarded, enemyData.name, cellName, killToken, killProgress[kind], need))
        else
            writeLog(string.format("Kill progress %s %d/%d: %s in %s",
                kind, killProgress[kind], need, enemyData.name, cellName))
        end
    elseif not credited then
        writeLog(string.format("Kill logged (weapon lock): %s in %s", enemyData.name, cellName))
    else
        writeLog(string.format("Kill logged (no AP checks configured for %s): %s in %s", killToken, enemyData.name, cellName))
    end
    state.writeKillsFile(logLine)
end

function state.recordPlayerKill(enemyData, killerName)
    if ActorDetection and ActorDetection.IsSummoned(enemyData and enemyData.name) then
        writeLog("Skipped summoned creature kill: " .. tostring(enemyData and enemyData.name))
        return
    end
    if state.cellPending or pendingCellLookup or cellNameRequestPending or cellLookupProbe.awaiting then
        table.insert(state.kills, { enemyData = enemyData, killerName = killerName })
        return
    end
    state.applyPlayerKill(enemyData, killerName)
end

state.flushPendingKills = function()
    if state.cellPending or pendingCellLookup or cellNameRequestPending or cellLookupProbe.awaiting then return end
    if #state.kills == 0 then return end
    local queued = state.kills
    state.kills = {}
    for _, rec in ipairs(queued) do
        state.applyPlayerKill(rec.enemyData, rec.killerName)
    end
end

local function initializeKillTracking()
    writeLog("Initializing kill tracking")

    if not ActorDetection then
        local success, module = pcall(function() return require("ActorDetection") end)
        if not success then
            writeLog("Failed to load ActorDetection module: " .. tostring(module), "ERROR")
            return
        end
        ActorDetection = module
    end

    ActorDetection.SetLog(writeLog)
    ActorDetection.SetTravelling(state.travelling)

    ActorDetection.Initialize(function(enemyData, killer)
        local killerName = "Unknown"
        pcall(function()
            if not killer or not killer:IsValid() then return end
            if killer:IsPlayerCharacter() then
                killerName = "Player"
            else
                local fullName = killer:GetFullName()
                killerName = fullName:match("([^%.]+)$") or fullName
            end
        end)
        if killerName ~= "Player" then return end
        state.recordPlayerKill(enemyData, killerName)
    end)

    writeLog("Kill tracking initialized successfully")
end

function state.applySkillXpMultiplier()
    if skillXpApplied then return end
    local n = tonumber(archipelagoSettings.skill_xp_multiplier) or 1
    if n < 1 then n = 1 end
    if n > 8 then n = 8 end
    if n <= 1 then
        skillXpApplied = true
        return
    end
    -- setgs is not saved, so this is only for this Lua session.
    local major = 0.75 / n
    local minor = 0.88 / n
    local ok, err = pcall(function()
        console.ExecuteConsole(string.format("setgs fskillusemajormult %.6f", major))
        console.ExecuteConsole(string.format("setgs fskilluseminormult %.6f", minor))
    end)
    if ok then
        skillXpApplied = true
        writeLog(string.format(
            "Applied %dx skill XP: fskillusemajormult=%.6f fskilluseminormult=%.6f",
            n, major, minor))
    else
        writeLog("Failed to apply skill XP multiplier: " .. tostring(err), "ERROR")
    end
end

function state.initializeWeaponLicenses()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then
        return
    end
    local initialized = false
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key == "weapon_licenses_initialized" and value == "True" then
            initialized = true
        end
    end
    file:close()
    if initialized or not state.weaponLock then
        return
    end
    local cats = { "blade", "blunt", "bow", "staff", "spell", "unarmed" }
    for _, cat in ipairs(cats) do
        local title = cat:sub(1, 1):upper() .. cat:sub(2)
        local globalName = "APWeaponLicense" .. title .. "Blocked"
        pcall(function()
            console.ExecuteConsole("set " .. globalName .. " to 1")
        end)
        writeLog("Weapon license init: " .. globalName .. " = 1")
    end
    pcall(function()
        console.ExecuteConsole("set APWeaponLicensesOn to 1")
    end)
    writeLog("Weapon licenses enabled - APWeaponLicensesOn set to 1")
    file = io.open(settingsPath, "a")
    if file then
        file:write("weapon_licenses_initialized=True\n")
        file:close()
        writeLog("Marked weapon licenses as initialized in settings file")
    else
        writeLog("Failed to write weapon_licenses_initialized to settings file", "ERROR")
    end
end

-- Main initialization function
function handleInitialization()
    -- Log path override info
    if pathOverrideLoaded then
        writeLog("Path override active - using custom path: " .. ARCHIPELAGO_BASE_DIR)
    end

    -- Retry encumbrance scaling if the object wasn't ready at script load
    if not init.encumbrance then
        applyEncumbranceScaling()
    end

    if not checkValidSession() then return end
    
    local settingsLoaded = loadSettings()
    if not settingsLoaded then
        return
    end

    state.loadKillProgress()
    state.applySkillXpMultiplier()

    local MapPins = require("MapPins")
    MapPins.bind({
        writeLog = writeLog,
        getArchipelagoPath = getArchipelagoPath,
        getCurrentFilePrefix = getCurrentFilePrefix,
        getSelectedRegionDungeons = getSelectedRegionDungeons,
        getSelectedRegions = getSelectedRegions,
        isRegionUnlocked = isRegionUnlockedViaReceipts,
    })
    MapPins.reset()

    local BountyTracking = require("BountyTracking")
    BountyTracking.bind({
        writeLog = writeLog,
        getArchipelagoPath = getArchipelagoPath,
        getCurrentFilePrefix = getCurrentFilePrefix,
        isCompletionAlreadyRecorded = isCompletionAlreadyRecorded,
        writeCompletionStatus = writeCompletionStatus,
        getCurrentCellName = getCurrentCellName,
        getCellKillType = getCellKillType,
        getDungeonMarkerMode = function()
            return archipelagoSettings.dungeon_marker_mode
        end,
        isCellLookupPending = function()
            return pendingCellLookup or cellNameRequestPending
        end,
        offerDungeonWarp = state.offerDungeonWarp,
        getBountyProgress = state.getBountyProgress,
        markBountyProgressReady = function()
            state.bountyProgressReady = true
        end,
    })
    BountyTracking.loadState()
    do
        local prefix = getCurrentFilePrefix()
        if prefix then
            local bountyFile = io.open(getArchipelagoPath(prefix .. "_bounty.txt"), "r")
            if bountyFile then
                bountyFile:close()
                state.writeKillsFile(nil)
            end
        end
    end
    initializeKillTracking()

    -- mod_fully_initialized only means goal globals were written. Any missed or needed
    -- inits still run.
    local continuingSession = init.modFully
    
    -- Handle initialization tasks (only once, when safe to run console commands)
    if init.needsShopStock then
        writeLog("Initializing progressive shop stock...")
        init.needsShopStock = false
        local success, error = pcall(initializeShopsanity)
        if success then
            init.shopStock = true
            writeLog("Progressive shop stock initialization successful")
        else
            writeLog("Progressive shop stock initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsArena then
        writeLog("Initializing arena...")
        init.needsArena = false
        local success, error = pcall(initializeArena)
        if success then
            init.arena = true
            writeLog("Arena initialization successful")
        else
            writeLog("Arena initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsShrines then
        writeLog("Initializing shrines...")
        init.needsShrines = false
        local success, error = pcall(initializeShrines)
        if success then
            init.shrines = true
            writeLog("Shrine initialization successful")
        else
            writeLog("Shrine initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsSidequests then
        writeLog("Initializing sidequests...")
        init.needsSidequests = false
        local success, error = pcall(initializeSidequests)
        if success then
            init.sidequests = true
            writeLog("Sidequest initialization successful")
        else
            writeLog("Sidequest initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsGates then
        init.needsGates = false
        local success, error = pcall(initializeGates)
        if success then
            init.gates = true
            writeLog("Oblivion Gate initialization complete")
        else
            writeLog("Gates initialization failed: " .. tostring(error), "ERROR")
        end
    end

    if init.needsDoomstones then
        init.needsDoomstones = false
        local success, error = pcall(initializeDoomstones)
        if success then
            init.doomstones = true
            writeLog("Doomstone initialization complete")
        else
            writeLog("Doomstones initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsGateVision and init.gates then
        init.needsGateVision = false
        local success, error = pcall(initializeGateVision)
        if success then
            init.gateVision = true
            writeLog("Gate vision initialization successful")
        else
            writeLog("Gate vision initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsFastTravel then
        writeLog("Initializing fast travel...")
        init.needsFastTravel = false
        local success, error = pcall(initializeFastTravel)
        if success then
            init.fastTravel = true
            writeLog("Fast travel initialization successful")
        else
            writeLog("Fast travel initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if init.needsClassSystem then
        writeLog("Initializing class system...")
        init.needsClassSystem = false
        local success, error = pcall(initializeClassSystem)
        if success then
            init.classSystem = true
            writeLog("Class system initialization successful")
        else
            writeLog("Class system initialization failed: " .. tostring(error), "ERROR")
        end
    end

    if init.needsDungeonCounters then
        writeLog("Initializing dungeon counters...")
        init.needsDungeonCounters = false
        local success, error = pcall(initializeDungeonCounters)
        if success ~= false then -- initializeDungeonCounters returns nil on success
            init.dungeonCounters = true
            writeLog("Dungeon counters initialization successful")
        else
            writeLog("Dungeon counters initialization failed: " .. tostring(error), "ERROR")
        end
    end

    if init.needsBounties then
        writeLog("Initializing bounty contracts...")
        init.needsBounties = false
        local success, error = pcall(function()
            require("BountyTracking").initialize()
        end)
        if success ~= false then
            init.bounties = true
            writeLog("Bounty initialization successful")
        else
            writeLog("Bounty initialization failed: " .. tostring(error), "ERROR")
        end
    end

    if init.needsWeaponLicenses then
        writeLog("Initializing weapon licenses...")
        init.needsWeaponLicenses = false
        local success, error = pcall(state.initializeWeaponLicenses)
        if success then
            init.weaponLicenses = true
            writeLog("Weapon license initialization successful")
        else
            writeLog("Weapon license initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    -- Set goal globals and mark initialization complete (only once per seed)
    if continuingSession then
        writeLog("------------------------------------------")
        writeLog("Settings file validated: already initialized. Pending subsystem inits already complete.")
        writeLog("------------------------------------------")
        state.pinsNeedRestore = true
        if currentCellName and currentCellName ~= "" and not state.travelling then
            state.pinsRestoreArmed = true
        end
        return
    end
    if not init.modFully then
        -- Validate currentGoal is set before attempting
        if currentGoal == "" then
            writeLog("Cannot initialize - no goal found in settings", "ERROR")
            return
        end
        
        -- Set goal-specific global variables based on goal type
        local success = pcall(function()
            if currentGoal == "shrine_seeker" and goalRequired > 0 then
                console.ExecuteConsole("set APShrineVictoryGoal to " .. tostring(goalRequired))
                writeLog("Set APShrineVictoryGoal to " .. tostring(goalRequired))
            elseif currentGoal == "gatecloser" and goalRequired > 0 then
                console.ExecuteConsole("set APGateVictoryGoal to " .. tostring(goalRequired))
                writeLog("Set APGateVictoryGoal to " .. tostring(goalRequired))
            elseif currentGoal == "dungeon_delver" and goalRequired > 0 then
                console.ExecuteConsole("set APDungeonVictoryGoal to " .. tostring(goalRequired))
                writeLog("Set APDungeonVictoryGoal to " .. tostring(goalRequired))
            elseif currentGoal == "nirnsanity" and goalRequired > 0 then
                console.ExecuteConsole("set APNirnrootVictoryGoal to " .. tostring(goalRequired))
                writeLog("Set APNirnrootVictoryGoal to " .. tostring(goalRequired))
            elseif currentGoal == "treasure_hunter" and goalRequired > 0 then
                console.ExecuteConsole("set APTreasureVictoryGoal to " .. tostring(goalRequired))
                writeLog("Set APTreasureVictoryGoal to " .. tostring(goalRequired))
            end
            
            -- Set APNirnrootCount for non-nirnsanity goals when nirnroot locations are enabled
            if currentGoal ~= "nirnsanity" then
                local filePrefix = getCurrentFilePrefix()
                local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
                local settingsFile = io.open(settingsPath, "r")
                if settingsFile then
                    for line in settingsFile:lines() do
                        local k, v = line:match("^(.-)=(.*)$")
                        if k == "nirnroot_count" then
                            local count = tonumber(v) or 0
                            if count > 0 then
                                console.ExecuteConsole("set APNirnrootCount to " .. tostring(count))
                                writeLog("Set APNirnrootCount to " .. tostring(count) .. " (non-nirnsanity nirnroot locations)")
                            end
                            break
                        end
                    end
                    settingsFile:close()
                end
            end
            
            -- Set goal type global - this triggers the correct quest in-game
            if currentGoal == "arena" then
                console.ExecuteConsole("set APGoal to 1")
            elseif currentGoal == "gatecloser" then
                console.ExecuteConsole("set APGoal to 2")
            elseif currentGoal == "shrine_seeker" then
                console.ExecuteConsole("set APGoal to 3")
            elseif currentGoal == "dungeon_delver" then
                console.ExecuteConsole("set APGoal to 4")
            elseif currentGoal == "light_the_dragonfires" then
                console.ExecuteConsole("set APGoal to 5")
            elseif currentGoal == "nirnsanity" then
                console.ExecuteConsole("set APGoal to 6")
            elseif currentGoal == "treasure_hunter" then
                console.ExecuteConsole("set APGoal to 7")
            elseif currentGoal == "bounty_hunter" then
                console.ExecuteConsole("set APGoal to 8")
            end
            if archipelagoSettings.ap_tips then
                console.ExecuteConsole("set APTipsEnabled to 1")
                writeLog("Set APTipsEnabled to 1")
            end
        end)
        
        if not success then
            writeLog("Failed to set goal globals", "ERROR")
            pcall(function()
                console.ExecuteConsole("MessageBox \"Failed to set Archipelago goal. Please reload your save.\"")
            end)
            return  -- Don't mark as initialized if goal setting failed
        end
        
        -- Mark as fully initialized
        init.modFully = true
        writeLog("")
        writeLog("==========================================")
        writeLog("ARCHIPELAGO MOD INITIALIZATION COMPLETE")
        writeLog("==========================================")
        writeLog("")
        
        -- Write to settings file
        local filePrefix = getCurrentFilePrefix()
        local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
        local file = io.open(settingsPath, "a")
    if file then
            file:write("mod_fully_initialized=True\n")
            file:close()
            writeLog("Successfully wrote mod_fully_initialized to settings file")
        else
            writeLog("Failed to write mod_fully_initialized to settings file", "ERROR")
        end
        -- After a fresh initialization, treat the next APAppliedCount=0 as a catch-up, not a reinit prompt
        suppressReinitOnNextZero = true
    end
end

function state.drainBridgeFiles()
    if not init.modFully then
        return
    end
    if not init.itemProcessingEnabled then
        init.initializationCompleteTime = os.time()
        init.itemProcessingEnabled = true
        writeLog("Initialization complete - starting 3-second delay before item processing")
        return
    end
    if (os.time() - init.initializationCompleteTime) < 3 then
        return
    end

    processItemEvents()

    if probeFinished and hasItemsInQueue() then
        processItemQueue()
    end

    processTrapQueue()
    processDeathlinkSignal()
    processMessageboxQueue()
end

function state.handlePeriodicProcessing()
    state.drainBridgeFiles()

    local now = os.clock()
    if now < state.nextSessionAt then
        return
    end
    state.nextSessionAt = now + 5

    local sessionValid = checkValidSession()
    if sessionValid and not state.allowAPSync then
        writeLog("Valid AP session detected mid-game")
        state.allowAPSync = true
        state.probeStartedForSession = false
    elseif not sessionValid then
        state.allowAPSync = false
        state.probeStartedForSession = false
    end

    if (not init.modFully) or (not sessionValid) then
        handleInitialization()
    end

    if init.encumbrance then
        local currentTime = os.time()
        if currentTime - lastEncumbranceValidation >= ENCUMBRANCE_VALIDATION_INTERVAL then
            lastEncumbranceValidation = currentTime
            validateEncumbranceScaling()
        end
    end

    if state.allowAPSync and init.modFully and not probeFinished and not apProbe.awaiting and not state.probeStartedForSession
        and not menuCheckInProgress()
        and not state.fadeWorldSetup
        and not pendingCellLookup
        and not cellLookupProbe.awaiting
        and not state.cellPending
        and not cellNameRequestPending
        and not state.apSyncOnStable then
        state.probeStartedForSession = true
        writeLog("Starting APSync probe (post-init)")
        startAPSyncProbe()
    end
end

function state.ensureTutorialHooks()
    if not setupNewDisplayHooked then
        local success = pcall(function()
            RegisterHook("Function /Game/UI/Modern/HUD/Tutorial/WBP_ModernTutorialDisplay.WBP_ModernTutorialDisplay_C:SetupNewDisplay", InterceptTutorialDisplay)
        end)
        if success then
            writeLog("Successfully hooked SetupNewDisplay")
            setupNewDisplayHooked = true
        end
    end
    if not setMenuModeHooked then
        local success = pcall(function()
            RegisterHook("Function /Game/UI/Modern/HUD/Tutorial/WBP_ModernTutorialDisplay.WBP_ModernTutorialDisplay_C:SetMenuMode", function(context)
                local widget = context:get()
                if not widget or not widget:IsValid() then return end
                local inMenuNow = false
                local okMenu, resMenu = pcall(IsPlayerInMenu)
                if okMenu then inMenuNow = resMenu end

                if inMenuNow then
                    local isActive = false
                    pcall(function()
                        if widget.CurrentDisplayTime and widget.CurrentDisplayTime > 0.0 then isActive = true end
                    end)
                    state.expireAPTutorialFallbackIfNeeded()
                    if isActive and lastAPTutorialMessage ~= "" then
                        pcall(function()
                            console.ExecuteConsole("Message \"" .. escapeForConsole(lastAPTutorialMessage) .. "\"")
                        end)
                        lastAPTutorialMessage = ""
                    end
                    CloseTutorialByTimeSqueeze(widget)
                    HardHideTutorialWidget(widget)
                end
            end)
        end)
        if success then
            writeLog("Successfully hooked SetMenuMode")
            setMenuModeHooked = true
        end
    end
end

function state.runPeriodicModWork()
    if state.isWorldUnstable() then
        state.loggedSkip = true
        return
    end
    state.loggedSkip = false

    if pendingTrackingToggle then
        pendingTrackingToggle = false
        if not nirnrootTrackingEnabled and not bossChestTrackingEnabled then
            autoTrackManualOff = false
            local canNirn = nirnrootInSeed and not nirnrootManualOff
            local canChest = chestInSeed
            if canNirn then
                nirnrootTrackingEnabled = true
                lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
                lastTrackingUpdate = 0
                pcall(function() console.ExecuteConsole('Message "Tracking Nirnroot"') end)
            elseif canChest then
                tryEnableChestTrackingForCurrentCell()
                if bossChestTrackingEnabled then
                    pcall(function() console.ExecuteConsole('Message "Tracking Boss Chests"') end)
                else
                    autoTrackManualOff = true
                    clearAPXMarker()
                    pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
                end
            else
                autoTrackManualOff = true
                clearAPXMarker()
                pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
            end
        elseif nirnrootTrackingEnabled then
            nirnrootTrackingEnabled = false
            if chestInSeed then
                clearAPXMarker()
                tryEnableChestTrackingForCurrentCell()
                if bossChestTrackingEnabled then
                    pcall(function() console.ExecuteConsole('Message "Tracking Boss Chests"') end)
                else
                    autoTrackManualOff = true
                    pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
                end
            else
                autoTrackManualOff = true
                clearAPXMarker()
                pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
            end
        else
            bossChestTrackingEnabled = false
            autoTrackManualOff = true
            clearAPXMarker()
            pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
        end
    end

    state.handlePeriodicProcessing()

    state.readCellLookupConsole()
    state.expireCellLookupIfStuck()
    processPendingMenuReinitCheck()
    apReadConsoleAndEmitCount()
    state.processPendingFadeActions()
    state.ensureTutorialHooks()
    state.expireAPTutorialFallbackIfNeeded()
    state.processTutorialQueue()

    if not state.isWorldUnstable() then
        state.runQueuedNirnrootRedetect()
        if nirnrootTrackingEnabled or bossChestTrackingEnabled then
            updatePeriodicTracking()
        end
        require("BountyTracking").updateTracking()

        local isFreezing = isGameFreezing()
        if isFreezing and not lastFreezeState then
            local widget = getTutorialWidget()
            state.expireAPTutorialFallbackIfNeeded()
            if widget and widget.IsValid and widget:IsValid() and lastAPTutorialMessage ~= "" then
                local isActive = false
                pcall(function()
                    if widget.CurrentDisplayTime and widget.CurrentDisplayTime > 0.0 then isActive = true end
                end)
                if isActive then
                    pcall(function()
                        console.ExecuteConsole("Message \"" .. escapeForConsole(lastAPTutorialMessage) .. "\"")
                    end)
                    lastAPTutorialMessage = ""
                end
            end
            CloseTutorialByTimeSqueeze(widget)
            HardHideTutorialWidget(widget)
        end
        lastFreezeState = isFreezing
    end
end

function state.startPeriodicLoop()
    if state.started then return end
    state.started = true
    RegisterHook("/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C:ReceiveTick", function()
        if pendingIcarianFlight then
            pendingIcarianFlight = false
            pcall(executeIcarianLaunch)
        end
        local now = os.clock()
        if now < state.nextPeriodAt then
            return
        end
        state.nextPeriodAt = now + (state.periodMs / 1000)
        local ok, err = pcall(state.runPeriodicModWork)
        if not ok then
            writeLog("Periodic tick error: " .. tostring(err), "ERROR")
        end
    end)
    writeLog("Tick hook registered for ongoing processing (2026-08-25-B)")
end

RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToBlackBeginEventReceived", function()
    state.markTravelling("fade-to-black")
end)

RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToBlackOverBeforeFastTravel", function()
    state.markTravelling("fade-to-black-fast-travel")
end)

state.tryRegisterHook("/Script/Altar.VEnhancedAltarPlayerController:OnLoadStarted", function()
    state.markTravelling("load-started")
    -- Save load can reset AP pin refs to ESP defaults. Re-place in Tamriel only.
    state.pinsNeedRestore = true
    state.pinsRestoreArmed = false
end, "OnLoadStarted")

state.tryRegisterHook("/Script/Altar.VEnhancedAltarPlayerController:OnLoadFinished", function()
    writeLog("Load finished (waiting for fade-to-game to resume)")
end, "OnLoadFinished")

state.tryRegisterHook("/Script/Altar.VDoor:OnBeginOverlapPreLoadBox", function()
    state.markTravelling("door-preload")
end, "VDoor:OnBeginOverlapPreLoadBox")

RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToGameBeginEventReceived", function()
    state.markArrived("fade-to-game")

    -- Reset probe state for this load
    probeFinished = false
    state.probeStartedForSession = false
    probeAttemptCount = 0  -- Reset attempt counter on each load
    pendingMenuReinitCheck = false
    menuCheckProbe.awaiting = false

    state.fadeWorldSetup = true
    state.apSyncOnStable = true
    state.cellPending = true

    if killTrackingEnabled and ActorDetection then
        ActorDetection.ClearKilledActors()
    end

    if not state.gameStarted then
        writeLog("Game fade-in detected")
        state.gameStarted = true
        if not init.modFully then
            writeLog("No init flags in memory. Reading settings file.")
            handleInitialization()
        else
            writeLog("------------------------------------------")
            writeLog("Settings file validated: already initialized. No initialization will run.")
            writeLog("------------------------------------------")
        end
        state.startPeriodicLoop()
    end
    
    -- Register notification hook for event tracking (guard to prevent duplicates)
        if not state.notificationHookRegistered then
        RegisterHook("Function /Script/Altar.VHUDSubtitleViewModel:ConsumeNotification", function(hudVM)
            if not hudVM then
                return
            end
            
            local success, actualHudVM = pcall(function()
                return hudVM:get()
            end)
            
            if not success or not actualHudVM.Notification then
                return
            end
            
            local textSuccess, text = pcall(function()
                return actualHudVM.Notification.Text:ToString()
            end)
            
            if not textSuccess then
                return
            end

            -- Shorten vanilla inventory add notifications.
            -- Completion tokens are checks and must fall through to the handler below.
            -- During a bulk grant, keep the toast visible but much shorter so the queue can drain.
            local inventoryText = text
                :gsub("\226\128[\152\153]", "'")
                :gsub("\194\180", "'")
                :gsub("\239\188\135", "'")
                :gsub("`", "'")
            if inventoryText:match("^%d+ .- added to the player's inventory$")
               and not inventoryText:match("Completion Token added to the player's inventory") then
                pcall(function()
                    local original = tonumber(actualHudVM.Notification.ShowSeconds)
                    if original and original > 0.5 and not loggedInventoryNotifyDefault then
                        loggedInventoryNotifyDefault = true
                        writeLog("Vanilla inventory notification duration: " .. tostring(original) .. "s")
                    end
                    actualHudVM.Notification.ShowSeconds = bulkItemGrantInProgress and 0.45 or 1
                end)
                return
            end
            
            -- intercept our probe command and fetch APAppliedCount
            if text == 'ConsoleCommand Message AP_SYNC COUNT ((GetGlobalValue APAppliedCount))' then
                if not probeFinished and not apProbe.awaiting then
                    startAPSyncProbe()
                end
                actualHudVM.Notification.ShowSeconds = 0.0001
                return
            end
            
            if isAPItemEventNotification(text) then
                return
            end

            -- sent by the .esp after state checks for the icarian flight trap
            if text == "APExecuteIcarianFlight" then
                actualHudVM.Notification.ShowSeconds = 0.0001
                DoIcarianFlightTrap()
                return
            end

            if text == "Warp accepted" then
                actualHudVM.Notification.ShowSeconds = 0.0001
                local marker = pendingWarpMarker
                if not marker or marker == "" then
                    local clearedName = state.lastClearedDungeonFromCompletions()
                    local usedFallback
                    marker, usedFallback = state.resolveWarpMarker(clearedName)
                    if usedFallback then
                        writeLog("Warp accepted with no stored marker; dungeon='" .. tostring(clearedName) .. "' fallback " .. marker, "WARNING")
                    else
                        writeLog("Warp accepted after reload; restored marker for '" .. tostring(clearedName) .. "'")
                    end
                end
                pendingWarpMarker = nil
                local ok, err = pcall(function()
                    console.ExecuteConsole("player.moveto " .. marker)
                end)
                if ok then
                    writeLog("Dungeon warp accepted -> player.moveto " .. marker)
                else
                    writeLog("Dungeon warp moveto failed: " .. tostring(err), "ERROR")
                end
                return
            end

            if text == "Warp refused" then
                actualHudVM.Notification.ShowSeconds = 0.0001
                pendingWarpMarker = nil
                writeLog("Dungeon warp refused")
                return
            end

            -- Disable nirnroot auto-tracking only (Nirnsanity satchel full).
            if text == "APAutoTrackNirnOff" then
                actualHudVM.Notification.ShowSeconds = 0.0001
                nirnrootManualOff = true
                nirnrootTrackingEnabled = false
                if not bossChestTrackingEnabled then
                    clearAPXMarker()
                end
                writeLog("Nirnroot auto-tracking disabled via APAutoTrackNirnOff message")
                return
            end

            -- Re-enable nirnroot tracking only
            if text == "APAutoTrackNirnOn" then
                actualHudVM.Notification.ShowSeconds = 0.0001
                nirnrootManualOff = false
                -- Only start scanning if auto_tracking is on and global OFF is not set,
                -- and we're not currently in a dungeon/boss-chest cell.
                if archipelagoSettings.auto_tracking and not autoTrackManualOff and not bossChestTrackingEnabled then
                    nirnrootTrackingEnabled = true
                    lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
                    lastTrackingUpdate = 0
                end
                writeLog("Nirnroot auto-tracking re-enabled via APAutoTrackNirnOn message")
                return
            end

            -- AP sync messages
            do
                local countStr = text:match("^AP_SYNC COUNT (%d+)$")
                if countStr and not probeFinished then
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    local ingameCount = tonumber(countStr) or 0
                    lastIngameAPAppliedCount = ingameCount
                    local diskCount = getBridgeStatusAPCount()
                    local diff = diskCount - ingameCount
                    if diff ~= 0 then
                        writeLog("AP sync count received - in-game: " .. tostring(ingameCount) .. ", bridge status: " .. tostring(diskCount) .. ", diff: " .. tostring(diff))
                    end
                    -- Use APSync Probe to determine if game is new -- If we see ingamecount of 0, this is a new save
                    -- If this is the first time seeing 0, we auto-init if not already initialized
                    -- If this is a subsequent 0, we check settings and if we see they were previously initialized, prompt for reinit
                    -- This handles a situation where a player makes a new character or loads a wrong save
                    if ingameCount == 0 then
                        -- If we just reinitialized, skip reinit logic once to allow APSync catch-up (0 vs receipts)
                        if suppressReinitOnNextZero then
                            writeLog("Skipping reinit re-prompt; forcing APSync catch-up of diff=" .. tostring(diff))
                            suppressReinitOnNextZero = false
                            if diff > 0 then
                                local removed = truncateBridgeStatusTail(diff)
                                pcall(function()
                                    console.ExecuteConsole("Message \"APSync: requesting resend of " .. tostring(removed) .. " items\"")
                                end)
                            end
                            probeFinished = true
                            return
                        end
                        -- Refresh settings to learn disk-initialized state for the current prefix
                        pcall(function() loadSettings() end)
                        if init.modFully then
                            if reinitPending then
                                writeLog("APAppliedCount=0 with reinit already pending; waiting for player response")
                                return
                            end
                            local ok = pcall(function()
                                console.ExecuteConsole("set APReinitRequest to 1")
                            end)
                            if ok then
                                writeLog("Requested reinit confirmation for this save (APReinitRequest=1) due to APAppliedCount=0 with prior initialization")
                                reinitPending = true
                            end
                            return
                        else
                            -- Not initialized yet for this seed: perform initialization now
                            writeLog("APAppliedCount=0 and settings indicate not initialized; performing initialization")
                            handleInitialization()
                            -- Continue into normal diff handling below
                        end
                    end
                    -- in-game has more than disk; warn the user but allow processing
                    if ingameCount > diskCount then
                        writeLog("Save has " .. tostring(ingameCount) .. " items but AP session only has " .. tostring(diskCount) .. " - warning user", "WARNING")
                        pcall(function()
                            console.ExecuteConsole("MessageBox \"Warning: This save has more AP items than your connected session. Load a matching save or reconnect to this save's slot/seed.\"")
                        end)
                        probeFinished = true  -- Probe completed; user has been warned
                        return
                    end
                    if diff > 0 and diff <= 20 then
                        local removed = truncateBridgeStatusTail(diff)
                        pcall(function()
                            console.ExecuteConsole("Message \"APSync: requesting resend of " .. tostring(removed) .. " items\"")
                        end)
                        probeFinished = true
                        probeAttemptCount = 0  -- Reset attempt counter
                        return
                    elseif diff > 20 then
                        pcall(function()
                            console.ExecuteConsole("set APSyncRequest to 1")
                        end)
                        return
                    else
                        probeFinished = true
                        probeAttemptCount = 0  -- Reset attempt counter
                        return
                    end
                end

                if text == "AP_SYNC APPROVED" and not probeFinished then
                    -- Compute the diff at the time of approval and request exactly that many
                    local diskCount = getBridgeStatusAPCount()
                    local ingameCount = tonumber(lastIngameAPAppliedCount or 0) or 0
                    local diff = diskCount - ingameCount
                    if diff > 0 then
                        local removed = truncateBridgeStatusTail(diff)
                        pcall(function()
                            console.ExecuteConsole("Message \"APSync: requesting resend of " .. tostring(removed) .. " items\"")
                        end)
                    else
                        writeLog("AP sync approval received but no diff to resend", "DEBUG")
                    end
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    probeFinished = true
                    probeAttemptCount = 0  -- Reset attempt counter
                    return
                end

                if text == "AP_SYNC DENIED" and not probeFinished then
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    writeLog("AP sync large resend denied by player")
                    probeFinished = true
                    probeAttemptCount = 0  -- Reset attempt counter
                    return
                end

                -- Handle reinit confirmation via in-game dialog
                if text == 'AP_REINIT APPROVED' and reinitPending then
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    resetSettings()
                    reinitPending = false
                    return
                end
                if text == 'AP_REINIT DENIED' and reinitPending then
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    writeLog('AP reinit denied by player')
                    reinitPending = false
                    -- Ensure probe completes so item processing can proceed
                    probeFinished = true
                    probeAttemptCount = 0  -- Reset attempt counter
                    -- Suppression for this save is persisted by the in-game script via APDisabled=1
                    return
                end
            end
            
            -- Handle dungeon mapping fallback notice from in-game script
            if text == "Dungeon Mapping not found or unsupported Dungeon" then
                -- Hide the notification and log quietly
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                writeLog("Dungeon Mapping not found or unsupported Dungeon", "DEBUG")
                return
            end
            
            -- Handle quest/shrine completion notifications
            local completionMatch = text:match("^%d+ AP (.+) Completion Token added to the player's inventory$")
                                   or text:match("^AP (.+) Completion Token added to the player's inventory$")
            if completionMatch then
                -- Hide the completion notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Convert shrine name to match the expected EDID format
                local shrineName = completionMatch:gsub("%s+", "")  -- Remove spaces
                local completionTokenEdid = "AP" .. shrineName .. "CompletionToken"
                writeCompletionStatus(completionTokenEdid)
                
                -- Remove the corresponding unlock token from inventory
                local unlockTokenEdid = config.unlockToCompletionMapping[completionTokenEdid]
                if unlockTokenEdid then
                    local removeCommand = "player.removeitem " .. unlockTokenEdid .. " 1"
                    local removeSuccess, removeResult = pcall(function()
                        console.ExecuteConsole(removeCommand)
                    end)
                    
                    if removeSuccess then
                        writeLog("Removed unlock token: " .. unlockTokenEdid)
                    end
                end
                return
            end

            -- Handle Arena win notifications
            local arenaWinNumber = text:match("Arena Win (%d+)")
            if arenaWinNumber then
                local winNum = tonumber(arenaWinNumber)
                if winNum and winNum >= 1 and winNum <= 21 then
                    -- Hide the notification
                    local setShowSuccess, setShowResult = pcall(function()
                        actualHudVM.Notification.ShowSeconds = 0.0001
                    end)
                    
                    -- Write completion status for this Arena win
                    local completionEdid = "APArenaMatch" .. arenaWinNumber .. "Victory"
                    writeCompletionStatus(completionEdid)
                    writeLog("Arena match completed: Arena Win " .. arenaWinNumber)
                    return
                end
            end

            -- Handle Arena Grand Champion notification
            if text == "Arena Grand Champion Victory" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                -- Write Victory to completion file
                writeCompletionStatus("Victory")
                writeLog("Arena Victory written to completion file")
                return
            end

            -- Handle shop token notifications
            local shopTokenValue = text:match("AP Shop Token Value (%d+) Acquired")
            if shopTokenValue then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Remove the corresponding shop check items from all merchant chests
                local shopCheckEdid = "APShopCheckValue" .. shopTokenValue
                for _, chestRef in ipairs(config.merchantChests) do
                    local removeCommand = chestRef .. ".RemoveItem " .. shopCheckEdid .. " 999"
                    console.ExecuteConsole(removeCommand)
                end
                writeLog("Removed all " .. shopCheckEdid .. " from all merchant chests")
                
                -- Write completion status for this shop token
                local completionTokenEdid = "APShopTokenValue" .. shopTokenValue .. "CompletionToken"
                writeCompletionStatus(completionTokenEdid)
                writeLog("Shop Token check triggered for value: " .. shopTokenValue)
                return
            end

            -- Handle player death for deathlink
            if text == "Death" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Write deathlink to completion file
                writeCompletionStatus("Deathlink")
                writeLog("Death detected - Deathlink sent to client")
                return
            end

            -- Handle Oblivion Gate closure notifications
            if text == "Oblivion Gate Closed" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Write completion status for Oblivion Gate closure
                writeCompletionStatus("Oblivion Gate Closed")
                writeLog("Oblivion Gate Closed")
                return
            end

            -- Check for dungeon   messages
            if text:match("Dungeon Cleared") then
                -- Hide the notification
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)

                -- Extract dungeon name from the HUD text "<Name> Dungeon Cleared"
                local clearedName = text:match("^(.+)%s+Dungeon Cleared$") or text
                -- Trim whitespace
                clearedName = (clearedName or ""):match("^%s*(.-)%s*$")
                writeLog("Parsed dungeon cleared name: '" .. tostring(clearedName) .. "'")

                -- Seed dungeon checks only. Bounty warps are offered from Lua when the
                -- contract completes; they do not wait on CK Dungeon Cleared.
                local regionName = findRegionForDungeon(clearedName)
                if regionName then
                    bossChestTrackingEnabled = false
                    clearAPXMarker()
                    writeLog("Stopped boss-chest autotrack after Dungeon Cleared: " .. clearedName)
                end
                if regionName and isRegionUnlockedViaReceipts(regionName) then
                    if isCompletionAlreadyRecorded(text) then
                        writeLog("Duplicate dungeon clear detected, ignoring: " .. clearedName, "DEBUG")
                    else
                        writeCompletionStatus(text)
                        writeLog("Validated Dungeon Cleared: " .. clearedName .. " (Region: " .. regionName .. ")")

                        local regionVar = "AP" .. regionName:gsub("%W", "") .. "DungeonCount"
                        local decCmd = "set " .. regionVar .. " to " .. regionVar .. " - 1"
                        local okDec, errDec = pcall(function()
                            console.ExecuteConsole(decCmd)
                        end)
                        if okDec then
                            writeLog("Decremented " .. regionVar .. " by 1")
                        else
                            writeLog("Failed to decrement " .. regionVar .. ": " .. tostring(errDec), "ERROR")
                        end
                        require("MapPins").recycleRegionDungeonPin(regionName, clearedName)
                        state.offerDungeonWarp(clearedName)
                    end
                else
                    if regionName then
                        writeLog("Dungeon Clear ignored (region locked): '" .. tostring(clearedName) .. "' in region '" .. tostring(regionName) .. "'", "DEBUG")
                    else
                        writeLog("Dungeon Clear ignored (not a seed dungeon check): '" .. tostring(clearedName) .. "'", "DEBUG")
                    end
                end
                return
            end
            
            
            local skillName, skillIndex = text:match("^([%a%s%-]+) Skill Increase (%d+)$")
            if not skillName then
                skillName = text:match("^([%a%s%-]+) Skill Increase$")
            end
            if skillName then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Report the specific skill increase
                writeCompletionStatus(skillName .. " Skill Increase")
                if skillIndex then
                    writeLog("Skill Increase: " .. skillName .. " " .. tostring(skillIndex))
                else
                    writeLog("Skill Increase: " .. skillName)
                end
                return
            end

            -- Handle sidequest completion messages
            if config.sidequestMappings[text] then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Write completion status for this sidequest
                writeCompletionStatus(text)
                writeLog("Sidequest completed: " .. text)
                return
            end


            -- Check for ayleid well visited messages
            if text == "Ayleid Well Visited" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                writeCompletionStatus("Ayleid Well Visited")
                writeLog("Ayleid Well Visited")
                return
            end

            -- Doomstones: "<Name> Doomstone Visited"
            do
                local baseName = text:match('^(.+) Doomstone Visited$')
                if baseName then
                    pcall(function()
                        actualHudVM.Notification.ShowSeconds = 0.0001
                    end)
                    local stoneKey = baseName .. " Stone" -- config key
                    local region = (config.doomstoneRegions or {})[stoneKey]
                    if region then
                        if areRegionsDisabled() or isRegionUnlockedViaReceipts(region) then
                            local completionMessage = text -- write exactly what we read
                            writeCompletionStatus(completionMessage)
                            writeLog('Birthsign Stone visited (accepted): ' .. text .. ' -> completion="' .. completionMessage .. '" (Region: ' .. region .. ')')
                        else
                            writeLog('Birthsign Stone visit ignored (region locked): ' .. baseName .. ' (Region: ' .. region .. ')', 'DEBUG')
                        end
                    else
                        writeLog('Birthsign Stone visit unrecognized: ' .. baseName, 'WARNING')
                    end
                    return
                end
            end
            
            -- Handle Shrine Seeker Victory message
            if text == "Shrine Seeker Victory" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Write Victory to completion file
                writeCompletionStatus("Victory")
                writeLog("Shrine Seeker Victory written to completion file")
                
                return
            end
            
            -- Handle Gatecloser Victory message
            if text == "Gatecloser Victory" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Write Victory to completion file
                writeCompletionStatus("Victory")
                writeLog("Gatecloser Victory written to completion file")
                
                return
            end

            -- Handle gold collection milestone messages (Treasure Hunter)
            local goldAmount = text:match("^(%d+) Gold Collected$")
            if goldAmount then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)

                writeCompletionStatus(goldAmount .. " Gold Collected")
                writeLog("Gold milestone recorded: " .. goldAmount .. " Gold Collected")
                return
            end

            local fenceAmount = text:match("^Black Market: (%d+) Gold Fenced$")
            if fenceAmount then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                writeCompletionStatus(text)
                writeLog("Black Market fence recorded: " .. text)
                return
            end
            
            -- Handle Nirnroot harvest messages
            if text == "Nirnroot Harvested" then
                -- Hide the notification
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Send check to client
                writeCompletionStatus("Nirnroot Harvested")
                writeLog("Nirnroot Harvested check sent to client")
                state.redetectNirnrootAfterHarvest()
                
                return
            end
            
            -- Additional Nirnroot harvest messages (non nirnsanity?)
            if text == "You successfully harvest Nirnroot." then
                -- Hide the notification
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Send check to client
                writeCompletionStatus("Nirnroot Harvested")
                writeLog("Nirnroot Harvested check sent to client")
                state.redetectNirnrootAfterHarvest()
                
                return
            end
            
            -- Handle Nirnsanity Victory message
            if text == "Nirnsanity Victory" then
                -- Hide the notification
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Write Victory to completion file
                writeCompletionStatus("Victory")
                writeLog("Nirnsanity Victory written to completion file")
                
                return
            end

            -- Handle Treasure Hunter Victory message
            if text == "Treasure Hunter Victory" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                writeCompletionStatus("Victory")
                writeLog("Treasure Hunter Victory written to completion file")
                return
            end

            -- Handle Bounty Hunter Victory message
            if text == "Bounty Hunter Victory" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                writeCompletionStatus("Victory")
                writeLog("Bounty Hunter Victory written to completion file")
                return
            end

            -- Main Quest Milestones
            if text == "Deliver the Amulet" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                writeCompletionStatus("Deliver the Amulet")
                writeLog("Deliver the Amulet milestone recorded")
                return
            end
            if text == "Breaking the Siege of Kvatch: Gate Closed" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Breaking the Siege of Kvatch: Gate Closed")
                writeLog("Breaking the Siege of Kvatch: Gate Closed milestone recorded")
                return
            end
            if text == "Breaking the Siege of Kvatch" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Breaking the Siege of Kvatch")
                writeLog("Breaking the Siege of Kvatch milestone recorded")
                return
            end

            if text == "Battle for Castle Kvatch" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Battle for Castle Kvatch")
                writeLog("Battle for Castle Kvatch milestone recorded")
                return
            end

            -- MQ05 checks
            if text == "Acquire Commentaries Vol I" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("The Path of Dawn: Acquire Commentaries Vol I")
                writeLog("Acquire Commentaries Vol I recorded")
                return
            end
            if text == "Acquire Commentaries Vol II" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("The Path of Dawn: Acquire Commentaries Vol II")
                writeLog("Acquire Commentaries Vol II recorded")
                return
            end
            if text == "Acquire Commentaries Vol III" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("The Path of Dawn: Acquire Commentaries Vol III")
                writeLog("Acquire Commentaries Vol III recorded")
                return
            end
            if text == "Acquire Commentaries Vol IV" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("The Path of Dawn: Acquire Commentaries Vol IV")
                writeLog("Acquire Commentaries Vol IV recorded")
                return
            end
            if text == "The Path of Dawn" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("The Path of Dawn")
                writeLog("The Path of Dawn recorded")
                return
            end

            -- Dagon Shrine
            if text == "Dagon Shrine" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Dagon Shrine")
                writeLog("Dagon Shrine completion recorded")
                return
            end
            if text == "Dagon Shrine: Mysterium Xarxes Acquired" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Dagon Shrine: Mysterium Xarxes Acquired")
                writeLog("Dagon Shrine: Mysterium Xarxes Acquired recorded")
                return
            end
            if text == "Harrow is dead" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Dagon Shrine: Kill Harrow")
                writeLog("Kill Harrow recorded")
                return
            end
            if text == "Jearl is dead" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Spies: Kill Jearl")
                writeLog("Kill Jearl recorded")
                return
            end
            if text == "Saveri Faram is dead" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Spies: Kill Saveri Faram")
                writeLog("Kill Saveri Faram recorded")
                return
            end

            if text == "Find the Heir" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Find the Heir")
                writeLog("Find the Heir milestone recorded")
                return
            end
            if text == "Weynon Priory" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Weynon Priory")
                writeLog("Weynon Priory milestone recorded")
                return
            end

            -- Additional Main Quest / Related Milestones
            if text == "Spies" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Spies")
                writeLog("Spies milestone recorded")
                return
            end
            if text == "Blood of the Daedra" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Daedra")
                writeLog("Blood of the Daedra milestone recorded")
                return
            end
            if text == "Blood of the Divines" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Divines")
                writeLog("Blood of the Divines milestone recorded")
                return
            end
            -- Blood of the Divines Sub-steps
            if text == "Blood of the Divines: Free Spirit 1" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Divines: Free Spirit 1")
                writeLog("Blood of the Divines: Free Spirit 1 recorded")
                return
            end
            if text == "Blood of the Divines: Free Spirit 2" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Divines: Free Spirit 2")
                writeLog("Blood of the Divines: Free Spirit 2 recorded")
                return
            end
            if text == "Blood of the Divines: Free Spirit 3" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Divines: Free Spirit 3")
                writeLog("Blood of the Divines: Free Spirit 3 recorded")
                return
            end
            if text == "Blood of the Divines: Free Spirit 4" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Divines: Free Spirit 4")
                writeLog("Blood of the Divines: Free Spirit 4 recorded")
                return
            end
            if text == "Blood of the Divines: Armor of Tiber Septim" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Blood of the Divines: Armor of Tiber Septim")
                writeLog("Blood of the Divines: Armor of Tiber Septim recorded")
                return
            end
            if text == "Bruma Gate" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Bruma Gate")
                writeLog("Bruma Gate milestone recorded")
                return
            end
            if text == "Miscarcand: Great Welkynd Stone" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Miscarcand: Great Welkynd Stone")
                writeLog("Miscarcand: Great Welkynd Stone milestone recorded")
                return
            end
            if text == "Miscarcand" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Miscarcand")
                writeLog("Miscarcand milestone recorded")
                return
            end
            if text == "Defense of Bruma" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Defense of Bruma")
                writeLog("Defense of Bruma milestone recorded")
                return
            end
            if text == "Great Gate" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Great Gate")
                writeLog("Great Gate milestone recorded")
                return
            end
            if text == "Paradise" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Paradise")
                writeLog("Paradise milestone recorded")
                return
            end
            if text == "Paradise: Bands of the Chosen Acquired" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Paradise: Bands of the Chosen Acquired")
                writeLog("Paradise: Bands of the Chosen Acquired recorded")
                return
            end
            if text == "Paradise: Bands of the Chosen Removed" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Paradise: Bands of the Chosen Removed")
                writeLog("Paradise: Bands of the Chosen Removed recorded")
                return
            end
            if text == "Attack on Fort Sutch" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                writeCompletionStatus("Attack on Fort Sutch")
                writeLog("Attack on Fort Sutch milestone recorded")
                return
            end

            -- Handle Dungeon Delver Victory message
            if text == "Dungeon Delver Victory" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)

                -- Write Victory to completion file
                writeCompletionStatus("Victory")
                writeLog("Dungeon Delver Victory written to completion file")

                return
            end

            -- Handle Light the Dragonfires Victory message (Main Quest completion)
            if text == "Light the Dragonfires Victory" then
                -- Hide notification quickly
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                writeCompletionStatus("Victory")
                writeLog("Light the Dragonfires Victory written to completion file")
                return
            end

            do
                local okBounty, bountyHit = pcall(function()
                    return require("BountyTracking").tryCompleteFromToken(text)
                end)
                if okBounty and bountyHit then
                    pcall(function()
                        actualHudVM.Notification.ShowSeconds = 0.0001
                    end)
                    return
                end
            end

            if text == "AP_TOGGLE_TRACK" then
                pcall(function() actualHudVM.Notification.ShowSeconds = 0.0001 end)
                local canNirn = nirnrootInSeed and not nirnrootManualOff
                local canChest = chestInSeed
                if not nirnrootTrackingEnabled and not bossChestTrackingEnabled then
                    if canNirn then
                        nirnrootTrackingEnabled = true
                        lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
                        lastTrackingUpdate = 0
                        pcall(function() console.ExecuteConsole('Message "Tracking Nirnroot ON"') end)
                    elseif canChest then
                        bossChestTrackingEnabled = true
                        lastBossChestMessage = os.clock()
                        lastTrackingUpdate = 0
                        pcall(function() console.ExecuteConsole('Message "Tracking Boss Chest ON"') end)
                    end
                elseif nirnrootTrackingEnabled then
                    nirnrootTrackingEnabled = false
                    if canChest then
                        clearAPXMarker()
                        bossChestTrackingEnabled = true
                        lastBossChestMessage = os.clock()
                        lastTrackingUpdate = 0
                        pcall(function() console.ExecuteConsole('Message "Tracking Boss Chest ON"') end)
                    else
                        clearAPXMarker()
                        pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
                    end
                else
                    bossChestTrackingEnabled = false
                    clearAPXMarker()
                    pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
                end
                return
            end

            if text == "AP_TRACK_NIRNROOT" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)

                nirnrootTrackingEnabled = not nirnrootTrackingEnabled

                if nirnrootTrackingEnabled then
                    lastTrackingUpdate = 0
                    lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
                    writeLog("Nirnroot tracking enabled")
                    pcall(function()
                        console.ExecuteConsole('Message "Nirnroot tracking ON"')
                    end)
                else
                    writeLog("Nirnroot tracking disabled")
                    pcall(function()
                        console.ExecuteConsole('Message "Nirnroot tracking OFF"')
                    end)
                end
                return
            end

            if text == "AP_TRACK_BOSS_CHEST" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)

                bossChestTrackingEnabled = not bossChestTrackingEnabled

                if bossChestTrackingEnabled then
                    lastTrackingUpdate = 0
                    writeLog("Boss chest tracking enabled")
                    pcall(function()
                        console.ExecuteConsole('Message "Boss chest tracking ON"')
                    end)
                else
                    writeLog("Boss chest tracking disabled")
                    pcall(function()
                        console.ExecuteConsole('Message "Boss chest tracking OFF"')
                    end)
                end
                return
            end
        end)
        state.notificationHookRegistered = true
        writeLog("Notification hook registered for event tracking")
        end
    end)

-- F11 keybind registration
RegisterKeyBind(Key.F11, function()
    pendingTrackingToggle = true
end)


