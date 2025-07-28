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

-- Settings for shrine offering automation
local archipelagoSettings = {
    free_offerings = true  -- Automatically add shrine offerings when receiving shrine tokens
}

-- Queue for displaying messages when multiple items are processed
local messageboxQueue = {}

-- Session flags to track initialization status
local progressiveShopStockInitialized = false
local arenaInitialized = false
local shrinesInitialized = false
local gatesInitialized = false
local gateVisionInitialized = false
local modFullyInitialized = false

-- Initialization flags
local needsProgressiveShopStockInit = false
local needsArenaInit = false
local needsShrinesInit = false
local needsGatesInit = false
local needsGateVisionInit = false
local hasShownNoSettingsMessage = false


-- Frame counter for periodic item processing (every 5 seconds at 60fps)
local frameCounter = 0
local targetFrames = 300


-- Current goal from settings file
local currentGoal = ""
local goalRequired = 0


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

-- Get current connection file prefix (enables simultaneous sessions)
local function getCurrentFilePrefix()
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
local function loadSettings()
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
    
    writeLog("Settings loaded - needsProgressiveShopStockInit: " .. tostring(needsProgressiveShopStockInit) .. ", needsArenaInit: " .. tostring(needsArenaInit) .. ", needsShrinesInit: " .. tostring(needsShrinesInit) .. ", needsGatesInit: " .. tostring(needsGatesInit) .. ", needsGateVisionInit: " .. tostring(needsGateVisionInit))
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
    
    -- Set APGatesEnabled to 1 to enable Oblivion Gates
    console.ExecuteConsole("set APGatesEnabled to 1")
    writeLog("Gates initialization complete - APGatesEnabled set to 1")
    
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

