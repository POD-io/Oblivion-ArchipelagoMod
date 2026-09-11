--[[
    Bounty contracts, wildlife hunt pin, bounty quest-slot recycle.
]]

local config = require("ArchipelagoConfig")
local console = require("OBRConsole")
local UEHelpers = require("UEHelpers")
local MapPins = require("MapPins")

local M = {}

local D = {}
local contracts = {}
local rank = 0
local lastWildlifeScan = 0
local lastWildlifeX = nil
local lastWildlifeY = nil
local lastWildlifeZ = nil
local wildlifeInWorld = false
local wildlifeMarkerOn = false
local WILDLIFE_SCAN_INTERVAL = 20.0
local WILDLIFE_TOAST_INTERVAL = 60.0
local lastHuntToastAt = 0
local WILDLIFE_MOVE_THRESHOLD = 400
-- Wildlife scan range in UE cm (200m).
local WILDLIFE_MAX_DIST = 20000
local UE5_TO_OBL = 0.7
local refreshWildlifeMarker

local function writeLog(message, level)
    if D.writeLog then
        D.writeLog(message, level)
    end
end

local function showBountyMessage(text)
    if not text or text == "" then
        return
    end
    local safe = tostring(text):gsub('"', "")
    pcall(function()
        console.ExecuteConsole('Message "' .. safe .. '"')
    end)
end

local function bountyMarkerFor(contract)
    if not contract then return nil end
    if contract.dungeon and config.dungeonMapMarkers[contract.dungeon] then
        return config.dungeonMapMarkers[contract.dungeon]
    end
    if contract.marker and contract.marker ~= "" then
        return contract.marker
    end
    return nil
end

local revealedMarkers = {}

local function revealBountyMapMarker(marker, dungeonName)
    if not marker or marker == "" or revealedMarkers[marker] then
        return
    end
    local mode = D.getDungeonMarkerMode and D.getDungeonMarkerMode() or "reveal_and_fast_travel"
    local command
    if mode ~= "reveal_only" then
        command = "ShowMap " .. marker .. ", 1"
    else
        command = "ShowMap " .. marker
    end
    local ok, err = pcall(function()
        console.ExecuteConsole(command)
    end)
    if ok then
        revealedMarkers[marker] = true
        writeLog("Revealed bounty map marker '" .. tostring(dungeonName) .. "' (" .. marker .. ") mode=" .. tostring(mode))
    else
        writeLog("Failed to reveal bounty map marker '" .. tostring(dungeonName) .. "': " .. tostring(err), "ERROR")
    end
end

local function parseBountyLine(value)
    local parts = {}
    for part in (value .. "|"):gmatch("(.-)|") do
        table.insert(parts, part)
    end
    return {
        type = parts[1] or "",
        dungeon = parts[2] or "",
        marker = parts[3] or "",
        target = parts[4] or "",
        cull = tonumber(parts[5]) or 0,
        checks = tonumber(parts[6]) or 1,
        display = parts[7] or "",
        occupant = parts[8] or "",
        done = false,
        cullProgress = 0,
    }
end

local function progressKey(contract)
    if contract.dungeon ~= "" then
        return contract.dungeon
    end
    return "wildlife_" .. tostring(contract.index)
end

local function applyBountyProgress(progress)
    progress = progress or {}
    for _, contract in ipairs(contracts) do
        if (contract.type == "cull" or contract.type == "wildlife") and not contract.done then
            contract.cullProgress = progress[progressKey(contract)] or 0
        end
    end
end

function M.bountyProgress()
    local progress = {}
    for _, contract in ipairs(contracts) do
        if (contract.type == "cull" or contract.type == "wildlife") and not contract.done then
            local n = tonumber(contract.cullProgress) or 0
            if n > 0 then
                progress[progressKey(contract)] = n
            end
        end
    end
    return progress
end

local function countBountyContractsFromReceipts()
    local filePrefix = D.getCurrentFilePrefix and D.getCurrentFilePrefix()
    if not filePrefix then return 0 end
    local statusPath = D.getArchipelagoPath(filePrefix .. "_bridge_status.txt")
    local file = io.open(statusPath, "r")
    if not file then return 0 end
    local content = file:read("*a") or ""
    file:close()
    local count = 0
    for _ in content:gmatch("Progressive Bounty Contract") do
        count = count + 1
    end
    return count
