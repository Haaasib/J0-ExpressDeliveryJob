local blips = {}
local peds = {}

notify = function(a, b)
SendNUIMessage({
    action = "updateStatusBar",
    text = b
})
end
hideStatusBar = function()
    SendNUIMessage({
        action = "hideStatusBar"
    })
end


Citizen.CreateThread(function()

    for i, location in ipairs(J0.locations) do
        local blip = jo.blip.create(vec3(location.coords.x, location.coords.y, location.coords.z), location.name, "blip_ambient_wagon")
        table.insert(blips, blip)
        local ped = jo.entity.create('mp_chu_rob_fortmercer_males_01', vec3(location.coords.x, location.coords.y, location.coords.z), 90.0, true)
        table.insert(peds, ped)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
    end
    local group = "interaction"
    local key = "INPUT_LOOT"
    local duration = 1000
    local isNearLocation = false
    local currentLocation = nil
    local promptCreated = false
    local promptLabel = "Interact With Frontier Express"
    while true do
        Citizen.Wait(100)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearLocation = false
        local closestLocation = nil
        local closestDistance = 100.0
        
        for i, location in ipairs(J0.locations) do
            local distance = #(playerCoords - vector3(location.coords.x, location.coords.y, location.coords.z))
            
            if distance < 3.0 then
                if distance < closestDistance then
                    closestDistance = distance
                    closestLocation = location
                    nearLocation = true
                end
            end
        end
        
        if nearLocation and not isNearLocation then
            isNearLocation = true
            currentLocation = closestLocation
            jo.prompt.create(group, promptLabel, key, duration)
            promptCreated = true
        elseif not nearLocation and isNearLocation then
            isNearLocation = false
            currentLocation = nil
            if promptCreated then
                jo.prompt.deleteGroup(group)
                promptCreated = false
            end
        end
        
        if isNearLocation and promptCreated then
            if jo.prompt.isCompleted(group, key) then
                jo.callback.triggerServer('J0-FrontierExpress:getPlayerData', function(playerData)
                    
                    local cacheKey = currentLocation.name .. "_" .. playerData.level
                    local cachedContracts = J0.getCachedContracts(cacheKey)
                    
                    if cachedContracts then
                        contracts = cachedContracts
                    else
                        contracts = J0.generateNewContracts(playerData.level, J0.maxContractsPerGeneration, currentLocation)
                        J0.cacheContracts(cacheKey, contracts)
                    end
                    
                    contracts = filterCompletedContracts(contracts)
                    
                    SendNUIMessage({
                        action = "openDeliveryUi",
                        data = playerData,
                        contracts = contracts
                    })
                    SetNuiFocus(true, true)
                end)
                jo.prompt.waitRelease(key)
            end
            jo.prompt.displayGroup(group, "Main Menu")
        end
    end
end)

function getLocationIndex(location)
    for i, loc in ipairs(J0.locations) do
        if loc.coords.x == location.coords.x and loc.coords.y == location.coords.y and loc.coords.z == location.coords.z then
            return i
        end
    end
    return 1
end

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeDeliveryUi"
    })
    cb('ok')
end)

local currentMission = nil
local missionThread = nil
local currentCart = nil
local currentBoxes = {}
local boxDepoBoxes = {}
local isNearBoxDepo = false
local boxDepoPrompt = false
local currentHeldBox = nil
local isNearCart = false
local cartPrompt = false
local currentCartData = nil
local deliveryBlip = nil
local isNearDelivery = false
local deliveryPrompt = false
local deliveryLocation = nil
local boxesDelivered = 0
local allBoxesLoaded = false
local completedContracts = {}
local isSpawningCart = false
local respawnCartThread = nil 


local pendingNuiCallbacks = {}

function filterCompletedContracts(contracts)
    local filteredContracts = {}
    for _, contract in ipairs(contracts) do
        local cartType = contract.selectedCart or "default"
        local contractKey = contract.from .. "_" .. contract.to .. "_" .. cartType
        if not completedContracts[contractKey] then table.insert(filteredContracts, contract) end
    end
    return filteredContracts
end

function markContractAsCompleted(contract)
    local cartType = contract.selectedCart or "default"
    completedContracts[contract.from .. "_" .. contract.to .. "_" .. cartType] = true
end

