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

-- Base directory for all Archipelago files
local ARCHIPELAGO_BASE_DIR = os.getenv("USERPROFILE") .. "\\Documents\\My Games\\Oblivion Remastered\\Saved\\Archipelago"

-- Quality-of-life settings
local archipelagoSettings = {
    free_offerings = true,  -- Automatically add shrine offerings when receiving shrine tokens
    dungeon_marker_mode = "reveal_and_fast_travel" -- or "reveal_only"
}

-- Queue for displaying messages when multiple items are processed
local messageboxQueue = {}

-- Session flags to track initialization status
local progressiveShopStockInitialized = false
local arenaInitialized = false
local shrinesInitialized = false
local gatesInitialized = false
local gateVisionInitialized = false
local fastTravelInitialized = false
local classSystemInitialized = false
local modFullyInitialized = false

-- Feather effect removal timing
local featherRemoveTime = nil

-- Initialization flags
local needsProgressiveShopStockInit = false
local needsArenaInit = false
local needsShrinesInit = false
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


local function getArchipelagoPath(filename)
    return ARCHIPELAGO_BASE_DIR .. "\\" .. filename
end


-- Logging function with timestamp and level support
local function writeLog(message, level)
    level = level or "INFO"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logMessage = string.format("[%s] [%s] %s", timestamp, level, message)
    
    local logPath = getArchipelagoPath("archipelago_debug.log")
    local file = io.open(logPath, "a")
    if file then
        file:write(logMessage .. "\n")
        file:close()
    end
end

local function initializeLog()
    os.execute('mkdir "' .. ARCHIPELAGO_BASE_DIR .. '" 2>nul')
    writeLog("Archipelago Mod Initialized")
end

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
}

pcall(function()
    PropertyTypes.ArrayProperty.Size = 0x10
    RegisterCustomProperty({ Name = "OutputBuffer", Type = PropertyTypes.ArrayProperty, BelongsToClass = "/Script/Engine.Console", OffsetInternal = 0x50, ArrayProperty = { Type = PropertyTypes.StrProperty } })
    RegisterCustomProperty({ Name = "OutputBufferSize", Type = PropertyTypes.IntProperty, BelongsToClass = "/Script/Engine.Console", OffsetInternal = 0x58 })
end)

local function apFindConsole()
    if apProbe.console and apProbe.console:IsValid() then return apProbe.console end
    local inst = FindFirstOf("Console")
    if inst and inst:IsValid() then apProbe.console = inst end
    return apProbe.console
end

local function apReadConsoleAndEmitCount()
    local inst = apFindConsole(); if not inst then return end
    local newCount = inst.OutputBufferSize
    if apProbe.awaiting and newCount > apProbe.lastCount then
        local value = nil
        for i = apProbe.lastCount, newCount - 1 do
            local line = inst.OutputBuffer[i+1]:ToString()
            local v = line:match(">>%s*(%d+)") or line:match("^(%d+)$")
            if v then value = v end
        end
    if value then
            if not probeFinished then
                local ingameCount = tonumber(value) or 0
                local diskCount = getBridgeStatusAPCount()
                local diff = diskCount - ingameCount
                writeLog("AP sync: in-game=" .. tostring(ingameCount) .. ", bridge=" .. tostring(diskCount) .. ", diff=" .. tostring(diff))
                -- Defer zero-count diff handling to the notification hook so it can prompt for reinit or auto-init
                if ingameCount ~= 0 then
                    if ingameCount > diskCount then
                        -- Keep probe unfinished to block processing; notification hook will show the messagebox
                    elseif diff > 0 and diff <= 20 then
                        local removed = truncateBridgeStatusTail(diff)
                        pcall(function()
                            console.ExecuteConsole("Message \"APSync: requesting resend of " .. tostring(removed) .. " items\"")
                        end)
                        probeFinished = true
                    elseif diff > 20 then
                        pcall(function()
                            console.ExecuteConsole("set APSyncRequest to 1")
                        end)
                        -- wait for APPROVED/DENIED before marking handled
                    else
                        probeFinished = true
                    end
                end
            end
            pcall(function()
                console.ExecuteConsole('Message "AP_SYNC COUNT ' .. tostring(value) .. '"')
            end)
            apProbe.awaiting = false
        end
    end
    apProbe.lastCount = newCount
