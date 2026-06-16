--[[
    Archipelago Integration Mod for Oblivion Remastered
    
    Integrates Oblivion Remastered with the Archipelago multiworld randomizer.
    Handles receiving items from other players and sending completion status back.
    
    Features:
    - Processes items received from the Archipelago client
    - Automatically adds shrine offerings when receiving shrine tokens (if enabled)
    - Tracks quest completion status for the randomizer
    - Uses console commands for game state changes
    
    File Communication:
    - Uses text files in the user's save directory for communication with the Archipelago client
    - Supports multiple connection sessions via file prefixes
    - Logs all activity for debugging purposes
--]]

local UEHelpers = require("UEHelpers")
local config = require("ArchipelagoConfig")
local console = require("OBRConsole")

print("========================================")
print("ARCHIPELAGO PATH DEBUG START")
print("========================================")

local ap_userprofile = os.getenv("USERPROFILE")
print("USERPROFILE = " .. tostring(ap_userprofile))

local ap_default_dir = tostring(ap_userprofile) .. "\\Documents\\My Games\\Oblivion Remastered\\Saved\\Archipelago"
print("DEFAULT_ARCHIPELAGO_DIR = " .. ap_default_dir)

local ap_test_connection = ap_default_dir .. "\\current_connection.txt"
local ap_test_override = ap_default_dir .. "\\path_override.txt"
print("Checking current_connection.txt")
print("PATH = " .. ap_test_connection)

local f = io.open(ap_test_connection, "r")
if f then
    print("RESULT = FOUND")
    f:close()
else
    print("RESULT = NOT FOUND")
end

print("Checking path_override.txt")
print("PATH = " .. ap_test_override)

f = io.open(ap_test_override, "r")
if f then
    print("RESULT = FOUND")

    local line = f:read("*line")
    print("CONTENTS = " .. tostring(line))

    f:close()
else
    print("RESULT = NOT FOUND")
end

print("========================================")
print("ARCHIPELAGO PATH DEBUG END")
print("========================================")

-- ActorDetection module
local ActorDetection = nil
local killTrackingEnabled = false
local hasDungeonKillChecks = false
local hasOverworldKillChecks = false

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
    silent_auto_tracking = false -- do not show "Message" notifications for tracking
}

-- Queue for displaying messages when multiple items are processed
local messageboxQueue = {}

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

-- Session flags to track initialization status
local progressiveShopStockInitialized = false
local arenaInitialized = false
local shrinesInitialized = false
local sidequestsInitialized = false
local gatesInitialized = false
local gateVisionInitialized = false
local fastTravelInitialized = false
local classSystemInitialized = false
local modFullyInitialized = false
local encumbranceScalingApplied = false

-- apply Encumbrance fix once per session
local function applyEncumbranceScaling()
    if encumbranceScalingApplied then return true end
    local ok, result = pcall(function()
        local obj = StaticFindObject(ENCUMBRANCE_SETTINGS_OBJ)
        if obj and obj:IsValid() then
            obj.DefaultStrengthEncumbranceMult = ENCUMBRANCE_MULT
            return true
        end
        return false
    end)
    if ok and result then
        encumbranceScalingApplied = true
        writeLog(string.format("Encumbrance scaling applied: DefaultStrengthEncumbranceMult = %d", ENCUMBRANCE_MULT))
        return true
    end
    return false
end

-- read back the live value and reapply if the game has reset it.
local lastEncumbranceValidation = 0
local ENCUMBRANCE_VALIDATION_INTERVAL = 120  -- seconds between validation checks
local function validateEncumbranceScaling()
    if not encumbranceScalingApplied then return end  -- not applied yet; retry path handles this
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
            encumbranceScalingApplied = false
            applyEncumbranceScaling()
        end
    end
end

pcall(applyEncumbranceScaling)

-- Initialization flags
local needsProgressiveShopStockInit = false
local needsArenaInit = false
local needsShrinesInit = false
local needsSidequestsInit = false
local needsGatesInit = false
local needsGateVisionInit = false
local needsFastTravelInit = false
local needsClassSystemInit = false
local needsDungeonCountersInit = false
local dungeonCountersInitialized = false
local hasShownNoSettingsMessage = false
-- Track if we showed the "no connection file" message and if a connection follow-up was shown
local hadNoConnectionMessage = false
local hasShownConnectionEstablished = false


-- Frame counter for periodic item processing (every 5 seconds at 60fps)
local frameCounter = 0
local targetFrames = 300


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
    foundFormID = nil
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
    if apProbe.console and apProbe.console:IsValid() then return apProbe.console end
    local inst = FindFirstOf("Console")
    if inst and inst:IsValid() then 
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
        writeLog("AP sync: in-game=" .. countStr .. ", bridge=" .. tostring(diskCount) .. ", diff=" .. tostring(diff))

        if ingameCount == 0 and modFullyInitialized and not suppressReinitOnNextZero then
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

-- Cell lookup functions (same pattern as AP sync probe)
local function readCellLookupConsole()
    local inst = apFindConsole()
    if not inst or not cellLookupProbe.awaiting then return end
    
    local newCount = inst.OutputBufferSize
    
    if newCount > cellLookupProbe.lastCount then
        -- Read new lines
        for i = cellLookupProbe.lastCount, newCount - 1 do
            local line = inst.OutputBuffer[i+1]:ToString()
            
            -- Look for FormID pattern "Cell: 000a7543"
            local formID = line:match("Cell:%s*(%x+)")
            if formID then
                cellLookupProbe.foundFormID = formID:upper()
                cellLookupProbe.awaiting = false
                cellNameRequestPending = false
                
                -- Resolve FormID to a cell name + EditorID and cache both.
                -- On failure (FormID not in CSV), currentCellName stays nil and
                -- getCurrentCellName() will fall back to the world name (L_PersistentDungeon).
                local cellName, cellEditorID = lookupCellNameByFormID(cellLookupProbe.foundFormID)
                if cellName then
                    currentCellName = cellName
                    currentCellEditorID = cellEditorID or ""
                    -- Detect Oblivion interior cells by EditorID pattern
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
                                enableBossChestTracking()
                            end
                        end
                    end
                else
                    -- FormID not in CSV: check the live world name before falling back.
                    -- Oblivion worldspace exterior cells won't be in the CSV but the world
                    -- name will contain "oblivion", so we can still classify them correctly.
                    local worldFull = ""
                    pcall(function()
                        local p = UEHelpers:GetPlayer()
                        if p and p:IsValid() then
                            worldFull = p:GetWorld():GetFullName() or ""
                        end
                    end)
                    if worldFull:lower():find("oblivion") then
                        local mapName = worldFull:match("/([^/]+)%.") or worldFull:match("/([^/]+)$") or "Oblivion Plane"
                        currentCellName = mapName
                        currentCellEditorID = ""
                        currentCellIsOblivion = true
                        writeLog("Cell not in CSV but world name indicates Oblivion: " .. mapName .. " (FormID: " .. cellLookupProbe.foundFormID .. ")")
                    else
                        -- Genuinely unknown cell; store FormID for debug logging.
                        currentCellName = "Unknown Cell (FormID: " .. cellLookupProbe.foundFormID .. ")"
                        currentCellEditorID = ""
                        currentCellIsOblivion = false
                        writeLog("Cell FormID not in database: " .. cellLookupProbe.foundFormID .. " — using fallback name")
                    end
                end
                return
            end
        end
    end
    
    cellLookupProbe.lastCount = newCount