RegisterNUICallback('startMission', function(data, cb)
    pendingNuiCallbacks.startMission = cb
    TriggerServerEvent('J0-FrontierExpress:startMission', data)
end)

RegisterNUICallback('completeMission', function(data, cb)
    TriggerServerEvent('J0-FrontierExpress:completeMission', data, true)
    cb('ok')
end)

RegisterNUICallback('failMission', function(data, cb)
    TriggerServerEvent('J0-FrontierExpress:completeMission', data, false)
    cb('ok')
end)

RegisterNetEvent('J0-FrontierExpress:completeMissionClient')
AddEventHandler('J0-FrontierExpress:completeMissionClient', function(missionData, success)
    jo.ui.stopTimer() 
    
    if missionThread then
        missionThread = nil
    end
    
    cleanupMissionObjects()
    
    currentMission = nil
    
    SetNuiFocus(false, false)
    
    if success then
        jo.notif.simpleTop('Frontier Express', "Mission completed successfully!", 5000)
    else
        jo.notif.simpleTop('Frontier Express', "Mission failed!", 5000)
    end
end)

RegisterNetEvent('J0-FrontierExpress:startMissionClient')
AddEventHandler('J0-FrontierExpress:startMissionClient', function(missionData, groupId)
    jo.notif.simpleTop('Frontier Express', "You Started " .. missionData.contractName .. " !", 5000)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeDeliveryUi"
    })
    jo.ui.initTimer()
    jo.ui.startTimer(missionData.timeLimit*60)
    
    currentMission = missionData
    currentMission.groupId = groupId 
    allBoxesLoaded = false
end)

RegisterNetEvent('J0-FrontierExpress:missionStartResponse')
AddEventHandler('J0-FrontierExpress:missionStartResponse', function(response)
    if pendingNuiCallbacks.startMission then
        pendingNuiCallbacks.startMission(response)
        pendingNuiCallbacks.startMission = nil
    end
end)

RegisterNUICallback('getPlayerData', function(data, cb)
    jo.callback.triggerServer('J0-FrontierExpress:getPlayerData', function(playerData)
        cb(playerData)
    end)
end)

RegisterNUICallback('getPlayerInfo', function(data, cb)
    jo.callback.triggerServer('J0-FrontierExpress:getPlayerInfoById', data.playerId, function(result)
        cb(result)
    end)
end)

RegisterCommand('fixDeliveryWagon', function()
    fixDeliveryWagon()
end, false)

function cleanupOldCarts()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local vehicles = GetGamePool('CVehicle')
    local cleanedCount = 0
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distance = #(playerCoords - vehicleCoords)
            local vehicleModel = GetEntityModel(vehicle)
            if (vehicleModel == -1347283941 or vehicleModel == 219205323) and distance < 100.0 then
                SetEntityAsMissionEntity(vehicle, false, true)
                DeleteVehicle(vehicle)
                cleanedCount = cleanedCount + 1
            end
        end
    end
end


function spawnVehicleSafely(cartModel, spawnCoords, spawnHeading)
    if isSpawningCart then
        return nil
    end
    
    isSpawningCart = true
    
    if currentCart and DoesEntityExist(currentCart) then
        SetEntityAsMissionEntity(currentCart, false, true)
        DeleteVehicle(currentCart)
        currentCart = nil
    end
    
    local playerCoords = GetEntityCoords(PlayerPedId())
    local vehicles = GetGamePool('CVehicle')
    local cleanedCount = 0
    
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distance = #(playerCoords - vehicleCoords)
            local vehicleModel = GetEntityModel(vehicle)
            
            if (vehicleModel == cartModel or vehicleModel == -1347283941 or vehicleModel == 219205323) and distance < 50.0 then
                SetEntityAsMissionEntity(vehicle, false, true)
                DeleteVehicle(vehicle)
                cleanedCount = cleanedCount + 1
            end
        end
    end
    
    if cleanedCount > 0 then
        Citizen.Wait(800)
    else
        Citizen.Wait(300)
    end
    
    local checkVehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(checkVehicles) do
        if DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distance = #(vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z) - vehicleCoords)
            local vehicleModel = GetEntityModel(vehicle)
            if (vehicleModel == cartModel or vehicleModel == -1347283941 or vehicleModel == 219205323) and distance < 5.0 then
                SetEntityAsMissionEntity(vehicle, false, true)
                DeleteVehicle(vehicle)
                Citizen.Wait(200)
            end
        end
    end
    
    RequestModel(cartModel)
    local timeout = 0
    while not HasModelLoaded(cartModel) and timeout < 50 do
        Citizen.Wait(100)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(cartModel) then
        isSpawningCart = false
        notify('Frontier Express', "Failed to load cart model!")
        return nil
    end
    
    local newCart = CreateVehicle(cartModel, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnHeading, true, true)
    
    if DoesEntityExist(newCart) then
        SetEntityAsMissionEntity(newCart, true, true)
        SetVehicleOnGroundProperly(newCart)
        SetModelAsNoLongerNeeded(cartModel)
        isSpawningCart = false
        return newCart
    else
        SetModelAsNoLongerNeeded(cartModel)
        isSpawningCart = false
        return nil
    end
