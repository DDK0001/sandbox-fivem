if not lib then return end

local function fetchSlotRestrictions()
    local restrictions = {
        [1] = { name = "WEAPON SLOT 1", restrictions = { type = "weapon_prefix", prefix = "WEAPON_", exclude = false } },
        [2] = { name = "WEAPON SLOT 2", restrictions = { type = "weapon_prefix", prefix = "WEAPON_", exclude = false } },
        [3] = {
            name = "HOTKEY SLOT 3",
            exclude_items = { "backpack", "large_backpack", "military_backpack", "armor", "heavyarmor", "pdarmor", "phone", "parachute" },
            restrictions = {
                type = "weapon_prefix",
                prefix = "WEAPON_",
                exclude = true
            },
        },
        [4] = {
            name = "HOTKEY SLOT 4",
            exclude_items = { "backpack", "large_backpack", "military_backpack", "armor", "heavyarmor", "pdarmor", "phone", "parachute" },
            restrictions = {
                type = "weapon_prefix",
                prefix = "WEAPON_",
                exclude = true
            },
        },
        [5] = {
            name = "HOTKEY SLOT 5",
            exclude_items = { "backpack", "large_backpack", "military_backpack", "armor", "heavyarmor", "pdarmor", "phone", "parachute" },
            restrictions = {
                type = "weapon_prefix",
                prefix = "WEAPON_",
                exclude = true
            },
        },
        [6] = { name = "BACKPACK", restrictions = { type = "allowed_items", items = { "backpack", "large_backpack", "military_backpack" } } },
        [7] = { name = "BODY ARMOR", restrictions = { type = "allowed_items", items = { "armor", "heavyarmor", "pdarmor" } } },
        [8] = { name = "PHONE", restrictions = { type = "allowed_items", items = { "phone" } } },
        [9] = { name = "PARACHUTE", restrictions = { type = "allowed_items", items = { "parachute" } } }
    }

    local formattedRestrictions = {}
    for i = 1, 9 do
        formattedRestrictions[tostring(i)] = restrictions[i]
    end

    return formattedRestrictions
end

---@param itemName string
---@param slot number
---@return boolean
local function canItemBePlacedInSlot(itemName, slot)
    local restrictions = fetchSlotRestrictions()
    local slotConfig = restrictions[tostring(slot)]
    
    if not slotConfig or not slotConfig.restrictions then
        return true
    end
    
    if slotConfig.exclude_items and slotConfig.exclude_items[itemName] then
        return false
    end
    
    local restrictionsConfig = slotConfig.restrictions
    
    if restrictionsConfig.type == 'weapon_prefix' then
        local startsWithPrefix = itemName:sub(1, #restrictionsConfig.prefix) == (restrictionsConfig.prefix or '')
        return restrictionsConfig.exclude and not startsWithPrefix or startsWithPrefix
    elseif restrictionsConfig.type == 'allowed_items' then
        for _, allowedItem in ipairs(restrictionsConfig.items) do
            if itemName == allowedItem then
                return true
            end
        end
        return false
    end
    
    return true
end

lib.callback.register('ox_inventory:fetchSlotRestrictions', function(source)
    return fetchSlotRestrictions()
end)

return {
    fetch = fetchSlotRestrictions,
    canItemBePlacedInSlot = canItemBePlacedInSlot,
}