end

local function startCellLookup()
    apFindConsole()
    local inst = apProbe.console
    if not inst then return end
    
    cellLookupProbe.awaiting = true
    cellLookupProbe.lastCount = inst.OutputBufferSize
    cellLookupProbe.foundFormID = nil
    
    console.ExecuteConsole("player.getparentcell")
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
    progressiveShopStockInitialized = false
    arenaInitialized = false
    shrinesInitialized = false
    sidequestsInitialized = false
    gatesInitialized = false
    gateVisionInitialized = false
    fastTravelInitialized = false
    classSystemInitialized = false
    dungeonCountersInitialized = false
    encumbranceScalingApplied = false  -- allow reapplication for the new session
    needsProgressiveShopStockInit = false
    needsArenaInit = false
    needsShrinesInit = false
    needsSidequestsInit = false
    needsGatesInit = false
    needsGateVisionInit = false
    needsFastTravelInit = false
    needsClassSystemInit = false
    needsDungeonCountersInit = false
    modFullyInitialized = false
    probeFinished = false

    -- Proactively reload settings and run init now so user doesn't have to wait
    loadSettings()
    handleInitialization()

    -- Kick off a fresh APSync probe after initialization so resend happens post-init
    writeLog("Reinit: starting APSync probe to reconcile items after fresh init")
    if not probeFinished and not apProbe.awaiting then
        startAPSyncProbe()
        probeStartedForSession = true -- prevents false positive on APAppliedCount = 0 at startup
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

-- Function to find HUD widget
local function FindByName(class, name)
    local objs = FindAllOf(class)
    if not objs then return nil end
    for _, obj in ipairs(objs) do
        if obj:GetFullName():match(name) then return obj end
    end
    return nil
end

-- Message system for Archipelago notifications (Uses tutorial display area)
local InterceptTutorial = false
local QueuedArchipelagoMessage = ""
-- Track the last AP tutorial message so we can convert it to a console Message on menu/freeze
local lastAPTutorialMessage = ""

-- Default on-screen duration for AP tutorial messages (seconds)
-- Change this to adjust how long messages are shown in the HUD tutorial box
local AP_TUTORIAL_DEFAULT_TIME = 4.0

-- Hook guards
local setupNewDisplayHooked = false
local setMenuModeHooked = false

-- Helpers to force-close the tutorial message quickly when entering menu/freeze
local function CloseTutorialByTimeSqueeze(widget)
    local target = widget
    if (not target) or (not target.IsValid) or (not target:IsValid()) then
        target = FindByName("WBP_ModernTutorialDisplay_C", "WBP_PrimaryGameLayout_C")
    end
    if not target or not target.IsValid or not target:IsValid() then return false end
    -- Set 0.001 display time and force update/closing animations
    pcall(function()
        target.CurrentDisplayTime = 0.001
        if target.ManageCurrentDisplay then target:ManageCurrentDisplay() end
        if target.ManageDisplay then target:ManageDisplay() end
        if target.LaunchClosingAnimation then target:LaunchClosingAnimation() end
        if target.FinishAnimation then target:FinishAnimation() end
    end)
    return true
end

-- Force-hide helper
local function HardHideTutorialWidget(widget)
    local target = widget
    if (not target) or (not target.IsValid) or (not target:IsValid()) then
        target = FindByName("WBP_ModernTutorialDisplay_C", "WBP_PrimaryGameLayout_C")
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

-- Menu detection function
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

-- Cache the freeze/menu subsystem to avoid repeated object searches
local cachedFreezeSubsystem = nil

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
    local HudModel = FindByName("WBP_ModernTutorialDisplay_C", "WBP_PrimaryGameLayout_C")
    if not HudModel or not HudModel:IsValid() then 
        
        return 
    end
    
    QueuedArchipelagoMessage = message
    InterceptTutorial = true
    HudModel:SetupNewDisplay()
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
                -- Remember this AP message so we can convert it to a console Message if a menu/freeze occurs
                lastAPTutorialMessage = QueuedArchipelagoMessage or ""
                
                -- Set AP Tutorial Message display time
                tutorialMessage.DefaultDisplayTime = AP_TUTORIAL_DEFAULT_TIME
                tutorialMessage.CurrentDisplayTime = AP_TUTORIAL_DEFAULT_TIME
                
                -- Trigger the input method change to actually display the message
                tutorialMessage:ManageInputMethodeChange(1)
                
                pcall(function()
                    if tutorialMessage.SetVisibility then tutorialMessage:SetVisibility(0) end -- Visible
                    if tutorialMessage.SetRenderOpacity then tutorialMessage:SetRenderOpacity(1.0) end
                    if tutorialMessage.ResetAnimation then tutorialMessage:ResetAnimation() end
                    if tutorialMessage.LaunchOpenningAnimation then tutorialMessage:LaunchOpenningAnimation() end
                end)
                
                local okF, fr = pcall(isGameFreezing)
                lastFreezeState = okF and fr or false
                
                
            end
        end
        InterceptTutorial = false
        QueuedArchipelagoMessage = ""
    end
end




-- Function to display Archipelago notifications via tutorial display
local function ShowArchipelagoNotification(message)
    -- If currently frozen or in menu, route to console ["Message"]
    local inMenuNow = false
    local okMenu, resMenu = pcall(IsPlayerInMenu)
    if okMenu then inMenuNow = resMenu end
    if isGameFreezing() or inMenuNow then
        pcall(function()
            console.ExecuteConsole("Message \"" .. tostring(message) .. "\"")
        end)
        return
    end

    
    local success, err = pcall(function()
        BroadcastArchipelagoMessage(message)
    end)
    
    if not success then
        pcall(function()
            console.ExecuteConsole("Message \"" .. tostring(message) .. "\"")
        end)
        return
    end
