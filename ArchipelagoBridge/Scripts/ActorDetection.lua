local ActorDetection = {}

local UEHelpers = require("UEHelpers")

local config = {
    detectionRadius = 2000,
}

local onDeathCallback = nil
local hooksRegistered = false
local killedActors = {}
local playerEngagedActors = {}
local npcKilledActors = {}
local lastPlayerSpellTime = 0
local travelling = false
local deathVfxHookBound = 0
local chestScanEarliest = 0
local SPELL_KILL_WINDOW = 6
local SPELL_KILL_RANGE = 15000
local ActorDetectionLog = nil

function ActorDetection.SetLog(fn)
    ActorDetectionLog = fn
end

local function adLog(msg, level)
    if ActorDetectionLog then
        ActorDetectionLog(msg, level or "INFO")
    else
        print("ArchipelagoBridge " .. tostring(msg))
    end
end

function ActorDetection.SetTravelling(isTravelling)
    travelling = isTravelling and true or false
    if not travelling then
        chestScanEarliest = os.clock() + 5
    end
end

local function readWeaponTypeTag(weaponActor)
    local tagStr = nil
    pcall(function()
        if not weaponActor or not weaponActor.IsValid or not weaponActor:IsValid() then
            return
        end
        if not weaponActor.WeaponTypeTag then
            return
        end
        local tag = weaponActor.WeaponTypeTag
        local tagName = tag.TagName
        if tagName and tagName.ToString then
            tagStr = tostring(tagName:ToString())
        end
    end)
    return tagStr
end

function ActorDetection.GetWeaponKind(attacker)
    ActorDetection.lastWeaponDebug = { tag = "", bp = "", pairing = false }
    if not attacker then
        return "unarmed"
    end
    local pairing = nil
    pcall(function() pairing = attacker.WeaponsPairingComponent end)
    local pairingExists = false
    pcall(function() pairingExists = pairing and pairing.IsValid and pairing:IsValid() end)
    ActorDetection.lastWeaponDebug.pairing = pairingExists
    local weapon = nil
    pcall(function()
        if pairingExists then
            weapon = pairing.WeaponActor
        end
    end)
    local valid = false
    pcall(function() valid = weapon and weapon.IsValid and weapon:IsValid() end)
    if not valid then
        -- Pairing exists with no equipped WeaponActor: fists, not an unidentified weapon.
        return "unarmed"
    end
    local tag = (readWeaponTypeTag(weapon) or ""):lower()
    local bp = ""
    pcall(function()
        local fullName = weapon:GetFullName()
        bp = (fullName:match("([^%.]+)$") or fullName):lower()
    end)
    ActorDetection.lastWeaponDebug.tag = tag
    ActorDetection.lastWeaponDebug.bp = bp
    if tag:find("bow", 1, true) or bp:find("bow", 1, true) then
        return "bow"
    end
    if tag:find("staff", 1, true) or bp:find("staff", 1, true) then
        return "staff"
    end
    local last = tag:match("([^.]+)$")
    if last and last ~= "" and last ~= "weapontype" then
        return last
    end
    if bp:find("sword", 1, true) then return "sword" end
    if bp:find("mace", 1, true) then return "mace" end
    if bp:find("axe", 1, true) then return "axe" end
    if bp:find("dagger", 1, true) then return "dagger" end
    if bp:find("hammer", 1, true) then return "hammer" end
    if bp:find("blade", 1, true) then return "blade" end
    return "unknown"
end

ActorDetection.WEAPON_CATEGORIES = {
    dagger = "blade",
    shortsword = "blade",
    longsword = "blade",
    claymore = "blade",
    sword = "blade",
    blade = "blade",
    mace = "blunt",
    hammer = "blunt",
    warhammer = "blunt",
    axe = "blunt",
    battleaxe = "blunt",
    waraxe = "blunt",
    bow = "bow",
    staff = "staff",
    spell = "spell",
    unarmed = "unarmed",
}

ActorDetection.loggedUnknownWeapons = {}

