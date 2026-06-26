-- Early ox_inventory usable item exports.
-- This file loads before client/main.lua so ox_inventory can always find exports like:
--   qbx_weedfactory.joint_devil_kiss
--   qbx_weedfactory.edible_brownie_white_widow
-- Keep your ox_inventory item client.export resource name the same as this resource folder name.

local function notify(title, description, ntype)
    if lib and lib.notify then
        lib.notify({ title = title or 'Weed Shop', description = description or '', type = ntype or 'inform' })
    else
        TriggerEvent('ox_lib:notify', { title = title or 'Weed Shop', description = description or '', type = ntype or 'inform' })
    end
end

local function registerUseableExport(itemName, effectType)
    if type(itemName) ~= 'string' or itemName == '' then return end

    exports(itemName, function(data)
        -- This function is called directly by ox_inventory when the item is used.
        -- Do NOT call exports.ox_inventory:useItem() here, because that can loop back into the same export.
        TriggerEvent('benz_weedshops:client:useEffect', effectType or 'joint', itemName)
    end)
end

local registered = {}
local function safeRegister(itemName, effectType)
    if registered[itemName] then return end
    registered[itemName] = true
    registerUseableExport(itemName, effectType)
end

CreateThread(function()
    -- Wait one tick so shared config is fully available on slower starts.
    Wait(0)

    for strain, _ in pairs(Config.Strains or {}) do
        for _, r in pairs(Config.Rollables or {}) do
            safeRegister((r.itemPrefix or '') .. strain, r.effect or 'joint')
        end

        for _, e in pairs(Config.Edibles or {}) do
            safeRegister((e.itemPrefix or '') .. strain, e.effect or 'edible')
        end
    end

    -- Explicit fallback exports for all current install/items.lua products.
    -- These protect against config edits or old item definitions still being in ox_inventory.
    local fallbackJoints = {
        'joint_devil_kiss', 'king_joint_devil_kiss', 'infused_joint_devil_kiss',
        'joint_white_widow', 'king_joint_white_widow', 'infused_joint_white_widow',
        'joint_purple_punch', 'king_joint_purple_punch', 'infused_joint_purple_punch',
        'joint_og_kush', 'king_joint_og_kush', 'infused_joint_og_kush',
        'joint_gelato', 'king_joint_gelato', 'infused_joint_gelato',
        'joint_blue_dream', 'king_joint_blue_dream', 'infused_joint_blue_dream',
        'joint_mimosa', 'king_joint_mimosa', 'infused_joint_mimosa',
    }
    for _, itemName in ipairs(fallbackJoints) do safeRegister(itemName, 'joint') end

    local fallbackBlunts = {
        'blunt_devil_kiss', 'honey_blunt_devil_kiss', 'grape_blunt_devil_kiss', 'ww_blunt_devil_kiss',
        'blunt_white_widow', 'honey_blunt_white_widow', 'grape_blunt_white_widow', 'ww_blunt_white_widow',
        'blunt_purple_punch', 'honey_blunt_purple_punch', 'grape_blunt_purple_punch', 'ww_blunt_purple_punch',
        'blunt_og_kush', 'honey_blunt_og_kush', 'grape_blunt_og_kush', 'ww_blunt_og_kush',
        'blunt_gelato', 'honey_blunt_gelato', 'grape_blunt_gelato', 'ww_blunt_gelato',
        'blunt_blue_dream', 'honey_blunt_blue_dream', 'grape_blunt_blue_dream', 'ww_blunt_blue_dream',
        'blunt_mimosa', 'honey_blunt_mimosa', 'grape_blunt_mimosa', 'ww_blunt_mimosa',
    }
    for _, itemName in ipairs(fallbackBlunts) do safeRegister(itemName, 'blunt') end

    local strains = { 'devil_kiss', 'white_widow', 'purple_punch', 'og_kush', 'gelato', 'blue_dream', 'mimosa' }
    local ediblePrefixes = {
        'edible_brownie_', 'edible_cookie_', 'edible_gummies_', 'edible_rice_treat_',
        'edible_cupcake_', 'edible_chocolate_', 'edible_cereal_bar_', 'edible_lollipop_'
    }
    for _, strain in ipairs(strains) do
        for _, prefix in ipairs(ediblePrefixes) do
            safeRegister(prefix .. strain, 'edible')
        end
    end
end)

local function drinkWater(itemName)
    local duration = (Config.Progress and Config.Progress.Drink) or 3500
    local ok = true

    if lib and lib.progressCircle then
        ok = lib.progressCircle({
            duration = duration,
            label = 'Drinking water...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = false, car = true, combat = true },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 }
        })
    elseif lib and lib.progressBar then
        ok = lib.progressBar({
            duration = duration,
            label = 'Drinking water...',
            useWhileDead = false,
            canCancel = true,
            disable = { move = false, car = true, combat = true },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 }
        })
    else
        Wait(duration)
    end

    if ok then
        TriggerServerEvent('benz_weedshops:server:consumeDrink', itemName)
        notify('Water', 'You drank some water.', 'success')
    end
end

exports('water', function(data)
    drinkWater('water')
end)

exports('drinking_water', function(data)
    drinkWater('drinking_water')
end)
