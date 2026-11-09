local ADDON, ns = ...

local HIST_DAYS = 14
ns.scanStatus = ""

local function setStatus(text)
    ns.scanStatus = text
    if ns.OnScanStatus then ns.OnScanStatus(text) end
end

local function trimHistory(hist)
    local keys = {}
    for k in pairs(hist) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys - HIST_DAYS do hist[keys[i]] = nil end
end

-- средняя цена за последние 7 дней, не считая сегодня
function ns.WeekAvg(id)
    local p = ns.realm and ns.realm.prices[id]
    if not p or not p.hist then return end
    local today, sum, n = ns.Today(), 0, 0
    local keys = {}
    for k in pairs(p.hist) do if k ~= today then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return a > b end)
    for i = 1, math.min(7, #keys) do sum = sum + p.hist[keys[i]]; n = n + 1 end
    if n == 0 then return end
    return sum / n
end

--------------------------------------------------------------------
-- Скан ресурсов (товары: руда, травы, камни и т.п.) — точные цены
--------------------------------------------------------------------
local queue, current, timeoutTimer = {}, nil, nil
local nextQuery

local function knownItems()
    local set, list = {}, {}
    for _, m in pairs(ns.db.maps) do
        for id in pairs(m.items) do
            if not set[id] then set[id] = true; list[#list + 1] = id end
        end
    end
    return list
end

local function processCommodity(itemID)
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    if n == 0 then return end
    local rows, total = {}, 0
    for i = 1, n do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.quantity then
            rows[#rows + 1] = r
            total = total + r.quantity
        end
    end
    if total == 0 then return end
    -- рынок: цена, до которой набирается 15% всего объёма (защита от единичных дешёвых лотов)
    local need, acc, market = total * 0.15, 0, rows[#rows].unitPrice
    for _, r in ipairs(rows) do
        acc = acc + r.quantity
        if acc >= need then market = r.unitPrice; break end
    end
    local p = ns.realm.prices[itemID] or { hist = {} }
    p.p, p.min, p.q, p.t = market, rows[1].unitPrice, total, time()
    p.hist = p.hist or {}
    p.hist[ns.Today()] = market
    trimHistory(p.hist)
    ns.realm.prices[itemID] = p

    -- перепродажа: дешёвый «хвост» заметно ниже рынка
    local units, cost = 0, 0
    local cheap = 1 - ns.settings.cheapPct / 100
    for _, r in ipairs(rows) do
        if r.unitPrice <= market * cheap then
            units = units + r.quantity
            cost = cost + r.quantity * r.unitPrice
        else
            break
        end
    end
    ns.realm.cflips[itemID] = nil
    if units > 0 then
        local profit = units * market * 0.95 - cost
        if profit >= ns.settings.flipMinProfit then
            ns.realm.cflips[itemID] = {
                id = itemID, buy = cost / units, sell = market, units = units,
                profit = profit, t = time(),
            }
        end
    end
end

local function finishResources()
    current = nil
    ns.realm.scanTime = time()
    setStatus("Скан ресурсов готов: цены обновлены.")
    if ns.RefreshUI then ns.RefreshUI() end
end

nextQuery = function()
    if timeoutTimer then timeoutTimer:Cancel(); timeoutTimer = nil end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        current = nil
        setStatus("Аукцион закрыт — скан остановлен.")
        return
    end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(0.5, nextQuery)
        return
    end
    local id = table.remove(queue, 1)
    if not id then return finishResources() end
    current = id
    setStatus(string.format("Скан ресурсов: %s (осталось %d)", ns.ItemName(id), #queue))
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(id),
        { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, false)
    timeoutTimer = C_Timer.NewTimer(8, function() timeoutTimer = nil; nextQuery() end)
end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not current or itemID ~= current then return end
    processCommodity(itemID)
    C_Timer.After(0.2, nextQuery)
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if current and itemKey and itemKey.itemID == current then
        C_Timer.After(0.2, nextQuery)  -- не товар, пропускаем
    end
end)

function ns.ScanResources()
    if current then return setStatus("Скан уже идёт…") end
    queue = knownItems()
    if #queue == 0 then
        return setStatus("Нет собранных ресурсов — сначала соберите хоть что-нибудь.")
    end
    nextQuery()
end

--------------------------------------------------------------------
-- Полный скан аукциона — поиск сделок на перепродажу (раз в 15 минут)
--------------------------------------------------------------------
local fullRunning, waitTimer, worker = false, nil, nil

local function analyze()
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    local groups = {}
    for i = 0, n - 1 do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
        if itemID and itemID ~= 82800 and buyout and buyout > 0 and count and count > 0 then
            local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
            local key, ilvl
            if classID == 15 or classID == 9 or classID == 17 then
                key = itemID
            elseif classID == 2 or classID == 4 then
                local link = C_AuctionHouse.GetReplicateItemLink(i)
                ilvl = link and C_Item.GetDetailedItemLevelInfo(link)
                if ilvl then key = itemID .. ":" .. ilvl end
            end
            if key then
                local g = groups[key]
                if not g then g = { id = itemID, ilvl = ilvl, p = {} }; groups[key] = g end
                g.p[#g.p + 1] = buyout / count
            end
        end
        if i % 1500 == 0 then coroutine.yield(i, n) end
    end

    local flips, k = {}, 0
    for _, g in pairs(groups) do
        local c = #g.p
        if c >= 4 then
            table.sort(g.p)
            local mn = g.p[1]
            local sell = math.min(g.p[2], g.p[math.ceil(c / 2)])
            local profit = sell * 0.95 - mn
            if mn <= sell * (1 - ns.settings.flipPct / 100) and profit >= ns.settings.flipMinProfit then
                flips[#flips + 1] = { id = g.id, ilvl = g.ilvl, buy = mn, sell = sell, profit = profit, count = c }
            end
        end
        k = k + 1
        if k % 500 == 0 then coroutine.yield(n, n) end
    end
    table.sort(flips, function(a, b) return a.profit > b.profit end)
    for i = #flips, 101, -1 do flips[i] = nil end
    ns.realm.flips = flips
    ns.realm.fullScanTime = time()
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    if not worker then self:Hide(); return end
    local ok, i, n = coroutine.resume(worker)
    if not ok then
        geterrorhandler()(i)
        worker = nil; fullRunning = false; self:Hide()
        setStatus("Ошибка при разборе скана.")
        return
    end
    if coroutine.status(worker) == "dead" then
        worker = nil; fullRunning = false; self:Hide()
        setStatus(string.format("Полный скан готов: найдено сделок — %d.", #ns.realm.flips))
        if ns.RefreshUI then ns.RefreshUI() end
    elseif i and n and n > 0 then
        setStatus(string.format("Разбор аукциона: %d%%", math.floor(i / n * 100)))
    end
end)

ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
    if not fullRunning or worker then return end
    if waitTimer then waitTimer:Cancel(); waitTimer = nil end
    worker = coroutine.create(analyze)
    driver:Show()
end)

function ns.FullScan()
    if fullRunning then return setStatus("Полный скан уже идёт…") end
    local since = time() - (ns.realm.fullScanTime or 0)
    if since < 15 * 60 then
        return setStatus(string.format("Полный скан доступен раз в 15 минут (ещё %d мин).", math.ceil((900 - since) / 60)))
    end
    fullRunning = true
    setStatus("Полный скан: ждём ответа сервера…")
    C_AuctionHouse.ReplicateItems()
    waitTimer = C_Timer.NewTimer(60, function()
        waitTimer = nil
        if not worker then
            fullRunning = false
            setStatus("Сервер не ответил. Попробуйте позже (ограничение — раз в 15 минут).")
        end
    end)
end

--------------------------------------------------------------------
-- Поиск предмета в окне аукциона по клику
--------------------------------------------------------------------
function ns.SearchAH(itemID)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return ns.Print("Откройте аукцион, чтобы искать предмет.")
    end
    local name = C_Item.GetItemNameByID(itemID)
    if not name then return ns.Print("Предмет ещё не загружен, нажмите ещё раз.") end
    local ok = pcall(function()
        local bar = AuctionHouseFrame.SearchBar
        bar.SearchBox:SetText(name)
        bar:StartSearch()
    end)
    if not ok then ns.Print("Не удалось запустить поиск — введите «" .. name .. "» вручную.") end
end