end

local function startAPSyncProbe()
    apFindConsole()
    apProbe.awaiting = true
    apProbe.lastCount = apProbe.console and apProbe.console.OutputBufferSize or 0
    pcall(function()
        console.ExecuteConsole('GetGS "Start {ID:APSYNC}"')
        console.ExecuteConsole('GetGlobalValue APAppliedCount')
        console.ExecuteConsole('GetGS "End"')
    end)
end


-- Sync tracking and helpers
local probeFinished = false

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
    gatesInitialized = false
    gateVisionInitialized = false
    fastTravelInitialized = false
    classSystemInitialized = false
    dungeonCountersInitialized = false
    needsProgressiveShopStockInit = false
    needsArenaInit = false
    needsShrinesInit = false
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
        return nil  -- No connection file exists
    end
    
    for line in file:lines() do
        local prefix = line:match("^file_prefix=(.+)$")
        if prefix then
            file:close()
            return prefix
        end
    end
    file:close()
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
                    message = "You found your " .. itemName .. " at " .. target
                elseif eventType == "sent" then
                    message = "You sent '" .. itemName .. "' to '" .. target .. "'"
                elseif eventType == "received" then
                    message = target .. " found your " .. itemName
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
    -- Exact formats emitted by processItemEvents when routed via console 'Message'
    -- 1) You found your <item> at <target>
    if text:match("^You found your .- at .-$") then return true end
    -- 2) You sent '<item>' to '<target>'
    if text:match("^You sent%s*'.-'%s*to%s*'.-'$") then return true end
    -- 3) <someone> found your <item>
    if text:match("^.+%s+found your%s+.-$") then return true end
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
            elseif key == "selected_class" then
                selectedClass = value
                writeLog("Found selected_class: " .. value)
            end
        end
    end
    file:close()
    
    -- Set flags if we have settings but haven't initialized yet (using session flags)
    needsProgressiveShopStockInit = hasProgressiveShopStockSettings and not progressiveShopStockInitialized
    needsArenaInit = hasArenaSettings and not arenaInitialized
    needsShrinesInit = hasShrineSettings and not shrinesInitialized
    needsGatesInit = not gatesInitialized
    needsGateVisionInit = hasGateVisionSettings and not gateVisionInitialized
    needsFastTravelInit = hasFastTravelSettings and not fastTravelInitialized
    needsClassSystemInit = hasClassSystemSettings and not classSystemInitialized
    needsDungeonCountersInit = hasDungeonSettings and not dungeonCountersInitialized
    
    writeLog("Settings loaded - needsProgressiveShopStockInit: " .. tostring(needsProgressiveShopStockInit) .. ", needsArenaInit: " .. tostring(needsArenaInit) .. ", needsShrinesInit: " .. tostring(needsShrinesInit) .. ", needsGatesInit: " .. tostring(needsGatesInit) .. ", needsGateVisionInit: " .. tostring(needsGateVisionInit) .. ", needsFastTravelInit: " .. tostring(needsFastTravelInit) .. ", needsClassSystemInit: " .. tostring(needsClassSystemInit))
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
    
    -- Check if already initialized
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value and key == "arena_initialized" and value == "True" then
            initialized = true
            break
        end
    end
    file:close()
    
    if initialized then 
        return 
    end
    
    -- Set APArenaRank to 0 to block arena progression until unlocks are received
    console.ExecuteConsole("set APArenaRank to 0")
    writeLog("Arena initialization complete - APArenaRank set to 0")
    
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
        local count = getRegionDungeonCountFromSettings(regionName) or 0
        local regionVar = "AP" .. regionName:gsub("%W", "") .. "DungeonCount"
        local okSet, errSet = pcall(function()
            console.ExecuteConsole("set " .. regionVar .. " to " .. tostring(count))
        end)
        if okSet then
            writeLog("Initialized " .. regionVar .. " to " .. tostring(count))
        else
            writeLog("Failed to set " .. regionVar .. ": " .. tostring(errSet), "ERROR")
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
            
            -- Check if this is the final shop check value in the queue
            local currentValue = tonumber(itemName:match("APShopCheckValue(%d+)"))
            local isFinalShopCheck = true
            
            -- Look ahead in the queue to see if there are higher value shop check items
            for i = #itemsToProcess, 1, -1 do
                local futureItem = itemsToProcess[i]
                if futureItem:match("^APShopCheckValue%d+$") then
                    local futureValue = tonumber(futureItem:match("APShopCheckValue(%d+)"))
                    if futureValue and futureValue > currentValue then
                        isFinalShopCheck = false
                        break
                    end
                end
            end
            
            -- Show message for final shop check value
            if isFinalShopCheck then
                local randomMessage = config.shopStockMessages[math.random(1, #config.shopStockMessages)]
                queueMessagebox(randomMessage)
            end
            
            table.insert(processedItems, itemName)
        -- Handle Oblivion Gate Vision - set console variable
        elseif itemName == "Oblivion Gate Vision" then
            writeLog("Processing Oblivion Gate Vision - setting APGateMarkersVisible to 1")
            local success, result = pcall(function()
                console.ExecuteConsole("set APGateMarkersVisible to 1")
            end)
            
            if success then
                writeLog("Successfully set APGateMarkersVisible to 1")
                
                -- Show gate vision message
                local randomMessage = config.gateVisionMessages[math.random(1, #config.gateVisionMessages)]
                queueMessagebox(randomMessage)
                
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
                    
                    -- Check if this is the first arena unlock item in the queue
                    local isFirstArenaUnlock = true
                    for i = 1, #itemsToProcess do
                        if itemsToProcess[i]:match("^APArena.*Unlock$") and itemsToProcess[i] ~= itemName then
                            isFirstArenaUnlock = false
                            break
                        elseif itemsToProcess[i] == itemName then
                            break
                        end
                    end
                    
                    -- Show arena unlock message only once
                    if isFirstArenaUnlock then
                        if itemName == "APArenaPitDogUnlock" then
                            queueMessagebox("The gates of the Arena are now open to you.")
                        else
                            local randomMessage = config.arenaMessages[math.random(1, #config.arenaMessages)]
                            queueMessagebox(randomMessage)
                        end
                    end
                    
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
                    -- start a 30 second timer for feather removal
                    featherRemoveTime = os.time() + 30
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
        -- Handle Birth Sign item
        elseif itemName == "Birth Sign" then
            writeLog("Processing Birth Sign item - showing birth sign menu and setting APBirthSignSet")
            local success, result = pcall(function()
                console.ExecuteConsole("showbirthsignmenu")
                console.ExecuteConsole("set APBirthSignSet to 1")
            end)
            
            if success then
                writeLog("Birth sign menu shown; APBirthSignSet = 1")
                table.insert(processedItems, itemName)
            else
                writeLog("Failed to process Birth Sign item: " .. tostring(result), "ERROR")
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
    local connectionPath = getArchipelagoPath("current_connection.txt")
    local connectionFile = io.open(connectionPath, "r")
    if not connectionFile then
        -- No connection file found
        if not hasShownNoSettingsMessage then
            local success = pcall(function()
                console.ExecuteConsole("MessageBox \"No connection file found, is your AP client connected?\"")
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

-- Main initialization function
function handleInitialization()
    if not checkValidSession() then return end
    
    local settingsLoaded = loadSettings()
    if not settingsLoaded then
        return
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
            end
        end)
        
        if not success then
            writeLog("Failed to set goal globals", "ERROR")
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
    if (not modFullyInitialized) or (not checkValidSession()) then
            handleInitialization()
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
                        writeLog("Delaying item processing until APsync completes")
                    else
                        processItemQueue()
                    end
                end
                
                -- Process item events for display
                processItemEvents()
            end
        end
        
        -- Process messagebox queue
        processMessageboxQueue()
        
        -- Check if it's time to remove feather effect
        if featherRemoveTime and os.time() >= featherRemoveTime then
            local success, result = pcall(function()
                console.ExecuteConsole("Player.RemoveSpell APStandardFeather5Master")
            end)
            if success then
                writeLog("Removed feather effect after 30 seconds")
            else
                writeLog("Failed to remove feather effect: " .. tostring(result), "ERROR")
            end
            featherRemoveTime = nil
        end
    end
end

-- Use fade-in hook for startup, then switch to tick hook for ongoing processing
local tickHookLoaded = false
local gameStarted = false
local notificationHookRegistered = false
-- Only allow AP sync probe and messaging when a valid AP session is detected
local allowAPSync = false

-- Register fade-in hook for initial startup
RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToGameBeginEventReceived", function()
    -- Reset probe state for this load
    probeFinished = false
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
                
                -- Always run periodic processing (items, events, retries, etc.)
                handlePeriodicProcessing()

                -- Read console output and emit AP_SYNC COUNT if ready
                apReadConsoleAndEmitCount()
                
                -- Ensure tutorial hooks are registered (only once each)
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

    -- Deploy APSync Probe per OnFadeToGameBeginEvent (only if client is connected)
    allowAPSync = checkValidSession()
    if allowAPSync then
        if not probeFinished and not apProbe.awaiting then
            startAPSyncProbe()
        end
    else
        writeLog("Skipping APSync probe - no valid Archipelago session")
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
            
            -- intercept our probe command and fetch APAppliedCount
            if text == 'ConsoleCommand Message AP_SYNC COUNT ((GetGlobalValue APAppliedCount))' then
                -- Ignore if already handled or in-flight
                if not probeFinished and not apProbe.awaiting then
                    startAPSyncProbe()
                end
                actualHudVM.Notification.ShowSeconds = 0.0001
                return
            end
            
            -- Ignore notifications that were generated by processItemEvents display logic
            if isAPItemEventNotification(text) then
                -- Don't treat AP item-event messages as completion triggers
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
                            -- Already initialized on this seed: prompt user to confirm reinit for this new save
                            if not reinitPending then
                                local ok = pcall(function()
                                    console.ExecuteConsole('set APReinitRequest to 1')
                                end)
                                if ok then
                                    writeLog("Requested reinit confirmation for this save (APReinitRequest=1) due to APAppliedCount=0 with prior initialization")
                                    reinitPending = true
                                end
                            end
                            -- Wait for APPROVED/DENIED
                            return
                        else
                            -- Not initialized yet for this seed: perform initialization now
                            writeLog("APAppliedCount=0 and settings indicate not initialized; performing initialization")
                            handleInitialization()
                            -- Continue into normal diff handling below
                        end
                    end
                    -- in-game has more than disk; block this load
                    if ingameCount > diskCount then
                        pcall(function()
                            console.ExecuteConsole("MessageBox \"This save has more Archipelago items than your current AP session. Load a matching save, or connect the client to this save's slot/seed.\"")
                        end)
                        -- Keep probeFinished=false to block processing for this load
                        return
                    end
                    if diff > 0 and diff <= 20 then
                        local removed = truncateBridgeStatusTail(diff)
                        pcall(function()
                            console.ExecuteConsole("Message \"APSync: requesting resend of " .. tostring(removed) .. " items\"")
                        end)
                        probeFinished = true
                        return
                    elseif diff > 20 then
                        pcall(function()
                            console.ExecuteConsole("set APSyncRequest to 1")
                        end)
                        return
                    else
                        probeFinished = true
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
                    return
                end

                if text == "AP_SYNC DENIED" and not probeFinished then
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    writeLog("AP sync large resend denied by player")
                    probeFinished = true
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
            
            -- Handle quest completion notifications
            local completionMatch = text:match("AP (.+) Completion Token added to the player's inventory")
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

            -- Check for dungeon cleared messages
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

            -- Temporarily disable wayshrine, runestone, and doomstone tracking
            --[[
            -- Check for wayshrine visited messages
            if text == "Wayshrine Visited" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                writeCompletionStatus("Wayshrine Visited")
                writeLog("Wayshrine Visited")
                return
            end
            
            -- Check for runestone visited messages
            if text == "Runestone Visited" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                writeCompletionStatus("Runestone Visited")
                writeLog("Runestone Visited")
                return
            end
            
            -- Check for doomstone visited messages
            if text == "Doomstone Visited" then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                writeCompletionStatus("Doomstone Visited")
                writeLog("Doomstone Visited")
                return
            end
            --]]

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
        end)
        notificationHookRegistered = true
        writeLog("Notification hook registered for event tracking")
        end
    end)

