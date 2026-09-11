--[[
    Quest map pins: moveto packing, region dungeon arrows, cell-to-dungeon match.
    CK quest conditions decide whether a pin is visible; this only positions refs.
]]

local config = require("ArchipelagoConfig")
local console = require("OBRConsole")

local M = {}
local D = {}

local selectedDungeons = {}
local regionSlotMap = {}
local checkedDungeonOrder = nil

local PLACE_WORDS = {
    cave = true,
    cavern = true,
    caverns = true,
    mine = true,
    hollow = true,
    tomb = true,
    ruins = true,
}

local AMBIGUOUS_STEMS = {
    abandoned = true,
    barren = true,
    bleak = true,
    echo = true,
    shattered = true,
    wind = true,
    howling = true,
    veyond = true,
    amelion = true,
}

local function writeLog(message, level)
    if D.writeLog then
        D.writeLog(message, level)
    end
end

local function copyList(source)
    local out = {}
    for i, item in ipairs(source) do
        out[i] = item
    end
    return out
end

local function applySwapClears(slots, clearedNames)
    for _, cleared in ipairs(clearedNames) do
        local idx = nil
        for i, name in ipairs(slots) do
            if name == cleared then
                idx = i
                break
            end
        end
        local last = #slots
        if idx and last > 0 then
            if idx ~= last then
                slots[idx] = slots[last]
            end
            slots[last] = nil
        end
    end
    return slots
end

function M.moveRef(refEdid, mapMarker)
    if not refEdid or not mapMarker or refEdid == "" or mapMarker == "" then
        return false
    end
    local ok, err = pcall(function()
        console.ExecuteConsole(refEdid .. ".moveto " .. mapMarker)
    end)
    if ok then
        writeLog("Moved " .. refEdid .. ".moveto " .. mapMarker)
        return true
    end
    writeLog("Failed " .. refEdid .. ".moveto " .. mapMarker .. ": " .. tostring(err), "ERROR")
    return false
end

local function wordBoundaryMatch(cellName, phrase)
    if not cellName or not phrase or phrase == "" then
        return false
    end
    if cellName == phrase then
        return true
    end
    local i, j = cellName:find(phrase, 1, true)
    if not i then
        return false
    end
    local before = (i == 1) or (cellName:sub(i - 1, i - 1) == " ")
    local afterc = cellName:sub(j + 1, j + 1)
    local after = afterc == "" or afterc == " " or afterc == "'"
    return before and after
end

function M.cellMatchesDungeon(cellName, dungeonName)
    if not cellName or not dungeonName or dungeonName == "" then
        return false
    end
    if wordBoundaryMatch(cellName, dungeonName) then
        return true
    end
    local last = dungeonName:match("([^%s]+)$")
    if not last or not PLACE_WORDS[last:lower()] then
        return false
    end
    local leftover = dungeonName:sub(1, #dungeonName - #last - 1)
    if leftover == "" then
        return false
    end
    if not leftover:find(" ", 1, true) and AMBIGUOUS_STEMS[leftover:lower()] then
        return false
    end
    return wordBoundaryMatch(cellName, leftover)
end

function M.setSelectedDungeons(names)
    selectedDungeons = names or {}
    regionSlotMap = {}
    checkedDungeonOrder = nil
end

function M.selectedDungeonForCell(cellName)
    if not cellName or cellName == "" then
        return nil
    end
    local best = nil
    local bestLen = 0
    for _, dungeon in ipairs(selectedDungeons) do
        if M.cellMatchesDungeon(cellName, dungeon) and #dungeon > bestLen then
            best = dungeon
            bestLen = #dungeon
        end
    end
    return best
end

local function loadCheckedProgress()
    if checkedDungeonOrder then
        return
    end
    checkedDungeonOrder = {}
    local filePrefix = D.getCurrentFilePrefix and D.getCurrentFilePrefix()
    if not filePrefix or not D.getArchipelagoPath then
        return
    end
    local file = io.open(D.getArchipelagoPath(filePrefix .. "_completed.txt"), "r")
    if not file then
        return
    end
    for line in file:lines() do
        local stored = (line or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
        if stored ~= "" then
            local dungeon = stored:match("^(.+)%s+Dungeon Cleared$")
            if dungeon then
                table.insert(checkedDungeonOrder, dungeon)
            end
        end
    end
    file:close()
end

local function rememberDungeonCleared(name)
    loadCheckedProgress()
    for _, existing in ipairs(checkedDungeonOrder) do
        if existing == name then
            return
        end
    end
    table.insert(checkedDungeonOrder, name)
end

local function currentRegionSlots(regionName)
    if regionSlotMap[regionName] then
        return regionSlotMap[regionName]
    end
    loadCheckedProgress()
    local original = {}
    if D.getSelectedRegionDungeons then
        original = D.getSelectedRegionDungeons(regionName) or {}
    end
    local inRegion = {}
    for _, name in ipairs(original) do
        inRegion[name] = true
    end
    local cleared = {}
    for _, name in ipairs(checkedDungeonOrder) do
        if inRegion[name] then
            table.insert(cleared, name)
        end
    end
    local slots = applySwapClears(copyList(original), cleared)
    regionSlotMap[regionName] = slots
    return slots
end

local function regionRef(regionName, slot)
    return "APDungeonMarker" .. regionName:gsub("%W", "") .. tostring(slot) .. "Ref"
end

function M.placeRegionDungeonPins(regionName)
    if not regionName or regionName == "" then
        return
    end
    local slots = currentRegionSlots(regionName)
    if #slots == 0 then
        writeLog("No dungeons found in settings for region '" .. tostring(regionName) .. "'", "WARNING")
        return
    end
    for i, dungeonName in ipairs(slots) do
        local marker = config.dungeonMapMarkers[dungeonName]
        if marker then
            M.moveRef(regionRef(regionName, i), marker)
        else
            writeLog("No map marker for region pin '" .. dungeonName .. "'", "WARNING")
        end
    end
    writeLog("Placed " .. tostring(#slots) .. " region pins for " .. tostring(regionName))
end

function M.recycleRegionDungeonPin(regionName, clearedName)
    if not regionName or regionName == "" or not clearedName or clearedName == "" then
        return
    end
    local slots = currentRegionSlots(regionName)
    local idx = nil
    for i, name in ipairs(slots) do
        if name == clearedName then
            idx = i
            break
        end
    end
    if not idx then
        writeLog("No active pin slot for cleared '" .. tostring(clearedName) .. "' in " .. tostring(regionName), "WARNING")
        return
    end
    local last = #slots
    if idx ~= last then
        local lastName = slots[last]
        local marker = config.dungeonMapMarkers[lastName]
        if marker then
            slots[idx] = lastName
            M.moveRef(regionRef(regionName, idx), marker)
            writeLog("Recycled " .. regionRef(regionName, idx) .. " " .. tostring(clearedName) .. " -> " .. tostring(lastName))
        else
            writeLog("No map marker for last region pin '" .. tostring(lastName) .. "'", "WARNING")
        end
    else
        writeLog("Cleared last region pin " .. tostring(clearedName) .. "; count hide is enough")
    end
    slots[last] = nil
    rememberDungeonCleared(clearedName)
end

function M.restoreRegionPins()
    if not (D.getSelectedRegions and D.isRegionUnlocked) then
        return
    end
    for _, regionName in ipairs(D.getSelectedRegions() or {}) do
        if D.isRegionUnlocked(regionName) then
            M.placeRegionDungeonPins(regionName)
        end
    end
end

function M.bind(deps)
    D = deps or {}
end

function M.reset()
    regionSlotMap = {}
    checkedDungeonOrder = nil
end

return M
