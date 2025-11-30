local DB_FILE = "server/db.json"
local RESOURCE_NAME = GetCurrentResourceName()


function loadDatabase()
    local file = LoadResourceFile(RESOURCE_NAME, DB_FILE)
    return file and file ~= "" and json.decode(file) or {}
end

function saveDatabase(data)
    return SaveResourceFile(RESOURCE_NAME, DB_FILE, json.encode(data), -1)
end


function getPlayerIdentifier(source)
    return jo.framework:getUser(source):getIdentifiers().charid
end

function createNewPlayerData(source)
    local user = jo.framework:getUser(source)
    local date = os.date("%Y-%m-%d")
    return {
        charId = getPlayerIdentifier(source), name = user:getRPName(),
        level = 1, xp = 0, maxXp = 100, totalDeliveries = 0, totalEarnings = 0,
        successRate = 100, daysActive = 1, missionsCompleted = 0, missionsFailed = 0,
        lastActive = date, joinDate = date, recentDeliveries = {}
    }
end

function calculateLevelAndXP(currentXP)
    local level, xpForCurrentLevel, xpForNextLevel = 1, 0, 100
    while currentXP >= xpForNextLevel do
        level, xpForCurrentLevel, xpForNextLevel = level + 1, xpForNextLevel, xpForNextLevel + (50 + (level * 10))
    end
    return level, xpForCurrentLevel, xpForNextLevel
end

function getPlayerData(source)
    local charId = getPlayerIdentifier(source)
    local db = loadDatabase()
    if not db[charId] then db[charId] = createNewPlayerData(source) else db[charId].lastActive = os.date("%Y-%m-%d") end
    saveDatabase(db)
    local playerData = db[charId]
    local level, _, nextLevelXP = calculateLevelAndXP(playerData.xp)
    playerData.level, playerData.maxXp = level, nextLevelXP
    return playerData
end

function updatePlayerStats(source, missionData, success)
    local charId = getPlayerIdentifier(source)
    local db = loadDatabase()
    if not db[charId] then return false end
    local player = db[charId]
    if success then
       jo.framework:addMoney(source,missionData.reward,0)
        player.missionsCompleted, player.totalDeliveries = player.missionsCompleted + 1, player.totalDeliveries + 1
        player.totalEarnings, player.xp = player.totalEarnings + missionData.reward, player.xp + missionData.xp
        table.insert(player.recentDeliveries, 1, {from = missionData.from, to = missionData.to, reward = missionData.reward, time = os.date("%Y-%m-%d %H:%M:%S"), status = "completed"})
    else
        player.missionsFailed = player.missionsFailed + 1
        table.insert(player.recentDeliveries, 1, {from = missionData.from, to = missionData.to, reward = missionData.reward, time = os.date("%Y-%m-%d %H:%M:%S"), status = "failed"})
    end
    if #player.recentDeliveries > 10 then table.remove(player.recentDeliveries, #player.recentDeliveries) end
    local totalMissions = player.missionsCompleted + player.missionsFailed
    if totalMissions > 0 then player.successRate = math.floor((player.missionsCompleted / totalMissions) * 100) end
    player.lastActive = os.date("%Y-%m-%d")
    saveDatabase(db)
    return true
end

local activeGroups = {}
local groupCounter = 0

function getPlayerInfoById(playerId)
    local source = tonumber(playerId)
    if not source then return { success = false, message = "Invalid player ID" } end
    local user = jo.framework:getUser(source)
    if not user then return { success = false, message = "Player not found" } end
    return { success = true, name = user:getRPName(), source = source }
end

function createGroup(leaderSource, friends)
    groupCounter = groupCounter + 1
    local groupId = "group_" .. groupCounter
    local leaderName = jo.framework:getUser(leaderSource):getRPName()
    local group = {id = groupId, leader = {source = leaderSource, name = leaderName}, members = {}, created = os.time(), active = true}
    table.insert(group.members, {source = leaderSource, name = leaderName})
    for _, friend in ipairs(friends) do table.insert(group.members, {source = friend.source, name = friend.name}) end
    activeGroups[groupId] = group
    return groupId
end

function removeGroup(groupId) if activeGroups[groupId] then activeGroups[groupId] = nil return true end return false end
function getGroup(groupId) return activeGroups[groupId] end

local serverSpawnedObjects = {}

