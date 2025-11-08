_placedStills = {}
_inProgBrews = {}

_placedBarrels = {}
_inProgAges = {}

-- Enhanced Systems
_stillHeat = {} -- Heat tracking per still (indexed by stillId)
_policeAlerts = {} -- Active police alerts
_activeDeliveries = {} -- Active delivery missions
_lastAlertTime = {} -- Cooldown tracking for alerts (indexed by stillId)

local bought = {}

-- Helper Functions
local function GetMoonshineRep(source)
    local char = exports['sandbox-characters']:FetchCharacterSource(source)
    if char then
        local reps = char:GetData("Reputations") or {}
        return reps["moonshine"] or 0
    end
    return 0
end

local function AddMoonshineRep(source, amount)
    exports['sandbox-characters']:RepAdd(source, "moonshine", amount)
end

local function CalculateQuality(recipe, skillChecks, stillTier, temperature, weather, skillLevel)
    local baseQuality = recipe.baseQuality
    local factors = _qualityFactors
    
    -- Skill contribution (0-30% based on skill level, max 1000 rep = 30%)
    local skillContribution = math.min(skillLevel / 1000, 1.0) * 30 * factors.skillMultiplier
    
    -- Skill check contribution (0-25% based on success rate)
    local checkSuccessRate = skillChecks.success / skillChecks.total
    local checkContribution = checkSuccessRate * 25 * factors.skillChecks
    
    -- Still tier contribution (0-10%)
    local tierContribution = (_stillTiers[stillTier]?.efficiency or 0.75) * 10 * factors.stillTier
    
    -- Temperature contribution (0-15%)
    local tempContribution = 0
    if temperature >= _temperatureEffects.optimal.min and temperature <= _temperatureEffects.optimal.max then
        tempContribution = 15 * factors.temperature
    elseif temperature >= _temperatureEffects.good.min and temperature <= _temperatureEffects.good.max then
        tempContribution = 10 * factors.temperature
    elseif temperature >= _temperatureEffects.poor.min and temperature <= _temperatureEffects.poor.max then
        tempContribution = 5 * factors.temperature
    else
        tempContribution = -10 * factors.temperature -- Penalty for extreme temps
    end
    
    -- Weather modifier
    local weatherMod = _weatherEffects[weather] or 1.0
    
    -- Calculate final quality
    local quality = baseQuality + skillContribution + checkContribution + tierContribution + tempContribution
    quality = quality * weatherMod
    
    -- Apply still efficiency
    quality = quality * (_stillTiers[stillTier]?.efficiency or 0.75)
    
    -- Clamp between 1-100
    return math.max(1, math.min(100, math.floor(quality)))
end

local function GetRecipeById(recipeId)
    for k, v in ipairs(_moonshineRecipes) do
        if v.id == recipeId then
            return v
        end
    end
    return nil
end

local function CheckRecipeUnlocked(source, recipeId)
    local rep = GetMoonshineRep(source)
    local requiredRep = _reputationSystem.unlockRecipes[recipeId] or 0
    return rep >= requiredRep
end

local function AddHeatToStill(stillId, amount)
    _stillHeat[stillId] = (_stillHeat[stillId] or 0) + amount
    if _stillHeat[stillId] > _policeDetection.maxHeat then
        _stillHeat[stillId] = _policeDetection.maxHeat
    end
    return _stillHeat[stillId]
end

local function CheckPoliceAlert(coords, stillId)
    local heat = _stillHeat[stillId] or 0
    
    if heat >= _policeDetection.alertThreshold then
        local lastAlert = _lastAlertTime[stillId] or 0
        if os.time() - lastAlert > _policeDetection.alertCooldown then
            _lastAlertTime[stillId] = os.time()
            
            -- Send alert to police
            local alertData = {
                type = "moonshine",
                coords = coords,
                stillId = stillId,
                heat = heat,
            }
            
            -- Check for nearby police and send alerts
            for _, playerId in ipairs(GetPlayers()) do
                local player = Player(tonumber(playerId))
                if player and player.state.onDuty == "police" then
                    -- Send alert to all police (they can see distance on their end)
                    TriggerClientEvent("Drugs:Client:Moonshine:PoliceAlert", tonumber(playerId), {
                        coords = coords,
                        heat = heat,
                        stillId = stillId,
                    })
                end
            end
            
            return true
        end
    end
    
    -- Check for raid chance
    if heat >= _policeDetection.raidThreshold then
        if math.random() < _policeDetection.raidChance then
            return "raid"
        end
    end
    
    return false
end

local year = os.date("%Y")
local month = os.date("%m")
local _toolsForSale = {
    {
        id = 1,
        item = "moonshine_still",
        coin = "MALD",
        price = 60,
        qty = 5,
        vpn = true,
        limited = {
            id = year + month,
            qty = 5,
        }
    },
}