end

local bountySlotList = nil
local checkedBountyOrder = nil
local lastJournalPoll = 0

local function rememberBountyCleared(index)
    if not checkedBountyOrder then
        checkedBountyOrder = {}
    end
    local key = tostring(index)
    for _, existing in ipairs(checkedBountyOrder) do
        if existing == key then
            return
        end
    end
    table.insert(checkedBountyOrder, key)
end

local function contractByIndex(index)
    for _, contract in ipairs(contracts) do
        if contract.index == index then
            return contract
        end
    end
    return nil
end

local function currentBountySlots()
    if bountySlotList then
        return bountySlotList
    end
    -- Rebuild from .done. Journal tokens are the contract display names.
    local slots = {}
    for _, contract in ipairs(contracts) do
        if contract.index <= rank and contract.type ~= "wildlife" and not contract.done then
            table.insert(slots, tostring(contract.index))
        end
    end
    bountySlotList = slots
    return bountySlotList
end

local function placeBountySlot(slot, contract)
    if not contract then return end
    local marker = bountyMarkerFor(contract)
    if not marker then
        writeLog("No map marker for bounty " .. tostring(contract.index) .. " (" .. tostring(contract.dungeon) .. "); skipping quest slot", "WARNING")
        return
    end
    MapPins.moveRef("APBountyMarker" .. tostring(slot) .. "Ref", marker)
    revealBountyMapMarker(marker, contract.dungeon)
end