function spawnMissionObjectsServer(missionData, groupId)
    local missionLocation = nil
    for i, location in ipairs(J0.locations) do if location.name == missionData.from then missionLocation = location break end end
    if not missionLocation then return nil end
    local availableCarts = {} for cartName, cartData in pairs(J0.Carts) do table.insert(availableCarts, cartName) end
    local selectedCart = availableCarts[math.random(1, #availableCarts)]
    local cartData = J0.Carts[selectedCart]
    if not cartData then return nil end
    local cartId = CreateVehicle(cartData.cart_model, missionLocation.spawn.coords.x, missionLocation.spawn.coords.y, missionLocation.spawn.coords.z, missionLocation.spawn.heading, true, true)
    local boxDepo, boxModel, boxAmount = missionLocation.BoxDepo, cartData.box_model, cartData.box_amount
    local spacing, rows = 1.5, math.ceil(math.sqrt(boxAmount))
    local cols = math.ceil(boxAmount / rows)
    local boxPositions = {}
    for i = 1, boxAmount do
        local row, col = math.floor((i - 1) / cols), (i - 1) % cols
        local x, y, z = boxDepo.x + (col - cols/2) * spacing, boxDepo.y + (row - rows/2) * spacing, boxDepo.z
        table.insert(boxPositions, {x = x, y = y, z = z, heading = boxDepo.w})
    end
    local spawnedObjects = {cartId = cartId, cartData = cartData, boxModel = boxModel, boxPositions = boxPositions, groupId = groupId}
    serverSpawnedObjects[groupId or "solo"] = spawnedObjects
    return spawnedObjects
end

function cleanupServerObjects(groupId)
    local key = groupId or "solo"
    local objects = serverSpawnedObjects[key]
    if objects then if objects.cartId and DoesEntityExist(objects.cartId) then DeleteEntity(objects.cartId) end serverSpawnedObjects[key] = nil end
end

jo.callback.registerCallback('J0-FrontierExpress:getPlayerData', getPlayerData)
jo.callback.registerCallback('J0-FrontierExpress:updatePlayerStats', updatePlayerStats)
jo.callback.registerCallback('J0-FrontierExpress:getPlayerInfoById', getPlayerInfoById)


RegisterServerEvent('J0-FrontierExpress:startMission')
AddEventHandler('J0-FrontierExpress:startMission', function(missionData)
    local source = source
    local friends = missionData.friends or {}
    if #friends > 0 then
        local groupId = createGroup(source, friends)
        local spawnedObjects = spawnMissionObjectsServer(missionData, groupId)
        local group = getGroup(groupId)
        if group then for _, member in ipairs(group.members) do TriggerClientEvent('J0-FrontierExpress:startMissionClient', member.source, missionData, groupId) TriggerClientEvent('J0-FrontierExpress:spawnMissionObjects', member.source, missionData, groupId, spawnedObjects) end end
        TriggerClientEvent('J0-FrontierExpress:missionStartResponse', source, { success = true, groupId = groupId })
    else
        local spawnedObjects = spawnMissionObjectsServer(missionData, nil)
        TriggerClientEvent('J0-FrontierExpress:startMissionClient', source, missionData, nil)
        TriggerClientEvent('J0-FrontierExpress:spawnMissionObjects', source, missionData, nil, spawnedObjects)
        TriggerClientEvent('J0-FrontierExpress:missionStartResponse', source, { success = true, groupId = nil })
    end
end)

RegisterServerEvent('J0-FrontierExpress:completeMission')
AddEventHandler('J0-FrontierExpress:completeMission', function(missionData, success)
    local source = source
    local result = updatePlayerStats(source, missionData, success)
    if missionData.groupId and activeGroups[missionData.groupId] then
        local group = getGroup(missionData.groupId)
        if group then for _, member in ipairs(group.members) do TriggerClientEvent('J0-FrontierExpress:completeMissionClient', member.source, missionData, success) end end
        cleanupServerObjects(missionData.groupId)
        removeGroup(missionData.groupId)
    else
        cleanupServerObjects(nil)
        TriggerClientEvent('J0-FrontierExpress:completeMissionClient', source, missionData, success)
    end
    if result then TriggerClientEvent('J0-FrontierExpress:missionCompleted', source, getPlayerData(source), missionData, success) end
end)