end

RegisterNetEvent('J0-FrontierExpress:respawnCart')
AddEventHandler('J0-FrontierExpress:respawnCart', function()
    if isSpawningCart then
        return
    end
    
    if not currentMission or not currentCartData then
        notify('Frontier Express', "No active mission to respawn cart!")
        return
    end
    
    local missionLocation = nil
    for i, location in ipairs(J0.locations) do
        if location.name == currentMission.from then
            missionLocation = location
            break
        end
    end
    
    if not missionLocation then
        return
    end
    
    local spawn = missionLocation.spawn
    local cartModel = currentCartData.cart_model
    local newCart = spawnVehicleSafely(cartModel, spawn.coords, spawn.heading)
    
    if newCart then
        currentCart = newCart
    end
end)


RegisterNetEvent('J0-FrontierExpress:missionCompleted')
AddEventHandler('J0-FrontierExpress:missionCompleted', function(playerData, missionData, success)
    jo.ui.stopTimer() 
end)

RegisterNetEvent('J0-FrontierExpress:spawnMissionObjects')
AddEventHandler('J0-FrontierExpress:spawnMissionObjects', function(missionData, groupId, serverSpawnedObjects)
    if serverSpawnedObjects then
        if DoesEntityExist(serverSpawnedObjects.cartId) then
            currentCart = serverSpawnedObjects.cartId
            SetEntityAsMissionEntity(currentCart, true, true)
            SetVehicleOnGroundProperly(currentCart)
        else
            if not isSpawningCart and serverSpawnedObjects.cartData then
                local missionLocation = nil
                for i, location in ipairs(J0.locations) do
                    if location.name == missionData.from then
                        missionLocation = location
                        break
                    end
                end
                if missionLocation then
                    local spawn = missionLocation.spawn
                    local cartModel = serverSpawnedObjects.cartData.cart_model
                    local newCart = spawnVehicleSafely(cartModel, spawn.coords, spawn.heading)
                    if newCart then
                        currentCart = newCart
                    end
                end
            end
        end
        
        currentCartData = serverSpawnedObjects.cartData
        
        if serverSpawnedObjects.boxPositions and serverSpawnedObjects.boxModel then
            spawnBoxesFromServerData(serverSpawnedObjects.boxPositions, serverSpawnedObjects.boxModel)
        end
    end
    
    if missionThread then
        missionThread = nil
    end
    
    missionThread = Citizen.CreateThread(function()
        local timeLimit = missionData.timeLimit * 60 * 1000 
        local startTime = GetGameTimer()
        
        while currentMission and (GetGameTimer() - startTime) < timeLimit do
            Citizen.Wait(1000) 
        end
        
        if currentMission then
            jo.notif.simpleTop('Frontier Express', "Mission " .. currentMission.contractName .. " timed out and failed!", 5000)
            
            cleanupMissionObjects()
            
            TriggerServerEvent('J0-FrontierExpress:completeMission', currentMission, false)
            
            currentMission = nil
            missionThread = nil
        end
    end)
end)



AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for i, ped in ipairs(peds) do
            DeletePed(ped)
        end
        peds = {}
        
        cleanupMissionObjects()
    end
end)


