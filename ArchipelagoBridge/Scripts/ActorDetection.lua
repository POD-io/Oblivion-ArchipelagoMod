local ActorDetection = {}

local UEHelpers = require("UEHelpers")

local config = {
    detectionRadius = 2000,
}

local onDeathCallback = nil
local killedActors = {}
local playerEngagedActors = {}
local npcKilledActors = {}
local lastPlayerSpellTime = 0

local function getActorFormID(actor)
    if not actor or not actor:IsValid() then return nil end
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

local function OnEnemyDeath(enemyData, killer)
    if onDeathCallback then
        onDeathCallback(enemyData, killer)
    end
end

function ActorDetection.Initialize(callback)
    onDeathCallback = callback

    -- Primary kill hook: weapon / bow kills for all attackers.
    -- Player kills are processed immediately; NPC kills are excluded
    RegisterHook("/Script/Altar.VPairedPawn:OnCombatHitDealt", function(Context, HitEvent)
        local hEvent = HitEvent:get()
        local Attacker, Target = hEvent.Attacker, hEvent.Target
        if not Attacker or not Target then return end
        if Target:IsPlayerCharacter() then return end

        local actorKey = nil
        pcall(function() actorKey = Target:GetFullName() end)

        local isDead = false
        pcall(function() isDead = Target:IsDead() end)

        local attackerIsPC = false
        pcall(function() attackerIsPC = Attacker:IsPlayerCharacter() end)

        if not attackerIsPC then
            -- NPC delivered the killing blow — exclude
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
        if formID then
            OnEnemyDeath({
                actor = Target, formID = formID, name = getActorName(Target),
                level = getActorLevel(Target), location = Target:K2_GetActorLocation()
            }, Attacker)
        end
    end)

    -- Track when the player casts a spell so OnDeathVFX can attribute nearby deaths.
    RegisterHook("/Script/Altar.VPairedPawn:SendSpellCast", function(Context)
        pcall(function()
            local pawn = Context:get()
            if not pawn or not pawn:IsValid() then return end
            local isPC = false
            pcall(function() isPC = pawn:IsPlayerCharacter() end)
            if isPC then lastPlayerSpellTime = os.time() end
        end)
    end)

    -- Secondary hooks: OnDeathVFX fires for spell kills
    local magicHookPaths = {
        "/Game/Dev/NPCs/BP_Generic_NPC.BP_Generic_NPC_C:OnDeathVFX",
        "/Game/Dev/Creatures/BP_Generic_Creature.BP_Generic_Creature_C:OnDeathVFX",
    }
    for _, hookPath in ipairs(magicHookPaths) do
        pcall(function()
            RegisterHook(hookPath, function(Context)
                pcall(function()
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
                    if dist > 8000 then return end

                    local isSpellKill = (os.time() - lastPlayerSpellTime) <= 3 and dist <= 2000
                    if not playerEngagedActors[actorKey] and not isSpellKill then return end

                    killedActors[actorKey] = true
                    OnEnemyDeath({
                        actor = target, formID = formID,
                        name = shortName, level = getActorLevel(target), location = targetLoc
                    }, player)
                end)
            end)
        end)
    end
end

-- Reset kill state on cell transition
function ActorDetection.ClearKilledActors()
    killedActors = {}
    playerEngagedActors = {}
    npcKilledActors = {}
    lastPlayerSpellTime = 0
end

-- Sphere scan for nearby containers used by boss-chest tracking
function ActorDetection.DetectNearbyContainers(radius)
    radius = radius or config.detectionRadius

    local player = UEHelpers:GetPlayer()
    if not player or not player:IsValid() then return {} end

    local actorClass = StaticFindObject("/Script/Engine.Actor")
    if not actorClass then return {} end

    local actorList = {}
    local playerLoc = player:K2_GetActorLocation()
    local kismetSystem = UEHelpers.GetKismetSystemLibrary()
    local worldContext = UEHelpers.GetWorldContextObject()
    if not kismetSystem or not worldContext then return {} end

    kismetSystem:SphereOverlapActors(worldContext, playerLoc, radius, {}, actorClass, { player }, actorList)

    local containers = {}
    for _, actorRef in ipairs(actorList) do
        pcall(function()
            local actor = actorRef:get()
            if not actor then return end
            local isValid = false
            pcall(function() isValid = actor:IsValid() end)
            if not isValid then return end
            local fullName = ""
            pcall(function() fullName = actor:GetFullName() end)
            if fullName == "" then return end
            if fullName:match("Chest") or fullName:match("Coffin") or fullName:match("Barrel") or
               fullName:match("Crate") or fullName:match("Container") or fullName:match("Sack") or
               fullName:match("Urn") then
                local formID = getActorFormID(actor)
                local name = getActorName(actor)
                local location = nil
                pcall(function() location = actor:K2_GetActorLocation() end)
                if formID and location then
                    containers[formID] = {
                        actor = actor,
                        formID = formID,
                        name = name,
                        location = location,
                        fullName = fullName
                    }
                end
            end
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
