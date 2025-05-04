local _G = GLOBAL
local ACTIONS = _G.ACTIONS
local FRAMES = _G.FRAMES

local function getKeyFromConfig(name)
    local k = GetModConfigData(name)
    return (type(k) == "string") and _G[k] or k
end

local FILTER_ITEM_KEY = getKeyFromConfig("FILTER_ITEM_KEY")
local TOGGLE_PICKUP_FILTER_KEY = getKeyFromConfig("TOGGLE_PICKUP_FILTER_KEY")

local TAG_FILTERED = "pf_no_pickup"
local SAVE_FILE = "pickup_filter_data.txt"

local filterEnabled = true

local function saveFilter(tbl)
    local out, n = {}, 0
    for prefab in pairs(tbl) do
        n = n + 1
        out[n] = prefab
    end
    _G.TheSim:SetPersistentString(SAVE_FILE, table.concat(out, "\n"), false)
end

local function loadFilter(callback)
    _G.TheSim:GetPersistentString(
        SAVE_FILE,
        function(ok, data)
            local filter = {}
            if ok and data then
                for prefab in data:gmatch("[^\r\n]+") do
                    filter[prefab] = true
                end
            end
            callback(filter)
        end
    )
end

local pickupFilter = {prefabs = {}}
loadFilter(function(filter)
    pickupFilter.prefabs = filter
end)

local function tintItem(ent, on)
    if ent and ent.AnimState then
        if on and filterEnabled then
            ent.AnimState:SetMultColour(1, 0, 0, 1)
            ent:AddTag(TAG_FILTERED)
        else
            ent.AnimState:SetMultColour(1, 1, 1, 1)
            ent:RemoveTag(TAG_FILTERED)
        end
    end
end

local function talk(msg)
    local ply = _G.ThePlayer
    if ply and ply.components.talker then
        ply.components.talker:Say(msg)
    else
        print("[Pickup Filter] " .. msg)
    end
end

local function canBeFiltered(ent)
    return (ent
        and ent.replica
        and ent.replica.inventoryitem
        and ent.replica.inventoryitem:CanBePickedUp()
    )
    or (ent and ent:HasTag("pickable"))
end

local function CanMouseThroughFiltered(ent)
    if filterEnabled and ent:HasTag(TAG_FILTERED) then
        return true, true
    end
end

local REMOVE_INTERACTIONS_BOOL = getKeyFromConfig("REMOVE_INTERACTIONS_FROM_FILTERED_BOOL")

AddPrefabPostInitAny(
    function(inst)
        if not inst or not inst.prefab or not pickupFilter.prefabs[inst.prefab] then
            return
        end
        inst:DoTaskInTime(
            FRAMES * 2,
            function()
                if REMOVE_INTERACTIONS_BOOL then
                    inst.CanMouseThrough = CanMouseThroughFiltered
                end
                tintItem(inst, true)
            end
        )
    end
)

local ALLOW_MOUSE_PICKUP_BOOL = getKeyFromConfig("ALLOW_MOUSE_PICKUP_THROUGH_FILTER_BOOL")

AddClassPostConstruct(
    "components/playeractionpicker",
    function(self)
        local function filterActions(actions, inst)
            if not (filterEnabled and inst == _G.ThePlayer) then
                return actions
            end

            for i = #actions, 1, -1 do
                local act = actions[i]
                if act and act.target and act.target.prefab and pickupFilter.prefabs[act.target.prefab] then
                    local isFilteredAction = not ALLOW_MOUSE_PICKUP_BOOL and (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP)
                    local isExamineOrWalk = REMOVE_INTERACTIONS_BOOL and (act.action == ACTIONS.LOOKAT or act.action == ACTIONS.WALKTO)
                    
                    if isFilteredAction or isExamineOrWalk then
                        table.remove(actions, i)
                    end
                end
            end
            return actions
        end

        local originalGetLeftClickActions = self.GetLeftClickActions
        function self:GetLeftClickActions(...)
            local actions = originalGetLeftClickActions(self, ...)
            return filterActions(actions, self.inst)
        end

        local originalGetRightClickActions = self.GetRightClickActions
        function self:GetRightClickActions(...)
            local actions = originalGetRightClickActions(self, ...)
            return filterActions(actions, self.inst)
        end
    end
)

AddClassPostConstruct(
    "components/playercontroller",
    function(playercontroller)
        local originalGetActionButtonAction = playercontroller.GetActionButtonAction
        function playercontroller:GetActionButtonAction(force_target, ...)
            local act = originalGetActionButtonAction(self, force_target, ...)
            if
                act and (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP) and filterEnabled and
                    pickupFilter.prefabs[act.target.prefab] and
                    self.inst == _G.ThePlayer
             then
                return
            end
            return act
        end
    end
)

AddClassPostConstruct(
    "components/inventoryitem_replica",
    function(self)
        local originalCanBePickedUp = self.CanBePickedUp
        function self:CanBePickedUp(picker)
            if filterEnabled and picker == _G.ThePlayer and self.inst and self.inst:HasTag(TAG_FILTERED) then
                return false
            end
            return originalCanBePickedUp(self, picker)
        end
    end
)

_G.TheInput:AddKeyDownHandler(
    FILTER_ITEM_KEY,
    function()
        if _G.IsPaused() then
            return
        end

        local ent = _G.TheInput:GetWorldEntityUnderMouse()
        if not (ent and ent.prefab and canBeFiltered(ent)) then
            talk("I can’t filter that.")
            return
        end

        local prefab = ent.prefab
        local now_filtered = not pickupFilter.prefabs[prefab]
        pickupFilter.prefabs[prefab] = now_filtered or nil
        saveFilter(pickupFilter.prefabs)

        talk(
            now_filtered and string.format("Okay! I’ll ignore “%s” from now on.", ent.name or prefab) or
                string.format("Got it! I’ll pick up “%s” again.", ent.name or prefab)
        )

        for _, ent in pairs(_G.Ents) do
            if ent and ent.prefab and ent.prefab == prefab then
                tintItem(ent, now_filtered and filterEnabled)
            end
        end
    end
)

_G.TheInput:AddKeyDownHandler(
    TOGGLE_PICKUP_FILTER_KEY,
    function()
        if _G.IsPaused() then
            return
        end
        filterEnabled = not filterEnabled

        talk(filterEnabled and "Pickup filter enabled." or "Pickup filter temporarily disabled.")

        for _, ent in pairs(_G.Ents) do
            if ent and ent.prefab and pickupFilter.prefabs[ent.prefab] then
                tintItem(ent, filterEnabled)
            end
        end
    end
)
