--[[
    Archipelago Integration Mod for Oblivion Remastered
    
    This mod integrates Oblivion Remastered with the Archipelago multiworld randomizer.
    It handles receiving items from other players and sending completion status back.
    
    Features:
    - Processes items received from the Archipelago client
    - Automatically adds shrine offerings when receiving shrine tokens (if enabled)
    - Tracks quest completion status for the randomizer
    - Provides fallback mechanisms for console command execution
    
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

-- Default settings (can be overridden by settings file)
local archipelagoSettings = {
    free_offerings = true  -- Whether to automatically add shrine offerings when receiving shrine tokens
}

-- Shrine offering mappings for free offerings mode
-- When a shrine token is received, these items are automatically added to help with shrine quests
local SHRINE_OFFERINGS = {
    ["Azura Shrine Token"] = {{"Glow Dust", 1}},
    ["Boethia Shrine Token"] = {{"Daedra Heart", 1}},
    ["Namira Shrine Token"] = {{"Cheap Wine", 5}},
    ["Sanguine Shrine Token"] = {{"Cyrodiilic Brandy", 1}},
    ["Sheogorath Shrine Token"] = {{"Lesser Soul Gem", 1}, {"Lettuce", 1}, {"Yarn", 1}},
    ["Vaermina Shrine Token"] = {{"Black Soul Gem", 1}},
    ["Clavicus Vile Shrine Token"] = {{"Gold", 500}},
    ["Hircine Shrine Token"] = {{"Wolf Pelt", 1}},
    ["Malacath Shrine Token"] = {{"Troll Fat", 1}},
    ["Mephala Shrine Token"] = {{"Nightshade", 1}},
    ["Meridia Shrine Token"] = {{"Ectoplasm", 1}},
    ["Molag Bal Shrine Token"] = {{"Lion Pelt", 1}}
}

-- Helper function to construct file paths
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

-- Initialize the Archipelago directory and logging
local function initializeLog()
    os.execute('mkdir "' .. ARCHIPELAGO_BASE_DIR .. '" 2>nul')
    writeLog("Archipelago Mod Initialized")
end

-- Get the current connection file prefix from the connection file
-- This allows multiple Archipelago sessions to run simultaneously
local function getCurrentFilePrefix()
    local connectionPath = getArchipelagoPath("current_connection.txt")
    local file = io.open(connectionPath, "r")
    if not file then
        return "item_queue"  -- Default prefix if no connection file exists
    end
    
    for line in file:lines() do
        local prefix = line:match("^file_prefix=(.+)$")
        if prefix then
            file:close()
            return prefix
        end
    end
    file:close()
    return "item_queue"  -- Fallback to default
end

-- Load mod settings from the settings file
local function loadSettings()
    local filePrefix = getCurrentFilePrefix()
    local settingsPath = getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    
    if not file then
        return  -- Use default settings if file doesn't exist
    end
    
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.+)$")
        if key == "free_offerings" then
            archipelagoSettings.free_offerings = (value == "True")
        end
        -- Add more settings here as needed
    end
    file:close()
end

-- Add shrine offerings to the item queue if the feature is enabled
-- This helps players by automatically providing required shrine offering items
local function addShrineOfferings(itemName, queuePath)
    local offerings = SHRINE_OFFERINGS[itemName]
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

-- Process the item queue file and give items to the player
-- This is the main function that handles items received from the multiworld
local function processItemQueue()
    local filePrefix = getCurrentFilePrefix()
    local queuePath = getArchipelagoPath(filePrefix .. "_items.txt")
    local file = io.open(queuePath, "r")
    
    if not file then
        return
    end
    
    local itemsToProcess = {}
    
    -- Read all items from the queue and add shrine offerings if applicable
    for line in file:lines() do
        if line and line ~= "" then
            local itemName = line:match("^(.-)%s*$")
            table.insert(itemsToProcess, itemName)
            addShrineOfferings(itemName, queuePath)
        end
    end
    file:close()
    
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
    
    -- Give each item to the player using console commands
    for _, itemName in ipairs(itemsToProcess) do
        local edid = config.itemMappings[itemName]
        if edid then
            -- Set default quantity and adjust for specific item types
            local quantity = 1
            if itemName:find("Potion") then
                quantity = 3  -- Give multiple potions for better utility
            elseif itemName == "Gold" then
                quantity = 500  -- Standard gold amount
            end
            
            local addItemCommand = "player.additem " .. edid .. " " .. quantity
            local success, result = pcall(function()
                console.ExecuteConsole(addItemCommand)
            end)
            
            if success then
                writeLog("Added item: " .. itemName .. " x" .. quantity)
            else
                writeLog("Failed to add item: " .. itemName, "ERROR")
            end
        else
            writeLog("Unknown item: " .. itemName, "WARNING")
        end
    end
    
    -- Clean up the processed queue file
    if #itemsToProcess > 0 then
        os.remove(queuePath)
        writeLog("Processed " .. #itemsToProcess .. " items")
    end
end

-- Write quest completion status to file for the Archipelago client
-- This notifies the multiworld when we complete a location
local function writeCompletionStatus(completionTokenEdid)
    local filePrefix = getCurrentFilePrefix()
    local statusPath = getArchipelagoPath(filePrefix .. "_completed.txt")
    local file = io.open(statusPath, "a")
    if file then
        file:write(completionTokenEdid .. "\n")
        file:close()
        writeLog("Quest completed: " .. completionTokenEdid)
    end
end



-- Main notification hook - handles game notifications to trigger item processing and quest completion
-- This is the primary mechanism for detecting when to process items or record completions
local hookSuccess, hookError = pcall(function()
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
        
        -- Check for pending items and trigger processing
        local filePrefix = getCurrentFilePrefix()
        local queuePath = getArchipelagoPath(filePrefix .. "_items.txt")
        local file = io.open(queuePath, "r")
        if file then
            file:close()
            
            -- Try to set the game variable to trigger item processing
            local consoleSuccess, consoleResult = pcall(function()
                console.ExecuteConsole("set APItemPending to 1")
            end)
            
            if consoleSuccess then
                writeLog("Set APItemPending to 1")
            else
                writeLog("Failed to set APItemPending: " .. tostring(consoleResult), "ERROR")
            end
        end
        
        -- Handle quest completion notifications
        local completionMatch = text:match("AP (.+) Completion Token added to the player's inventory")
        if completionMatch then
            -- Hide the completion notification quickly to reduce visual spam
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
        
        -- Handle item processing trigger notification
        if text:match("AP Items Ready For Processing") then
            -- Hide the processing notification quickly
            local setShowSuccess, setShowResult = pcall(function()
                actualHudVM.Notification.ShowSeconds = 0.0001
            end)
            
            -- Process all pending items
            processItemQueue()
            
            -- Reset the processing flag
            local resetSuccess, resetResult = pcall(function()
                console.ExecuteConsole("set APItemPending to 0")
            end)
            
            if resetSuccess then
                writeLog("Reset APItemPending to 0")
            end
            return
        end
    end)
end)

-- Mod initialization
print("Archipelago mod loading...")
initializeLog()
loadSettings()

-- Report hook registration status
if hookSuccess then
    writeLog("Notification hook registered successfully")
else
    writeLog("Failed to register notification hook: " .. tostring(hookError), "ERROR")
end

writeLog("Archipelago mod initialized")
print("Archipelago mod loaded successfully") 