function ActorDetection.WeaponCategory(kind)
    local key = string.lower(tostring(kind or ""))
    local category = ActorDetection.WEAPON_CATEGORIES[key]
    if category then
        return category
    end
    local dbg = ActorDetection.lastWeaponDebug or {}
    local stamp = key .. "|" .. tostring(dbg.tag or "") .. "|" .. tostring(dbg.bp or "")
    if not ActorDetection.loggedUnknownWeapons[stamp] then
        ActorDetection.loggedUnknownWeapons[stamp] = true
        print(string.format(
            "ArchipelagoBridge unknown weapon kind=%s tag=%s bp=%s pairing=%s",
            tostring(kind), tostring(dbg.tag), tostring(dbg.bp), tostring(dbg.pairing)))
    end
    return "unknown"
end

ActorDetection.KNOWN_WEAPON_KINDS = {
    "unarmed",
    "unknown",
    "dagger",
    "mace",
    "shortsword",
    "longsword",
    "sword",
    "claymore",
    "bow",
    "battleaxe",
    "axe",
    "waraxe",
    "staff",
    "spell",
    "hammer",
    "warhammer",
    "blade",
}

local function getActorFormID(actor)
    local okValid, valid = pcall(function()
        return actor and actor.IsValid and actor:IsValid()
    end)
    if not okValid or not valid then return nil end
    local RefComp = actor.TESRefComponent or actor.RefComponent or actor.TESReferenceComponent
    if RefComp and RefComp:IsValid() then
        local RefForm = RefComp.FormIDInstance or (RefComp.GetFormIDInstance and pcall(function() return RefComp:GetFormIDInstance() end))
        if RefForm then
            return string.format("0x%x", RefForm)
        end
    end
    return nil
end

local function getActorName(actor)
    if not actor or not actor:IsValid() then return "Unknown" end
    local fullName = actor:GetFullName()
    return fullName:match("([^%.]+)$") or fullName
end

local function getActorLevel(actor)
    if not actor or not actor:IsValid() then return nil end
    local level = nil
    pcall(function()
        if actor.OblivionActorStatePairingComponent and actor.OblivionActorStatePairingComponent:IsValid() then
            local comp = actor.OblivionActorStatePairingComponent
            level = tonumber(comp.Level or comp.CharacterLevel or comp.ActorLevel)
        end
    end)
    return level
end

function ActorDetection.IsSummoned(name)
    if not name then return false end
    return string.find(string.lower(tostring(name)), "bp_summon_", 1, true) ~= nil
end

local function OnEnemyDeath(enemyData, killer)
    if ActorDetection.IsSummoned(enemyData and enemyData.name) then
        return
    end
    if onDeathCallback then
        onDeathCallback(enemyData, killer)
    end
end