function spawnBoxesFromServerData(boxPositions, boxModel)
    for i, box in ipairs(boxDepoBoxes) do if DoesEntityExist(box) then DeleteObject(box) end end
    boxDepoBoxes = {}
    local boxModelHash = GetHashKey(boxModel)
    RequestModel(boxModelHash)
    while not HasModelLoaded(boxModelHash) do Citizen.Wait(100) end
    for i, pos in ipairs(boxPositions) do
        local box = CreateObject(boxModelHash, pos.x, pos.y, pos.z, true, true, true)
        if DoesEntityExist(box) then
            SetEntityHeading(box, pos.heading)
            FreezeEntityPosition(box, true)
            SetEntityAsMissionEntity(box, true, true)
            table.insert(boxDepoBoxes, box)
        end
    end
    SetModelAsNoLongerNeeded(boxModelHash)
end

function spawnBoxesAtDepo(location, cartData)
    local boxDepo, boxModel, boxAmount = location.BoxDepo, GetHashKey(cartData.box_model), cartData.box_amount
    for i, box in ipairs(boxDepoBoxes) do if DoesEntityExist(box) then DeleteObject(box) end end
    boxDepoBoxes = {}
    RequestModel(boxModel)
    while not HasModelLoaded(boxModel) do Citizen.Wait(100) end
    local spacing, rows, cols = 1.5, math.ceil(math.sqrt(boxAmount)), math.ceil(boxAmount / rows)
    for i = 1, boxAmount do
        local row, col = math.floor((i - 1) / cols), (i - 1) % cols
        local x, y, z = boxDepo.x + (col - cols/2) * spacing, boxDepo.y + (row - rows/2) * spacing, boxDepo.z
        local box = CreateObject(boxModel, x, y, z, true, true, true)
        if DoesEntityExist(box) then
            SetEntityHeading(box, boxDepo.w)
            FreezeEntityPosition(box, true)
            SetEntityAsMissionEntity(box, true, true)
            table.insert(boxDepoBoxes, box)
        end
    end
    SetModelAsNoLongerNeeded(boxModel)
    notify('Frontier Express', "Boxes spawned at depot! Go pick them up.")
end

function spawnCartAtLocation(location, cartType)
    local spawn = location.spawn
    local cartModel = J0.Carts[cartType].cart_model
    local newCart = spawnVehicleSafely(cartModel, spawn.coords, spawn.heading)
    if newCart then
        currentCart = newCart
    end
end