local function recycleBountyPin(contract)
    local slots = currentBountySlots()
    local idx = nil
    local clearedKey = tostring(contract.index)
    for i, name in ipairs(slots) do
        if name == clearedKey then
            idx = i
            break
        end
    end
    if not idx then
        pcall(function()
            console.ExecuteConsole("set APBountyCount to " .. tostring(#slots))
        end)
        return
    end
    local last = #slots
    if idx ~= last then
        local lastContract = contractByIndex(tonumber(slots[last]))
        slots[idx] = slots[last]
        placeBountySlot(idx, lastContract)
        writeLog("Recycled APBountyMarker" .. tostring(idx) .. "Ref bounty " .. clearedKey
            .. " -> " .. tostring(lastContract and lastContract.index))
    else
        writeLog("Cleared last bounty pin " .. clearedKey .. "; count hide is enough")
    end
    slots[last] = nil
    rememberBountyCleared(contract.index)
    pcall(function()
        console.ExecuteConsole("set APBountyCount to " .. tostring(#slots))
    end)
end

local function placeNewBountyPin()
    local contract = contractByIndex(rank)
    local slots = currentBountySlots()
    if not contract or contract.type == "wildlife" then
        pcall(function()
            console.ExecuteConsole("set APBountyCount to " .. tostring(#slots))
        end)
        return
    end
    local already = false
    for _, item in ipairs(slots) do
        if item == tostring(rank) then
            already = true
            break
        end
    end
    if not already then
        table.insert(slots, tostring(rank))
    end
    pcall(function()
        console.ExecuteConsole("set APBountyCount to " .. tostring(#slots))
    end)
    placeBountySlot(#slots, contract)
end

local function placeCurrentBountyPins()
    local slots = currentBountySlots()
    pcall(function()
        console.ExecuteConsole("set APBountyCount to " .. tostring(#slots))
    end)
    for i, index in ipairs(slots) do
        placeBountySlot(i, contractByIndex(tonumber(index)))
    end
    writeLog("Placed " .. tostring(#slots) .. " bounty pins (rank " .. tostring(rank) .. ")")
end

local function occupantMatchesEnemy(occupant, enemyName)
    local name = (enemyName or ""):lower()
    local occ = (occupant or ""):lower()
    if occ == "" then
        return true
    end
    if occ:find("bandit", 1, true) then return name:find("bandit", 1, true) ~= nil end
    if occ:find("goblin", 1, true) then return name:find("goblin", 1, true) ~= nil end
    if occ:find("marauder", 1, true) then return name:find("marauder", 1, true) ~= nil end
    if occ:find("necromancer", 1, true) then return name:find("necromancer", 1, true) ~= nil end
    if occ:find("conjurer", 1, true) then return name:find("conjurer", 1, true) ~= nil end
    if occ:find("vampire", 1, true) then return name:find("vampire", 1, true) ~= nil end
    if occ:find("undead", 1, true) then
        return name:find("skeleton", 1, true) ~= nil
            or name:find("zombie", 1, true) ~= nil
            or name:find("ghost", 1, true) ~= nil
            or name:find("wraith", 1, true) ~= nil
            or name:find("lich", 1, true) ~= nil
    end
    if occ:find("monster", 1, true) then
        return name:find("imp", 1, true) ~= nil
            or name:find("troll", 1, true) ~= nil
            or name:find("wisp", 1, true) ~= nil
            or name:find("spriggan", 1, true) ~= nil
            or name:find("minotaur", 1, true) ~= nil
            or name:find("dreugh", 1, true) ~= nil
            or name:find("ogre", 1, true) ~= nil
    end
    if occ:find("mythic", 1, true) then return name:find("mythic", 1, true) ~= nil end
    if occ:find("dremora", 1, true) or occ:find("daedra", 1, true) then
        return name:find("dremora", 1, true) ~= nil or name:find("daedra", 1, true) ~= nil
    end
    if occ:find("natural", 1, true) then
        return name:find("wolf", 1, true) ~= nil
            or name:find("bear", 1, true) ~= nil
            or name:find("deer", 1, true) ~= nil
            or name:find("rat", 1, true) ~= nil
            or name:find("mudcrab", 1, true) ~= nil
            or name:find("boar", 1, true) ~= nil
            or name:find("lion", 1, true) ~= nil
            or name:find("dog", 1, true) ~= nil
    end
    return name:find(occ, 1, true) ~= nil
end

-- NPC *boss EDIDs and VampirePatriarch. Named uniques are exact BP paths.
local function isNpcBossKill(enemyName, occupant)
    local name = enemyName or ""
    local lower = name:lower()
    local occ = (occupant or ""):lower()
    if occ:find("vampire", 1, true) then
        return lower:find("vampirepatriarch", 1, true) ~= nil
    end
    if occ:find("bandit", 1, true)
        or occ:find("marauder", 1, true)
        or occ:find("necromancer", 1, true)
        or occ:find("conjurer", 1, true) then
        return lower:find("boss", 1, true) ~= nil
    end
    return false
end

local function bountyCheckNames(contract)
    local display = (contract and contract.display) or ""
    local checks = tonumber(contract and contract.checks) or 1
    if display == "" then
        return { "Bounty " .. tostring(contract.index) }
    end
    if checks <= 1 then
        return { display }
    end
    local names = {}
    for n = 1, checks do
        names[n] = string.format("%s (%d/%d)", display, n, checks)
    end
    return names
end

local function tokenMatchesContract(token, contract)
    if not token or not contract then
        return false
    end
    local display = contract.display or ""
    if token == display or (display ~= "" and token == "Bounty: " .. display) then
        return true
    end
    for _, name in ipairs(bountyCheckNames(contract)) do
        if token == name then
            return true
        end
    end
    return false
end

local function journalMarksContractDone(contract)
    if not contract or not D.isCompletionAlreadyRecorded then
        return false
    end
    local display = contract.display or ""
    if display ~= "" and (
        D.isCompletionAlreadyRecorded(display)
        or D.isCompletionAlreadyRecorded("Bounty: " .. display)
    ) then
        return true
    end
    for _, name in ipairs(bountyCheckNames(contract)) do
        if D.isCompletionAlreadyRecorded(name) then
            return true
        end
    end
    return false
end

local function completeBountyContract(contract)
    if not contract or contract.done then
        return
    end
    contract.done = true
    local checks = contract.checks or 1
    local names = bountyCheckNames(contract)
    for n = 1, checks do
        local name = names[n] or names[1]
        if not (D.isCompletionAlreadyRecorded and D.isCompletionAlreadyRecorded(name)) then
            D.writeCompletionStatus(name)
        end
    end
    pcall(function()
        console.ExecuteConsole("set APBountyRemaining to APBountyRemaining - 1")
    end)
    recycleBountyPin(contract)
    if contract.type == "wildlife" then
        refreshWildlifeMarker(true)
    end
    writeLog("Bounty " .. tostring(contract.index) .. " completed (" .. tostring(contract.display) .. ")")
    local dungeon = contract.dungeon
    if dungeon and dungeon ~= "" and contract.type ~= "wildlife" and D.offerDungeonWarp then
        D.offerDungeonWarp(dungeon)
    end
end

function M.bind(deps)
    D = deps or {}
end

function M.grantContract()
    rank = rank + 1
    pcall(function()
        console.ExecuteConsole("set APBountyRank to APBountyRank + 1")
    end)
    placeNewBountyPin()
    writeLog("Progressive Bounty Contract applied; rank now " .. tostring(rank))
end

function M.loadState()
    contracts = {}
    rank = 0
    bountySlotList = nil
    checkedBountyOrder = nil
    local filePrefix = D.getCurrentFilePrefix and D.getCurrentFilePrefix()
    if not filePrefix then return end
    local settingsPath = D.getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "r")
    if not file then return end
    local parsed = {}
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.*)$")
        if key and value then
            local index = key:match("^bounty_(%d+)$")
            if index then
                local contract = parseBountyLine(value)
                contract.index = tonumber(index) or 0
                parsed[contract.index] = contract
            end
        end
    end
    file:close()
    local keys = {}
    for index in pairs(parsed) do
        table.insert(keys, index)
    end
    table.sort(keys)
    for _, index in ipairs(keys) do
        local contract = parsed[index]
        contract.done = journalMarksContractDone(contract)
        table.insert(contracts, contract)
    end
    if D.getBountyProgress then
        applyBountyProgress(D.getBountyProgress())
    end
    if #contracts > 0 then
        rank = 1 + countBountyContractsFromReceipts()
    else
        rank = 0
    end
    writeLog("Loaded " .. tostring(#contracts) .. " bounty contracts (rank " .. tostring(rank) .. ")")
    if D.markBountyProgressReady then
        D.markBountyProgressReady()
    end
end

function M.initialize()
    M.loadState()
    local remaining = 0
    for _, contract in ipairs(contracts) do
        if not contract.done then
            remaining = remaining + 1
        end
    end
    pcall(function()
        console.ExecuteConsole("set APBountyRemaining to " .. tostring(remaining))
        console.ExecuteConsole("set APBountyRank to " .. tostring(rank))
    end)
    placeCurrentBountyPins()
    local filePrefix = D.getCurrentFilePrefix and D.getCurrentFilePrefix()
    if not filePrefix then return end
    local settingsPath = D.getArchipelagoPath(filePrefix .. "_settings.txt")
    local file = io.open(settingsPath, "a")
    if file then
        file:write("bounty_initialized=True\n")
        file:close()
        writeLog("Marked bounties as initialized")
    else
        writeLog("Failed to write bounty_initialized to settings file", "ERROR")
    end
end

function M.restoreBountyPins()
    if #contracts > 0 then
        placeCurrentBountyPins()
    end
end

function M.onKill(enemyData)
    if #contracts == 0 then
        return
    end
    local enemyName = enemyData and enemyData.name or ""
    local cellName = D.getCurrentCellName and D.getCurrentCellName() or ""
    local cellKillType = D.getCellKillType and D.getCellKillType() or ""

    for _, contract in ipairs(contracts) do
        if not contract.done and contract.index <= rank then
            if contract.type == "wildlife" then
                if cellKillType == "overworld" then
                    local target = contract.target or ""
                    local matched = false
                    for bp in target:gmatch("[^,]+") do
                        bp = bp:match("^%s*(.-)%s*$")
                        if bp ~= "" and enemyName:find(bp, 1, true) then
                            matched = true
                            break
                        end
                    end
                    if not matched then
                        local lower = enemyName:lower()
                        local targetLower = target:lower()
                        if targetLower:find("deer", 1, true) then
                            matched = lower:find("deer", 1, true) ~= nil
                        elseif targetLower:find("mudcrab", 1, true) then
                            matched = lower:find("mudcrab", 1, true) ~= nil
                        end
                    end
                    if matched then
                        local need = contract.cull or 0
                        if need < 1 then need = 1 end
                        contract.cullProgress = (contract.cullProgress or 0) + 1
                        writeLog(string.format("Bounty %d wildlife: %d/%d",
                            contract.index, contract.cullProgress, need))
                        local huntName = (contract.display or "Hunt"):gsub("%s*%(%d+%)%s*$", "")
                        showBountyMessage(string.format("%s %d/%d", huntName, contract.cullProgress, need))
                        if contract.cullProgress >= need then
                            completeBountyContract(contract)
                        else
                            refreshWildlifeMarker(true)
                        end
                        return
                    end
                end
            elseif MapPins.cellMatchesDungeon(cellName, contract.dungeon) then
                if contract.type == "named" then
                    if contract.target ~= "" and enemyName:find(contract.target, 1, true) then
                        completeBountyContract(contract)
                        return
                    end
                elseif contract.type == "boss" then
                    if isNpcBossKill(enemyName, contract.occupant)
                        and occupantMatchesEnemy(contract.occupant or "", enemyName) then
                        completeBountyContract(contract)
                        return
                    end
                elseif contract.type == "cull" then
                    if occupantMatchesEnemy(contract.occupant or contract.target, enemyName) then
                        contract.cullProgress = (contract.cullProgress or 0) + 1
                        local need = contract.cull or 0
                        writeLog(string.format("Bounty %d cull %s: %d/%d",
                            contract.index, contract.dungeon, contract.cullProgress, need))
                        local label = contract.occupant or "Cull"
                        if label ~= "Undead" and not label:match("s$") then
                            label = label .. "s"
                        end
                        showBountyMessage(string.format("%s %d/%d", label, contract.cullProgress, need))
                        if contract.cullProgress >= need then
                            completeBountyContract(contract)
                        end
                        return
                    end
                end
            end
        end
    end
end

local function activeWildlifeClasses()
    local classes = {}
    local seen = {}
    for _, contract in ipairs(contracts) do
        if contract.type == "wildlife" and not contract.done and contract.index <= rank then
            for bp in (contract.target or ""):gmatch("[^,]+") do
                bp = bp:match("^%s*(.-)%s*$") or ""
                if bp ~= "" and not seen[bp] then
                    seen[bp] = true
                    table.insert(classes, bp)
                end
            end
        end
    end
    return classes
end

local function setWildlifeValid(on)
    if on then
        wildlifeMarkerOn = true
    else
        if wildlifeMarkerOn then
            pcall(function()
                console.ExecuteConsole("set APWildlifeTrackValid to 0")
            end)
        end
        wildlifeMarkerOn = false
        wildlifeInWorld = false
        lastWildlifeX = nil
        lastWildlifeY = nil
        lastWildlifeZ = nil
    end
end

local function actorIsDead(obj)
    local dead = false
    pcall(function()
        dead = obj:IsDead() == true
    end)
    return dead
end

refreshWildlifeMarker = function(force)
    local classes = activeWildlifeClasses()
    if #classes == 0 then
        setWildlifeValid(false)
        return
    end
    local cellKillType = D.getCellKillType and D.getCellKillType() or ""
    if cellKillType ~= "overworld" then
        setWildlifeValid(false)
        return
    end
    local now = os.clock()
    if not force and (now - lastWildlifeScan) < WILDLIFE_SCAN_INTERVAL then
        return
    end
    lastWildlifeScan = now

    local player = nil
    pcall(function()
        player = UEHelpers:GetPlayer()
    end)
    if not player or not player:IsValid() then
        return
    end
    local playerLoc = player:K2_GetActorLocation()
    local nearestDist = WILDLIFE_MAX_DIST
    local nearestLoc = nil

    for _, className in ipairs(classes) do
        local instances = nil
        pcall(function()
            instances = FindAllOf(className)
        end)
        if instances then
            for _, obj in ipairs(instances) do
                if obj and obj:IsValid() and obj.bHidden ~= true and not actorIsDead(obj) then
                    local loc = nil
                    pcall(function()
                        loc = obj:K2_GetActorLocation()
                    end)
                    if loc then
                        local dist = math.sqrt(
                            (loc.X - playerLoc.X)^2 +
                            (loc.Y - playerLoc.Y)^2 +
                            (loc.Z - playerLoc.Z)^2
                        )
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestLoc = loc
                        end
                    end
                end
            end
        end
    end

    if not nearestLoc then
        setWildlifeValid(false)
        return
    end

    local moved = true
    if lastWildlifeX then
        local dx = math.abs(nearestLoc.X - lastWildlifeX)
        local dy = math.abs(nearestLoc.Y - lastWildlifeY)
        local dz = math.abs(nearestLoc.Z - lastWildlifeZ)
        if dx <= WILDLIFE_MOVE_THRESHOLD and dy <= WILDLIFE_MOVE_THRESHOLD and dz <= WILDLIFE_MOVE_THRESHOLD then
            moved = false
        end
    end
    if not moved and wildlifeMarkerOn then
        return
    end

    local ox = nearestLoc.X * UE5_TO_OBL
    local oy = -nearestLoc.Y * UE5_TO_OBL
    local oz = nearestLoc.Z * UE5_TO_OBL
    pcall(function()
        if not wildlifeInWorld then
            console.ExecuteConsole("APBountyMarkerWildlifeRef.moveto player")
            wildlifeInWorld = true
        end
        console.ExecuteConsole(string.format("APBountyMarkerWildlifeRef.setpos x %.2f", ox))
        console.ExecuteConsole(string.format("APBountyMarkerWildlifeRef.setpos y %.2f", oy))
        console.ExecuteConsole(string.format("APBountyMarkerWildlifeRef.setpos z %.2f", oz))
        console.ExecuteConsole("set APWildlifeTrackValid to 1")
        local nowToast = os.clock()
        if (nowToast - lastHuntToastAt) >= WILDLIFE_TOAST_INTERVAL then
            console.ExecuteConsole('Message "you sense your hunt nearby..."')
            lastHuntToastAt = nowToast
        end
    end)
    wildlifeMarkerOn = true
    lastWildlifeX = nearestLoc.X
    lastWildlifeY = nearestLoc.Y
    lastWildlifeZ = nearestLoc.Z
end

function M.tryCompleteFromToken(token)
    token = (token or ""):gsub("\r", ""):match("^%s*(.-)%s*$") or ""
    if token == "" then
        return false
    end
    for _, contract in ipairs(contracts) do
        if not contract.done and tokenMatchesContract(token, contract) then
            completeBountyContract(contract)
            return true
        end
    end
    return false
end

function M.updateTracking()
    local now = os.clock()
    if now - lastJournalPoll >= 1.0 then
        lastJournalPoll = now
        local recorded = {}
        local filePrefix = D.getCurrentFilePrefix and D.getCurrentFilePrefix()
        if filePrefix and D.getArchipelagoPath then
            local file = io.open(D.getArchipelagoPath(filePrefix .. "_completed.txt"), "r")
            if file then
                for line in file:lines() do
                    local stored = (line or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
                    if stored ~= "" then
                        recorded[stored] = true
                    end
                end
                file:close()
            end
        end
        for _, contract in ipairs(contracts) do
            if not contract.done then
                local hit = recorded[contract.display or ""]
                    or recorded["Bounty: " .. (contract.display or "")]
                if not hit then
                    for _, name in ipairs(bountyCheckNames(contract)) do
                        if recorded[name] then
                            hit = true
                            break
                        end
                    end
                end
                if hit then
                    completeBountyContract(contract)
                end
            end
        end
    end
    refreshWildlifeMarker(false)
end

function M.cellHasActiveBounty()
    local cellName = D.getCurrentCellName and D.getCurrentCellName() or ""
    if cellName == "" then
        return false
    end
    for _, contract in ipairs(contracts) do
        if not contract.done and contract.index <= rank and contract.type ~= "wildlife" then
            if MapPins.cellMatchesDungeon(cellName, contract.dungeon) then
                return true
            end
        end
    end
    return false
end

function M.shouldSuppressBossChestMessage()
    if D.isCellLookupPending and D.isCellLookupPending() then
        return true
    end
    return M.cellHasActiveBounty()
end

return M