function ActorDetection.Initialize(callback)
    onDeathCallback = callback
    print("ArchipelagoBridge ActorDetection 2026-09-01-A")
    if hooksRegistered then return end
    hooksRegistered = true

    RegisterHook("/Script/Altar.VPairedPawn:OnCombatHitDealt",
        function() end,
        function(Context, HitEvent)
            pcall(function()
                if travelling then return end
                if not HitEvent then return end
                local hEvent = HitEvent:get()
                if not hEvent then return end

                local Attacker, Target = nil, nil
                pcall(function() Attacker = hEvent.Attacker end)
                pcall(function() Target = hEvent.Target end)
                if not Attacker or not Target then return end

                local targetOk, attackerOk = false, false
                pcall(function() targetOk = Target:IsValid() end)
                pcall(function() attackerOk = Attacker:IsValid() end)
                if not targetOk or not attackerOk then return end

                local targetIsPC = false
                pcall(function() targetIsPC = Target:IsPlayerCharacter() end)
                if targetIsPC then return end

                local actorKey = nil
                pcall(function() actorKey = Target:GetFullName() end)

                local isDead = false
                pcall(function() isDead = Target:IsDead() end)

                local attackerIsPC = false
                pcall(function() attackerIsPC = Attacker:IsPlayerCharacter() end)

                if not attackerIsPC then
                    if isDead and actorKey then npcKilledActors[actorKey] = true end
                    return
                end

                if not isDead then
                    if actorKey then playerEngagedActors[actorKey] = true end
                    return
                end

                if actorKey then
                    if killedActors[actorKey] then return end
                    killedActors[actorKey] = true
                end

                local formID = getActorFormID(Target)
                if not formID then return end

                local loc = nil
                pcall(function() loc = Target:K2_GetActorLocation() end)
                if not loc then return end

                local weaponType = ActorDetection.GetWeaponKind(Attacker)
                local spellAge = lastPlayerSpellTime > 0 and (os.time() - lastPlayerSpellTime) or nil
                if weaponType == "unarmed" and spellAge and spellAge <= SPELL_KILL_WINDOW then
                    weaponType = "spell"
                end

                OnEnemyDeath({
                    formID = formID,
                    name = getActorName(Target),
                    level = getActorLevel(Target),
                    playerLevel = getActorLevel(Attacker),
                    location = loc,
                    weaponType = weaponType,
                }, Attacker)
            end)
        end
    )

    RegisterHook("/Script/Altar.VPairedPawn:SendSpellCast", function(Context)
        pcall(function()
            if travelling then return end
            local pawn = Context:get()
            if not pawn or not pawn:IsValid() then return end
            local isPC = false
            pcall(function() isPC = pawn:IsPlayerCharacter() end)
            if isPC then
                lastPlayerSpellTime = os.time()
            end
        end)
    end)

    local magicHookPaths = {
        "/Script/Altar.VPairedPawn:OnDeathVFX",
        "/Game/Dev/NPCs/BP_Generic_NPC.BP_Generic_NPC_C:OnDeathVFX",
        "/Game/Dev/Creatures/BP_Generic_Creature.BP_Generic_Creature_C:OnDeathVFX",
    }
    for _, hookPath in ipairs(magicHookPaths) do
        local ok, err = pcall(function()
            RegisterHook(hookPath, function(Context)
                pcall(function()
                    if travelling then return end
                    local target = Context:get()
                    if not target or not target:IsValid() then return end

                    local isPC = false
                    pcall(function() isPC = target:IsPlayerCharacter() end)
                    if isPC then return end

                    local actorKey = "?"
                    pcall(function() actorKey = target:GetFullName() end)
                    local shortName = actorKey:match("([^%.]+)$") or actorKey

                    local formID = getActorFormID(target)
                    if not formID then return end
                    if killedActors[actorKey] then return end
                    if npcKilledActors[actorKey] then return end

                    local player = UEHelpers:GetPlayer()
                    if not player or not player:IsValid() then return end
                    local playerLoc, targetLoc
                    pcall(function() playerLoc = player:K2_GetActorLocation() end)
                    pcall(function() targetLoc = target:K2_GetActorLocation() end)
                    if not playerLoc or not targetLoc then return end

                    local dist = math.sqrt(
                        (targetLoc.X - playerLoc.X)^2 +
                        (targetLoc.Y - playerLoc.Y)^2 +
                        (targetLoc.Z - playerLoc.Z)^2
                    )
                    if dist > SPELL_KILL_RANGE then return end

                    local isSpellKill = lastPlayerSpellTime > 0
                        and (os.time() - lastPlayerSpellTime) <= SPELL_KILL_WINDOW
                        and dist <= SPELL_KILL_RANGE
                    if not playerEngagedActors[actorKey] and not isSpellKill then return end

                    killedActors[actorKey] = true
                    local weaponType = "unarmed"
                    if isSpellKill then
                        weaponType = "spell"
                    else
                        weaponType = ActorDetection.GetWeaponKind(player)
                    end
                    OnEnemyDeath({
                        formID = formID,
                        name = shortName,
                        level = getActorLevel(target),
                        playerLevel = getActorLevel(player),
                        location = targetLoc,
                        weaponType = weaponType,
                    }, player)
                end)
            end)
        end)
        if ok then
            deathVfxHookBound = deathVfxHookBound + 1
            adLog("OnDeathVFX hook bound: " .. hookPath)
        else
            adLog("OnDeathVFX hook FAILED: " .. hookPath .. " " .. tostring(err), "WARN")
        end
    end
    if deathVfxHookBound == 0 then
        adLog("No OnDeathVFX hooks bound — spell kills that miss combat-hit will not credit", "WARN")
    end
