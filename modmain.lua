local GLOBAL = GLOBAL
local ACTIONS = GLOBAL.ACTIONS
local FRAMES = GLOBAL.FRAMES
local TheSim = GLOBAL.TheSim
local TheInput = GLOBAL.TheInput

local function getConfiguredKey(name)
    local value = GetModConfigData(name)
    if type(value) == "string" then
        return GLOBAL[value]
    end
    return value
end

local keyToggle = getConfiguredKey("TOGGLE_PICKUP_FILTER")
local keyQuick = getConfiguredKey("FILTER_QUICK_TOGGLE")

local tagFiltered = "pf_no_pickup"
local saveFile = "pickup_filter_data.txt"

local filterEnabled = true
local filteredPrefabs = {}

local function saveFiltered()
    local list = {}
    for prefab in pairs(filteredPrefabs) do
        list[#list + 1] = prefab
    end
    TheSim:SetPersistentString(saveFile, table.concat(list, "\n"), false)
end

local function loadFiltered()
    TheSim:GetPersistentString(
        saveFile,
        function(success, data)
            if success and type(data) == "string" then
                for line in data:gmatch("[^\r\n]+") do
                    filteredPrefabs[line] = true
                end
            end
        end
    )
end

loadFiltered()

local function canFilter(ent)
    if not ent then
        return false
    end
    local rep = ent.replica and ent.replica.inventoryitem
    return (rep and rep:CanBePickedUp()) or ent:HasTag("pickable")
end

local function colorize(entity, active)
    if entity and entity.AnimState then
        if active then
            entity.AnimState:SetMultColour(1, 0, 0, 1)
            entity:AddTag(tagFiltered)
        else
            entity.AnimState:SetMultColour(1, 1, 1, 1)
            entity:RemoveTag(tagFiltered)
        end
    end
end

local function say(message)
    local ply = GLOBAL.ThePlayer
    if ply and ply.components.talker then
        ply.components.talker:Say(message)
    else
        GLOBAL.print("[PickupFilter] " .. message)
    end
end

AddPrefabPostInitAny(
    function(inst)
        if filteredPrefabs[inst.prefab] then
            inst:DoTaskInTime(
                FRAMES * 2,
                function()
                    colorize(inst, true)
                end
            )
        end
    end
)

local function stripActions(self, actions)
    if not (filterEnabled and self.inst == GLOBAL.ThePlayer) then
        return actions
    end
    for i = #actions, 1, -1 do
        local act = actions[i]
        if (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP) and filteredPrefabs[act.target.prefab] then
            table.remove(actions, i)
        end
    end
    return actions
end

AddClassPostConstruct(
    "components/playeractionpicker",
    function(Class)
        local oldLeft = Class.GetLeftClickActions
        local oldRight = Class.GetRightClickActions

        function Class:GetLeftClickActions(...)
            return stripActions(self, oldLeft(self, ...))
        end

        function Class:GetRightClickActions(...)
            return stripActions(self, oldRight(self, ...))
        end
    end
)

AddClassPostConstruct(
    "components/playercontroller",
    function(Class)
        local oldGet = Class.GetActionButtonAction
        function Class:GetActionButtonAction(...)
            local act = oldGet(self, ...)
            if
                act and (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP) and filterEnabled and
                    filteredPrefabs[act.target.prefab] and
                    self.inst == GLOBAL.ThePlayer
             then
                return nil
            end
            return act
        end
    end
)

AddClassPostConstruct(
    "components/inventoryitem_replica",
    function(Class)
        local oldCan = Class.CanBePickedUp
        function Class:CanBePickedUp(picker)
            if filterEnabled and picker == GLOBAL.ThePlayer and self.inst:HasTag(tagFiltered) then
                return false
            end
            return oldCan(self, picker)
        end
    end
)

TheInput:AddKeyDownHandler(
    keyToggle,
    function()
        if GLOBAL.IsPaused() then
            return
        end
        local ent = TheInput:GetWorldEntityUnderMouse()
        if not canFilter(ent) then
            say("I can't filter that.")
            return
        end
        local name = ent.prefab
        local enabled = not filteredPrefabs[name]
        filteredPrefabs[name] = enabled and true or nil
        saveFiltered()

        say(
            enabled and string.format("Now ignoring '%s'.", ent.name or name) or
                string.format("Now picking '%s' again.", ent.name or name)
        )
        for _, e in pairs(GLOBAL.Ents) do
            if e.prefab == name then
                colorize(e, enabled and filterEnabled)
            end
        end
    end
)

TheInput:AddKeyDownHandler(
    keyQuick,
    function()
        if GLOBAL.IsPaused() then
            return
        end
        filterEnabled = not filterEnabled
        say(filterEnabled and "Pickup filter enabled." or "Pickup filter disabled temporarily.")
        for _, ent in pairs(GLOBAL.Ents) do
            if filteredPrefabs[ent.prefab] then
                colorize(ent, filterEnabled)
            end
        end
    end
)
