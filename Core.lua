local ADDON, ns = ...
FarmGuide = ns

ns.version = "1.1.0"
ns.onLogin = {}

--------------------------------------------------------------------
-- События
--------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.handlers = {}

function ns:On(event, fn)
    if not self.handlers[event] then
        self.handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(self.handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = ns.handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FarmGuide|r: " .. tostring(msg))
end

--------------------------------------------------------------------
-- База данных
--------------------------------------------------------------------
local defaults = {
    -- HUD
    hudRadius = 300,       -- дальность прорисовки: ярдов от центра до края
    hudRotate = true,      -- вращать вместе с персонажем
    hudDim = 0.15,         -- затемнение фона (0..1)
    hudSize = 0.9,         -- размер HUD: доля высоты экрана
    hudX = 0,              -- сдвиг центра HUD, пиксели
    hudY = 0,
    hudAlpha = 1,          -- прозрачность всего HUD
    hudLine = 3,           -- толщина линий маршрута
    hudIcon = 18,          -- размер иконок точек
    hudText = true,        -- показывать текст сверху
    hudTextScale = 1,
    hudTextY = -110,       -- положение текста от верха экрана
    hudHideCombat = true,  -- прятать HUD в бою
    hudSound = true,       -- звук при взятии точки
    reachYards = 25,       -- ближе этого — точка считается взятой
    -- маршрут
    filter = "both",       -- both / ore / herb
    mergeYards = 20,       -- точки ближе этого сливаются в одну
    -- аукцион
    flipMinProfit = 200 * 10000, -- минимальная прибыль сделки, медь
    cheapPct = 25,         -- ресурс считается дешёвым, если ниже рынка на столько %
    flipPct = 40,          -- предмет — сделка, если дешевле следующего лота на столько %
    -- прочее
    mainScale = 1,
    minimapHide = false,
    minimapAngle = 225,
}
ns.defaults = defaults

function ns.ResetSettings(prefix)
    for k, v in pairs(defaults) do
        if not prefix or k:find("^" .. prefix) or (prefix == "hud" and k == "reachYards") then
            ns.settings[k] = v
        end
    end
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    FarmGuideDB = FarmGuideDB or {}
    local db = FarmGuideDB
    db.settings = db.settings or {}
    for k, v in pairs(defaults) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    db.maps = db.maps or {}
    db.realms = db.realms or {}
    ns.db = db
    ns.settings = db.settings
end)

ns:On("PLAYER_LOGIN", function()
    local realm = GetNormalizedRealmName() or GetRealmName() or "?"
    local r = ns.db.realms[realm] or {}
    r.prices = r.prices or {}
    r.flips = r.flips or {}
    r.cflips = r.cflips or {}
    r.scanTime = r.scanTime or 0
    r.fullScanTime = r.fullScanTime or 0
    ns.db.realms[realm] = r
    ns.realm = r
    ns.realmName = realm
    for _, fn in ipairs(ns.onLogin) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
    ns.Print("загружен. |cffffff00/fg|r — окно, |cffffff00/fg hud|r — HUD маршрута.")
end)

--------------------------------------------------------------------
-- Карта и координаты
--------------------------------------------------------------------
local sizeCache = {}

-- размер карты в ярдах
function ns.MapSize(mapID)
    local c = sizeCache[mapID]
    if c then return c[1], c[2] end
    local w, h
    if C_Map.GetMapWorldSize then
        w, h = C_Map.GetMapWorldSize(mapID)
    end
    if not w or w == 0 then
        local _, p0 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, p1 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if p0 and p1 then
            w = math.abs(p0.y - p1.y)
            h = math.abs(p0.x - p1.x)
        end
    end
    if not w or w == 0 then w, h = 1000, 1000 end
    sizeCache[mapID] = { w, h }
    return w, h
end

-- позиция игрока на карте уровня «зона» (пещеры и микро-карты переводятся в зону)
function ns.GetZonePos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    local info = C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and info.mapType and info.mapType > Enum.UIMapType.Zone
        and info.parentMapID and info.parentMapID > 0 and guard < 5 do
        local cont, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not cont or not world then break end
        local _, ppos = C_Map.GetMapPosFromWorldPos(cont, world, info.parentMapID)
        if not ppos then break end
        mapID = info.parentMapID
        x, y = ppos:GetXY()
        info = C_Map.GetMapInfo(mapID)
        guard = guard + 1
    end
    return mapID, x, y
end

function ns.Yards(mapID, x1, y1, x2, y2)
    local w, h = ns.MapSize(mapID)
    local dx, dy = (x1 - x2) * w, (y1 - y2) * h
    return math.sqrt(dx * dx + dy * dy)
end

function ns.MapName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("Карта " .. tostring(mapID))
end

function ns.GetMap(mapID)
    local m = ns.db.maps[mapID]
    if not m then
        m = { nodes = {}, items = {}, time = 0, gathers = 0 }
        ns.db.maps[mapID] = m
    end
    return m
end

--------------------------------------------------------------------
-- Предметы и цены
--------------------------------------------------------------------
function ns.ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if not name then
        C_Item.RequestLoadItemDataByID(id)
        return "Предмет #" .. id
    end
    return name
end

function ns.ItemIcon(id)
    return C_Item.GetItemIconByID(id) or 134400
end

-- рыночная цена на аукционе (медь за штуку) или nil
function ns.Price(id)
    local p = ns.realm and ns.realm.prices[id]
    return p and p.p
end

-- цена для подсчёта ценности: аукцион, иначе цена у торговца
function ns.Value(id)
    local p = ns.Price(id)
    if p then return p end
    local vendor = select(11, C_Item.GetItemInfo(id))
    return vendor or 0
end

function ns.MapValue(m)
    local v = 0
    for id, q in pairs(m.items) do
        v = v + ns.Value(id) * q
    end
    return v
end

function ns.Money(c)
    c = math.floor(c or 0)
    local neg = c < 0
    if neg then c = -c end
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local out
    if g >= 100 then
        out = BreakUpLargeNumbers(g) .. "|cffffd700з|r"
    elseif g > 0 then
        out = g .. "|cffffd700з|r " .. s .. "|cffc7c7cfс|r"
    else
        out = s .. "|cffc7c7cfс|r " .. (c % 100) .. "|cffeda55fм|r"
    end
    return neg and ("-" .. out) or out
end

function ns.PerHour(value, seconds)
    if not seconds or seconds < 60 then return 0 end
    return value / seconds * 3600
end

function ns.Duration(sec)
    sec = math.floor(sec or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dч %02dм", h, m) end
    return string.format("%dм", m)
end

function ns.Today()
    return date("%Y%m%d")
end

-- лучшая зона по золоту в час (нужно минимум 5 минут фарма в зоне)
function ns.BestZone()
    local bestID, bestGph
    for mapID, m in pairs(ns.db.maps) do
        if m.time >= 300 then
            local gph = ns.PerHour(ns.MapValue(m), m.time)
            if not bestGph or gph > bestGph then bestID, bestGph = mapID, gph end
        end
    end
    return bestID, bestGph
end

function ns.FreeBagSlots()
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local n = C_Container.GetContainerNumFreeSlots(bag)
        free = free + (n or 0)
    end
    return free
end