exports('MoonshineStillGenerate', function(tier)
    return MySQL.insert.await('INSERT INTO moonshine_stills (created, tier) VALUES(?, ?)', { os.time(), tier })
end)

exports('MoonshineStillGet', function(stillId)
    return MySQL.single.await(
        'SELECT id, tier, created, cooldown, active_cook FROM moonshine_stills WHERE id = ?', { stillId })
end)

exports('MoonshineStillIsPlaced', function(stillId)
    return MySQL.scalar.await('SELECT COUNT(still_id) as Count FROM placed_moonshine_stills WHERE still_id = ?',
        { stillId }) > 0
end)

exports('MoonshineStillCreatePlaced', function(stillId, owner, tier, coords, heading, created)
    local itemInfo = exports.ox_inventory:ItemsGetData("moonshine_still")
    local stillData = exports['sandbox-drugs']:MoonshineStillGet(stillId)
    
    -- Check if still is already placed (in database)
    local isPlaced = exports['sandbox-drugs']:MoonshineStillIsPlaced(stillId)
    
    local cooldown = nil
    local activeBrew = false
    local pickupReady = false
    
    if isPlaced then
        -- Still is already placed - preserve its current state if valid
        -- Check if it has an active brew that's still valid
        if stillData and stillData.active_cook ~= nil then
            local cookData = json.decode(stillData.active_cook)
            if cookData and cookData.end_time and os.time() < cookData.end_time then
                -- Active brew is still valid - preserve it
                activeBrew = true
                pickupReady = os.time() > cookData.end_time
                _inProgBrews[stillId] = cookData
            else
                -- Active brew expired - clear it
                MySQL.query.await('UPDATE moonshine_stills SET active_cook = NULL WHERE id = ?', { stillId })
            end
        end
        
        -- Check cooldown - only preserve if still active
        if stillData and stillData.cooldown and os.time() < stillData.cooldown then
            cooldown = stillData.cooldown
        else
            -- Clear expired cooldown
            if stillData and stillData.cooldown then
                MySQL.query.await('UPDATE moonshine_stills SET cooldown = NULL WHERE id = ?', { stillId })
            end
        end
        
        -- Update existing record (moving a still that was previously placed)
        MySQL.query.await(
            "UPDATE placed_moonshine_stills SET owner = ?, placed = ?, expires = ?, coords = ?, heading = ? WHERE still_id = ?",
            {
                owner,
                os.time(),
                created + itemInfo.durability,
                json.encode(coords),
                heading,
                stillId,
            })
    else
        -- Fresh placement - reset all state for this still ID
        -- Clear any old active_cook and cooldown from database
        MySQL.query.await('UPDATE moonshine_stills SET active_cook = NULL, cooldown = NULL WHERE id = ?', { stillId })
        
        -- Clear any in-memory state for this still (heat, alerts, brews)
        _inProgBrews[stillId] = nil
        _stillHeat[stillId] = nil
        _lastAlertTime[stillId] = nil
        
        -- Insert new record (fresh placement)
        MySQL.insert.await(
            "INSERT INTO placed_moonshine_stills (still_id, owner, placed, expires, coords, heading) VALUES(?, ?, ?, ?, ?, ?)",
            {
                stillId,
                owner,
                os.time(),
                created + itemInfo.durability,
                json.encode(coords),
                heading,
            })
    end

    -- Create/update state for this still - each still ID is completely independent
    _placedStills[stillId] = {
        id = stillId,
        owner = owner,
        tier = tier,
        placed = os.time(),
        expires = created + itemInfo.durability,
        cooldown = cooldown,
        activeBrew = activeBrew,
        pickupReady = pickupReady,
        coords = coords,
        heading = heading,
    }

    TriggerClientEvent("Drugs:Client:Moonshine:CreateStill", -1, _placedStills[stillId])
end)

exports('MoonshineStillRemovePlaced', function(stillId)
    local s = MySQL.query.await('DELETE FROM placed_moonshine_stills WHERE still_id = ?', { stillId })
    if s.affectedRows > 0 then
        _placedStills[stillId] = nil
        _inProgBrews[stillId] = nil
        _stillHeat[stillId] = nil -- Clear heat for this still
        _lastAlertTime[stillId] = nil -- Clear alert cooldown for this still
        TriggerClientEvent("Drugs:Client:Moonshine:RemoveStill", -1, stillId)
    end
    return s.affectedRows > 0
end)