end

-- Process item events file and display messages to player
local function processItemEvents()
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return end
    
    local eventsPath = getArchipelagoPath(filePrefix .. "_item_events.txt")
    local file = io.open(eventsPath, "r")
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
                    -- Use the tutorial display area
                    ShowArchipelagoNotification(message)
                end
            end
        end
    end
    file:close()
    
    -- Clear the file after processing
    os.remove(eventsPath)
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
            console.ExecuteConsole(command)
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
    
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            if key == "free_offerings" then
                archipelagoSettings.free_offerings = (value == "True")
            elseif key == "goal" then
                currentGoal = value
                writeLog("Found goal: " .. value)
                if value == "nirnsanity" then nirnrootInSeed = true end
            elseif key == "goal_required" then
                goalRequired = tonumber(value) or 0
                writeLog("Found goal_required: " .. tostring(goalRequired))
            elseif key == "mod_fully_initialized" and value == "True" then
                modFullyInitialized = true
                writeLog("Found mod already fully initialized from previous session")
            elseif key == "progressive_shop_stock_initialized" and value == "True" then
                progressiveShopStockInitialized = true
                writeLog("Found progressive shop stock already initialized from previous session")
            elseif key == "progressive_shop_stock" and value == "True" then
                hasProgressiveShopStockSettings = true
                writeLog("Found progressive_shop_stock=True in settings file")
            elseif key == "arena_initialized" and value == "True" then
                arenaInitialized = true
                writeLog("Found arena already initialized from previous session")
            elseif key == "enable_arena" and value == "True" then
                hasArenaSettings = true
                writeLog("Found enable_arena=True in settings file")
            elseif key == "shrines_initialized" and value == "True" then
                shrinesInitialized = true
                writeLog("Found shrines already initialized from previous session")

            elseif key == "active_shrines" and value ~= "" then
                hasShrineSettings = true
                writeLog("Found active_shrines=" .. value .. " in settings file")
            elseif key == "sidequests_initialized" and value == "True" then
                sidequestsInitialized = true
                writeLog("Found sidequests already initialized from previous session")
            elseif key == "selected_sidequests" and value ~= "" then
                hasSidequestSettings = true
                writeLog("Found selected_sidequests in settings file")
            elseif key == "gates_initialized" and value == "True" then
                gatesInitialized = true
                writeLog("Found gates already initialized from previous session")
            elseif key == "gate_vision" and value == "on" then
                hasGateVisionSettings = true
                writeLog("Found gate_vision=on in settings file")
            elseif key == "gate_vision_initialized" and value == "True" then
                gateVisionInitialized = true
                writeLog("Found gate vision already initialized from previous session")
            elseif key == "fast_travel_initialized" and value == "True" then
                fastTravelInitialized = true
                writeLog("Found fast travel already initialized from previous session")
            elseif key == "fast_travel_item" and value:lower() == "true" then
                hasFastTravelSettings = true
                writeLog("Found fast_travel_item=True in settings file")
            elseif key == "class_system_enabled" and value == "True" then
                hasClassSystemSettings = true
                writeLog("Found class_system_enabled=True in settings file")
            elseif key == "class_system_initialized" and value == "True" then
                classSystemInitialized = true
                writeLog("Found class system already initialized from previous session")
            elseif key == "selected_regions" and value ~= "" then
                hasDungeonSettings = true
                writeLog("Found selected_regions in settings")
            elseif key == "dungeon_marker_mode" then
                local v = value:lower()
                if v == "reveal_only" then
                    archipelagoSettings.dungeon_marker_mode = "reveal_only"
                else
                    archipelagoSettings.dungeon_marker_mode = "reveal_and_fast_travel"
                end
                writeLog("Found dungeon_marker_mode=" .. archipelagoSettings.dungeon_marker_mode)
            elseif key == "dungeon_warp" then
                local v = value:lower()
                if v == "on" or v == "item" or v == "early_item" or v == "off" then
                    archipelagoSettings.dungeon_warp = v
                    writeLog("Found dungeon_warp=" .. v)
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
                writeLog("Found selected_class: " .. value)
            elseif key == "track_kills" and value == "True" then
                killTrackingEnabled = true
                writeLog("Found track_kills=True in settings file")
            elseif key == "dungeon_kills" then
                hasDungeonKillChecks = (tonumber(value) or 0) > 0
            elseif key == "overworld_kills" then
                hasOverworldKillChecks = (tonumber(value) or 0) > 0
            elseif key == "auto_tracking" then
                archipelagoSettings.auto_tracking = (value == "True")
                writeLog("Found auto_tracking=" .. tostring(archipelagoSettings.auto_tracking))
                pcall(function()
                    local val = archipelagoSettings.auto_tracking and 1 or 0
                    console.ExecuteConsole("set APAutoTrackEnabled to " .. val)
                end)
            elseif key == "silent_auto_tracking" then
                archipelagoSettings.silent_auto_tracking = (value == "True")
                writeLog("Found silent_auto_tracking=" .. tostring(archipelagoSettings.silent_auto_tracking))
            elseif key == "nirnroot_count" then
                if (tonumber(value) or 0) > 0 then nirnrootInSeed = true end
            elseif key == "dungeon_selected_count" then
                chestInSeed = (tonumber(value) or 0) > 0
            end
        end
    end
    file:close()
    
    -- Set flags if we have settings but haven't initialized yet (using session flags)
    needsProgressiveShopStockInit = hasProgressiveShopStockSettings and not progressiveShopStockInitialized
    needsArenaInit = hasArenaSettings and not arenaInitialized
    needsShrinesInit = hasShrineSettings and not shrinesInitialized
    needsSidequestsInit = hasSidequestSettings and not sidequestsInitialized
    needsGatesInit = not gatesInitialized
    needsGateVisionInit = hasGateVisionSettings and not gateVisionInitialized
    needsFastTravelInit = hasFastTravelSettings and not fastTravelInitialized
    needsClassSystemInit = hasClassSystemSettings and not classSystemInitialized
    needsDungeonCountersInit = hasDungeonSettings and not dungeonCountersInitialized
    
    writeLog("Settings loaded - needsProgressiveShopStockInit: " .. tostring(needsProgressiveShopStockInit) .. ", needsArenaInit: " .. tostring(needsArenaInit) .. ", needsShrinesInit: " .. tostring(needsShrinesInit) .. ", needsSidequestsInit: " .. tostring(needsSidequestsInit) .. ", needsGatesInit: " .. tostring(needsGatesInit) .. ", needsGateVisionInit: " .. tostring(needsGateVisionInit) .. ", needsFastTravelInit: " .. tostring(needsFastTravelInit) .. ", needsClassSystemInit: " .. tostring(needsClassSystemInit))
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
    
    -- Read gate_count from settings file
    local gateCount = 0
    file = io.open(settingsPath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(.-)=(.*)$")
            if key and value and key == "gate_count" then
                gateCount = tonumber(value) or 0
                break
            end
        end
        file:close()
    end
    
    -- Only enable gates if gate_count > 0
    if gateCount > 0 then
        -- Set APGatesEnabled to 1 to enable Oblivion Gates
        console.ExecuteConsole("set APGatesEnabled to 1")
        writeLog("Gates initialization complete - APGatesEnabled set to 1 (gate_count: " .. tostring(gateCount) .. ")")
    else
        writeLog("Gates initialization skipped - gate_count is 0")
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
    
    -- Give each item to the player using console commands
    for _, itemName in ipairs(itemsToProcess) do
        
        -- Handle Region Access items (e.g., "West Weald Access"): reveal only selected dungeons' markers
        local regionAccess = itemName:match("^(.*) Access$")
        if regionAccess then
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
        -- Handle Deathlink item - kill the player
        elseif itemName == "Deathlink" then
            writeLog("Processing Deathlink - killing player")
            local success, result = pcall(function()
                console.ExecuteConsole("player.kill")
            end)
            if success then
                writeLog("Player killed by Deathlink")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to execute Deathlink: " .. tostring(result), "ERROR")
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
            if edid then
                -- Set quantity based on item type
                local quantity = 1
                if itemName:find("Potion") or itemName == "Skooma" then
                    quantity = 3
                elseif itemName == "Steel Arrows" then
                    quantity = 5
                elseif itemName == "Fire Arrow Bundle" then
                    quantity = 100
                elseif itemName == "Gold (10)" then
                    quantity = 10
                elseif itemName == "Gold" or itemName == "Clavicus Gold" then
                    quantity = 500
                elseif itemName == "Greater Soulgem Package" then
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

-- Check if a completion has already been recorded
local function isCompletionAlreadyRecorded(completionTokenEdid)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then return false end
    
    local statusPath = getArchipelagoPath(filePrefix .. "_completed.txt")
    local file = io.open(statusPath, "r")
    if not file then return false end
    
    for line in file:lines() do
        if line == completionTokenEdid then
            file:close()
            return true
        end
    end
    file:close()
    return false
end

-- Write quest completion status to file for the Archipelago client
-- This notifies the multiworld when we complete a location
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
            modFullyInitialized = false
            writeLog("Reconnect detected; forcing settings reload by clearing modFullyInitialized")
        else
            writeLog("Failed to display 'connection established' message", "ERROR")
        end
    end
    -- Reset the disconnect gate so future disconnects can alert again
    hasShownNoSettingsMessage = false
    
    return true  -- Valid session found
end

-- Get current cell/location name for kill tracking
-- Search cell lookup file for a specific FormID
lookupCellNameByFormID = function(formID)
    if not formID then return nil end
    
    -- Normalize FormID to uppercase without 0x prefix
    formID = formID:upper():gsub("^0X", "")
    -- Ensure exactly 8 characters with leading zeros
    if #formID < 8 then
        formID = string.rep("0", 8 - #formID) .. formID
    end
    
    -- Try the scripts folder first (this mod folder), then Archipelago folder
    local file = nil
    local scriptDir = getScriptDirectory()
    if scriptDir and scriptDir ~= "" then
        local scriptPath = scriptDir .. "\\oblivion_cell_database.csv"
        file = io.open(scriptPath, "r")
    end
    
    if not file then
        file = io.open("oblivion_cell_database.csv", "r")
    end
    
    if not file then
        local lookupPath = getArchipelagoPath("oblivion_cell_database.csv")
        file = io.open(lookupPath, "r")
    end
    
    if not file then
        writeLog("Cell lookup file not found (oblivion_cell_database.csv)", "WARN")
        return nil
    end
    
    -- CSV format: CellName,FormID,EditorID,Type
    -- Example: Nenalata Wendesel,000A7543,Nenalata02,CELL
    for line in file:lines() do
        if not line:match("^%s*$") then
            -- Split by comma
            local parts = {}
            for part in line:gmatch("([^,]+)") do
                table.insert(parts, part:match("^%s*(.-)%s*$")) -- Trim whitespace
            end
            
            -- Check if second field matches our FormID
            if #parts >= 2 then
                local lineFormID = parts[2]:upper():gsub("^0X", "")
                if lineFormID == formID then
                    file:close()
                    return parts[1], parts[3] -- Return cell name, EditorID
                end
            end
        end
    end
    
    file:close()
    return nil
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

    -- Tamriel can always be identified directly from the world name.
    if worldFullName:find("Tamriel") then
        currentCellName = "Tamriel"
        return "Tamriel"
    end

    -- Oblivion worldspaces (e.g. L_OblivionRD002) can be detected from the world name
    -- Cache the result so kills are classified correctly even when the fade event didn't fire.
    if worldFullName:lower():find("oblivion") then
        local mapName = worldFullName:match("/([^/]+)%.") or worldFullName:match("/([^/]+)$") or "Oblivion Plane"
        currentCellName = mapName
        currentCellIsOblivion = true
        return mapName
    end

    -- For interior cells, kick off a CSV lookup
    if not cellNameRequestPending then
        cellNameRequestPending = true
        if apProbe.awaiting then
            pendingCellLookup = true
        else
            startCellLookup()
        end
    end

    -- Return the raw map name as a temporary fallback until the lookup resolves.
    local mapName = worldFullName:match("/([^/]+)%.") or worldFullName:match("/([^/]+)$") or "Unknown Location"
    return mapName
end

-- Returns "overworld", "oblivion", or "dungeon" based on the current cell.
local function getCellKillType()
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
local UE5_TO_OBL = 0.7

-- Move the quest marker to (x,y,z) and activate it, but only send console commands
-- if the target has actually moved beyond MARKER_MOVE_THRESHOLD since the last update.
local function updateAPXMarker(x, y, z)
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

local function clearAPXMarker()
    if not lastMarkerX then return end
    pcall(function()
        console.ExecuteConsole("set APAutoTrackValid to 0")
    end)
    lastMarkerX = nil
    lastMarkerY = nil
    lastMarkerZ = nil
end

local function enableBossChestTracking()
    nirnrootTrackingEnabled = false
    bossChestTrackingEnabled = true
    lastBossChestMessage = 0
    lastTrackingUpdate = 0
end

local function enableNirnrootTracking()
    bossChestTrackingEnabled = false
    nirnrootTrackingEnabled = true
    lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
    lastTrackingUpdate = 0
end

local function disableAllAutoTrack()
    nirnrootTrackingEnabled = false
    bossChestTrackingEnabled = false
end

local function shouldAutoTrack()
    return archipelagoSettings.auto_tracking and not autoTrackManualOff
end

local function processPendingFadeActions()
    if apProbe.awaiting then return end

    if pendingCellLookup then
        pendingCellLookup = false
        startCellLookup()
    end

    if pendingMarkerClear then
        pendingMarkerClear = false
        clearAPXMarker()
    end

    if pendingAutoTrack == "boss" then
        enableBossChestTracking()
        pendingAutoTrack = nil
    elseif pendingAutoTrack == "nirn" then
        enableNirnrootTracking()
        pendingAutoTrack = nil
    elseif pendingAutoTrack == "off" then
        disableAllAutoTrack()
        pendingAutoTrack = nil
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
        writeLog("Player not found or invalid for periodic tracking", "ERROR")
        return 
    end
    
    -- Track Nirnroot
    if nirnrootTrackingEnabled and currentTime - lastNirnrootMessage >= NIRNROOT_MESSAGE_INTERVAL then
        lastNirnrootMessage = currentTime

        local playerLoc = player:K2_GetActorLocation()
        local instances = FindAllOf("BP_NirnrootPlant_C")
        local nearestDist = 99999999
        local nearestDir = "?"
        local nearestDistMeters = nil
        local nearestLoc = nil

        pcall(function()
            if instances then
                for _, obj in ipairs(instances) do
                    if obj and obj:IsValid() then
                        -- bHidden == true means harvested or streamed out; skip those
                        local isHidden = obj.bHidden
                        if isHidden ~= true then
                            local loc = obj:K2_GetActorLocation()
                            local dist = math.sqrt(
                                (loc.X - playerLoc.X)^2 +
                                (loc.Y - playerLoc.Y)^2 +
                                (loc.Z - playerLoc.Z)^2
                            )
                            if dist < nearestDist then
                                nearestDist = dist
                                nearestDistMeters = math.floor(dist / 100)
                                nearestLoc = loc
                                -- UE4 Y+ = South, so negate Y to get correct compass direction
                                local angle = math.atan(-(loc.Y - playerLoc.Y), loc.X - playerLoc.X) * (180 / math.pi)
                                if angle < 0 then angle = angle + 360 end
                                local dirs = {"E","NE","N","NW","W","SW","S","SE"}
                                nearestDir = dirs[math.floor((angle + 22.5) / 45) % 8 + 1]
                            end
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
        else
            clearAPXMarker()
        end
    end

    -- Track Boss Chests
    if bossChestTrackingEnabled and currentTime - lastBossChestMessage >= BOSS_CHEST_MESSAGE_INTERVAL then
        lastBossChestMessage = currentTime

        local containers = ActorDetection.DetectNearbyContainers(5000)
        local playerLoc = player:K2_GetActorLocation()

        -- Collect boss containers with distances
        local bossContainers = {}
        for formID, data in pairs(containers) do
            if data.fullName:lower():match("boss") or data.name:lower():match("boss") or
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

            if not archipelagoSettings.silent_auto_tracking then
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

-- Initialize kill tracking system
local function initializeKillTracking()
    if not killTrackingEnabled then
        return
    end
    
    writeLog("Initializing kill tracking system")
    
    -- load ActorDetection module
    if not ActorDetection then
        local success, module = pcall(function() return require("ActorDetection") end)
        if not success then
            writeLog("Failed to load ActorDetection module: " .. tostring(module), "ERROR")
            return
        end
        ActorDetection = module
    end

    ActorDetection.Initialize(function(enemyData, killer)
        -- Check if tracking still enabled
        if not killTrackingEnabled then return end
        
        -- Determine killer name
        local killerName = "Unknown"
        if killer and killer:IsValid() then
            if killer:IsPlayerCharacter() then
                killerName = "Player"
            else
                local fullName = killer:GetFullName()
                killerName = fullName:match("([^%.]+)$") or fullName
            end
        end
        
        -- only log player kills
        local isPlayerKill = (killerName == "Player")
        if not isPlayerKill then return end
        
        -- Get current cell/world name
        local cellName = getCurrentCellName()
        local cellKillType = getCellKillType()
        -- Oblivion plane kills are excluded from both overworld and dungeon counts
        -- They are logged to the debug file but never written as AP check completions
        -- Can be used if we add new checks for Oblivion kills
        local killToken
        if cellKillType == "overworld" then
            killToken = "Overworld Kill"
        elseif cellKillType == "oblivion" then
            killToken = "Oblivion Kill"
        else
            killToken = "Dungeon Kill"
        end
        local killTypeEnabled = (cellKillType == "overworld" and hasOverworldKillChecks)
                             or (cellKillType == "dungeon" and hasDungeonKillChecks)

        -- Always log to _kills.txt for debug
        local filePrefix = getCurrentFilePrefix()
        local debugFilename = filePrefix and (filePrefix .. "_kills.txt") or "manual_kills.txt"
        local killsPath = getArchipelagoPath(debugFilename)
        local debugFile = io.open(killsPath, "a")
        if debugFile then
            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
            local levelStr = enemyData.level and (" Lv" .. enemyData.level) or ""
            local locationStr = string.format(" at %.0f,%.0f,%.0f",
                enemyData.location.X, enemyData.location.Y, enemyData.location.Z)
            debugFile:write(string.format("[%s] [%s] %s%s (FormID: %s) killed by %s in %s%s\n",
                timestamp, killToken, enemyData.name, levelStr, enemyData.formID,
                killerName, cellName, locationStr))
            debugFile:close()
        end

        -- Write to _completed.txt for the AP client to process (only when kills are enabled)
        if killTypeEnabled and filePrefix then
            writeCompletionStatus(killToken)
            writeLog(string.format("Kill check written: %s in %s (%s)", enemyData.name, cellName, killToken))
        else
            writeLog(string.format("Kill logged (no AP checks configured for %s): %s in %s", killToken, enemyData.name, cellName))
        end
    end)
    
    writeLog("Kill tracking initialized successfully")
end

-- Main initialization function
function handleInitialization()
    -- Log path override info
    if pathOverrideLoaded then
        writeLog("Path override active - using custom path: " .. ARCHIPELAGO_BASE_DIR)
    end

    -- Retry encumbrance scaling if the object wasn't ready at script load
    if not encumbranceScalingApplied then
        applyEncumbranceScaling()
    end

    if not checkValidSession() then return end
    
    local settingsLoaded = loadSettings()
    if not settingsLoaded then
        return
    end
    
    -- Initialize kill tracking if enabled
    if killTrackingEnabled then
        initializeKillTracking()
    end
    
    -- If already initialized, we're done
    if modFullyInitialized then return end
    
    -- Handle initialization tasks (only once, when safe to run console commands)
    if needsProgressiveShopStockInit then
        writeLog("Initializing progressive shop stock...")
        needsProgressiveShopStockInit = false
        local success, error = pcall(initializeShopsanity)
        if success then
            progressiveShopStockInitialized = true
            writeLog("Progressive shop stock initialization successful")
        else
            writeLog("Progressive shop stock initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsArenaInit then
        writeLog("Initializing arena...")
        needsArenaInit = false
        local success, error = pcall(initializeArena)
        if success then
            arenaInitialized = true
            writeLog("Arena initialization successful")
        else
            writeLog("Arena initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsShrinesInit then
        writeLog("Initializing shrines...")
        needsShrinesInit = false
        local success, error = pcall(initializeShrines)
        if success then
            shrinesInitialized = true
            writeLog("Shrine initialization successful")
        else
            writeLog("Shrine initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsSidequestsInit then
        writeLog("Initializing sidequests...")
        needsSidequestsInit = false
        local success, error = pcall(initializeSidequests)
        if success then
            sidequestsInitialized = true
            writeLog("Sidequest initialization successful")
        else
            writeLog("Sidequest initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsGatesInit then
        needsGatesInit = false
        local success, error = pcall(initializeGates)
        if success then
            gatesInitialized = true
            writeLog("Oblivion Gate initialization complete")
        else
            writeLog("Gates initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsGateVisionInit and gatesInitialized then
        needsGateVisionInit = false
        local success, error = pcall(initializeGateVision)
        if success then
            gateVisionInitialized = true
            writeLog("Gate vision initialization successful")
        else
            writeLog("Gate vision initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsFastTravelInit then
        writeLog("Initializing fast travel...")
        needsFastTravelInit = false
        local success, error = pcall(initializeFastTravel)
        if success then
            fastTravelInitialized = true
            writeLog("Fast travel initialization successful")
        else
            writeLog("Fast travel initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    if needsClassSystemInit then
        writeLog("Initializing class system...")
        needsClassSystemInit = false
        local success, error = pcall(initializeClassSystem)
        if success then
            classSystemInitialized = true
            writeLog("Class system initialization successful")
        else
            writeLog("Class system initialization failed: " .. tostring(error), "ERROR")
        end
    end

    if needsDungeonCountersInit then
        writeLog("Initializing dungeon counters...")
        needsDungeonCountersInit = false
        local success, error = pcall(initializeDungeonCounters)
        if success ~= false then -- initializeDungeonCounters returns nil on success
            dungeonCountersInitialized = true
            writeLog("Dungeon counters initialization successful")
        else
            writeLog("Dungeon counters initialization failed: " .. tostring(error), "ERROR")
        end
    end
    
    -- Set goal globals and mark initialization complete (only once per seed)
    if not modFullyInitialized then
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
        modFullyInitialized = true
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

-- Track initialization completion for 3-second delay
local initializationCompleteTime = 0
local itemProcessingEnabled = false

-- Periodic processing function - handles ongoing item processing only
local function handlePeriodicProcessing()
    frameCounter = frameCounter + 1
    if frameCounter >= targetFrames then
        frameCounter = 0       
        
    -- Re-check for a valid session every ~5s; also handle mid-session disconnects
    local sessionValid = checkValidSession()
    if sessionValid and not allowAPSync then
        writeLog("Valid AP session detected mid-game")
        allowAPSync = true
        probeStartedForSession = false
    elseif not sessionValid then
        allowAPSync = false
        probeStartedForSession = false
    end

    if (not modFullyInitialized) or (not sessionValid) then
        handleInitialization()
    end

    -- Periodic encumbrance validation: re-apply if needed
    if encumbranceScalingApplied then
        local currentTime = os.time()
        if currentTime - lastEncumbranceValidation >= ENCUMBRANCE_VALIDATION_INTERVAL then
            lastEncumbranceValidation = currentTime
            validateEncumbranceScaling()
        end
    end

    -- Start probe AFTER initialization to avoid reading init console output as APAppliedCount.
    if allowAPSync and modFullyInitialized and not probeFinished and not apProbe.awaiting and not probeStartedForSession
        and not menuCheckInProgress() then
        probeStartedForSession = true
        writeLog("Starting APSync probe (post-init)")
        startAPSyncProbe()
    end
        
        -- Start 3-second timer when initialization completes
        if modFullyInitialized and not itemProcessingEnabled then
            initializationCompleteTime = os.time()
            itemProcessingEnabled = true
            writeLog("Initialization complete - starting 3-second delay before item processing")
        end
        
        -- Check if there are items in the queue (only if mod is fully initialized and 3 seconds have passed)
        if modFullyInitialized and itemProcessingEnabled then
            local currentTime = os.time()
            if currentTime - initializationCompleteTime >= 3 then
                local hasItems = hasItemsInQueue()
                if hasItems then
                    -- Gate item processing until APsync has completed
                    if not probeFinished then
                        -- Only increment if we haven't reached the limit
                        if probeAttemptCount < 3 then
                            probeAttemptCount = probeAttemptCount + 1
                            writeLog("Delaying item processing until APsync completes (attempt " .. probeAttemptCount .. "/3)")
                        end
                        
                        if probeAttemptCount >= 3 then
                            if not probeStuckMessageShown then
                                writeLog("APsync probe failed after 3 attempts - restarting probe", "ERROR")
                                pcall(function()
                                    console.ExecuteConsole('Message "APSync Probe stuck - restarting probe attempt"')
                                end)
                                probeStuckMessageShown = true
                            end
                            -- Kill current probe and restart
                            apProbe.awaiting = false
                            probeAttemptCount = 0
                            probeStuckMessageShown = false
                            if allowAPSync and not menuCheckInProgress() then
                                startAPSyncProbe()
                            end
                        end
                    else
                        probeAttemptCount = 0
                        probeStuckMessageShown = false
                        processItemQueue()
                    end
                end
                
                -- Process item events for display
                processItemEvents()

                -- Process any pending traps
                processTrapQueue()
            end
        end
        
        -- Process messagebox queue
        processMessageboxQueue()
    end
end

-- Use fade-in hook for startup, then switch to tick hook for ongoing processing
local tickHookLoaded = false
local gameStarted = false
local notificationHookRegistered = false
-- Only allow AP sync probe and messaging when a valid AP session is detected
local allowAPSync = false

local probeStartedForSession = false

-- Register fade-in hook for initial startup
RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToGameBeginEventReceived", function()
    -- Reset probe state for this load
    probeFinished = false
    probeStartedForSession = false
    probeAttemptCount = 0  -- Reset attempt counter on each load
    pendingMenuReinitCheck = false
    menuCheckProbe.awaiting = false
    if not gameStarted then
        writeLog("Game fade-in detected")
        gameStarted = true
        
        if not modFullyInitialized then
            writeLog("Mod not fully initialized - running initialization")
            handleInitialization()
        else
            writeLog("Mod already fully initialized - skipping initialization")
        end
        
        if not tickHookLoaded then
            RegisterHook("/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C:ReceiveTick", function()
                local currentTime = os.time()

                -- Icarian Flight trap
                if pendingIcarianFlight then
                    pendingIcarianFlight = false
                    executeIcarianLaunch()
                end

                -- Consume F11 toggle flag here
                if pendingTrackingToggle then
                    pendingTrackingToggle = false
                    if not nirnrootTrackingEnabled and not bossChestTrackingEnabled then
                        -- OFF → next mode. Skip types not in seed or manually suppressed.
                        autoTrackManualOff = false
                        local canNirn = nirnrootInSeed and not nirnrootManualOff
                        local canChest = chestInSeed
                        if canNirn then
                            nirnrootTrackingEnabled = true
                            lastNirnrootMessage = os.clock() - NIRNROOT_MESSAGE_INTERVAL + 3
                            lastTrackingUpdate = 0
                            pcall(function() console.ExecuteConsole('Message "Tracking Nirnroot"') end)
                        elseif canChest then
                            bossChestTrackingEnabled = true
                            lastBossChestMessage = 0
                            lastTrackingUpdate = 0
                            pcall(function() console.ExecuteConsole('Message "Tracking Boss Chests"') end)
                        else
                            autoTrackManualOff = true
                            clearAPXMarker()
                            pcall(function() console.ExecuteConsole('Message "Tracking OFF"') end)
                        end
                    elseif nirnrootTrackingEnabled then
                        nirnrootTrackingEnabled = false
                        if chestInSeed then
                            clearAPXMarker()
                            bossChestTrackingEnabled = true
                            lastBossChestMessage = 0
                            lastTrackingUpdate = 0
                            pcall(function() console.ExecuteConsole('Message "Tracking Boss Chests"') end)
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

                -- Always run periodic processing (items, events, retries, etc.)
                handlePeriodicProcessing()

                readCellLookupConsole()
                processPendingMenuReinitCheck()
                apReadConsoleAndEmitCount()
                processPendingFadeActions()

                if nirnrootTrackingEnabled or bossChestTrackingEnabled then
                    updatePeriodicTracking()
                end

                
                -- Ensure tutorial hooks are registered
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
                            -- When menu state changes, re-broadcast the active message to restore text if cleared
                            local inMenuNow = false
                            local okMenu, resMenu = pcall(IsPlayerInMenu)
                            if okMenu then inMenuNow = resMenu end
                            
                            if inMenuNow then
                                -- If a tutorial is currently active and it's our AP message, convert it to a console Message
                                local isActive = false
                                pcall(function()
                                    if widget.CurrentDisplayTime and widget.CurrentDisplayTime > 0.0 then isActive = true end
                                end)
                                if isActive and lastAPTutorialMessage ~= "" then
                                    pcall(function()
                                        console.ExecuteConsole("Message \"" .. escapeForConsole(lastAPTutorialMessage) .. "\"")
                                    end)
                                    lastAPTutorialMessage = ""
                                end
                                -- Entered a menu: decisively close the tutorial box
                                CloseTutorialByTimeSqueeze(widget)
                                HardHideTutorialWidget(widget)
                            end
                            -- Menu baseline tracking not needed beyond this point
                        end)
                    end)
                    if success then
                        writeLog("Successfully hooked SetMenuMode")
                        setMenuModeHooked = true
                    end
                end
                -- Freeze watcher: on transition to freezing, convert AP message to console then close the tutorial display
                local isFreezing = isGameFreezing()
                if isFreezing and not lastFreezeState then
                    local widget = FindByName("WBP_ModernTutorialDisplay_C", "WBP_PrimaryGameLayout_C")
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
            end)
            tickHookLoaded = true
            writeLog("Tick hook registered for ongoing processing")
        end
    end

    -- Deploy APSync Probe per OnFadeToGameBeginEvent (only if client is connected).
    allowAPSync = checkValidSession()
    if allowAPSync then
        if not probeFinished and not apProbe.awaiting and not menuCheckInProgress() then
            startAPSyncProbe()
            probeStartedForSession = true
        end
    else
        writeLog("Skipping APSync probe - no valid Archipelago session")
    end

    -- On cell transition: refresh cell state and clear the actor table
    -- Runs when kill tracking OR auto-track mode is active.
    if killTrackingEnabled or archipelagoSettings.auto_tracking then
        currentCellName = nil
        currentCellEditorID = nil
        currentCellIsOblivion = false
        cellNameRequestPending = false

        -- Detect worldspace directly from the world name.
        local worldName = ""
        pcall(function()
            local player = UEHelpers:GetPlayer()
            if player and player:IsValid() then
                worldName = player:GetWorld():GetFullName() or ""
            end
        end)

        if worldName:find("Tamriel") then
            currentCellName = "Tamriel"
            currentCellIsOblivion = false
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
            -- Oblivion worldspace (exterior Oblivion plane, e.g. OblivionRD001, OblivionMQKvatch)
            local mapName = worldName:match("/([^/]+)%.") or worldName:match("/([^/]+)$") or "Oblivion Plane"
            currentCellName = mapName
            currentCellIsOblivion = true
            writeLog("Cell set to Oblivion worldspace: " .. mapName)
            if shouldAutoTrack() then
                pendingAutoTrack = "off"
                pendingMarkerClear = true
            end
        else
            pendingCellLookup = true
            cellNameRequestPending = true
            if shouldAutoTrack() and chestInSeed then
                pendingMarkerClear = true
                pendingAutoTrack = "boss"
            end
        end

        if killTrackingEnabled and ActorDetection then
            ActorDetection.ClearKilledActors()
        end
    end
    
    -- Register notification hook for event tracking (guard to prevent duplicates)
        if not notificationHookRegistered then
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

            -- Shorten vanilla inventory add notifications
            if text:match('^%d+ .- added to the player\'s inventory$')
               and not text:match('^%d+ AP .- Completion Token added to the player\'s inventory$') then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 1.5
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
                        if modFullyInitialized then
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

                -- Validate against settings-chosen dungeons and ensure its region is unlocked via receipts
                local regionName = findRegionForDungeon(clearedName)
                if regionName and isRegionUnlockedViaReceipts(regionName) then
                    -- Check if this dungeon was already cleared
                    if isCompletionAlreadyRecorded(text) then
                        writeLog("Duplicate dungeon clear detected, ignoring: " .. clearedName, "DEBUG")
                    else
                        -- Send completion to AP client
                        writeCompletionStatus(text) -- Preserve existing completion token format
                        writeLog("Validated Dungeon Cleared: " .. clearedName .. " (Region: " .. regionName .. ")")

                        -- Decrement AP<Region>DungeonCount by 1
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
                        
                        -- Signal in-game quest to offer warp
                        local okWarp, errWarp = pcall(function()
                            console.ExecuteConsole("set APOfferWarp to 1")
                        end)
                        if okWarp then
                            writeLog("Set APOfferWarp to 1 for dungeon clear: " .. clearedName)
                        else
                            writeLog("Failed to set APOfferWarp: " .. tostring(errWarp), "ERROR")
                        end
                    end
                else
                    -- Not validated; just log
                    if regionName then
                        writeLog("Dungeon Clear ignored (region locked): '" .. tostring(clearedName) .. "' in region '" .. tostring(regionName) .. "'", "DEBUG")
                    else
                        writeLog("Dungeon Clear not found in this seed: '" .. tostring(clearedName) .. "'", "WARNING")
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
            
            -- Handle Nirnroot harvest messages
            if text == "Nirnroot Harvested" then
                -- Hide the notification
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                -- Send check to client
                writeCompletionStatus("Nirnroot Harvested")
                writeLog("Nirnroot Harvested check sent to client")
                
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
            

            -- ========================================
            -- DEBUG SECTION, LEAVE FOR NOW BUT CAN CLEAN UP LATER
            -- ========================================
            -- Handle Kill Tracking Toggle Commands
            if text == "APKillTracking Enable" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                if not killTrackingEnabled then
                    killTrackingEnabled = true
                    initializeKillTracking()
                    writeLog("Kill tracking enabled via console command")
                    pcall(function()
                        console.ExecuteConsole('Message "Kill tracking enabled"')
                    end)
                else
                    writeLog("Kill tracking already enabled")
                    pcall(function()
                        console.ExecuteConsole('Message "Kill tracking already enabled"')
                    end)
                end
                return
            end
            
            if text == "APKillTracking Disable" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                killTrackingEnabled = false
                writeLog("Kill tracking disabled via console command")
                pcall(function()
                    console.ExecuteConsole('Message "Kill tracking disabled"')
                end)
                return
            end
            
            -- Handle Nirnroot Detection and Guidance
            if text == "AP_FIND_NIRNROOT" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                if not nirnrootInSeed then return end
                writeLog("Nirnroot detection triggered")
                
                if not ActorDetection then
                    local success, module = pcall(function() return require("ActorDetection") end)
                    if success then ActorDetection = module else return end
                end
                
                local player = UEHelpers:GetPlayer()
                if not player then
                    writeLog("Player not found for Nirnroot detection", "ERROR")
                    return
                end
                
                local nirnroot, error = ActorDetection.FindNearestNirnroot(player)
                
                if nirnroot then
                    writeLog(string.format("Nirnroot found: %dm %s (bearing %d°)", 
                        nirnroot.distanceMeters, nirnroot.compassDirection, nirnroot.bearing))
                    
                    -- Send two separate simple messages
                    pcall(function()
                        console.ExecuteConsole('Message "Nirnroot detected"')
                    end)
                    
                    local detailMsg = string.format('Message "direction - %s, distance: %dm"', nirnroot.compassDirection, nirnroot.distanceMeters)
                    pcall(function()
                        console.ExecuteConsole(detailMsg)
                    end)
                else
                    local errorMsg = error or "No Nirnroot found"
                    writeLog("Nirnroot detection failed: " .. errorMsg)
                    pcall(function()
                        console.ExecuteConsole('Message "No Nirnroot found"')
                    end)
                end
                return
            end
            
            -- Handle Boss Container Search
            if text == "AP_FIND_BOSS_CHEST" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                writeLog("Boss container search triggered")
                
                if not ActorDetection then
                    local success, module = pcall(function() return require("ActorDetection") end)
                    if success then ActorDetection = module else return end
                end
                
                local containers = ActorDetection.DetectNearbyContainers()
                local bossContainers = {}
                
                for formID, data in pairs(containers) do
                    if data.fullName:lower():match("boss") or data.name:lower():match("boss") then
                        table.insert(bossContainers, {
                            formID = formID,
                            name = data.name,
                            fullName = data.fullName,
                            location = data.location
                        })
                    end
                end
                
                if #bossContainers > 0 then
                    writeLog("Found " .. #bossContainers .. " boss containers")
                    pcall(function()
                        console.ExecuteConsole('Message "Found ' .. #bossContainers .. ' boss containers nearby"')
                    end)
                else
                    writeLog("No boss containers found")
                    pcall(function()
                        console.ExecuteConsole('Message "No boss containers found in range"')
                    end)
                end
                return
            end

            -- ========================================
            -- ^^^  DEBUG SECTION, LEAVE FOR NOW BUT CAN CLEAN UP LATER
            -- ========================================
            
            -- Cycle tracking mode: Off -> Nirnroot -> Boss Chest -> Off
            -- Triggered by F11 keybind
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
                        lastBossChestMessage = 0
                        lastTrackingUpdate = 0
                        pcall(function() console.ExecuteConsole('Message "Tracking Boss Chest ON"') end)
                    end
                elseif nirnrootTrackingEnabled then
                    nirnrootTrackingEnabled = false
                    if canChest then
                        clearAPXMarker()
                        bossChestTrackingEnabled = true
                        lastBossChestMessage = 0
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

            -- Handle Nirnroot Tracking Toggle
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
            
            -- Handle Boss Chest Tracking Toggle
            if text == "AP_TRACK_BOSS_CHEST" then
                pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                bossChestTrackingEnabled = not bossChestTrackingEnabled
                
                if bossChestTrackingEnabled then
                    lastTrackingUpdate = 0  -- Force immediate update
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
        notificationHookRegistered = true
        writeLog("Notification hook registered for event tracking")
        end
    end)

-- F11 keybind registration
RegisterKeyBind(Key.F11, function()
    pendingTrackingToggle = true
end)


