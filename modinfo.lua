name = "Pickup Filter"
description = "Filter items you pickup by pressing a key!"

icon_atlas = "modicon.xml"
icon = "modicon.tex"

author = "Boas"
version = "1.0.5"
forumthread = ""

dont_starve_compatible = false
reign_of_giants_compatible = false
dst_compatible = true

all_clients_require_mod = false
client_only_mod = true

api_version = 10

local function AddConfigOption(desc, data, hover)
    return {description = desc, data = data, hover = hover}
end

local function AddConfig(label, name, options, default, hover)
    return {
        label = label,
        name = name,
        options = options,
        default = default,
        hover = hover
    }
end

local function AddSectionTitle(title)
    return AddConfig(title, "", {{description = "", data = 0}}, 0)
end

local function GetKeyboardOptions()
    local keys = {}

    local function AddConfigKey(t, key)
        t[#t + 1] = AddConfigOption(key, "KEY_" .. key)
    end

    local function AddDisabledConfigOption(t)
        t[#t + 1] = AddConfigOption("Disabled", false)
    end

    AddDisabledConfigOption(keys)

    local alphabet = {
        "A","B","C","D","E","F","G","H","I","J","K","L","M",
        "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"
    }

    for i = 1, 26 do
        AddConfigKey(keys, alphabet[i])
    end

    for i = 1, 12 do
        AddConfigKey(keys, "F" .. i)
    end

    AddDisabledConfigOption(keys)

    return keys
end

local function GetToggleOptions()
    return {
        AddConfigOption("Disabled", false),
        AddConfigOption("Enabled", true)
    }
end

local KeyboardOptions = GetKeyboardOptions()
local ToggleOptions = GetToggleOptions()
local AssignKeyMessage = "Assign a key"

configuration_options =
{
    AddSectionTitle("Pickup Filter Keybinds"),
    AddConfig(
        "Filter Item",
        "FILTER_ITEM_KEY",
        KeyboardOptions,
        "KEY_F1",
        AssignKeyMessage
    ),
    AddConfig(
        "Toggle Pickup Filter",
        "TOGGLE_PICKUP_FILTER_KEY",
        KeyboardOptions,
        "KEY_F2",
        AssignKeyMessage
    ),
    AddSectionTitle("Advanced Settings"),
    AddConfig(
        "Allow Mouse Pickup",
        "ALLOW_MOUSE_PICKUP_THROUGH_FILTER_BOOL",
        ToggleOptions,
        false,
        "Allows mouse clicks to bypass the pickup filter"
    ),
    AddConfig(
        "Remove Interactions",
        "REMOVE_INTERACTIONS_FROM_FILTERED_BOOL",
        ToggleOptions,
        false,
        "Prevents all interactions, including examine, with items that are currently filtered."
    ),
    AddConfig(
        "Red Tint",
        "RED_TINT_ENABLED_BOOL",
        ToggleOptions,
        true,
        "Enable red highlight for filtered items.\nItems are still filtered even if highlighting is disabled."
    ),
    AddSectionTitle("Save Settings"),
    AddConfig(
        "Remember Filtered Targets",
        "PERSISTENCE_MODE",
        {
            AddConfigOption("Don't save", "disabled", "Never remember your filtered targets."),
            AddConfigOption("Save for all games", "game", "Remember filtered targets in every world."),
            AddConfigOption("Save per world", "world", "Each world remembers its own filtered targets."),
        },
        "game",
        "Choose how your filter is remembered"
    ),
}