exports('MoonshineStillStartCook', function(stillId, cooldown, results)
    MySQL.query.await('UPDATE moonshine_stills SET cooldown = ?, active_cook = ? WHERE id = ?',
        { cooldown, json.encode(results), stillId })
    _placedStills[stillId].cooldown = cooldown
    _placedStills[stillId].activeBrew = true
    _placedStills[stillId].pickupReady = false
    _inProgBrews[stillId] = results

    TriggerClientEvent("Drugs:Client:Moonshine:UpdateStillData", -1, stillId, _placedStills[stillId])
end)

exports('MoonshineStillFinishCook', function(stillId)
    MySQL.query.await('UPDATE moonshine_stills SET active_cook = NULL WHERE id = ?', { stillId })
    _placedStills[stillId].activeBrew = false
    _placedStills[stillId].pickupReady = false
    _inProgBrews[stillId] = nil
    TriggerClientEvent("Drugs:Client:Moonshine:UpdateStillData", -1, stillId, _placedStills[stillId])
end)

exports('MoonshineBarrelGenerate', function(...)
    -- Generate barrel metadata for items (returns table, not database ID)
    -- Accepts any arguments for compatibility but ignores them
    return {
        Quality = math.random(1, 100),
        Drinks = math.random(15, 30),
    }
end)

exports('MoonshineBarrelCreateDatabase', function(quality, drinks)
    -- Create a barrel record in the database and return the ID
    local barrelId = MySQL.insert.await(
        'INSERT INTO moonshine_barrels (quality, drinks) VALUES(?, ?)',
        { quality or math.random(1, 100), drinks or math.random(15, 30) }
    )
    return barrelId
end)

exports('MoonshineBarrelIsPlaced', function(barrelId)
    return MySQL.scalar.await('SELECT COUNT(*) as Count FROM placed_moonshine_barrels WHERE barrel_id = ?',
        { barrelId }) > 0
end)

exports('MoonshineBarrelCreatePlaced', function(owner, coords, heading, created, brewData)
    local itemInfo = exports.ox_inventory:ItemsGetData("moonshine_barrel")
    
    -- Check if dev mode is enabled
    local isDevMode = _devMode or (exports["sandbox-base"]:GetEnvironment():upper() == "DEV")
    local ready = 0
    
    if isDevMode then
        -- Use dev aging time (in seconds)
        ready = os.time() + _devAgingTime
    else
        -- Use normal aging time (2 days = 48 hours)
        ready = os.time() + (60 * 60 * 24 * 2)
    end

    -- Create a barrel record in moonshine_barrels table first (required for foreign key)
    local barrelId = exports['sandbox-drugs']:MoonshineBarrelCreateDatabase(
        brewData?.Quality,
        brewData?.Drinks
    )
    
    if not barrelId then
        exports['sandbox-base']:LoggerWarn("Drugs:Moonshine", "Failed to create barrel record")
        return
    end
    
    MySQL.insert.await(
        "INSERT INTO placed_moonshine_barrels (barrel_id, owner, placed, ready, expires, coords, heading, brew_data) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
        {
            barrelId,
            owner,
            os.time(),
            ready,
            created + itemInfo.durability,
            json.encode(coords),
            heading,
            json.encode(brewData),
        })

    _placedBarrels[barrelId] = {
        id = barrelId,
        owner = owner,
        placed = os.time(),
        ready = ready,
        expires = created + itemInfo.durability,
        pickupReady = false,
        coords = coords,
        heading = heading,
        brewData = brewData,
    }

    _inProgAges[barrelId] = ready

    TriggerClientEvent("Drugs:Client:Moonshine:CreateBarrel", -1, _placedBarrels[barrelId])
end)

exports('MoonshineBarrelRemovePlaced', function(barrelId)
    local s = MySQL.query.await('DELETE FROM placed_moonshine_barrels WHERE barrel_id = ?', { barrelId })
    if s.affectedRows > 0 then
        _placedBarrels[barrelId] = nil
        TriggerClientEvent("Drugs:Client:Moonshine:RemoveBarrel", -1, barrelId)
    end
    return s.affectedRows > 0
end)

