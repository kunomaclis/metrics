Ashita.Ability = { }

-- ------------------------------------------------------------------------------------------------------
-- Get ability data.
-- https://wiki.ashitaxi.com/doku.php?id=addons:adk:iresourcemanager
-- Types
-- * 1  = Most self-targetting abilities including 2-hours.
-- * 6  = SMN using BloodPactRage
-- * 10 = BloodPactWard
-- * 12 = Curing Waltz
-- * 13 = Steps
-- * 14 = Animated Flourish
-- * 16 = Spectral Jig
-- * 17 = Building Flourish
-- * 18 = BloodPactRage
-- * 21 = Rune Enchantment
-- * 23 = Swipe, Lunge
-- Offsets
-- * WS have zero offset.
-- * Abilities have 512 offset.
-- ------------------------------------------------------------------------------------------------------
---@param id integer
---@return table
-- ------------------------------------------------------------------------------------------------------
Ashita.Ability.GetByID = function(id)
    if not id then
        Debug.Error.Add(Debug.Error.ERROR, "Ashita.Ability.GetByID", "Parameter \"id\" was nil.")
        return nil
    end

    local resourceManager = AshitaCore:GetResourceManager()
    local abilityData = resourceManager and resourceManager:GetAbilityById(id)

    if not abilityData then
        Debug.Error.Add(Debug.Error.ERROR, "Ashita.Ability.GetByID", string.format("No ability data: ID {%d}.", id or 0))
        abilityData = { Id = id, Name = string.format("(%d) UNK Ability", id or 0), Type = 0 }
    else
        abilityData = { Id = id, Name = Ashita.Ability.Name(id, abilityData), Type = abilityData.Type }
    end

    return abilityData
end

-- ------------------------------------------------------------------------------------------------------
-- Get the name of an ability. If we already have the ability data then we don't need to get it again.
-- ------------------------------------------------------------------------------------------------------
---@param id    integer ability ID
---@param data? table   ability table if we already have it.
---@return string
-- ------------------------------------------------------------------------------------------------------
Ashita.Ability.Name = function(id, data)
    if not id then
        Debug.Error.Add(Debug.Error.ERROR, "Ashita.Ability.Name", string.format("Parameter \"id\" was nil."))
        return 'Error'
    end

    local ability = data or Ashita.Ability.GetByID(id)

    if not ability or not ability.Name or not ability.Name[1] then
        return "Error"
    end

    return ability.Name[3]
end

-- ------------------------------------------------------------------------------------------------------
-- Get the current recast time for an ability by the abilities ID.
-- ------------------------------------------------------------------------------------------------------
---@param id number ability ID
---@return number
-- ------------------------------------------------------------------------------------------------------
Ashita.Ability.RecastID = function(id)
    if not id then
        Debug.Error.Add(Debug.Error.ERROR, "Ashita.Ability.RecastID", "Parameter \"id\" was nil.")
        return 0
    end

    local memoryManager = AshitaCore:GetMemoryManager()
    local recast = memoryManager and memoryManager:GetRecast()
    if not recast then
        return 0
    end

    for i = 0, 31 do
        local abilityId = recast:GetAbilityTimerId(i)
        if abilityId == id then
            return math.floor(recast:GetAbilityTimer(i) / 60)
        end
    end

    return 0
end