end

function ActorDetection.ClearKilledActors()
    killedActors = {}
    playerEngagedActors = {}
    npcKilledActors = {}
    lastPlayerSpellTime = 0
end

-- VContainer instances only.
function ActorDetection.DetectNearbyContainers(radius)
    if travelling then return {} end
    if os.clock() < chestScanEarliest then return {} end
    radius = radius or config.detectionRadius

    local player = UEHelpers:GetPlayer()
    local playerValid = false
    pcall(function()
        playerValid = player and player.IsValid and player:IsValid()
    end)
    if not playerValid then return {} end

    local playerLoc = nil
    pcall(function() playerLoc = player:K2_GetActorLocation() end)
    if not playerLoc then return {} end

    local instances = nil
    pcall(function()
        instances = FindAllOf("VContainer")
    end)
    if not instances then return {} end

    local containers = {}
    for _, actor in ipairs(instances) do
        pcall(function()
            if not actor then return end
            local fullName = actor:GetFullName() or ""
            if fullName == "" then return end
            if not (fullName:match("Chest") or fullName:match("Coffin") or fullName:match("Barrel") or
               fullName:match("Crate") or fullName:match("Container") or fullName:match("Sack") or
               fullName:match("Urn")) then
                return
            end
            local location = actor:K2_GetActorLocation()
            if not location then return end
            local dx = location.X - playerLoc.X
            local dy = location.Y - playerLoc.Y
            local dz = location.Z - playerLoc.Z
            if (dx * dx + dy * dy + dz * dz) > (radius * radius) then
                return
            end
            local formID = getActorFormID(actor) or fullName
            containers[formID] = {
                formID = formID,
                name = fullName:match("([^%.]+)$") or fullName,
                location = location,
                fullName = fullName
            }
        end)
    end
    return containers
end

-- Find the nearest unharvested Nirnroot plant and return directional data
function ActorDetection.FindNearestNirnroot(player, maxDistance)
    maxDistance = maxDistance or 10000

    if not player or not player:IsValid() then
        return nil, "Player not found"
    end

    local playerLoc = player:K2_GetActorLocation()

    local classNames = {
        "BP_NirnrootPlant_C",
        "BP_Nirnroot_C",
        "BP_Flora_NirnrootPlant_C",
        "BP_Flora_Nirnroot_C",
        "BP_Flora_InteractibleObjects_C",
    }

    local nearest = nil
    local nearestDistance = maxDistance
    local totalScanned = 0

    for _, className in ipairs(classNames) do
        local instances = FindAllOf(className)
        if instances and #instances > 0 then
            totalScanned = totalScanned + #instances
            for _, obj in ipairs(instances) do
                if obj and obj:IsValid() then
                    local fullName = obj:GetFullName()
                    local isNirnroot = (className ~= "BP_Flora_InteractibleObjects_C") or fullName:match("[Nn]irnroot")
                    if isNirnroot then
                        local ok, location = pcall(function() return obj:K2_GetActorLocation() end)
                        if ok and location then
                            local distance = math.sqrt(
                                (location.X - playerLoc.X)^2 +
                                (location.Y - playerLoc.Y)^2 +
                                (location.Z - playerLoc.Z)^2
                            )
                            if distance < nearestDistance then
                                nearestDistance = distance
                                nearest = { object = obj, location = location, distance = distance, fullName = fullName }
                            end
                        end
                    end
                end
            end
        end
    end

    if nearest then
        local dx = nearest.location.X - playerLoc.X
        local dy = nearest.location.Y - playerLoc.Y
        local angle = math.atan2(dy, dx) * (180 / math.pi)
        if angle < 0 then angle = angle + 360 end
        local directions = {"E", "NE", "N", "NW", "W", "SW", "S", "SE"}
        nearest.compassDirection = directions[math.floor((angle + 22.5) / 45) % 8 + 1]
        nearest.distanceMeters = math.floor(nearest.distance / 100)
        nearest.bearing = math.floor(angle)
        return nearest, nil
    end

    return nil, "No Nirnroot found within range (scanned " .. tostring(totalScanned) .. " flora objects)"
end

return ActorDetection