AddEventHandler("Drugs:Server:Startup", function()
    -- Initialize Moonshine Reputation System
    exports['sandbox-characters']:RepCreate("moonshine", "Moonshine Brewing", {
        { label = "Novice", value = 100 },
        { label = "Apprentice", value = 500 },
        { label = "Journeyman", value = 1500 },
        { label = "Expert", value = 3000 },
        { label = "Master", value = 5000 },
        { label = "Grandmaster", value = 10000 },
    }, false)
    
    exports['sandbox-pedinteraction']:VendorCreate("MoonshineSeller", "ped", "Karen", `S_F_Y_Bartender_01`, {
        coords = vector3(755.504, -1860.620, 48.292),
        heading = 307.963,
        scenario = "WORLD_HUMAN_SMOKING"
    }, _toolsForSale, "fas fa-jar", "View Offers", false, false, true)

    local stills = MySQL.query.await('SELECT * FROM placed_moonshine_stills WHERE expires > ?', { os.time() })
    for k, v in ipairs(stills) do
        if _placedStills[v.still_id] == nil then
            local stillData = exports['sandbox-drugs']:MoonshineStillGet(v.still_id)

            if stillData ~= nil then
                local coords = json.decode(v.coords)
                
                -- Validate cooldown - clear if expired
                local cooldown = nil
                if stillData.cooldown and os.time() < stillData.cooldown then
                    cooldown = stillData.cooldown
                else
                    -- Clear expired cooldown from database
                    if stillData.cooldown then
                        MySQL.query.await('UPDATE moonshine_stills SET cooldown = NULL WHERE id = ?', { v.still_id })
                    end
                end
                
                -- Validate active brew - only keep if still valid
                local activeBrew = false
                local pickupReady = false
                if stillData.active_cook then
                    local f = json.decode(stillData.active_cook)
                    if f and f.end_time and os.time() < f.end_time then
                        -- Active brew is still valid
                        activeBrew = true
                        pickupReady = os.time() > f.end_time
                        _inProgBrews[v.still_id] = f
                    else
                        -- Active brew expired - clear it
                        MySQL.query.await('UPDATE moonshine_stills SET active_cook = NULL WHERE id = ?', { v.still_id })
                    end
                end
                
                _placedStills[v.still_id] = {
                    id = v.still_id,
                    owner = v.owner,
                    tier = stillData.tier,
                    placed = v.placed,
                    expires = v.expires,
                    cooldown = cooldown,
                    activeBrew = activeBrew,
                    pickupReady = pickupReady,
                    coords = coords,
                    heading = v.heading,
                }
            end
        end
    end

    exports['sandbox-base']:LoggerTrace("Drugs:Moonshine", string.format("Restored ^2%s^7 Moonshine Stills", #stills))

    local barrels = MySQL.query.await('SELECT * FROM placed_moonshine_barrels WHERE expires > ?', { os.time() })
    for k, v in ipairs(barrels) do
        if _placedBarrels[v.barrel_id] == nil then
            local coords = json.decode(v.coords)

            _placedBarrels[v.barrel_id] = {
                id = v.barrel_id,
                owner = v.owner,
                placed = v.placed,
                ready = v.ready,
                expires = v.expires,
                pickupReady = os.time() > (v.ready or 0),
                coords = coords,
                heading = v.heading,
                brewData = json.decode(v.brew_data),
            }

            if v.ready > os.time() then
                _inProgAges[v.barrel_id] = v.ready
            end
        end
    end

    exports['sandbox-base']:LoggerTrace("Drugs:Moonshine", string.format("Restored ^2%s^7 Moonshine Barrels", #barrels))

    exports['sandbox-base']:MiddlewareAdd("Characters:Spawning", function(source)
        TriggerLatentClientEvent("Drugs:Client:Moonshine:SetupStills", source, 50000, _placedStills)
        TriggerLatentClientEvent("Drugs:Client:Moonshine:SetupBarrels", source, 50000, _placedBarrels)
    end, 1)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:FinishStillPlacement", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char ~= nil then
            local slot = exports['sandbox-drugs']:GetPlacementData(source)
            if slot and (slot.name == "moonshine_still" or slot.Name == "moonshine_still") then
                local md = slot.metadata or slot.MetaData or {}
                
                -- Always generate a NEW still when placing - each still is independent
                local stillId = exports['sandbox-drugs']:MoonshineStillGenerate(1)
                local stillData = exports['sandbox-drugs']:MoonshineStillGet(stillId)
                
                if stillData and exports.ox_inventory:RemoveItem(source, "moonshine_still", 1, md) then
                    exports['sandbox-drugs']:MoonshineStillCreatePlaced(stillId, char:GetData("SID"),
                        stillData.tier,
                        data.endCoords.coords, data.endCoords.rotation, stillData.created)
                    exports['sandbox-drugs']:ClearPlacementData(source)
                    cb(true)
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:PickupStill", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        local pState = Player(source).state
        if char ~= nil then
            if data then
                if exports['sandbox-drugs']:MoonshineStillIsPlaced(data) then
                    local stillData = exports['sandbox-drugs']:MoonshineStillGet(data)
                    if pState.onDuty == "police" or stillData.owner == char:GetData("SID") then
                        if exports['sandbox-drugs']:MoonshineStillRemovePlaced(data) then
                            cb(true)
                        else
                            cb(false)
                        end
                    else
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:CheckStill", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char ~= nil then
            if data and _placedStills[data] ~= nil then
                if _placedStills[data].cooldown == nil or os.time() > _placedStills[data].cooldown then
                    cb(true)
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:StartCooking", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        
        if char == nil then
            exports['sandbox-base']:LoggerWarn("Drugs:Moonshine", "StartCooking: Character not found for source " .. source)
            cb(false)
            return
        end
        
        if not data or not data.stillId then
            exports['sandbox-base']:LoggerWarn("Drugs:Moonshine", "StartCooking: Invalid data from source " .. source)
            exports['sandbox-hud']:Notification(source, "error", "Invalid request data")
            cb(false)
            return
        end
        
        if _placedStills[data.stillId] == nil then
            exports['sandbox-base']:LoggerWarn("Drugs:Moonshine", 
                string.format("StartCooking: Still %s not found in placed stills", data.stillId))
            exports['sandbox-hud']:Notification(source, "error", "Still not found")
            cb(false)
            return
        end
        
        if _placedStills[data.stillId].cooldown ~= nil and os.time() <= _placedStills[data.stillId].cooldown then
            exports['sandbox-hud']:Notification(source, "error", "Still is on cooldown")
            cb(false)
            return
        end
        
        -- Still is ready, proceed with cooking
        local stillData = exports['sandbox-drugs']:MoonshineStillGet(data.stillId)
        local still = _placedStills[data.stillId]
        
        -- Get recipe
        local recipe = GetRecipeById(data.recipeId or "classic")
        if not recipe then
            exports['sandbox-hud']:Notification(source, "error", "Invalid recipe")
            cb(false)
            return
        end
        
        -- Check if recipe is unlocked
        if not CheckRecipeUnlocked(source, recipe.id) then
            exports['sandbox-hud']:Notification(source, "error", 
                string.format("Recipe locked! Need %d reputation", _reputationSystem.unlockRecipes[recipe.id]))
            cb(false)
            return
        end
        
        -- Check ingredients
        local sid = char:GetData("SID")
        local hasIngredients = true
        for k, ingredient in ipairs(recipe.ingredients) do
            if not exports.ox_inventory:ItemsHas(sid, 1, ingredient.item, ingredient.amount) then
                hasIngredients = false
                exports['sandbox-hud']:Notification(source, "error", 
                    string.format("Missing %d %s", ingredient.amount, ingredient.item))
                break
            end
        end
        
        if not hasIngredients then
            cb(false)
            return
        end
        
        -- Remove ingredients
        for k, ingredient in ipairs(recipe.ingredients) do
            exports.ox_inventory:Remove(sid, 1, ingredient.item, ingredient.amount, false)
        end
        
        -- Get temperature and weather from client
        local temperature = data.temperature or 20
        local weather = data.weather or "clear"
        
        -- Calculate quality
        local skillLevel = GetMoonshineRep(source)
        
        -- Validate results data structure
        if not data.results or not data.results.success or not data.results.total then
            exports['sandbox-base']:LoggerWarn("Drugs:Moonshine", 
                string.format("Invalid results data from player %s: %s", source, json.encode(data.results)))
            exports['sandbox-hud']:Notification(source, "error", "Invalid skill check results")
            cb(false)
            return
        end
        
        local quality = CalculateQuality(recipe, data.results, stillData.tier, temperature, weather, skillLevel)
        
        -- Add heat to still (each still has its own heat tracking)
        local heat = AddHeatToStill(data.stillId, _policeDetection.heatPerBrew)
        
        -- Check for police alert
        local alertResult = CheckPoliceAlert(still.coords, data.stillId)
        if alertResult == "raid" then
            -- Raid triggered - destroy still and lose items
            exports['sandbox-hud']:Notification(source, "error", "Police raid! Your still has been destroyed!")
            AddMoonshineRep(source, -_reputationSystem.repLossOnRaid)
            exports['sandbox-drugs']:MoonshineStillRemovePlaced(data.stillId)
            cb(false)
            return
        end
        
        -- Start cooking
        local isDevMode = _devMode or (exports["sandbox-base"]:GetEnvironment():upper() == "DEV")
        local cookTime = _stillTiers[stillData.tier]?.cookTime or 30
        local cookTimeSeconds = 0
        local cookTimeDisplay = ""
        
        if isDevMode then
            -- Use dev cook time (in seconds)
            cookTimeSeconds = _devCookTime
            cookTimeDisplay = string.format("%d seconds", _devCookTime)
        else
            -- Use normal cook time (convert minutes to seconds)
            cookTimeSeconds = 60 * cookTime
            cookTimeDisplay = string.format("%d minutes", cookTime)
        end
        
        local cooldownTime = os.time() + (60 * 60 * 2) -- 2 hour cooldown
        
        exports['sandbox-drugs']:MoonshineStillStartCook(data.stillId, cooldownTime, {
            start_time = os.time(),
            end_time = os.time() + cookTimeSeconds,
            quality = quality,
            recipe = recipe.id,
            heat = heat,
        })

        exports['sandbox-hud']:Notification(source, "success",
            string.format("Brew Started! Quality: %d/100 | Heat: %d/100 | Ready in %s",
                quality, heat, cookTimeDisplay))
        
        exports['sandbox-base']:LoggerInfo("Drugs:Moonshine",
            string.format("Player %s started brew on still %s with recipe %s, quality %d", 
                source, data.stillId, recipe.id, quality))
        
        cb(true)
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:PickupCook", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char ~= nil then
            if data and _placedStills[data] ~= nil then
                local stillData = exports['sandbox-drugs']:MoonshineStillGet(data)
                if stillData.active_cook ~= nil then
                    local cookData = json.decode(stillData.active_cook)
                    if os.time() > cookData.end_time then
                        local recipe = GetRecipeById(cookData.recipe or "classic")
                        local drinks = math.random(15, 30)
                        
                        -- Add reputation for successful brew
                        AddMoonshineRep(source, _reputationSystem.repPerBrew)
                        
                        if exports.ox_inventory:AddItem(char:GetData("SID"), "moonshine_barrel", 1, {
                                Brew = {
                                    Quality = cookData.quality,
                                    Drinks = drinks,
                                    Recipe = cookData.recipe or "classic",
                                    StartTime = os.time(),
                                }
                            }, 1, false, false, false, false, false, false, false) then
                            exports['sandbox-drugs']:MoonshineStillFinishCook(data)
                            exports['sandbox-hud']:Notification(source, "success", 
                                string.format("Brew Complete! Quality: %d/100 | Reputation +%d", 
                                    cookData.quality, _reputationSystem.repPerBrew))
                            cb(true)
                        else
                            cb(false)
                        end
                    else
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:GetStillDetails", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char ~= nil then
            if data and _placedStills[data] ~= nil then
                local stillData = exports['sandbox-drugs']:MoonshineStillGet(data)

                local menu = {
                    main = {
                        label = "Still Information",
                        items = {}
                    },
                }

                if stillData.cooldown ~= nil then
                    local timeUntil = stillData.cooldown - os.time()
                    if timeUntil > 0 then
                        table.insert(menu.main.items, {
                            label = "On Cooldown",
                            description = string.format("Available %s (in about %s)</li>",
                                os.date("%m/%d/%Y %I:%M %p", stillData.cooldown), GetFormattedTimeFromSeconds(timeUntil)),
                        })
                    else
                        table.insert(menu.main.items, {
                            label = "Cooldown Expired",
                            description = string.format("Expired at %s</li>",
                                os.date("%m/%d/%Y %I:%M %p", stillData.cooldown)),
                        })
                    end
                else
                    table.insert(menu.main.items, {
                        label = "Not On Cooldown",
                        description = string.format("No Cooldown Information Available"),
                    })
                end

                if stillData.active_cook ~= nil then
                    local cook = json.decode(stillData.active_cook)

                    local timeUntil = cook.end_time - os.time()
                    if timeUntil > 0 then
                        table.insert(menu.main.items, {
                            label = "Brew Status",
                            description = string.format("Finishes at %s (in about %s)",
                                os.date("%m/%d/%Y %I:%M %p", cook.end_time), GetFormattedTimeFromSeconds(timeUntil)),
                        })
                    else
                        table.insert(menu.main.items, {
                            label = "Brew Status",
                            description = string.format("Finished at %s", os.date("%m/%d/%Y %I:%M %p", cook.end_time)),
                        })
                    end
                else
                    table.insert(menu.main.items, {
                        label = "Brew Status",
                        description = string.format("No Active Brew"),
                    })
                end

                cb(menu)
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:FinishBarrelPlacement", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char ~= nil then
            local slot = exports['sandbox-drugs']:GetPlacementData(source)
            if slot and (slot.name == "moonshine_barrel" or slot.Name == "moonshine_barrel") then
                local md = slot.metadata or slot.MetaData or {}
                if exports.ox_inventory:RemoveItem(source, "moonshine_barrel", 1, md) then
                    exports['sandbox-drugs']:MoonshineBarrelCreatePlaced(char:GetData("SID"), data.endCoords.coords,
                        data.endCoords.rotation, os.time(), md.Brew)
                    exports['sandbox-drugs']:ClearPlacementData(source)
                    cb(true)
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:PickupBarrel", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        local pState = Player(source).state
        if char ~= nil then
            if data then
                if exports['sandbox-drugs']:MoonshineBarrelIsPlaced(data) then
                    if pState.onDuty == "police" or _placedBarrels[data]?.owner == char:GetData("SID") then
                        if exports['sandbox-drugs']:MoonshineBarrelRemovePlaced(data) then
                            cb(true)
                        else
                            cb(false)
                        end
                    else
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:GetBarrelDetails", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char ~= nil then
            if data and _placedBarrels[data] ~= nil then
                local menu = {
                    main = {
                        label = "Oak Barrel Information",
                        items = {}
                    },
                }

                if os.time() < (_placedBarrels[data]?.ready or 0) then
                    -- Still aging
                    local timeUntil = (_placedBarrels[data]?.ready or 0) - os.time()
                    table.insert(menu.main.items, {
                        label = "Aging Process Still In Progress",
                        description = string.format("Finishes At %s (in about %s)",
                            os.date("%m/%d/%Y %I:%M %p", _placedBarrels[data]?.ready),
                            GetFormattedTimeFromSeconds(math.max(0, timeUntil))),
                    })
                else
                    -- Finished aging
                    table.insert(menu.main.items, {
                        label = "Aging Process Finished",
                        description = string.format("Finished At %s",
                            os.date("%m/%d/%Y %I:%M %p", _placedBarrels[data]?.ready)),
                    })
                end

                cb(menu)
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:PickupBrew", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char == nil then
            cb(false)
            return
        end
        
        local sid = char:GetData("SID")
        if not data or _placedBarrels[data] == nil then
            exports['sandbox-hud']:Notification(source, "error", "Barrel not found")
            cb(false)
            return
        end
        
        local barrel = _placedBarrels[data]
        local ownerSid = tostring(barrel.owner or "")
        local playerSid = tostring(sid)
        
        -- Check ownership (compare as strings to handle type mismatches)
        if ownerSid ~= "" and ownerSid ~= playerSid then
            exports['sandbox-hud']:Notification(source, "error", "You don't own this barrel")
            cb(false)
            return
        end
        
        local requiredJars = barrel.brewData?.Drinks or 15
        
        -- Check if player has enough jars
        if not exports.ox_inventory:ItemsHas(sid, 1, "moonshine_jar", requiredJars) then
            exports['sandbox-hud']:Notification(source, "error",
                string.format("Missing Empty Jars! You need %s empty jars to fill.", requiredJars))
            cb(false)
            return
        end
        
        -- Remove jars
        if not exports.ox_inventory:Remove(sid, 1, "moonshine_jar", requiredJars, false) then
            exports['sandbox-hud']:Notification(source, "error", "Failed to remove jars")
            cb(false)
            return
        end
        
        -- Add moonshine items with recipe metadata
        local quality = barrel.brewData?.Quality or math.random(1, 100)
        local recipeId = barrel.brewData?.Recipe or "classic"
        local recipe = GetRecipeById(recipeId)
        local recipeLabel = recipe and recipe.label or "Classic Moonshine"
        
        -- Create metadata for each jar with recipe information
        local moonshineMetadata = {
            Recipe = recipeId,
            RecipeLabel = recipeLabel,
            Quality = quality,
        }
        
        if exports.ox_inventory:AddItem(sid, "moonshine", requiredJars, moonshineMetadata, 1, false, false, false, false, false, false, quality) then
            exports['sandbox-drugs']:MoonshineBarrelRemovePlaced(data)
            exports['sandbox-hud']:Notification(source, "success",
                string.format("Filled %s jars with %s! Quality: %d/100", requiredJars, recipeLabel, quality))
            cb(true)
        else
            exports['sandbox-hud']:Notification(source, "error", "Failed to add moonshine to inventory")
            -- Try to give jars back
            exports.ox_inventory:AddItem(sid, "moonshine_jar", requiredJars, {}, 1, false, false, false, false, false, false)
            cb(false)
        end
    end)

    -- Get Available Recipes
    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:GetRecipes", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char then
            local rep = GetMoonshineRep(source)
            local recipes = {}
            
            for k, recipe in ipairs(_moonshineRecipes) do
                local unlocked = CheckRecipeUnlocked(source, recipe.id)
                table.insert(recipes, {
                    id = recipe.id,
                    label = recipe.label,
                    description = recipe.description,
                    ingredients = recipe.ingredients,
                    baseQuality = recipe.baseQuality,
                    difficulty = recipe.difficulty,
                    unlocked = unlocked,
                    requiredRep = _reputationSystem.unlockRecipes[recipe.id] or 0,
                })
            end
            
            cb({ recipes = recipes, reputation = rep })
        else
            cb(false)
        end
    end)
    
    -- Upgrade Still
    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:UpgradeStill", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char and data and _placedStills[data] then
            local stillData = exports['sandbox-drugs']:MoonshineStillGet(data)
            local currentTier = stillData.tier
            local nextTier = currentTier + 1
            
            if not _stillTiers[nextTier] then
                exports['sandbox-hud']:Notification(source, "error", "Still is already at maximum tier")
                cb(false)
                return
            end
            
            -- Check reputation requirement
            local requiredRep = _upgradeSystem.requireRep[nextTier] or 0
            if GetMoonshineRep(source) < requiredRep then
                exports['sandbox-hud']:Notification(source, "error", 
                    string.format("Need %d reputation to upgrade", requiredRep))
                cb(false)
                return
            end
            
            -- Check cost
            local cost = _stillTiers[nextTier].upgradeCost
            if cost > 0 then
                -- Check if player has enough money (using bank or cash)
                local bankAccount = exports['sandbox-finance']:BankAccountGet(char:GetData("SID"), "checking")
                if not bankAccount or bankAccount.balance < cost then
                    exports['sandbox-hud']:Notification(source, "error", 
                        string.format("Need $%d to upgrade", cost))
                    cb(false)
                    return
                end
                
                -- Deduct money
                exports['sandbox-finance']:BankAccountRemove(char:GetData("SID"), "checking", cost, "Moonshine Still Upgrade")
            end
            
            -- Update tier in database
            MySQL.query.await('UPDATE moonshine_stills SET tier = ? WHERE id = ?', { nextTier, data })
            _placedStills[data].tier = nextTier
            
            exports['sandbox-hud']:Notification(source, "success", 
                string.format("Still upgraded to %s!", _stillTiers[nextTier].label))
            cb(true)
        else
            cb(false)
        end
    end)
    
    -- Get Delivery Mission
    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:GetDelivery", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char then
            local rep = GetMoonshineRep(source)
            
            if rep < _deliverySystem.minRep then
                exports['sandbox-hud']:Notification(source, "error", 
                    string.format("Need %d reputation for deliveries", _deliverySystem.minRep))
                cb(false)
                return
            end
            
            -- Check if player has moonshine to deliver
            local sid = char:GetData("SID")
            local moonshine = exports.ox_inventory:ItemsGetFirst(sid, "moonshine", 1)
            if not moonshine then
                exports['sandbox-hud']:Notification(source, "error", "You need moonshine to deliver")
                cb(false)
                return
            end
            
            -- Generate delivery location
            local playerCoords = GetEntityCoords(GetPlayerPed(source))
            local angle = math.random() * 2 * math.pi
            local distance = math.random(_deliverySystem.minDistance, _deliverySystem.maxDistance)
            local deliveryCoords = vector3(
                playerCoords.x + math.cos(angle) * distance,
                playerCoords.y + math.sin(angle) * distance,
                playerCoords.z
            )
            
            -- Calculate payment based on quality
            local quality = moonshine.Quality or 50
            local payment = _deliverySystem.basePay + (quality * _deliverySystem.payPerQuality)
            
            local deliveryId = #_activeDeliveries + 1
            _activeDeliveries[deliveryId] = {
                id = deliveryId,
                source = source,
                sid = sid,
                coords = deliveryCoords,
                payment = payment,
                quality = quality,
                startTime = os.time(),
                expires = os.time() + _deliverySystem.deliveryTimeLimit,
            }
            
            cb({
                id = deliveryId,
                coords = deliveryCoords,
                payment = payment,
                timeLimit = _deliverySystem.deliveryTimeLimit,
            })
        else
            cb(false)
        end
    end)
    
    -- Complete Delivery
    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:CompleteDelivery", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char and data and _activeDeliveries[data] then
            local delivery = _activeDeliveries[data]
            
            if delivery.source ~= source then
                cb(false)
                return
            end
            
            if os.time() > delivery.expires then
                exports['sandbox-hud']:Notification(source, "error", "Delivery expired!")
                _activeDeliveries[data] = nil
                cb(false)
                return
            end
            
            -- Remove moonshine
            local moonshine = exports.ox_inventory:ItemsGetFirst(delivery.sid, "moonshine", 1)
            if moonshine and exports.ox_inventory:RemoveId(delivery.sid, 1, moonshine) then
                -- Pay player
                exports['sandbox-finance']:BankAccountAdd(delivery.sid, "checking", delivery.payment, "Moonshine Delivery")
                
                -- Add reputation
                AddMoonshineRep(source, _reputationSystem.repPerDelivery)
                
                exports['sandbox-hud']:Notification(source, "success", 
                    string.format("Delivery Complete! +$%d | Reputation +%d", 
                        delivery.payment, _reputationSystem.repPerDelivery))
                
                _activeDeliveries[data] = nil
                cb(true)
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)
    
    -- Get Reputation Info
    exports["sandbox-base"]:RegisterServerCallback("Drugs:Moonshine:GetReputation", function(source, data, cb)
        local char = exports['sandbox-characters']:FetchCharacterSource(source)
        if char then
            local rep = GetMoonshineRep(source)
            cb({
                reputation = rep,
                unlockRecipes = _reputationSystem.unlockRecipes,
            })
        else
            cb(false)
        end
    end)
end)
