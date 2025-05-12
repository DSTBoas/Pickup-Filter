local _G = GLOBAL
local ACTIONS = _G.ACTIONS
local FRAMES = _G.FRAMES
local TheNet = _G.TheNet

local function getKeyFromConfig(name)
    local k = GetModConfigData(name)
    return (type(k) == "string") and _G[k] or k
end

local FILTER_ITEM_KEY = getKeyFromConfig("FILTER_ITEM_KEY")
local TOGGLE_PICKUP_FILTER_KEY = getKeyFromConfig("TOGGLE_PICKUP_FILTER_KEY")
local ALLOW_MOUSE_PICKUP_BOOL = getKeyFromConfig("ALLOW_MOUSE_PICKUP_THROUGH_FILTER_BOOL")
local REMOVE_INTERACTIONS_BOOL = getKeyFromConfig("REMOVE_INTERACTIONS_FROM_FILTERED_BOOL")
local PERSISTENCE_MODE = GetModConfigData("PERSISTENCE_MODE") or "game"

local function IsFiltered(ent)
    return ent and ent._pf_filtered
end

local function GetSaveFile()
    if PERSISTENCE_MODE == "disabled" then
        return nil
    elseif PERSISTENCE_MODE == "world" then
        local id = TheNet and TheNet.GetSessionIdentifier and TheNet:GetSessionIdentifier() or "unknown"
        return string.format("pickup_filter_data_%s.txt", id)
    else
        return "pickup_filter_data.txt"
    end
end

local function saveFilter(tbl)
    local file = GetSaveFile()
    if not file then
        return
    end

    local out, n = {}, 0
    for prefab in pairs(tbl) do
        n = n + 1
        out[n] = prefab
    end
    _G.TheSim:SetPersistentString(file, table.concat(out, "\n"), false)
end

local function loadFilter(cb)
    local file = GetSaveFile()
    if not file then
        cb({})
        return
    end

    _G.TheSim:GetPersistentString(
        file,
        function(ok, data)
            local filter = {}
            if ok and data then
                for prefab in data:gmatch("[^\r\n]+") do
                    filter[prefab] = true
                end
            end
            cb(filter)
        end
    )
end

local filterEnabled = true
local pickupFilter = {prefabs = {}}

loadFilter(
    function(filter)
        pickupFilter.prefabs = filter
    end
)

local function tintEntity(ent, on)
    if not (ent and ent.AnimState) then
        return
    end

    ent._pf_filtered = on or nil

    if filterEnabled and on then
        ent.AnimState:SetMultColour(1, 0, 0, 1)
    else
        ent.AnimState:SetMultColour(1, 1, 1, 1)
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
    return (ent and ent.replica and ent.replica.inventoryitem and ent.replica.inventoryitem:CanBePickedUp()) or
        (ent and ent:HasTag("pickable"))
end

local function PatchCanMouseThrough(inst)
    if inst._pf_can_mouse_wrapped then
        return
    end

    inst._pf_can_mouse_wrapped = true
    inst._pf_original_can_mouse = inst.CanMouseThrough

    inst.CanMouseThrough = function(self, ...)
        if filterEnabled and IsFiltered(self) then
            return true, true
        end
        if self._pf_original_can_mouse then
            return self._pf_original_can_mouse(self, ...)
        end
    end
end

AddPrefabPostInitAny(
    function(inst)
        if not inst then
            return
        end

        if REMOVE_INTERACTIONS_BOOL then
            PatchCanMouseThrough(inst)
        end

        if inst.prefab and pickupFilter.prefabs[inst.prefab] then
            tintEntity(inst, true)
        end
    end
)

AddClassPostConstruct(
    "components/playeractionpicker",
    function(self)
        local function filterActions(actions, inst)
            if not (filterEnabled and inst == _G.ThePlayer) then
                return actions
            end

            for i = #actions, 1, -1 do
                local act = actions[i]
                if act and act.target and pickupFilter.prefabs[act.target.prefab] then
                    local isFilteredAction =
                        not ALLOW_MOUSE_PICKUP_BOOL and (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP)
                    local isExamineOrWalkTo =
                        REMOVE_INTERACTIONS_BOOL and (act.action == ACTIONS.LOOKAT or act.action == ACTIONS.WALKTO)

                    if isFilteredAction or isExamineOrWalkTo then
                        table.remove(actions, i)
                    end
                end
            end
            return actions
        end

        local old_left = self.GetLeftClickActions
        self.GetLeftClickActions = function(...)
            return filterActions(old_left(...), self.inst)
        end

        local old_right = self.GetRightClickActions
        self.GetRightClickActions = function(...)
            return filterActions(old_right(...), self.inst)
        end
    end
)

AddClassPostConstruct(
    "components/playercontroller",
    function(pc)
        local old = pc.GetActionButtonAction
        function pc:GetActionButtonAction(force_target, ...)
            local act = old(self, force_target, ...)
            if
                act and (act.action == ACTIONS.PICK or act.action == ACTIONS.PICKUP) and filterEnabled and
                    pickupFilter.prefabs[act.target.prefab] and
                    self.inst == _G.ThePlayer
             then
                return nil
            end
            return act
        end
    end
)

AddClassPostConstruct(
    "components/inventoryitem_replica",
    function(replica)
        local old = replica.CanBePickedUp
        function replica:CanBePickedUp(picker)
            if filterEnabled and picker == _G.ThePlayer and IsFiltered(self.inst) then
                return false
            end
            return old(self, picker)
        end
    end
)

_G.TheInput:AddKeyDownHandler(
    FILTER_ITEM_KEY,
    function()
        if _G.IsPaused() then
            return
        end

        local touched = {}
        if REMOVE_INTERACTIONS_BOOL then
            for _, inst in pairs(_G.Ents) do
                if IsFiltered(inst) then
                    touched[inst] = inst.CanMouseThrough
                    inst.CanMouseThrough = nil
                end
            end
        end

        _G.ThePlayer:DoTaskInTime(
            FRAMES,
            function()
                local ent = _G.TheInput:GetWorldEntityUnderMouse()

                for inst, wrapped in pairs(touched) do
                    inst.CanMouseThrough = function(self, ...)
                        if filterEnabled and IsFiltered(self) then
                            return true, true
                        end
                        return wrapped and wrapped(self, ...)
                    end
                end
                touched = nil

                if not (ent and ent.prefab and canBeFiltered(ent)) then
                    talk("I can't filter that.")
                    return
                end

                local prefab = ent.prefab
                local now_filtered = not pickupFilter.prefabs[prefab]
                pickupFilter.prefabs[prefab] = now_filtered or nil
                saveFilter(pickupFilter.prefabs)

                talk(
                    now_filtered and string.format("Okay! I'll ignore “%s” from now on.", ent.name or prefab) or
                        string.format("Got it! I'll pick up “%s” again.", ent.name or prefab)
                )

                for _, inst in pairs(_G.Ents) do
                    if inst and inst.prefab == prefab then
                        tintEntity(inst, now_filtered and filterEnabled)
                    end
                end
            end
        )
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

        for _, inst in pairs(_G.Ents) do
            if inst and pickupFilter.prefabs[inst.prefab] then
                tintEntity(inst, filterEnabled)
            end
        end
    end
)
