local createdZones = {}
local createdBlips = {}
local createdBossZones = {}
local createdStashZones = {}
local createdSupplyStoreZones = {}
local createdCustomerStoreZones = {}
local currentLocationId = nil
local cachedLocations = {}
local currentRollType = nil
local currentEdibleType = nil
local customerCart = {}
local customerProducts = {}
local currentCustomerLocationId = nil

local function notify(msg, type)
    lib.notify({ title = 'Weed Factory', description = msg, type = type or 'inform' })
end

local function doProgress(label, duration, anim, disable)
    return lib.progressCircle({
        duration = duration,
        label = label,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = disable or { move = true, car = true, combat = true },
        anim = anim or { dict = 'amb@prop_human_bum_bin@base', clip = 'base' }
    })
end

local function requirementLines(req)
    local lines = {}
    for _, item in ipairs(req.items or {}) do
        local status = item.ok and '✅' or '❌'
        lines[#lines + 1] = ('%s %s: %s/%s'):format(status, item.label or item.item, item.have or 0, item.need or 0)
    end
    return table.concat(lines, '\n')
end

local function scaledCraftDuration(baseDuration, amount)
    amount = math.max(1, tonumber(amount) or 1)
    local multi = Config.MultiCraft or {}
    if multi.ScaleProgressTime == false then return baseDuration end
    local perItem = tonumber(multi.ProgressTimePerItem)
    if perItem and perItem > 0 then
        return math.min((multi.MaxProgressTime or 120000), math.max(multi.MinProgressTime or 1000, perItem * amount))
    end
    return math.min((multi.MaxProgressTime or 120000), math.max(multi.MinProgressTime or 1000, (baseDuration or 1000) * amount))
end

local function craftAmountOptions(req)
    local multi = Config.MultiCraft or {}
    local maxCraft = tonumber(req.maxCraft) or 0
    if not multi.Enabled then return { 1 } end

    local amounts = {}
    local seen = {}
    for _, amount in ipairs(multi.Amounts or { 1, 5, 10, 25, 50 }) do
        amount = tonumber(amount) or 0
        if amount > 0 and amount <= maxCraft and not seen[amount] then
            amounts[#amounts + 1] = amount
            seen[amount] = true
        end
    end

    if multi.EnableCraftMax ~= false and maxCraft > 0 and not seen[maxCraft] then
        amounts[#amounts + 1] = maxCraft
    end

    table.sort(amounts)
    if #amounts == 0 and maxCraft >= 1 then amounts[1] = 1 end
    return amounts
end

local function showRequirementPopup(action, args, progressLabel, duration, anim, serverEvent)
    args = args or {}
    args.amount = args.amount or 1

    local req = lib.callback.await('benz_weedshops:server:getRequirements', false, action, args)
    if not req then
        return notify('Unable to load item requirements.', 'error')
    end

    local description = requirementLines(req)
    if description == '' then description = 'No item requirements found.' end

    local options = {
        {
            title = req.title or 'Item Requirements',
            description = description .. ('\n\nMax craftable: %s'):format(req.maxCraft or 0),
            icon = req.hasAll and 'circle-check' or 'circle-xmark',
            disabled = true
        }
    }

    if req.hasAll then
        for _, amount in ipairs(craftAmountOptions(req)) do
            options[#options + 1] = {
                title = ('%s x%s'):format(req.actionLabel or 'Craft', amount),
                description = ('Craft %s at once. Ingredients and rewards are multiplied by %s.'):format(amount, amount),
                icon = amount == (tonumber(req.maxCraft) or 0) and 'layer-group' or 'play',
                onSelect = function()
                    local finalArgs = {}
                    for i, v in ipairs(args.serverArgs or {}) do finalArgs[i] = v end
                    finalArgs[#finalArgs + 1] = amount
                    if doProgress((progressLabel or 'Crafting...') .. (' x%s'):format(amount), scaledCraftDuration(duration, amount), anim) then
                        TriggerServerEvent(serverEvent, table.unpack(finalArgs))
                    end
                end
            }
        end
    else
        options[#options + 1] = {
            title = 'Missing Required Items',
            description = 'Gather the items above before making this.',
            icon = 'triangle-exclamation',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'weed_requirements_popup',
        title = req.title or 'Item Requirements',
        options = options
    })
    lib.showContext('weed_requirements_popup')
end


local function categoryLabel(key)
    key = tostring(key or 'other')
    return (key:gsub('_', ' '):gsub('(%a)([%w_\']*)', function(first, rest) return first:upper() .. rest end))
end

local function strainCategory(strain, data)
    local categories = Config.StrainCategories or {}
    return (data and data.category) or categories[strain] or 'hybrid'
end

local function rollableCategory(rollType, data)
    if data and data.category then return data.category end
    rollType = tostring(rollType or '')
    if rollType:find('blunt') then return 'blunts' end
    if rollType:find('infused') or rollType:find('king') then return 'premium_joints' end
    return 'joints'
end

local function edibleCategory(edibleType, data)
    if data and data.category then return data.category end
    edibleType = tostring(edibleType or '')
    if edibleType:find('gummy') or edibleType:find('lollipop') then return 'candy' end
    if edibleType:find('bar') or edibleType:find('treat') then return 'bars_treats' end
    return 'baked_goods'
end

local function bagCategory(weight, data)
    if data and data.category then return data.category end
    local amount = tonumber(data and data.amount) or 0
    if amount >= 28 then return 'bulk_bags' end
    if amount >= 7 then return 'large_bags' end
    return 'small_bags'
end

local function categoryOrder(kind)
    local cfg = (Config.MenuCategoryOrder or {})[kind]
    if cfg then return cfg end
    if kind == 'strains' then return { 'indica', 'sativa', 'hybrid', 'premium', 'signature', 'other' } end
    if kind == 'rollables' then return { 'joints', 'premium_joints', 'blunts', 'signature', 'other' } end
    if kind == 'edibles' then return { 'baked_goods', 'candy', 'bars_treats', 'drinks', 'other' } end
    if kind == 'bags' then return { 'small_bags', 'large_bags', 'bulk_bags', 'other' } end
    return { 'other' }
end

local function categoryMeta(kind, key)
    local all = Config.MenuCategories or {}
    local meta = all[kind] and all[kind][key] or nil
    return {
        label = (meta and meta.label) or categoryLabel(key),
        icon = (meta and meta.icon) or 'folder',
        description = meta and meta.description or nil
    }
end

local function sortMenuOptions(opts)
    table.sort(opts, function(a, b) return tostring(a.title) < tostring(b.title) end)
    return opts
end

local function orderedCategoryKeys(kind, grouped)
    local keys, seen = {}, {}
    for _, key in ipairs(categoryOrder(kind)) do
        if grouped[key] and #grouped[key] > 0 then
            keys[#keys + 1] = key
            seen[key] = true
        end
    end
    local extras = {}
    for key, values in pairs(grouped) do
        if not seen[key] and #values > 0 then extras[#extras + 1] = key end
    end
    table.sort(extras)
    for _, key in ipairs(extras) do keys[#keys + 1] = key end
    return keys
end

local function openCategoryMenu(id, title, kind, grouped, openCategory)
    local opts = {}
    for _, key in ipairs(orderedCategoryKeys(kind, grouped)) do
        local categoryKey = key
        local meta = categoryMeta(kind, categoryKey)
        local label = meta.label
        opts[#opts + 1] = {
            title = label,
            description = meta.description or ('%s option(s)'):format(#grouped[categoryKey]),
            icon = meta.icon,
            arrow = true,
            onSelect = function() openCategory(categoryKey, label) end
        }
    end
    if #opts == 0 then opts[#opts + 1] = { title = 'No options configured', icon = 'triangle-exclamation', disabled = true } end
    lib.registerContext({ id = id, title = title, options = opts })
    lib.showContext(id)
end

local function strainOptions(eventName, category)
    local opts = {}
    for strain, data in pairs(Config.Strains or {}) do
        if not category or strainCategory(strain, data) == category then
            opts[#opts + 1] = {
                title = data.label or strain,
                description = 'Use this strain',
                event = eventName,
                args = { strain = strain, locationId = currentLocationId }
            }
        end
    end
    return sortMenuOptions(opts)
end

local function openStrainMenu(id, title, eventName, locationId)
    currentLocationId = locationId or currentLocationId
    local grouped = {}
    for strain, data in pairs(Config.Strains or {}) do
        local category = strainCategory(strain, data)
        grouped[category] = grouped[category] or {}
        grouped[category][#grouped[category] + 1] = strain
    end

    openCategoryMenu(id, title, 'strains', grouped, function(category, label)
        local categoryId = id .. '_category_' .. category
        lib.registerContext({
            id = categoryId,
            title = label,
            menu = id,
            options = strainOptions(eventName, category)
        })
        lib.showContext(categoryId)
    end)
end


local function rollTypeOptions(locationId)
    currentLocationId = locationId or currentLocationId
    local grouped = {}
    for rollType, data in pairs(Config.Rollables or {}) do
        local category = rollableCategory(rollType, data)
        grouped[category] = grouped[category] or {}
        grouped[category][#grouped[category] + 1] = { key = rollType, data = data }
    end

    openCategoryMenu('weed_roll_type_menu', 'Roll Joints & Blunts', 'rollables', grouped, function(category, label)
        local opts = {}
        for _, entry in ipairs(grouped[category] or {}) do
            local rollType, data = entry.key, entry.data
            opts[#opts + 1] = {
                title = data.label or rollType,
                description = ('Requires %sx flower + %s'):format(data.flower or 1, data.requiredItem or Config.RequiredItems.rollingPaper),
                icon = 'cannabis',
                arrow = true,
                onSelect = function()
                    currentRollType = rollType
                    openStrainMenu('weed_roll_strain_' .. rollType, 'Roll ' .. (data.label or rollType), 'benz_weedshops:client:roll', currentLocationId)
                end
            }
        end
        lib.registerContext({ id = 'weed_roll_type_menu_' .. category, title = label, menu = 'weed_roll_type_menu', options = sortMenuOptions(opts) })
        lib.showContext('weed_roll_type_menu_' .. category)
    end)
end

local function edibleTypeOptions(locationId)
    currentLocationId = locationId or currentLocationId
    local grouped = {}
    for edibleType, data in pairs(Config.Edibles or {}) do
        local category = edibleCategory(edibleType, data)
        grouped[category] = grouped[category] or {}
        grouped[category][#grouped[category] + 1] = { key = edibleType, data = data }
    end

    openCategoryMenu('weed_edible_type_menu', 'Make Edibles', 'edibles', grouped, function(category, label)
        local opts = {}
        for _, entry in ipairs(grouped[category] or {}) do
            local edibleType, data = entry.key, entry.data
            opts[#opts + 1] = {
                title = data.label or edibleType,
                description = ('Requires %sx flower + %s'):format(data.flower or 1, data.baseItem or Config.RequiredItems.edibleBase),
                icon = 'cookie',
                arrow = true,
                onSelect = function()
                    currentEdibleType = edibleType
                    openStrainMenu('weed_edible_strain_' .. edibleType, 'Make ' .. (data.label or edibleType), 'benz_weedshops:client:edible', currentLocationId)
                end
            }
        end
        lib.registerContext({ id = 'weed_edible_type_menu_' .. category, title = label, menu = 'weed_edible_type_menu', options = sortMenuOptions(opts) })
        lib.showContext('weed_edible_type_menu_' .. category)
    end)
end

RegisterNetEvent('benz_weedshops:client:growMenu', function(data) openStrainMenu('weed_grow_menu', 'Select Strain To Grow', 'benz_weedshops:client:grow', data and data.locationId) end)
RegisterNetEvent('benz_weedshops:client:dryMenu', function(data) openStrainMenu('weed_dry_menu', 'Dry/Cure Flower', 'benz_weedshops:client:dry', data and data.locationId) end)
RegisterNetEvent('benz_weedshops:client:rollMenu', function(data) rollTypeOptions(data and data.locationId) end)
RegisterNetEvent('benz_weedshops:client:edibleMenu', function(data) edibleTypeOptions(data and data.locationId) end)
RegisterNetEvent('benz_weedshops:client:bongMenu', function(data) openStrainMenu('weed_bong_menu', 'Pack Bong', 'benz_weedshops:client:bong', data and data.locationId) end)

for weight in pairs(Config.Weights) do
    RegisterNetEvent('benz_weedshops:client:bag:' .. weight, function(data)
        TriggerEvent('benz_weedshops:client:bag', { strain = data.strain, weight = weight, locationId = data.locationId or currentLocationId })
    end)
end

RegisterNetEvent('benz_weedshops:client:bagMenu', function(data)
    currentLocationId = data and data.locationId or currentLocationId
    local grouped = {}
    for weight, wdata in pairs(Config.Weights or {}) do
        local category = bagCategory(weight, wdata)
        grouped[category] = grouped[category] or {}
        grouped[category][#grouped[category] + 1] = { key = weight, data = wdata }
    end

    openCategoryMenu('weed_bag_menu', 'Package Weed Bags', 'bags', grouped, function(category, label)
        local opts = {}
        for _, entry in ipairs(grouped[category] or {}) do
            local weight, wdata = entry.key, entry.data
            opts[#opts + 1] = {
                title = wdata.label or weight,
                description = ('Requires %s dried flower'):format(wdata.amount or 1),
                icon = 'bag-shopping',
                arrow = true,
                onSelect = function()
                    openStrainMenu('weed_bag_strain_' .. weight, 'Package ' .. (wdata.label or weight), 'benz_weedshops:client:bag:' .. weight, currentLocationId)
                end
            }
        end
        lib.registerContext({ id = 'weed_bag_menu_' .. category, title = label, menu = 'weed_bag_menu', options = sortMenuOptions(opts) })
        lib.showContext('weed_bag_menu_' .. category)
    end)
end)

RegisterNetEvent('benz_weedshops:client:grow', function(data)
    showRequirementPopup('grow', {
        strain = data.strain,
        locationId = data.locationId,
        serverArgs = { data.strain, data.locationId }
    }, 'Growing plant...', Config.Progress.Grow, nil, 'benz_weedshops:server:grow')
end)
RegisterNetEvent('benz_weedshops:client:dry', function(data)
    showRequirementPopup('dry', {
        strain = data.strain,
        locationId = data.locationId,
        serverArgs = { data.strain, data.locationId }
    }, 'Drying flower...', Config.Progress.Dry, nil, 'benz_weedshops:server:dry')
end)
RegisterNetEvent('benz_weedshops:client:roll', function(data)
    local rollType = currentRollType or 'classic_joint'
    showRequirementPopup('roll', {
        strain = data.strain,
        rollType = rollType,
        locationId = data.locationId,
        serverArgs = { data.strain, rollType, data.locationId }
    }, 'Rolling product...', Config.Progress.Roll, { dict = 'amb@world_human_aa_smoke@male@idle_a', clip = 'idle_c' }, 'benz_weedshops:server:roll')
end)
RegisterNetEvent('benz_weedshops:client:edible', function(data)
    local edibleType = currentEdibleType or 'brownie'
    showRequirementPopup('edible', {
        strain = data.strain,
        edibleType = edibleType,
        locationId = data.locationId,
        serverArgs = { data.strain, edibleType, data.locationId }
    }, 'Making edible...', Config.Progress.Edible, nil, 'benz_weedshops:server:edible')
end)
RegisterNetEvent('benz_weedshops:client:bong', function(data)
    showRequirementPopup('bong', {
        strain = data.strain,
        locationId = data.locationId,
        serverArgs = { data.strain, data.locationId }
    }, 'Packing bong...', Config.Progress.BongPack, nil, 'benz_weedshops:server:bong')
end)
RegisterNetEvent('benz_weedshops:client:bag', function(data)
    showRequirementPopup('bag', {
        strain = data.strain,
        weight = data.weight,
        locationId = data.locationId,
        serverArgs = { data.strain, data.weight, data.locationId }
    }, 'Packaging bag...', Config.Progress.Roll, nil, 'benz_weedshops:server:bag')
end)
RegisterNetEvent('benz_weedshops:client:sellMenu', function(data)
    TriggerServerEvent('benz_weedshops:server:sellAll', data and data.locationId)
end)

RegisterNetEvent('benz_weedshops:client:useEffect', function(effectType, itemName)
    local cfg = Config.Effects[effectType]
    if not cfg then return end

    local useCfg = Config.UseProducts or {}
    local disable = {
        move = useCfg.AllowWalking ~= false and false or true,
        car = useCfg.AllowInVehicle == true and false or true,
        combat = useCfg.AllowCombat == true and false or true
    }

    local anim = useCfg.Animations and useCfg.Animations[effectType] or nil
    if not anim then
        anim = { dict = 'amb@world_human_smoking@male@male_a@enter', clip = 'enter', flag = 49 }
    end

    if doProgress(useCfg.Label or 'Using product...', Config.Progress.Smoke, anim, disable) then
        -- ox_inventory client exports do not always consume custom items automatically.
        -- When an item name is supplied, remove exactly one after the use progress succeeds.
        if itemName then
            TriggerServerEvent('benz_weedshops:server:consumeProduct', itemName)
        end
        AnimpostfxPlay(cfg.effect, cfg.duration, false)
        ShakeGameplayCam('DRUNK_SHAKE', 0.35)
        SetTimecycleModifier('spectator5')
        Wait(cfg.duration)
        StopGameplayCamShaking(true)
        ClearTimecycleModifier()
        AnimpostfxStop(cfg.effect)
    end
end)

local validCoords

local zoneEvents = {
    grow = 'benz_weedshops:client:growMenu',
    dry = 'benz_weedshops:client:dryMenu',
    roll = 'benz_weedshops:client:rollMenu',
    edibles = 'benz_weedshops:client:edibleMenu',
    bags = 'benz_weedshops:client:bagMenu',
    bong = 'benz_weedshops:client:bongMenu',
    sell = 'benz_weedshops:client:sellMenu'
}

local function runStationAction(stationType, locationId, stationId)
    local event = zoneEvents[stationType]
    if not event then
        return notify(('Station type %s is not configured.'):format(stationType or 'unknown'), 'error')
    end
    currentLocationId = locationId or currentLocationId
    TriggerEvent(event, { locationId = locationId, stationId = stationId, stationType = stationType })
end


local function removeBlips()
    for _, blip in ipairs(createdBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    createdBlips = {}
end

local function removeBossZones()
    for _, zoneId in ipairs(createdBossZones) do exports.ox_target:removeZone(zoneId) end
    createdBossZones = {}
end

local function removeStashZones()
    for _, zoneId in ipairs(createdStashZones) do exports.ox_target:removeZone(zoneId) end
    createdStashZones = {}
end

local function removeSupplyStoreZones()
    for _, zoneId in ipairs(createdSupplyStoreZones) do exports.ox_target:removeZone(zoneId) end
    createdSupplyStoreZones = {}
end

local function removeCustomerStoreZones()
    for _, zoneId in ipairs(createdCustomerStoreZones) do exports.ox_target:removeZone(zoneId) end
    createdCustomerStoreZones = {}
end

local function openBossMenu(location)
    currentLocationId = location and location.id or currentLocationId
    if not currentLocationId then return notify('No business location found.', 'error') end

    local account = lib.callback.await('benz_weedshops:server:getBusinessAccount', false, currentLocationId)
    if not account then return notify('No permission to use the business account.', 'error') end

    local balanceText = account.unknown and 'Balance unavailable from banking export' or ('$' .. tostring(account.balance or 0))
    local opts = {
        {
            title = 'Business Account',
            description = ('Account: %s\nBalance: %s'):format(account.account or account.job or 'business', balanceText),
            icon = 'building-columns',
            disabled = true
        },
        {
            title = 'Deposit Money',
            description = 'Deposit cash or bank money into the society/business account.',
            icon = 'money-bill-transfer',
            onSelect = function()
                local input = lib.inputDialog('Deposit To Business', {
                    { type = 'number', label = 'Amount', default = 100, min = 1, required = true },
                    { type = 'select', label = 'From Account', default = 'cash', options = {
                        { value = 'cash', label = 'Cash' },
                        { value = 'bank', label = 'Bank' }
                    }, required = true }
                })
                if not input then return end
                TriggerServerEvent('benz_weedshops:server:depositBusinessAccount', currentLocationId, input[1], input[2])
            end
        },
        {
            title = 'Withdraw Money',
            description = 'Withdraw from the society/business account to yourself.',
            icon = 'hand-holding-dollar',
            onSelect = function()
                local input = lib.inputDialog('Withdraw From Business', {
                    { type = 'number', label = 'Amount', default = 100, min = 1, required = true },
                    { type = 'select', label = 'Pay To', default = 'cash', options = {
                        { value = 'cash', label = 'Cash' },
                        { value = 'bank', label = 'Bank' }
                    }, required = true }
                })
                if not input then return end
                TriggerServerEvent('benz_weedshops:server:withdrawBusinessAccount', currentLocationId, input[1], input[2])
            end
        },
        {
            title = 'Refresh Balance',
            icon = 'rotate',
            onSelect = function() openBossMenu(location) end
        }
    }

    lib.registerContext({ id = 'weed_business_account_' .. tostring(currentLocationId), title = (location and location.name or 'Business') .. ' Boss Menu', options = opts })
    lib.showContext('weed_business_account_' .. tostring(currentLocationId))
end

local function addStoreBlip(location)
    if not Config.EnableStoreBlips or not location or not validCoords(location.blip) then return end
    local blip = AddBlipForCoord(location.blip.x, location.blip.y, location.blip.z)
    SetBlipSprite(blip, (Config.Blip and Config.Blip.sprite) or 140)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, (Config.Blip and Config.Blip.scale) or 0.75)
    SetBlipColour(blip, (Config.Blip and Config.Blip.color) or 2)
    SetBlipAsShortRange(blip, Config.Blip == nil or Config.Blip.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(((Config.Blip and Config.Blip.namePrefix) or '') .. (location.name or 'Weed Store'))
    EndTextCommandSetBlipName(blip)
    createdBlips[#createdBlips + 1] = blip
end

local function addBossZone(location)
    if not Config.EnableBossMenuTarget or not location or not location.boss or not validCoords(location.boss.coords) then return end
    local zoneName = ('benz_weedshops_boss_%s'):format(location.id)
    local zoneId = exports.ox_target:addBoxZone({
        coords = location.boss.coords,
        size = location.boss.size or vec3(1.4, 1.4, 1.6),
        rotation = location.boss.rotation or 0.0,
        debug = Config.Debug,
        options = {{
            name = zoneName,
            icon = Config.BossMenuIcon or 'fa-solid fa-user-tie',
            label = location.boss.label or Config.BossMenuLabel or 'Open Boss Menu',
            groups = location.job and location.job ~= '' and location.job ~= 'none' and location.job or nil,
            distance = Config.TargetDistance or 2.0,
            onSelect = function()
                openBossMenu(location)
            end
        }}
    })
    createdBossZones[#createdBossZones + 1] = zoneId
end

local function addStashZone(location, stash)
    if Config.EnableBusinessStashes == false or not stash or not validCoords(stash.coords) then return end
    local zoneName = ('benz_weedshops_stash_%s_%s'):format(location.id, stash.id or math.random(10000,99999))
    local zoneId = exports.ox_target:addBoxZone({
        coords = stash.coords,
        size = stash.size or vec3(1.5, 1.5, 1.6),
        rotation = stash.rotation or 0.0,
        debug = Config.Debug,
        options = {{
            name = zoneName,
            icon = Config.StashTargetIcon or 'fa-solid fa-box-archive',
            label = stash.label or Config.StashTargetLabel or 'Open Business Stash',
            groups = location.job and location.job ~= '' and location.job ~= 'none' and location.job or nil,
            distance = Config.TargetDistance or 2.0,
            onSelect = function()
                TriggerServerEvent('benz_weedshops:server:openStash', location.id, stash.stashName)
            end
        }}
    })
    createdStashZones[#createdStashZones + 1] = zoneId
end


local function moneyText(amount)
    amount = math.floor(tonumber(amount) or 0)
    return ('$%s'):format(amount)
end

local function cartTotal()
    local total, count = 0, 0
    for id, qty in pairs(customerCart or {}) do
        local product = customerProducts[id]
        qty = tonumber(qty) or 0
        if product and qty > 0 then
            total = total + ((tonumber(product.price) or 0) * qty)
            count = count + qty
        end
    end
    return total, count
end

local function showCustomerCart()
    local total, count = cartTotal()
    local opts = {}

    opts[#opts + 1] = {
        title = ('Checkout Total: %s'):format(moneyText(total)),
        description = ('%s item(s) in cart'):format(count),
        icon = 'receipt',
        disabled = count <= 0
    }

    for id, qty in pairs(customerCart or {}) do
        local product = customerProducts[id]
        if product and qty > 0 then
            local lineTotal = (tonumber(product.price) or 0) * qty
            opts[#opts + 1] = {
                title = ('%sx %s'):format(qty, product.label or product.item),
                description = ('%s each | Line Total: %s | Select to remove'):format(moneyText(product.price), moneyText(lineTotal)),
                icon = product.icon or 'basket-shopping',
                onSelect = function()
                    customerCart[id] = nil
                    showCustomerCart()
                end
            }
        end
    end

    if count <= 0 then
        opts[#opts + 1] = { title = 'Cart is empty', description = 'Browse a category to add products.', icon = 'cart-shopping', disabled = true }
    else
        opts[#opts + 1] = {
            title = ('Checkout - %s'):format(moneyText(total)),
            description = 'Choose cash or bank payment.',
            icon = 'credit-card',
            arrow = true,
            onSelect = function()
                local payOpts = {}
                if not Config.CustomerPaymentAccounts or Config.CustomerPaymentAccounts.cash ~= false then
                    payOpts[#payOpts + 1] = { title = 'Pay Cash', description = ('Total: %s'):format(moneyText(total)), icon = 'money-bill', onSelect = function() TriggerServerEvent('benz_weedshops:server:checkoutCustomerCart', currentCustomerLocationId, customerCart, 'cash'); customerCart = {} end }
                end
                if not Config.CustomerPaymentAccounts or Config.CustomerPaymentAccounts.bank ~= false then
                    payOpts[#payOpts + 1] = { title = 'Pay Bank', description = ('Total: %s'):format(moneyText(total)), icon = 'building-columns', onSelect = function() TriggerServerEvent('benz_weedshops:server:checkoutCustomerCart', currentCustomerLocationId, customerCart, 'bank'); customerCart = {} end }
                end
                lib.registerContext({ id = 'weed_customer_pay', title = 'Choose Payment', menu = 'weed_customer_cart', options = payOpts })
                lib.showContext('weed_customer_pay')
            end
        }
        opts[#opts + 1] = { title = 'Clear Cart', description = 'Remove all items from the cart.', icon = 'ban', onSelect = function() customerCart = {}; showCustomerCart() end }
    end

    lib.registerContext({ id = 'weed_customer_cart', title = ('Shopping Cart - %s'):format(moneyText(total)), menu = 'weed_customer_menu', options = opts })
    lib.showContext('weed_customer_cart')
end

local function addCustomerProduct(product, qty)
    local stock = tonumber(product.stock)
    local maxQty = math.min(tonumber(product.max) or 25, stock and math.max(stock, 0) or 25)
    if maxQty <= 0 then return notify('This item is out of stock.', 'error') end
    qty = math.floor(tonumber(qty) or 1)
    qty = math.max(1, math.min(qty, maxQty))
    customerCart[product.id] = (customerCart[product.id] or 0) + qty
    notify(('Added %sx %s to cart.'):format(qty, product.label or product.item), 'success')
end

local function openCustomerQuantityMenu(product, backMenu)
    local stock = tonumber(product.stock)
    local maxQty = math.min(tonumber(product.max) or 25, stock and math.max(stock, 0) or 25)
    if maxQty <= 0 then return notify('This item is out of stock.', 'error') end

    local opts = {
        {
            title = product.label or product.item,
            description = ('Price: %s each | Stock: %s'):format(moneyText(product.price), stock ~= nil and stock or 'Available'),
            icon = product.icon or 'basket-shopping',
            disabled = true
        }
    }

    local quickAmounts = Config.CustomerQuickBuyAmounts or { 1, 2, 5, 10 }
    for _, amount in ipairs(quickAmounts) do
        if amount <= maxQty then
            opts[#opts + 1] = {
                title = ('Add x%s'):format(amount),
                description = ('Cart add total: %s'):format(moneyText((tonumber(product.price) or 0) * amount)),
                icon = 'plus',
                onSelect = function() addCustomerProduct(product, amount) end
            }
        end
    end

    opts[#opts + 1] = {
        title = 'Custom Quantity',
        description = ('Choose 1-%s'):format(maxQty),
        icon = 'keyboard',
        onSelect = function()
            local input = lib.inputDialog(product.label or product.item, {
                { type = 'number', label = 'Quantity', default = 1, min = 1, max = maxQty, required = true }
            })
            if not input then return end
            addCustomerProduct(product, input[1])
        end
    }

    opts[#opts + 1] = {
        title = 'View Cart',
        icon = 'cart-shopping',
        onSelect = showCustomerCart
    }

    lib.registerContext({ id = 'weed_customer_qty_' .. tostring(product.id):gsub('[^%w_]', '_'), title = 'Add To Cart', menu = backMenu or 'weed_customer_menu', options = opts })
    lib.showContext('weed_customer_qty_' .. tostring(product.id):gsub('[^%w_]', '_'))
end

local function customerProductOption(product, backMenu)
    local stockText = product.stock ~= nil and ('Stock: %s | '):format(product.stock) or ''
    return {
        title = product.label or product.item,
        description = ('%s%s each'):format(stockText, moneyText(product.price)),
        icon = product.icon or 'basket-shopping',
        disabled = product.stock ~= nil and tonumber(product.stock) <= 0,
        arrow = true,
        onSelect = function() openCustomerQuantityMenu(product, backMenu) end
    }
end

local function openCustomerProductsByFilter(id, title, parentMenu, filterFn)
    local opts = {}
    for _, product in pairs(customerProducts or {}) do
        if filterFn(product) then
            opts[#opts + 1] = customerProductOption(product, id)
        end
    end
    if #opts == 0 then opts[#opts + 1] = { title = 'No products available', description = 'No stock or no products in this category.', icon = 'circle-info', disabled = true } end
    table.sort(opts, function(a, b) return a.title < b.title end)
    opts[#opts + 1] = { title = 'View Cart', icon = 'cart-shopping', onSelect = showCustomerCart }
    lib.registerContext({ id = id, title = title, menu = parentMenu or 'weed_customer_menu', options = opts })
    lib.showContext(id)
end

local function openCustomerSubcategory(category, subcategory, label, parentMenu)
    local id = ('weed_customer_%s_%s'):format(category, tostring(subcategory):gsub('[^%w_]', '_'))
    openCustomerProductsByFilter(id, label, parentMenu or ('weed_customer_category_' .. category), function(product)
        return product.category == category and product.subcategory == subcategory
    end)
end

local function openCustomerCategory(category, label)
    local subcategories = {}
    local seen = {}
    for _, product in pairs(customerProducts or {}) do
        if product.category == category then
            local key = product.subcategory or 'all'
            if not seen[key] then
                seen[key] = true
                subcategories[#subcategories + 1] = {
                    key = key,
                    label = product.subcategoryLabel or product.typeLabel or label or key,
                    icon = product.subcategoryIcon or product.icon or 'basket-shopping'
                }
            end
        end
    end

    table.sort(subcategories, function(a, b) return (a.label or a.key) < (b.label or b.key) end)

    if #subcategories <= 1 then
        return openCustomerProductsByFilter('weed_customer_category_' .. category, label, 'weed_customer_menu', function(product)
            return product.category == category
        end)
    end

    local opts = {}
    for _, sub in ipairs(subcategories) do
        local available, stockTotal = 0, 0
        for _, product in pairs(customerProducts or {}) do
            if product.category == category and (product.subcategory or 'all') == sub.key then
                available = available + 1
                stockTotal = stockTotal + (tonumber(product.stock) or 0)
            end
        end
        opts[#opts + 1] = {
            title = sub.label,
            description = Config.CustomerStockFromBusinessStashes ~= false and ('%s product(s) | %s in stock'):format(available, stockTotal) or ('%s product(s)'):format(available),
            icon = sub.icon,
            arrow = true,
            onSelect = function() openCustomerSubcategory(category, sub.key, sub.label, 'weed_customer_category_' .. category) end
        }
    end
    opts[#opts + 1] = { title = 'View Cart', icon = 'cart-shopping', onSelect = showCustomerCart }

    lib.registerContext({ id = 'weed_customer_category_' .. category, title = label, menu = 'weed_customer_menu', options = opts })
    lib.showContext('weed_customer_category_' .. category)
end

local function openCustomerMenu(locationId)
    currentCustomerLocationId = locationId
    local data = lib.callback.await('benz_weedshops:server:getCustomerProducts', false, locationId)
    if not data then return notify('Unable to load customer menu.', 'error') end
    customerProducts = {}
    for _, product in ipairs(data.products or {}) do customerProducts[product.id] = product end

    local total, count = cartTotal()
    local opts = {
        {
            title = 'Browse Products',
            description = 'Choose a category below, then add products to your cart.',
            icon = 'store',
            disabled = true
        }
    }

    local ordered = Config.CustomerMenuOrder or { 'bags', 'joints', 'blunts', 'edibles', 'bongs' }
    for _, key in ipairs(ordered) do
        local cat = data.categories and data.categories[key] or {}
        local productCount, stockTotal = 0, 0
        for _, product in pairs(customerProducts or {}) do
            if product.category == key then
                productCount = productCount + 1
                stockTotal = stockTotal + (tonumber(product.stock) or 0)
            end
        end
        if productCount > 0 then
            opts[#opts + 1] = {
                title = cat.label or key,
                description = Config.CustomerStockFromBusinessStashes ~= false and ('%s product(s) | %s in stock'):format(productCount, stockTotal) or ('%s product(s)'):format(productCount),
                icon = cat.icon or 'store',
                arrow = true,
                onSelect = function() openCustomerCategory(key, cat.label or key) end
            }
        end
    end

    opts[#opts + 1] = {
        title = ('View Cart - %s'):format(moneyText(total)),
        description = ('%s item(s)'):format(count),
        icon = 'cart-shopping',
        onSelect = showCustomerCart
    }

    lib.registerContext({ id = 'weed_customer_menu', title = (data.location and data.location.name or 'Dispensary') .. ' Store', options = opts })
    lib.showContext('weed_customer_menu')
end

local function addCustomerStoreZone(location, store)
    if Config.EnableCustomerMenus == false or not store or not validCoords(store.coords) then return end
    local zoneName = ('benz_weedshops_customer_store_%s_%s'):format(location.id, store.id or math.random(10000,99999))
    local zoneId = exports.ox_target:addBoxZone({
        coords = store.coords,
        size = store.size or Config.DefaultCustomerStoreSize or vec3(1.6, 1.6, 1.8),
        rotation = store.rotation or 0.0,
        debug = Config.Debug,
        options = {{
            name = zoneName,
            icon = Config.CustomerStoreTargetIcon or 'fa-solid fa-store',
            label = store.label or Config.CustomerStoreTargetLabel or 'Open Dispensary Menu',
            distance = Config.TargetDistance or 2.0,
            onSelect = function()
                openCustomerMenu(location.id)
            end
        }}
    })
    createdCustomerStoreZones[#createdCustomerStoreZones + 1] = zoneId
end

local function addSupplyStoreZone(location, store)
    if Config.EnableSupplyStores == false or not store or not validCoords(store.coords) then return end
    local zoneName = ('benz_weedshops_supply_store_%s_%s'):format(location.id, store.id or math.random(10000,99999))
    local zoneId = exports.ox_target:addBoxZone({
        coords = store.coords,
        size = store.size or Config.DefaultSupplyStoreSize or vec3(1.6, 1.6, 1.8),
        rotation = store.rotation or 0.0,
        debug = Config.Debug,
        options = {{
            name = zoneName,
            icon = Config.SupplyStoreTargetIcon or 'fa-solid fa-cart-shopping',
            label = store.label or Config.SupplyStoreTargetLabel or 'Open Supply Store',
            groups = location.job and location.job ~= '' and location.job ~= 'none' and location.job or nil,
            distance = Config.TargetDistance or 2.0,
            onSelect = function()
                TriggerServerEvent('benz_weedshops:server:openSupplyStore', location.id, store.shopName)
            end
        }}
    })
    createdSupplyStoreZones[#createdSupplyStoreZones + 1] = zoneId
end

local function removeZones()
    for _, zoneId in ipairs(createdZones) do exports.ox_target:removeZone(zoneId) end
    createdZones = {}
end

function validCoords(coords)
    return coords and not (coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0)
end

local function addStationZone(location, station)
    if not validCoords(station.coords) then return end
    local event = zoneEvents[station.type]
    if not event then return end
    local def = Config.StationTypes[station.type] or {}
    local zoneName = ('benz_weedshops_%s_%s_%s'):format(location.id, station.type, station.id or math.random(10000,99999))
    local zoneId = exports.ox_target:addBoxZone({
        coords = station.coords,
        size = station.size or vec3(2.0, 2.0, 2.0),
        rotation = station.rotation or 0.0,
        debug = Config.Debug,
        options = {{
            name = zoneName,
            icon = def.icon or 'fa-solid fa-cannabis',
            label = station.label or def.label or station.type,
            -- Bong stations are public so customers/players can use bongs without needing the business job.
            groups = station.type ~= 'bong' and location.job and location.job ~= '' and location.job ~= 'none' and location.job or nil,
            distance = Config.TargetDistance or 2.0,
            onSelect = function()
                runStationAction(station.type, location.id, station.id)
            end
        }}
    })
    createdZones[#createdZones + 1] = zoneId
end

local function buildZones(locations)
    removeZones()
    removeBossZones()
    removeStashZones()
    removeSupplyStoreZones()
    removeCustomerStoreZones()
    removeBlips()
    cachedLocations = locations or {}
    for _, location in pairs(cachedLocations) do
        addStoreBlip(location)
        addBossZone(location)
        for _, station in ipairs(location.stations or {}) do addStationZone(location, station) end
        for _, stash in ipairs(location.stashes or {}) do addStashZone(location, stash) end
        for _, store in ipairs(location.supplyStores or {}) do addSupplyStoreZone(location, store) end
        for _, store in ipairs(location.customerStores or {}) do addCustomerStoreZone(location, store) end
    end
end

RegisterNetEvent('benz_weedshops:client:refreshZones', function(locations)
    buildZones(locations)
    notify('Weed locations refreshed.', 'success')
end)

RegisterNetEvent('benz_weedshops:client:openStash', function(stashName)
    if not stashName then return end
    exports.ox_inventory:openInventory('stash', stashName)
end)

RegisterNetEvent('benz_weedshops:client:openSupplyStore', function(shopName)
    if not shopName then return end
    exports.ox_inventory:openInventory('shop', { type = shopName, id = 1 })
end)

CreateThread(function()
    Wait(1500)
    local locations = lib.callback.await('benz_weedshops:server:getLocations', false)
    buildZones(locations or {})
end)

local function promptLocation()
    local input = lib.inputDialog('Create Weed Location', {
        { type = 'input', label = 'Location Name', placeholder = 'White Widow Vinewood', required = true },
        { type = 'input', label = 'Locked Job Name', placeholder = Config.DefaultJob, default = Config.DefaultJob, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:createLocation', { name = input[1], job = input[2] })
end

local function editLocation(loc, canChangeJob)
    local input = lib.inputDialog('Edit ' .. loc.name, {
        { type = 'input', label = 'Location Name', default = loc.name, required = true },
        { type = 'input', label = 'Locked Job Name', default = loc.job, disabled = not canChangeJob, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:updateLocation', loc.id, { name = input[1], job = input[2] })
end


local function setLocationBlipHere(loc)
    TriggerServerEvent('benz_weedshops:server:setLocationBlipHere', loc.id)
end

local function setBossMenuHere(loc)
    local input = lib.inputDialog('Set Boss Menu At Your Position', {
        { type = 'input', label = 'Boss Menu Label', default = (loc.boss and loc.boss.label) or Config.BossMenuLabel or 'Open Boss Menu', required = true },
        { type = 'number', label = 'Size X', default = loc.boss and loc.boss.size and loc.boss.size.x or 1.4, required = true },
        { type = 'number', label = 'Size Y', default = loc.boss and loc.boss.size and loc.boss.size.y or 1.4, required = true },
        { type = 'number', label = 'Size Z', default = loc.boss and loc.boss.size and loc.boss.size.z or 1.6, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:setBossMenuHere', loc.id, input[1], { x = input[2], y = input[3], z = input[4] })
end

local function moveWholeLocationHere(loc)
    local input = lib.inputDialog('Move Whole Location', {
        { type = 'checkbox', label = 'Move all stations relative to my current position', checked = true },
        { type = 'checkbox', label = 'Also move store blip here', checked = true },
        { type = 'checkbox', label = 'Also move boss menu here', checked = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:moveLocationHere', loc.id, input[1] == true, input[2] == true, input[3] == true)
end

local function addStationMenu(loc)
    local values = {}
    for stationType, data in pairs(Config.StationTypes) do values[#values + 1] = { value = stationType, label = data.label } end
    table.sort(values, function(a, b) return a.label < b.label end)
    local input = lib.inputDialog('Add Station At Your Position', {
        { type = 'select', label = 'Station Type', options = values, required = true },
        { type = 'input', label = 'Station Label', placeholder = 'Leave custom label here', required = false },
        { type = 'number', label = 'Size X', default = 2.0, required = true },
        { type = 'number', label = 'Size Y', default = 2.0, required = true },
        { type = 'number', label = 'Size Z', default = 2.0, required = true }
    })
    if not input then return end
    local def = Config.StationTypes[input[1]] or {}
    TriggerServerEvent('benz_weedshops:server:addStationHere', loc.id, input[1], input[2] ~= '' and input[2] or def.label, { x = input[3], y = input[4], z = input[5] })
end

local function editStation(st)
    local input = lib.inputDialog('Move/Edit Station', {
        { type = 'input', label = 'Station Label', default = st.label, required = true },
        { type = 'number', label = 'Size X', default = st.size and st.size.x or 2.0, required = true },
        { type = 'number', label = 'Size Y', default = st.size and st.size.y or 2.0, required = true },
        { type = 'number', label = 'Size Z', default = st.size and st.size.z or 2.0, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:updateStationHere', st.id, input[1], { x = input[2], y = input[3], z = input[4] })
end

local function stationListMenu(loc)
    local opts = {
        { title = 'Add Station Here', icon = 'plus', onSelect = function() addStationMenu(loc) end }
    }
    for _, st in ipairs(loc.stations or {}) do
        local def = Config.StationTypes[st.type] or {}
        opts[#opts + 1] = {
            title = ('#%s - %s'):format(st.id or '?', st.label or def.label or st.type),
            description = ('Type: %s'):format(def.label or st.type),
            icon = def.icon or 'location-dot',
            arrow = true,
            onSelect = function()
                lib.registerContext({ id = 'weed_station_actions_' .. st.id, title = st.label, menu = 'weed_stations_' .. loc.id, options = {
                    { title = 'Move/Edit To My Position', icon = 'arrows-up-down-left-right', onSelect = function() editStation(st) end },
                    { title = 'Delete Station', icon = 'trash', onSelect = function() TriggerServerEvent('benz_weedshops:server:deleteStation', st.id) end }
                }})
                lib.showContext('weed_station_actions_' .. st.id)
            end
        }
    end
    lib.registerContext({ id = 'weed_stations_' .. loc.id, title = loc.name .. ' Stations', menu = 'weed_location_' .. loc.id, options = opts })
    lib.showContext('weed_stations_' .. loc.id)
end

local function addStashMenu(loc)
    local input = lib.inputDialog('Add Business Stash At Your Position', {
        { type = 'input', label = 'Stash Label', default = 'Business Stash', required = true },
        { type = 'number', label = 'Slots', default = Config.DefaultStashSlots or 60, required = true },
        { type = 'number', label = 'Max Weight', default = Config.DefaultStashWeight or 250000, required = true },
        { type = 'number', label = 'Size X', default = 1.5, required = true },
        { type = 'number', label = 'Size Y', default = 1.5, required = true },
        { type = 'number', label = 'Size Z', default = 1.6, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:addStashHere', loc.id, input[1], input[2], input[3], { x = input[4], y = input[5], z = input[6] })
end

local function editStash(stash)
    local input = lib.inputDialog('Move/Edit Business Stash', {
        { type = 'input', label = 'Stash Label', default = stash.label or 'Business Stash', required = true },
        { type = 'number', label = 'Slots', default = stash.slots or Config.DefaultStashSlots or 60, required = true },
        { type = 'number', label = 'Max Weight', default = stash.weight or Config.DefaultStashWeight or 250000, required = true },
        { type = 'number', label = 'Size X', default = stash.size and stash.size.x or 1.5, required = true },
        { type = 'number', label = 'Size Y', default = stash.size and stash.size.y or 1.5, required = true },
        { type = 'number', label = 'Size Z', default = stash.size and stash.size.z or 1.6, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:updateStashHere', stash.id, input[1], input[2], input[3], { x = input[4], y = input[5], z = input[6] })
end

local function stashListMenu(loc)
    local opts = {
        { title = 'Add Stash Here', icon = 'plus', onSelect = function() addStashMenu(loc) end }
    }
    for _, stash in ipairs(loc.stashes or {}) do
        opts[#opts + 1] = {
            title = ('#%s - %s'):format(stash.id or '?', stash.label or 'Business Stash'),
            description = ('Slots: %s | Weight: %s'):format(stash.slots or Config.DefaultStashSlots or 60, stash.weight or Config.DefaultStashWeight or 250000),
            icon = Config.StashTargetIcon or 'box-archive',
            arrow = true,
            onSelect = function()
                lib.registerContext({ id = 'weed_stash_actions_' .. stash.id, title = stash.label or 'Business Stash', menu = 'weed_stashes_' .. loc.id, options = {
                    { title = 'Move/Edit To My Position', icon = 'arrows-up-down-left-right', onSelect = function() editStash(stash) end },
                    { title = 'Delete Stash', icon = 'trash', onSelect = function() TriggerServerEvent('benz_weedshops:server:deleteStash', stash.id) end }
                }})
                lib.showContext('weed_stash_actions_' .. stash.id)
            end
        }
    end
    lib.registerContext({ id = 'weed_stashes_' .. loc.id, title = loc.name .. ' Stashes', menu = 'weed_location_' .. loc.id, options = opts })
    lib.showContext('weed_stashes_' .. loc.id)
end


local function addSupplyStoreMenu(loc)
    local input = lib.inputDialog('Add Supply Store At Your Position', {
        { type = 'input', label = 'Store Label', default = 'Business Supply Store', required = true },
        { type = 'number', label = 'Size X', default = 1.6, required = true },
        { type = 'number', label = 'Size Y', default = 1.6, required = true },
        { type = 'number', label = 'Size Z', default = 1.8, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:addSupplyStoreHere', loc.id, input[1], { x = input[2], y = input[3], z = input[4] })
end

local function editSupplyStore(store)
    local input = lib.inputDialog('Move/Edit Supply Store', {
        { type = 'input', label = 'Store Label', default = store.label or 'Business Supply Store', required = true },
        { type = 'number', label = 'Size X', default = store.size and store.size.x or 1.6, required = true },
        { type = 'number', label = 'Size Y', default = store.size and store.size.y or 1.6, required = true },
        { type = 'number', label = 'Size Z', default = store.size and store.size.z or 1.8, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:updateSupplyStoreHere', store.id, input[1], { x = input[2], y = input[3], z = input[4] })
end

local function supplyStoreListMenu(loc)
    local opts = {
        { title = 'Add Supply Store Here', icon = 'plus', onSelect = function() addSupplyStoreMenu(loc) end }
    }
    for _, store in ipairs(loc.supplyStores or {}) do
        opts[#opts + 1] = {
            title = ('#%s - %s'):format(store.id or '?', store.label or 'Business Supply Store'),
            description = 'Players with this business job can buy supplies here.',
            icon = Config.SupplyStoreTargetIcon or 'cart-shopping',
            arrow = true,
            onSelect = function()
                lib.registerContext({ id = 'weed_supply_store_actions_' .. store.id, title = store.label or 'Business Supply Store', menu = 'weed_supply_stores_' .. loc.id, options = {
                    { title = 'Move/Edit To My Position', icon = 'arrows-up-down-left-right', onSelect = function() editSupplyStore(store) end },
                    { title = 'Delete Supply Store', icon = 'trash', onSelect = function() TriggerServerEvent('benz_weedshops:server:deleteSupplyStore', store.id) end }
                }})
                lib.showContext('weed_supply_store_actions_' .. store.id)
            end
        }
    end
    lib.registerContext({ id = 'weed_supply_stores_' .. loc.id, title = loc.name .. ' Supply Stores', menu = 'weed_location_' .. loc.id, options = opts })
    lib.showContext('weed_supply_stores_' .. loc.id)
end



local function addCustomerStoreMenu(loc)
    local input = lib.inputDialog('Add Customer Menu At Your Position', {
        { type = 'input', label = 'Menu Label', default = 'Dispensary Menu', required = true },
        { type = 'number', label = 'Size X', default = 1.6, required = true },
        { type = 'number', label = 'Size Y', default = 1.6, required = true },
        { type = 'number', label = 'Size Z', default = 1.8, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:addCustomerStoreHere', loc.id, input[1], { x = input[2], y = input[3], z = input[4] })
end

local function editCustomerStore(store)
    local input = lib.inputDialog('Move/Edit Customer Menu', {
        { type = 'input', label = 'Menu Label', default = store.label or 'Dispensary Menu', required = true },
        { type = 'number', label = 'Size X', default = store.size and store.size.x or 1.6, required = true },
        { type = 'number', label = 'Size Y', default = store.size and store.size.y or 1.6, required = true },
        { type = 'number', label = 'Size Z', default = store.size and store.size.z or 1.8, required = true }
    })
    if not input then return end
    TriggerServerEvent('benz_weedshops:server:updateCustomerStoreHere', store.id, input[1], { x = input[2], y = input[3], z = input[4] })
end

local function customerStoreListMenu(loc)
    local opts = {
        { title = 'Add Customer Menu Here', icon = 'plus', onSelect = function() addCustomerStoreMenu(loc) end }
    }
    for _, store in ipairs(loc.customerStores or {}) do
        opts[#opts + 1] = {
            title = ('#%s - %s'):format(store.id or '?', store.label or 'Dispensary Menu'),
            description = 'Public menu where customers browse, cart, and checkout.',
            icon = Config.CustomerStoreTargetIcon or 'store',
            arrow = true,
            onSelect = function()
                lib.registerContext({ id = 'weed_customer_store_actions_' .. store.id, title = store.label or 'Dispensary Menu', menu = 'weed_customer_stores_' .. loc.id, options = {
                    { title = 'Move/Edit To My Position', icon = 'arrows-up-down-left-right', onSelect = function() editCustomerStore(store) end },
                    { title = 'Delete Customer Menu', icon = 'trash', onSelect = function() TriggerServerEvent('benz_weedshops:server:deleteCustomerStore', store.id) end }
                }})
                lib.showContext('weed_customer_store_actions_' .. store.id)
            end
        }
    end
    lib.registerContext({ id = 'weed_customer_stores_' .. loc.id, title = loc.name .. ' Customer Menus', menu = 'weed_location_' .. loc.id, options = opts })
    lib.showContext('weed_customer_stores_' .. loc.id)
end

local function openLocationActions(loc, editor)
    local canChangeJob = editor.admin == true
    local opts = {
        { title = 'Edit Name / Job Lock', icon = 'pen-to-square', onSelect = function() editLocation(loc, canChangeJob) end },
        { title = 'Move Whole Location Here', description = 'Moves stations relative to you, with optional blip/boss move', icon = 'arrows-up-down-left-right', onSelect = function() moveWholeLocationHere(loc) end },
        { title = 'Set Store Blip Here', icon = 'map-location-dot', onSelect = function() setLocationBlipHere(loc) end },
        { title = 'Set Boss Menu Here', icon = 'user-tie', onSelect = function() setBossMenuHere(loc) end },
        { title = 'Stations', description = 'Add, move, resize, or delete stations', icon = 'location-dot', arrow = true, onSelect = function() stationListMenu(loc) end },
        { title = 'Business Stashes', description = 'Add, move, resize, or delete ox_inventory stashes', icon = 'box-archive', arrow = true, onSelect = function() stashListMenu(loc) end },
        { title = 'Supply Stores', description = 'Add, move, or delete ox_inventory supply shops', icon = 'cart-shopping', arrow = true, onSelect = function() supplyStoreListMenu(loc) end },
        { title = 'Customer Menus', description = 'Add, move, or delete public dispensary menus', icon = 'store', arrow = true, onSelect = function() customerStoreListMenu(loc) end }
    }
    if editor.admin then
        opts[#opts + 1] = { title = 'Delete Location', icon = 'trash', onSelect = function() TriggerServerEvent('benz_weedshops:server:deleteLocation', loc.id) end }
    end
    lib.registerContext({ id = 'weed_location_' .. loc.id, title = loc.name, menu = 'weed_admin_menu', options = opts })
    lib.showContext('weed_location_' .. loc.id)
end

local function openAdminMenu()
    local editor = lib.callback.await('benz_weedshops:server:getEditorData', false)
    if not editor then return notify('No permission.', 'error') end
    local opts = {}
    if editor.admin then opts[#opts + 1] = { title = 'Create New Location', icon = 'plus', onSelect = promptLocation } end
    for _, loc in pairs(editor.locations or {}) do
        if editor.admin or loc.job == editor.playerJob then
            opts[#opts + 1] = {
                title = ('#%s %s'):format(loc.id, loc.name),
                description = ('Job: %s | Stations: %s | Stashes: %s | Supply Stores: %s | Customer Menus: %s'):format(loc.job or 'none', #(loc.stations or {}), #(loc.stashes or {}), #(loc.supplyStores or {}), #(loc.customerStores or {})),
                icon = 'store', arrow = true, onSelect = function() openLocationActions(loc, editor) end
            }
        end
    end
    lib.registerContext({ id = 'weed_admin_menu', title = 'Weed Location Editor', options = opts })
    lib.showContext('weed_admin_menu')
end

RegisterCommand(Config.AdminCommand or 'weedadmin', openAdminMenu, false)

RegisterCommand(Config.CoordCommand or 'wwcoords', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local line = ("coords = vec3(%.2f, %.2f, %.2f), rotation = %.2f"):format(coords.x, coords.y, coords.z, heading)
    print('[benz_weedshops] ' .. line)
    lib.setClipboard(line)
    notify('Coords copied and printed in F8.', 'success')
end, false)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    local locations = lib.callback.await('benz_weedshops:server:getLocations', false)
    buildZones(locations or {})
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    local locations = lib.callback.await('benz_weedshops:server:getLocations', false)
    buildZones(locations or {})
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    Wait(1000)
    local locations = lib.callback.await('benz_weedshops:server:getLocations', false)
    buildZones(locations or {})
end)
