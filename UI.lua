local ADDON, ns = ...

local ROWS = 16
local main, tabs, panels, lists = nil, {}, {}, {}
local currentTab = 1
local FILTER_NAME = { both = "Руда и травы", ore = "Только руда", herb = "Только травы" }

--------------------------------------------------------------------
-- Подсказки
--------------------------------------------------------------------
function ns.GetTips(short)
    local tips = {}
    local r = ns.realm
    if not r then return tips end
    local mapID = ns.GetZonePos()

    local age = time() - (r.scanTime or 0)
    if r.scanTime == 0 then
        tips[#tips + 1] = "Цен ещё нет: откройте аукцион и нажмите «Скан ресурсов»."
    elseif age > 86400 then
        tips[#tips + 1] = "Цены устарели (" .. math.floor(age / 3600) .. " ч) — обновите скан на аукционе."
    end

    local best, bestGph = ns.BestZone()
    if best and mapID and best ~= mapID then
        local m = ns.db.maps[mapID]
        local cur = (m and m.time >= 300) and ns.PerHour(ns.MapValue(m), m.time) or nil
        if not cur or bestGph > cur * 1.15 then
            tips[#tips + 1] = string.format("Выгоднее зона «%s»: ~%s/ч.", ns.MapName(best), ns.Money(bestGph))
        end
    end

    if mapID then
        local m = ns.db.maps[mapID]
        local nodes = m and #m.nodes or 0
        if nodes > 0 and nodes < 15 then
            tips[#tips + 1] = "Маршрут неполный (" .. nodes .. " точек): облетите всю зону, точки добавятся сами."
        end
    end

    local free = ns.FreeBagSlots()
    if free <= 5 then tips[#tips + 1] = "Свободно мест в сумках: " .. free .. "." end

    if not short then
        for id, p in pairs(r.prices) do
            local avg = ns.WeekAvg(id)
            if avg and p.p then
                if p.p < avg * 0.75 then
                    tips[#tips + 1] = string.format("%s подешевел на %d%% к неделе — лучше придержать.",
                        ns.ItemName(id), math.floor((1 - p.p / avg) * 100))
                elseif p.p > avg * 1.25 then
                    tips[#tips + 1] = string.format("%s подорожал на %d%% к неделе — хорошее время продавать.",
                        ns.ItemName(id), math.floor((p.p / avg - 1) * 100))
                end
            end
        end
        local nf = #r.flips
        for _ in pairs(r.cflips) do nf = nf + 1 end
        if nf > 0 then tips[#tips + 1] = "Найдено сделок на перепродажу: " .. nf .. " — вкладка «Перепродажа»." end
    end
    return tips
end

--------------------------------------------------------------------
-- Список с колонками
--------------------------------------------------------------------
local function CreateList(parent, cols, onClick)
    local list = CreateFrame("Frame", nil, parent)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 4)
    list.data, list.offset, list.rows = {}, 0, {}

    local x = 4
    for _, col in ipairs(cols) do
        local fs = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(col.name)
        x = x + col.w
    end

    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, list)
        b:SetHeight(19)
        b:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 19)
        b:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.cells = {}
        local cx = 4
        for c, col in ipairs(cols) do
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.j or "LEFT")
            fs:SetWordWrap(false)
            b.cells[c] = fs
            cx = cx + col.w
        end
        b:SetScript("OnClick", function(self)
            if self.row and onClick then onClick(self.row) end
        end)
        list.rows[i] = b
    end

    list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    list.empty:SetPoint("CENTER")

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, math.min(#self.data - ROWS, self.offset - delta * 3))
        self:Refresh()
    end)

    function list:SetData(data, emptyText)
        self.data = data
        self.offset = 0
        self.empty:SetText(#data == 0 and (emptyText or "Нет данных") or "")
        self:Refresh()
    end

    function list:Refresh()
        for i, b in ipairs(self.rows) do
            local row = self.data[i + self.offset]
            b.row = row
            if row then
                for c, fs in ipairs(b.cells) do fs:SetText(row[c] or "") end
                b:Show()
            else
                b:Hide()
            end
        end
    end
    return list
end

local function iconText(id)
    return "|T" .. ns.ItemIcon(id) .. ":14:14|t " .. ns.ItemName(id)
end

local function pct(v)
    if not v then return "—" end
    local s = math.floor(v * 100 + 0.5)
    if s > 0 then return "|cff40ff40+" .. s .. "%|r" end
    if s < 0 then return "|cffff4040" .. s .. "%|r" end
    return "0%"
end

--------------------------------------------------------------------
-- Наполнение вкладок
--------------------------------------------------------------------
local function fillSummary()
    local p = panels[1]
    local mapID = ns.GetZonePos()
    local out = {}

    local best, bestGph = ns.BestZone()
    if best then
        out[#out + 1] = string.format("|cffffd200Лучшая зона:|r %s — ~%s/ч", ns.MapName(best), ns.Money(bestGph))
    else
        out[#out + 1] = "|cffffd200Лучшая зона:|r пока неизвестно — нужно хотя бы 5 минут фарма в зоне."
    end

    if mapID then
        local m = ns.GetMap(mapID)
        local route = ns.GetRoute(mapID)
        local len = ns.RouteLength(route, mapID)
        out[#out + 1] = string.format("|cffffd200Сейчас:|r %s — известно точек: %d, в маршруте: %d, длина круга: %d ярд",
            ns.MapName(mapID), #m.nodes, #route, len)
        if m.time >= 60 then
            out[#out + 1] = string.format("    фарм здесь: %s, %s/ч, ценность сбора ~%s за точку",
                ns.Duration(m.time), ns.Money(ns.PerHour(ns.MapValue(m), m.time)),
                ns.Money(m.gathers > 0 and ns.MapValue(m) / m.gathers or 0))
        end
    end

    local s = ns.session
    out[#out + 1] = string.format("|cffffd200Сессия:|r активный фарм %s, сборов %d, добыто на %s (%s/ч)",
        ns.Duration(s.active), s.nodes, ns.Money(ns.SessionValue()), ns.Money(ns.PerHour(ns.SessionValue(), s.active)))
    out[#out + 1] = "|cffffd200Фильтр маршрута:|r " .. FILTER_NAME[ns.settings.filter]
    out[#out + 1] = " "
    out[#out + 1] = "|cffffd200Подсказки:|r"
    local tips = ns.GetTips(false)
    if #tips == 0 then tips = { "Всё в порядке — летите по маршруту и собирайте." } end
    for i = 1, math.min(#tips, 9) do out[#out + 1] = "  • " .. tips[i] end
    p.text:SetText(table.concat(out, "\n"))
end

local function fillZones()
    local data = {}
    for mapID, m in pairs(ns.db.maps) do
        local v = ns.MapValue(m)
        data[#data + 1] = {
            ns.MapName(mapID),
            m.time >= 300 and ns.Money(ns.PerHour(v, m.time)) or "|cff888888мало данных|r",
            tostring(#m.nodes), tostring(m.gathers), ns.Duration(m.time),
            sort = m.time >= 300 and ns.PerHour(v, m.time) or -1,
        }
    end
    table.sort(data, function(a, b) return a.sort > b.sort end)
    lists[2]:SetData(data, "Зон ещё нет — соберите первую руду или траву.")
end

local function fillResources()
    local data, seen = {}, {}
    local total = {}
    for _, m in pairs(ns.db.maps) do
        for id, q in pairs(m.items) do total[id] = (total[id] or 0) + q; seen[id] = true end
    end
    for id in pairs(seen) do
        local p = ns.realm.prices[id]
        local avg = ns.WeekAvg(id)
        data[#data + 1] = {
            iconText(id),
            p and ns.Money(p.p) or "|cff888888нет скана|r",
            p and ns.Money(p.min) or "—",
            tostring(total[id]),
            (p and avg) and pct(p.p / avg - 1) or "—",
            id = id, sort = ns.Value(id) * total[id],
        }
    end
    table.sort(data, function(a, b) return a.sort > b.sort end)
    lists[3]:SetData(data, "Пока ничего не собрано.")
end

local function fillFlips()
    local data = {}
    for _, f in pairs(ns.realm.cflips) do
        data[#data + 1] = {
            iconText(f.id), ns.Money(f.buy), ns.Money(f.sell), ns.Money(f.profit),
            f.units .. " шт. дешевле рынка",
            id = f.id, sort = f.profit,
        }
    end
    for _, f in ipairs(ns.realm.flips) do
        data[#data + 1] = {
            iconText(f.id), ns.Money(f.buy), ns.Money(f.sell), ns.Money(f.profit),
            (f.ilvl and ("ур. " .. f.ilvl .. ", ") or "") .. f.count .. " лотов",
            id = f.id, sort = f.profit,
        }
    end
    table.sort(data, function(a, b) return a.sort > b.sort end)
    lists[4]:SetData(data, "Сделок нет. На аукционе: «Скан ресурсов» и «Полный скан».")
end

local fillers = {
    fillSummary, fillZones, fillResources, fillFlips,
    function() if ns.RefreshHUDPanel then ns.RefreshHUDPanel() end end,
    function() if ns.RefreshSettingsPanel then ns.RefreshSettingsPanel() end end,
}

function ns.ResetZone()
    local mapID = ns.GetZonePos()
    if not mapID then return ns.Print("не удалось определить зону.") end
    ns.db.maps[mapID] = nil
    ns.InvalidateRoute(mapID)
    ns.ResetHUDRoute()
    ns.Print("данные зоны «" .. ns.MapName(mapID) .. "» удалены.")
    ns.RefreshUI()
end

function ns.RebuildRoute()
    ns.InvalidateRoute()
    ns.ResetHUDRoute()
    ns.Print("маршрут перестроен.")
    ns.RefreshUI()
end

-- кнопка с подтверждением вторым нажатием
function ns.ConfirmButton(parent, text, w, onConfirm)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = false
            self:SetText(text)
            onConfirm()
        else
            self.armed = true
            self:SetText("|cffff4040Точно? Нажмите ещё раз|r")
            C_Timer.After(3, function()
                if self.armed then self.armed = false; self:SetText(text) end
            end)
        end
    end)
    return b
end

function ns.RefreshUI()
    if main and main:IsShown() then fillers[currentTab]() end
end

local function selectTab(i)
    currentTab = i
    for j, p in ipairs(panels) do p:SetShown(j == i) end
    for j, t in ipairs(tabs) do
        if j == i then t:LockHighlight() else t:UnlockHighlight() end
    end
    fillers[i]()
end

--------------------------------------------------------------------
-- Главное окно
--------------------------------------------------------------------
local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function createMain()
    main = CreateFrame("Frame", "FarmGuideMain", UIParent, "BasicFrameTemplateWithInset")
    main:SetSize(720, 500)
    main:SetScale(ns.settings.mainScale)
    main:SetPoint("CENTER")
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", main.StopMovingOrSizing)
    main:SetClampedToScreen(true)
    main:Hide()
    tinsert(UISpecialFrames, "FarmGuideMain")

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("FarmGuide — фарм руды и трав · " .. ns.credit)

    local names = { "Сводка", "Зоны", "Ресурсы", "Перепродажа", "HUD", "Настройки" }
    for i, n in ipairs(names) do
        local t = button(main, n, 110, function() selectTab(i) end)
        t:SetPoint("TOPLEFT", 12 + (i - 1) * 116, -30)
        tabs[i] = t
    end

    for i = 1, 6 do
        local p = CreateFrame("Frame", nil, main)
        p:SetPoint("TOPLEFT", 12, -60)
        p:SetPoint("BOTTOMRIGHT", -12, 42)
        p:Hide()
        panels[i] = p
    end

    local s = panels[1]
    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.text:SetPoint("TOPLEFT", 6, -6)
    s.text:SetPoint("RIGHT", -6, 0)
    s.text:SetJustifyH("LEFT")
    s.text:SetJustifyV("TOP")
    s.text:SetSpacing(4)

    lists[2] = CreateList(panels[2], {
        { name = "Зона", w = 230 }, { name = "Золото/час", w = 130, j = "RIGHT" },
        { name = "Точек", w = 70, j = "RIGHT" }, { name = "Сборов", w = 80, j = "RIGHT" },
        { name = "Время", w = 120, j = "RIGHT" },
    })
    lists[3] = CreateList(panels[3], {
        { name = "Предмет", w = 230 }, { name = "Рынок", w = 110, j = "RIGHT" },
        { name = "Минимум", w = 110, j = "RIGHT" }, { name = "Собрано", w = 80, j = "RIGHT" },
        { name = "К неделе", w = 100, j = "RIGHT" },
    }, function(row) ns.SearchAH(row.id) end)
    lists[4] = CreateList(panels[4], {
        { name = "Предмет (клик — найти)", w = 210 }, { name = "Купить", w = 95, j = "RIGHT" },
        { name = "Продать", w = 95, j = "RIGHT" }, { name = "Прибыль", w = 95, j = "RIGHT" },
        { name = "Примечание", w = 150, j = "RIGHT" },
    }, function(row) ns.SearchAH(row.id) end)

    if ns.BuildHUDPanel then ns.BuildHUDPanel(panels[5]) end
    if ns.BuildSettingsPanel then ns.BuildSettingsPanel(panels[6]) end

    -- нижняя панель
    local bHud = button(main, "Показать HUD", 130, function() ns.ToggleHUD() end)
    bHud:SetPoint("BOTTOMLEFT", 12, 12)
    local function hudText(shown) bHud:SetText(shown and "Скрыть HUD" or "Показать HUD") end
    local prev = ns.OnHUDToggled
    ns.OnHUDToggled = function(shown)
        hudText(shown)
        if prev then prev(shown) end
    end
    local bNext = button(main, "Следующая точка", 140, function() ns.HUDNext() end)
    bNext:SetPoint("LEFT", bHud, "RIGHT", 6, 0)
    local bRoute = button(main, "Перестроить маршрут", 160, function() ns.RebuildRoute() end)
    bRoute:SetPoint("LEFT", bNext, "RIGHT", 6, 0)
    local bSession = button(main, "Новая сессия", 120, function()
        ns.ResetSession(); ns.Print("начата новая сессия."); ns.RefreshUI()
    end)
    bSession:SetPoint("LEFT", bRoute, "RIGHT", 6, 0)
    local bScan = button(main, "Скан аукциона", 120, function()
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            ns.ScanResources()
        else
            ns.Print("сначала откройте аукцион у аукциониста.")
        end
    end)
    bScan:SetPoint("LEFT", bSession, "RIGHT", 6, 0)

    main:SetScript("OnShow", function() hudText(ns.IsHUDShown()); selectTab(currentTab) end)
    C_Timer.NewTicker(2, function() if main:IsShown() and currentTab == 1 then fillSummary() end end)
end

function ns.ToggleMain()
    if not main then createMain() end
    main:SetShown(not main:IsShown())
end

function ns.OpenTab(i)
    if not main then createMain() end
    currentTab = i
    if main:IsShown() then selectTab(i) else main:Show() end
end

function ns.ApplyMainScale()
    if main then main:SetScale(ns.settings.mainScale) end
end

--------------------------------------------------------------------
-- Панель на аукционе
--------------------------------------------------------------------
local ahPanel
ns:On("AUCTION_HOUSE_SHOW", function()
    if not ahPanel and AuctionHouseFrame then
        ahPanel = CreateFrame("Frame", nil, AuctionHouseFrame, "BackdropTemplate")
        ahPanel:SetSize(230, 120)
        ahPanel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
        ahPanel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        ahPanel:SetBackdropColor(0, 0, 0, 0.85)
        local t = ahPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("TOP", 0, -8)
        t:SetText("FarmGuide " .. ns.credit)
        local b1 = button(ahPanel, "Скан ресурсов", 200, function() ns.ScanResources() end)
        b1:SetPoint("TOP", 0, -26)
        local b2 = button(ahPanel, "Полный скан (перепродажа)", 200, function() ns.FullScan() end)
        b2:SetPoint("TOP", b1, "BOTTOM", 0, -4)
        ahPanel.status = ahPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ahPanel.status:SetPoint("TOPLEFT", 10, -84)
        ahPanel.status:SetPoint("RIGHT", -10, 0)
        ahPanel.status:SetJustifyH("LEFT")
        ahPanel.status:SetText(ns.scanStatus or "")
        local b3 = button(ahPanel, "Окно FarmGuide", 200, function() ns.ToggleMain() end)
        b3:SetPoint("TOP", ahPanel, "BOTTOM", 0, -2)
    end
end)

ns.OnScanStatus = function(text)
    if ahPanel then ahPanel.status:SetText(text) end
end

--------------------------------------------------------------------
-- Команды
--------------------------------------------------------------------
SLASH_FARMGUIDE1 = "/fg"
SLASH_FARMGUIDE2 = "/farmguide"
SlashCmdList.FARMGUIDE = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "" or cmd == nil then
        ns.ToggleMain()
    elseif cmd == "hud" then
        ns.ToggleHUD()
    elseif cmd == "next" then
        ns.HUDNext()
    elseif cmd == "zoom" then
        local v = tonumber(arg)
        if v and v >= 50 and v <= 3000 then
            ns.settings.hudRadius = v
            ns.Print("радиус HUD: " .. v .. " ярд")
        else
            ns.Print("пример: /fg zoom 300 (от 50 до 3000 ярдов)")
        end
    elseif cmd == "rotate" then
        ns.settings.hudRotate = not ns.settings.hudRotate
        ns.Print("вращение HUD: " .. (ns.settings.hudRotate and "вкл" or "выкл (север сверху)"))
    elseif cmd == "dim" then
        local v = tonumber(arg)
        if v and v >= 0 and v <= 1 then
            ns.settings.hudDim = v
            ns.ToggleHUD(true)
        else
            ns.Print("пример: /fg dim 0.2 (от 0 до 1)")
        end
    elseif cmd == "filter" then
        if arg == "ore" or arg == "herb" or arg == "both" then
            ns.settings.filter = arg
            ns.Print("фильтр маршрута: " .. FILTER_NAME[arg])
        else
            ns.Print("пример: /fg filter ore | herb | both")
        end
    elseif cmd == "profit" then
        local v = tonumber(arg)
        if v and v >= 0 then
            ns.settings.flipMinProfit = v * 10000
            ns.Print("минимальная прибыль сделки: " .. v .. " з")
        else
            ns.Print("пример: /fg profit 200 (в золотых)")
        end
    elseif cmd == "resetzone" then
        if arg == "yes" then
            ns.ResetZone()
        else
            ns.Print("удалить все точки текущей зоны: /fg resetzone yes")
        end
    else
        ns.Print("команды: /fg, /fg hud, /fg next, /fg zoom N, /fg rotate, /fg dim N, /fg filter ore|herb|both, /fg profit N, /fg resetzone yes")
    end
end
