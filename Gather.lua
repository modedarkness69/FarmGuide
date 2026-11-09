local ADDON, ns = ...

local ACTIVE_WINDOW = 180  -- сколько секунд после сбора считается «активным фармом»

ns.session = { start = GetTime(), active = 0, items = {}, nodes = 0 }
ns.lastGather = 0
ns.lastGatherMap = nil
ns.routeDirty = {}

local function classify(classID, subID)
    if classID == 7 then
        if subID == 7 then return "ore" end   -- Металл и камень
        if subID == 9 then return "herb" end  -- Травы
    end
end

function ns.AddNode(mapID, x, y, kind)
    local m = ns.GetMap(mapID)
    local best, bestD
    for _, n in ipairs(m.nodes) do
        if n.k == kind then
            local d = ns.Yards(mapID, x, y, n.x, n.y)
            if d < ns.settings.mergeYards and (not bestD or d < bestD) then best, bestD = n, d end
        end
    end
    if best then
        local w = math.min(best.c, 20)
        best.x = (best.x * w + x) / (w + 1)
        best.y = (best.y * w + y) / (w + 1)
        best.c = best.c + 1
        best.last = time()
    else
        best = { x = x, y = y, k = kind, c = 1, last = time() }
        table.insert(m.nodes, best)
        ns.routeDirty[mapID] = true
    end
    return best
end

local lootHandled = false

ns:On("LOOT_READY", function()
    if lootHandled then return end
    if IsFishingLoot and IsFishingLoot() then return end
    local fromNode, kind = false, nil
    local items = {}
    for slot = 1, GetNumLootItems() do
        if GetLootSlotType(slot) == Enum.LootSlotType.Item then
            local link = GetLootSlotLink(slot)
            if link then
                local itemID, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
                local qty = select(3, GetLootSlotInfo(slot)) or 1
                if itemID then
                    items[itemID] = (items[itemID] or 0) + qty
                    local k = classify(classID, subID)
                    if k == "ore" then kind = "ore" elseif k == "herb" and kind ~= "ore" then kind = "herb" end
                end
            end
            local guid = GetLootSourceInfo(slot)
            if guid and guid:find("^GameObject") then fromNode = true end
        end
    end
    if not (fromNode and kind) then return end
    lootHandled = true

    local mapID, x, y = ns.GetZonePos()
    if not mapID then return end
    ns.AddNode(mapID, x, y, kind)
    local m = ns.GetMap(mapID)
    m.gathers = m.gathers + 1
    for id, q in pairs(items) do
        m.items[id] = (m.items[id] or 0) + q
        ns.session.items[id] = (ns.session.items[id] or 0) + q
    end
    ns.session.nodes = ns.session.nodes + 1
    ns.lastGather = GetTime()
    ns.lastGatherMap = mapID
    if ns.OnGathered then ns.OnGathered(mapID, x, y) end
end)

ns:On("LOOT_CLOSED", function() lootHandled = false end)

function ns.SessionValue()
    local v = 0
    for id, q in pairs(ns.session.items) do v = v + ns.Value(id) * q end
    return v
end

function ns.ResetSession()
    ns.session = { start = GetTime(), active = 0, items = {}, nodes = 0 }
end

table.insert(ns.onLogin, function()
    C_Timer.NewTicker(5, function()
        if GetTime() - ns.lastGather < ACTIVE_WINDOW then
            ns.session.active = ns.session.active + 5
            local mapID = ns.GetZonePos()
            if mapID and mapID == ns.lastGatherMap then
                local m = ns.GetMap(mapID)
                m.time = m.time + 5
            end
        end
    end)
end)
