local _G = GLOBAL
local ACTIONS = _G.ACTIONS
local FRAMES = _G.FRAMES

local function key_from_config(name)
    local k = GetModConfigData(name)
    return (type(k) == "string") and _G[k] or k
end

local KEY_TOGGLE = key_from_config("TOGGLE_PICKUP_FILTER")
local KEY_QUICK_TOGGLE = key_from_config("FILTER_QUICK_TOGGLE")

local TAG_FILTERED = "pf_no_pickup"
local SAVE_FILE = "pickup_filter_data.txt"

local filter_on = true

local function save_filter(tbl)
    local out, n = {}, 0
    for prefab in pairs(tbl) do
        n = n + 1
        out[n] = prefab
    end
    _G.TheSim:SetPersistentString(SAVE_FILE, table.concat(out, "\n"), false)
end

local function load_filter()
    local filter = {}
    _G.TheSim:GetPersistentString(
        SAVE_FILE,
        function(ok, data)
            if ok and data then
                for prefab in data:gmatch("[^\r\n]+") do
                    filter[prefab] = true
                end
            end
        end
    )
    return filter
end

local pickup_filter = {prefabs = load_filter()}

local function colourise(ent, on)
    if ent and ent.AnimState then
        if on then
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
        print("[PickupFilter] " .. msg)
    end
end

local function can_be_filtered(ent)
    if not ent then
        return false
    end
    local rep = ent.replica and ent.replica.inventoryitem
    return (rep and rep:CanBePickedUp()) or ent:HasTag("pickable")
end

AddPrefabPostInitAny(
    function(inst)
        if not pickup_filter.prefabs[inst.prefab] then
            return
        end
        inst:DoTaskInTime(
            FRAMES * 2,
            function()
                colourise(inst, true)
            end
        )
    end
)

AddClassPostConstruct(
    "components/playeractionpicker",
    function(self)
        local function filterActions(actions, inst)
            if not (filter_on and inst == _G.ThePlayer) then
                return actions
            end
            for i = #actions, 1, -1 do
                local act = actions[i]
                if
                    act and act.target and pickup_filter.prefabs[act.target.prefab] and
                        (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP)
                 then
                    table.remove(actions, i)
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
    function(self)
        local originalGetActionButtonAction = self.GetActionButtonAction
        function self:GetActionButtonAction(forceTarget, ...)
            local act = originalGetActionButtonAction(self, forceTarget, ...)
            if
                filterOn and self.inst == GLOBAL.ThePlayer and act and pickupFilter.prefabs[act.target.prefab] and
                    (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP)
             then
                return nil
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
            if filter_on and picker == _G.ThePlayer and self.inst and self.inst:HasTag(TAG_FILTERED) then
                return false
            end
            return originalCanBePickedUp(self, picker)
        end
    end
)

_G.TheInput:AddKeyDownHandler(
    KEY_TOGGLE,
    function()
        if _G.IsPaused() then
            return
        end

        local ent = _G.TheInput:GetWorldEntityUnderMouse()
        if not (ent and ent.prefab and can_be_filtered(ent)) then
            talk("I can’t filter that.")
            return
        end

        local prefab = ent.prefab
        local now_filtered = not pickup_filter.prefabs[prefab]
        pickup_filter.prefabs[prefab] = now_filtered or nil
        save_filter(pickup_filter.prefabs)

        talk(
            now_filtered and string.format("Okay! I’ll ignore “%s” from now on.", ent.name or prefab) or
                string.format("Got it! I’ll pick up “%s” again.", ent.name or prefab)
        )

        for _, v in pairs(_G.Ents) do
            if v and v.prefab == prefab then
                colourise(v, now_filtered and filter_on)
            end
        end
    end
)

_G.TheInput:AddKeyDownHandler(
    KEY_QUICK_TOGGLE,
    function()
        if _G.IsPaused() then
            return
        end
        filter_on = not filter_on

        talk(filter_on and "Pickup filter enabled." or "Pickup filter temporarily disabled.")

        for _, ent in pairs(_G.Ents) do
            if pickup_filter.prefabs[ent.prefab] then
                colourise(ent, filter_on)
            end
        end
    end
)