-- Write processed items to bridge status file as a receipt
local function updateBridgeStatus(processedItems)
    local filePrefix = getCurrentFilePrefix()
    if not filePrefix then
        return
    end
    
    local statusPath = getArchipelagoPath(filePrefix .. "_bridge_status.txt")
    
    local itemsString = table.concat(processedItems, ",")
    
    local file = io.open(statusPath, "a")
    if file then
        file:write(itemsString .. ",")
        file:close()
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
    
    writeLog("Total items to process: " .. #itemsToProcess)
    
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
        writeLog("Processing item: '" .. itemName .. "'")
        
        -- Handle shop check items - add to merchant chests
        if itemName:match("^APShopCheckValue%d+$") then
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
        else
            local edid = config.itemMappings[itemName]
            if edid then
                -- Set quantity based on item type
                local quantity = 1
                if itemName:find("Potion") then
                    quantity = 3
                elseif itemName == "Gold" then
                    quantity = 500
                end
                
                local addItemCommand = "player.additem " .. edid .. " " .. quantity
                local success, result = pcall(function()
                    console.ExecuteConsole(addItemCommand)
                end)
                
                if success then
                    writeLog("Added item: " .. itemName .. " x" .. quantity)
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
        writeLog("Quest completed: " .. completionTokenEdid)
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
            else
                writeLog("Failed to display 'no settings file' message", "ERROR")
            end
        end
        return false  -- No valid session
    end
    file:close()
    
    return true  -- Valid session found
end

-- Main initialization function
local function handleInitialization()
    if not checkValidSession() then
        return
    end
    
    local settingsLoaded = loadSettings()
    if not settingsLoaded then
        return
    end
    
    -- If already initialized, we're done
    if modFullyInitialized then
        writeLog("Mod already fully initialized from previous session")
        return
    end
    
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
            writeLog("Oblivion Gates opened")
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
    
    -- Check if goal message needs to be shown (only once per seed)
    if not modFullyInitialized then
        -- Set goal-specific global variables based on goal type
        if currentGoal == "shrine_seeker" and goalRequired > 0 then
            console.ExecuteConsole("set APShrineVictoryGoal to " .. tostring(goalRequired))
            writeLog("Set APShrineVictoryGoal to " .. tostring(goalRequired))
        elseif currentGoal == "gatecloser" and goalRequired > 0 then
            console.ExecuteConsole("set APGateVictoryGoal to " .. tostring(goalRequired))
            writeLog("Set APGateVictoryGoal to " .. tostring(goalRequired))
        end
        
        -- Map goal values to display names
        local goalDisplayNames = {
            ["gatecloser"] = "Gatecloser",
            ["shrine_seeker"] = "Shrine Seeker", 
            ["arena"] = "Arena Champion"
        }
        
        -- Get display name or use original if not found
        local displayGoal = goalDisplayNames[currentGoal] or currentGoal
        
        -- Show goal message
        local goalMessage = "Archipelago Initialization Complete!  Goal: " .. displayGoal
        if goalRequired > 0 and (currentGoal == "shrine_seeker" or currentGoal == "gatecloser") then
            goalMessage = goalMessage .. " (" .. tostring(goalRequired) .. ")"
        end
        
        -- Show goal message
        local success = pcall(function()
            console.ExecuteConsole("MessageBox \"" .. goalMessage .. "\"")
        end)
        
        if success then
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
            else
                writeLog("Failed to write mod_fully_initialized to settings file", "ERROR")
            end
            

        else
            writeLog("Failed to display goal message", "ERROR")
        end
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
        
        -- Check if we need to reinitialize (if we previously had no valid session)
        if hasShownNoSettingsMessage and not modFullyInitialized then
            writeLog("Checking for valid session...")
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
                    processItemQueue()
                end
            end
        end
        
        -- Process messagebox queue
        processMessageboxQueue()
    end
end

-- Use fade-in hook for startup, then switch to tick hook for ongoing processing
local tickHookLoaded = false
local gameStarted = false

-- Register fade-in hook for initial startup
RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToGameBeginEventReceived", function()
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
                handlePeriodicProcessing()
            end)
            tickHookLoaded = true
            writeLog("Tick hook registered for ongoing processing")
        end
        
        -- Register notification hook for event tracking
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
                
                -- Check if arena is the current goal and show completion message
                if currentGoal == "arena" then
                    pcall(function()
                        console.ExecuteConsole("MessageBox \"Arena Goal Complete!\"")
                    end)
                    
                    -- Write Victory to completion file
                    writeCompletionStatus("Victory")
                    writeLog("Arena Victory written to completion file")
                end
                
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

            -- Handle APReset command
            if text == "APReset" then
                writeLog("=== APReset COMMAND RECEIVED ===")
                actualHudVM.Notification.ShowSeconds = 0.0001
                
                -- Check if there's a current connection file first
                local connectionPath = getArchipelagoPath("current_connection.txt")
                local connectionFile = io.open(connectionPath, "r")
                if not connectionFile then
                    writeLog("No current_connection.txt found - cannot reset without active connection")
                    console.ExecuteConsole("MessageBox \"No connection file found. Please connect your client first.\"")
                    return
                end
                connectionFile:close()
                
                -- Get current session prefix before deleting files
                local filePrefix = getCurrentFilePrefix()
                if filePrefix then
                    local filesToDelete = {
                        filePrefix .. "_settings.txt",
                        filePrefix .. "_items.txt", 
                        filePrefix .. "_bridge_status.txt",
                        filePrefix .. "_completed.txt"
                    }
                    
                    for _, filename in ipairs(filesToDelete) do
                        local filePath = getArchipelagoPath(filename)
                        os.remove(filePath)
                        writeLog("Deleted: " .. filename)
                    end
                    
                    -- Clear all internal flags
                    modFullyInitialized = false
                    progressiveShopStockInitialized = false
                    arenaInitialized = false
                    shrinesInitialized = false
                    gatesInitialized = false
                    gateVisionInitialized = false
                    hasShownNoSettingsMessage = false
                    needsProgressiveShopStockInit = false
                    needsArenaInit = false
                    needsShrinesInit = false
                    needsGatesInit = false
                    needsGateVisionInit = false
                    itemProcessingEnabled = false
                    initializationCompleteTime = 0

                    -- Prevent "no settings" message during reinitialization
                    hasShownNoSettingsMessage = true
                    
                    writeLog("=== APReset COMPLETE - All session files deleted ===")
                    console.ExecuteConsole("MessageBox \"APReset complete. Please reconnect your Archipelago client.\"")
                    
                    -- Reinitialize
                    handleInitialization()
                else
                    writeLog("Connection file exists but no valid prefix found")
                    console.ExecuteConsole("MessageBox \"Connection file exists but no valid session found.\"")
                end
                return
            end
            
            -- Handle Resend command (e.g., "Resend 3" removes last 3 items from bridge status)
            local resendMatch = text:match("^Resend (%d+)$")
            if resendMatch then
                local numItems = tonumber(resendMatch)
                if numItems and numItems > 0 then
                    writeLog("Resend " .. numItems .. " command received")
                    actualHudVM.Notification.ShowSeconds = 0.0001
                    
                    local filePrefix = getCurrentFilePrefix()
                    if filePrefix then
                        local statusPath = getArchipelagoPath(filePrefix .. "_bridge_status.txt")
                        local file = io.open(statusPath, "r")
                        if file then
                            local content = file:read("*all")
                            file:close()
                            
                            if content and content ~= "" then
                                local items = {}
                                for item in content:gmatch("([^,]+)") do
                                    table.insert(items, item)
                                end
                                
                                local itemsToRemove = math.min(numItems, #items)
                                for i = 1, itemsToRemove do
                                    table.remove(items)
                                end
                                
                                file = io.open(statusPath, "w")
                                if file then
                                    if #items > 0 then
                                        file:write(table.concat(items, ",") .. ",")
                                    end
                                    file:close()
                                    writeLog("Removed " .. itemsToRemove .. " items from bridge status")
                                    console.ExecuteConsole("MessageBox \"Removed " .. itemsToRemove .. " items. Client will resend them.\"")
                                end
                            end
                        end
                    end
                    return
                end
            end
            
            -- Handle Dungeon "Check:" command
            local messageMatch = text:match("^Message \"Check: (.+)\"$")
            if messageMatch then
                local dungeonName = messageMatch
                local isSupported = false
                
                for _, dungeon in ipairs(config.supportedDungeons) do
                    if dungeon == dungeonName then
                        isSupported = true
                        break
                    end
                end
                
                local response = isSupported and "Yes" or "No"
                console.ExecuteConsole("MessageBox \"" .. response .. "\"")
                writeLog("Dungeon check: " .. dungeonName .. " -> " .. response)
                return
            end
            
            -- Handle direct "Check:" command
            local directCheckMatch = text:match("^Check: (.+)$")
            if directCheckMatch then
                -- Hide the player's message
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                local dungeonName = directCheckMatch
                local isSupported = false
                
                for _, dungeon in ipairs(config.supportedDungeons) do
                    if dungeon == dungeonName then
                        isSupported = true
                        break
                    end
                end
                
                local response = isSupported and "Yes" or "No"
                pcall(function()
                    console.ExecuteConsole("Message \"" .. dungeonName .. ": " .. response .. "\"")
                end)
                writeLog("Dungeon check: " .. dungeonName .. " -> " .. response)
                
                return
            end
            
            -- Check for skill increase messages
            local skillName = text:match("Your (.+) skill has increased%.")
            if skillName then
                -- Hide the notification
                local setShowSuccess, setShowResult = pcall(function()
                    actualHudVM.Notification.ShowSeconds = 0.0001
                end)
                
                writeCompletionStatus("Skill Increase")
                writeLog("Skill Increase: " .. skillName)
                return
            end

            -- Check for dungeon cleared messages
            if text == "Dungeon Cleared" then
                writeCompletionStatus("Dungeon Cleared")
                writeLog("Dungeon Cleared")
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
                
                -- Show victory messagebox
                pcall(function()
                    console.ExecuteConsole("MessageBox \"Shrine Seeker Goal Complete!\"")
                end)
                
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
                
                -- Show victory messagebox
                pcall(function()
                    console.ExecuteConsole("MessageBox \"Gatecloser Goal Complete!\"")
                end)
                
                return
            end
        end)
        
        writeLog("Notification hook registered for event tracking")
    end
end)



-- Initialize mod
print("Archipelago mod loading...")
initializeLog()

writeLog("Archipelago mod initialized")
print("Archipelago mod loaded successfully") 