function fixDeliveryWagon()
    if not currentCartData then
        notify('Frontier Express', "No cart data available!")
        return
    end
    
    if currentCart and DoesEntityExist(currentCart) then
        local coords, heading = GetEntityCoords(currentCart), GetEntityHeading(currentCart)
        local loadedBoxes = #currentBoxes
        local cartModel = currentCartData.cart_model
        
        local newCart = spawnVehicleSafely(cartModel, coords, heading)
        
        if newCart then
            currentCart = newCart
            for i = 1, loadedBoxes do
                local boxModel = {-447665150, 1242644044, -106866375, -509228265, -581069256, -488847186, 1044628870}
                Citizen.InvokeNative(0xD80FAF919A2E56EA, currentCart, boxModel[math.random(1, #boxModel)])
            end
            notify('Frontier Express', "Wagon fixed with " .. loadedBoxes .. " boxes loaded!")
        end
    else
        notify('Frontier Express', "No wagon to fix!")
    end
end

function attachBoxToCart(box, cart)
    if not DoesEntityExist(box) or not DoesEntityExist(cart) then return false end
    local maxCapacity = currentCartData and currentCartData.box_amount or 13
    if #currentBoxes >= maxCapacity then notify('Frontier Express', "Cart is full! Cannot load more boxes.") return false end
    local boxModel = {1793592017, 1044628870, -1504084621}
    Citizen.InvokeNative(0xD80FAF919A2E56EA, cart, boxModel[math.random(1, #boxModel)])
    Citizen.Wait(100)
    table.insert(currentBoxes, "box_" .. #currentBoxes + 1)
    return true
end



function cleanupMissionObjects()
    if currentHeldBox and DoesEntityExist(currentHeldBox) then DetachEntity(currentHeldBox, true, true) DeleteObject(currentHeldBox) currentHeldBox = nil ClearPedTasks(PlayerPedId()) end
    
    if currentCart and DoesEntityExist(currentCart) then
        SetEntityAsMissionEntity(currentCart, false, true)
        DeleteVehicle(currentCart)
    end
    
    currentCart, currentCartData, currentBoxes, boxDepoBoxes = nil, nil, {}, {}
    if boxDepoPrompt then jo.prompt.deleteGroup("boxDepo") boxDepoPrompt = false end
    if cartPrompt then jo.prompt.deleteGroup("cart") cartPrompt = false end
    if deliveryBlip then RemoveBlip(deliveryBlip) deliveryBlip = nil end
    if deliveryPrompt then jo.prompt.deleteGroup("delivery") deliveryPrompt = false end
    isNearBoxDepo, isNearCart, isNearDelivery, deliveryLocation, boxesDelivered, allBoxesLoaded = false, false, false, nil, 0, false
    
    isSpawningCart = false
    if respawnCartThread then
        respawnCartThread = nil
    end
    
    ClearGpsMultiRoute()
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if not currentMission or currentHeldBox or allBoxesLoaded then if isNearBoxDepo then isNearBoxDepo = false end goto continue end
        local playerCoords = GetEntityCoords(PlayerPedId())
        local missionLocation = nil
        for i, location in ipairs(J0.locations) do if location.name == currentMission.from then missionLocation = location break end end
        if missionLocation then
            local boxDepo = missionLocation.BoxDepo
            local distance = #(playerCoords - vector3(boxDepo.x, boxDepo.y, boxDepo.z))
            local pulseDistance = 20.0 * (0.5 + 0.5 * math.sin(GetGameTimer() / 1000.0))
            if distance < pulseDistance then Citizen.InvokeNative(0x2A32FAA57B937173, 0xEC032ADD, boxDepo.x, boxDepo.y, boxDepo.z + 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 250, 250, 100, 250, 0, 0, 2, 0, 0, 0, 0) end
            if distance < 3.0 then
                if not isNearBoxDepo then isNearBoxDepo = true end
                local closestBox, closestDistance = nil, 999.0
                for i, box in ipairs(boxDepoBoxes) do
                    if DoesEntityExist(box) then
                        local boxDistance = #(playerCoords - GetEntityCoords(box))
                        if boxDistance < closestDistance then closestDistance, closestBox = boxDistance, box end
                    else table.remove(boxDepoBoxes, i) end
                end
                if closestBox and closestDistance < 2.0 then
                    DeleteObject(closestBox)
                    for i, box in ipairs(boxDepoBoxes) do if box == closestBox then table.remove(boxDepoBoxes, i) break end end
                    local ped = PlayerPedId()
                    RequestAnimDict("amb_wander@code_human_hay_bale_wander@male_a@base")
                    while not HasAnimDictLoaded("amb_wander@code_human_hay_bale_wander@male_a@base") do Citizen.Wait(100) end
                    TaskPlayAnim(ped, "amb_wander@code_human_hay_bale_wander@male_a@base", "base", 8.0, -8.0, -1, 31, 0, true, 0, false, 0, false)
                    local coords, boxModel = GetEntityCoords(ped), currentCartData and currentCartData.box_model or "p_crate03x"
                    RequestModel(GetHashKey(boxModel))
                    while not HasModelLoaded(GetHashKey(boxModel)) do Citizen.Wait(100) end
                    currentHeldBox = CreateObject(GetHashKey(boxModel), coords.x, coords.y, coords.z, true, true, true)
                    SetModelAsNoLongerNeeded(GetHashKey(boxModel))
                    AttachEntityToEntity(currentHeldBox, ped, GetPedBoneIndex(ped, 131), -0.05, 0.45, 0.5, 90.0, 90.0, 80.0, true, true, false, true, 1, true)
                    notify('Frontier Express', "Box picked up! Go to the cart to load it.")
                else notify('Frontier Express', "No box nearby!") end
            else if isNearBoxDepo then isNearBoxDepo = false end end
        end
        ::continue::
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if currentMission and currentCart and DoesEntityExist(currentCart) and not allBoxesLoaded then
            local playerCoords, cartCoords = GetEntityCoords(PlayerPedId()), GetEntityCoords(currentCart)
            local distance = #(playerCoords - cartCoords)
            local pulseDistance = 20.0 * (0.5 + 0.5 * math.sin(GetGameTimer() / 1000.0))
            if distance < pulseDistance then Citizen.InvokeNative(0x2A32FAA57B937173, 0xEC032ADD, cartCoords.x, cartCoords.y, cartCoords.z + 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 100, 250, 100, 250, 0, 0, 2, 0, 0, 0, 0) end
            if distance < 3.0 then
                if not isNearCart then isNearCart = true end
                if currentHeldBox then
                    if attachBoxToCart(currentHeldBox, currentCart) then
                        DetachEntity(currentHeldBox, true, true)
                        DeleteObject(currentHeldBox)
                        currentHeldBox = nil
                        ClearPedTasks(PlayerPedId())
                        if not IsPedInAnyVehicle(PlayerPedId(), false) then TaskWarpPedIntoVehicle(PlayerPedId(), currentCart, -1) end
                        if #boxDepoBoxes == 0 then allBoxesLoaded = true notify('Frontier Express', "All boxes loaded! Drive to delivery location.") setupDeliveryWaypoint() end
                    end
                end
            else if isNearCart then isNearCart = false end end
        elseif currentMission and currentCart and not DoesEntityExist(currentCart) then
            currentCart = nil
            if not isSpawningCart and currentCartData and not respawnCartThread then
                respawnCartThread = Citizen.CreateThread(function()
                    Citizen.Wait(500)
                    if currentMission and currentCartData and not isSpawningCart then
                        TriggerEvent('J0-FrontierExpress:respawnCart')
                    end
                    respawnCartThread = nil
                end)
            end
        else if isNearCart then isNearCart = false end end
    end
end)

function setupDeliveryWaypoint()
    if not currentMission then return end
    for i, location in ipairs(J0.locations) do if location.name == currentMission.to then deliveryLocation = location break end end
    if deliveryLocation then
        if deliveryBlip then RemoveBlip(deliveryBlip) end
        deliveryBlip = jo.blip.create(vec3(deliveryLocation.delivery.coords.x, deliveryLocation.delivery.coords.y, deliveryLocation.delivery.coords.z), "Delivery Point", "blip_ambient_wagon")
        StartGpsMultiRoute(70, true, true)
        Citizen.InvokeNative(0x64C59DD6834FA942, deliveryLocation.delivery.coords.x, deliveryLocation.delivery.coords.y, deliveryLocation.delivery.coords.z)
        Citizen.InvokeNative(0x4426D65E029A4DC0, true)
        notify('Frontier Express', "Delivery point marked! Drive to " .. currentMission.to .. " to deliver boxes.")
        startDeliveryThread()
    end
end

function startDeliveryThread()
    Citizen.CreateThread(function()
        while currentMission and deliveryLocation do
            Citizen.Wait(0)
            local playerCoords = GetEntityCoords(PlayerPedId())
            local deliveryCoords = vector3(deliveryLocation.delivery.coords.x, deliveryLocation.delivery.coords.y, deliveryLocation.delivery.coords.z)
            local distance = #(playerCoords - deliveryCoords)
            local pulseDistance = 20.0 * (0.5 + 0.5 * math.sin(GetGameTimer() / 1000.0))
            if distance < pulseDistance then Citizen.InvokeNative(0x2A32FAA57B937173, 0xEC032ADD, deliveryCoords.x, deliveryCoords.y, deliveryCoords.z + 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 250, 100, 100, 250, 0, 0, 2, 0, 0, 0, 0) end
            if distance < 10.0 then
                if not isNearDelivery then
                    isNearDelivery = true
                    notify('Frontier Express', "Arrived at delivery location! Mission completed.")
                    TaskLeaveVehicle(PlayerPedId(), currentCart, 0)
                    Citizen.Wait(2000)
                    completeDeliveryMission()
                end
            end
        end
        if isNearDelivery then isNearDelivery = false end
    end)
end


function completeDeliveryMission()
    cleanupMissionObjects()
    if currentMission then
        markContractAsCompleted(currentMission)
        hideStatusBar()
        jo.notif.simpleTop('Frontier Express', "You Completed " .. currentMission.contractName .. " !", 5000)
        local missionData = currentMission
        if currentMission.groupId then missionData.groupId = currentMission.groupId end
        TriggerServerEvent('J0-FrontierExpress:completeMission', missionData, true)
        SendNUIMessage({action = "completeMissionCallback", data = currentMission})
        Citizen.CreateThread(function() Citizen.Wait(3000) cleanupOldCarts() end)
    end
end


