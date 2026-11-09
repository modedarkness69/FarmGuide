local ADDON, ns = ...

--------------------------------------------------------------------
-- Виджеты
--------------------------------------------------------------------
local function Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    return fs
end

-- ползунок: get/set работают со значением настройки, fmt — подпись
local function Slider(parent, label, minV, maxV, step, get, set, fmt)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(300, 16)
    s:SetHitRectInsets(0, 0, -8, -8)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)

    s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 2, 2)
    s.label:SetText(label)
    s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", -2, 2)

    local function show(v) s.value:SetText(fmt and fmt(v) or tostring(v)) end

    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not self.updating then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetValue() + delta * step
        self:SetValue(math.max(minV, math.min(maxV, v)))
    end)
    function s:Refresh()
        self.updating = true
        local v = get()
        self:SetValue(v)
        show(v)
        self.updating = false
    end
    return s
end

local function Check(parent, label, get, set)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.label:SetText(label)
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    function c:Refresh() self:SetChecked(get() and true or false) end
    return c
end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function pctFmt(v) return math.floor(v * 100 + 0.5) .. "%" end
local function yardFmt(v) return v .. " ярд" end
local function pxFmt(v) return v .. " px" end

local function S() return ns.settings end

--------------------------------------------------------------------
-- Вкладка «HUD»
--------------------------------------------------------------------
local hudWidgets = {}

local function hudSetter(key)
    return function(v)
        S()[key] = v
        ns.ApplyHUDSettings()
    end
end
local function getter(key) return function() return S()[key] end end

function ns.BuildHUDPanel(p)
    local w = hudWidgets
    local h1 = Header(p, "Отображение")
    h1:SetPoint("TOPLEFT", 8, -4)
    local h2 = Header(p, "Положение и текст")
    h2:SetPoint("TOPLEFT", 356, -4)

    local left = {
        Slider(p, "Дальность прорисовки", 50, 2000, 25, getter("hudRadius"), hudSetter("hudRadius"), yardFmt),
        Slider(p, "Размер HUD (доля экрана)", 0.3, 1.2, 0.05, getter("hudSize"), hudSetter("hudSize"), pctFmt),
        Slider(p, "Прозрачность HUD", 0.1, 1, 0.05, getter("hudAlpha"), hudSetter("hudAlpha"), pctFmt),
        Slider(p, "Затемнение фона", 0, 0.8, 0.05, getter("hudDim"), hudSetter("hudDim"), pctFmt),
        Slider(p, "Толщина линий", 1, 8, 1, getter("hudLine"), hudSetter("hudLine"), pxFmt),
        Slider(p, "Размер иконок точек", 10, 40, 1, getter("hudIcon"), hudSetter("hudIcon"), pxFmt),
    }
    local right = {
        Slider(p, "Сдвиг по горизонтали", -600, 600, 10, getter("hudX"), hudSetter("hudX"), pxFmt),
        Slider(p, "Сдвиг по вертикали", -400, 400, 10, getter("hudY"), hudSetter("hudY"), pxFmt),
        Slider(p, "Размер текста", 0.5, 2, 0.05, getter("hudTextScale"), hudSetter("hudTextScale"), pctFmt),
        Slider(p, "Высота текста от верха экрана", -600, -20, 10,
            function() return S().hudTextY end, hudSetter("hudTextY"),
            function(v) return -v .. " px" end),
        Slider(p, "Точка взята, если ближе чем", 10, 80, 5, getter("reachYards"), hudSetter("reachYards"), yardFmt),
    }
    for i, s in ipairs(left) do
        s:SetPoint("TOPLEFT", 12, -44 - (i - 1) * 44)
        w[#w + 1] = s
    end
    for i, s in ipairs(right) do
        s:SetPoint("TOPLEFT", 360, -44 - (i - 1) * 44)
        w[#w + 1] = s
    end

    local checks = {
        Check(p, "Показывать HUD", function() return ns.IsHUDShown() end, function(v) ns.ToggleHUD(v) end),
        Check(p, "Вращать вместе с персонажем", getter("hudRotate"), hudSetter("hudRotate")),
        Check(p, "Показывать текст и подсказки", getter("hudText"), hudSetter("hudText")),
        Check(p, "Прятать HUD в бою", getter("hudHideCombat"), hudSetter("hudHideCombat")),
        Check(p, "Звук при взятии точки", getter("hudSound"), hudSetter("hudSound")),
    }
    for i, c in ipairs(checks) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        c:SetPoint("TOPLEFT", 8 + col * 225, -312 - row * 28)
        w[#w + 1] = c
    end

    local reset = ns.ConfirmButton(p, "Сбросить настройки HUD", 220, function()
        ns.ResetSettings("hud")
        ns.ApplyHUDSettings()
        ns.RefreshHUDPanel()
    end)
    reset:SetPoint("BOTTOMRIGHT", -8, 4)
end

function ns.RefreshHUDPanel()
    for _, wdg in ipairs(hudWidgets) do wdg:Refresh() end
end

--------------------------------------------------------------------
-- Вкладка «Настройки»
--------------------------------------------------------------------
local setWidgets = {}
local filterButtons = {}
local FILTERS = { { "both", "Руда и травы" }, { "ore", "Только руда" }, { "herb", "Только травы" } }

local function refreshFilters()
    for _, b in ipairs(filterButtons) do
        if S().filter == b.key then b:LockHighlight() else b:UnlockHighlight() end
    end
end

function ns.BuildSettingsPanel(p)
    local w = setWidgets

    -- маршрут
    local h1 = Header(p, "Маршрут")
    h1:SetPoint("TOPLEFT", 8, -4)
    local fl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fl:SetPoint("TOPLEFT", 12, -30)
    fl:SetText("Что собирать:")
    for i, f in ipairs(FILTERS) do
        local b = Button(p, f[2], 106, function()
            S().filter = f[1]
            refreshFilters()
            ns.Print("фильтр маршрута: " .. f[2])
        end)
        b.key = f[1]
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 110, -46)
        filterButtons[i] = b
    end

    local merge = Slider(p, "Радиус слияния точек", 5, 60, 5, getter("mergeYards"),
        function(v) S().mergeYards = v end, yardFmt)
    merge:SetPoint("TOPLEFT", 12, -98)
    w[#w + 1] = merge

    local bRebuild = Button(p, "Перестроить маршрут", 160, function() ns.RebuildRoute() end)
    bRebuild:SetPoint("TOPLEFT", 10, -130)
    local bNext = Button(p, "Следующая точка", 160, function() ns.HUDNext() end)
    bNext:SetPoint("LEFT", bRebuild, "RIGHT", 6, 0)
    local bZone = ns.ConfirmButton(p, "Удалить точки этой зоны", 326, function() ns.ResetZone() end)
    bZone:SetPoint("TOPLEFT", 10, -160)

    -- прочее
    local h3 = Header(p, "Прочее")
    h3:SetPoint("TOPLEFT", 8, -200)
    local mm = Check(p, "Кнопка у мини-карты", function() return not S().minimapHide end, function(v)
        S().minimapHide = not v
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    end)
    mm:SetPoint("TOPLEFT", 8, -226)
    w[#w + 1] = mm
    local scale = Slider(p, "Масштаб окна FarmGuide", 0.6, 1.5, 0.05, getter("mainScale"),
        function(v) S().mainScale = v; ns.ApplyMainScale() end, pctFmt)
    scale:SetPoint("TOPLEFT", 12, -280)
    w[#w + 1] = scale
    local bSession = Button(p, "Новая сессия", 160, function()
        ns.ResetSession(); ns.Print("начата новая сессия.")
    end)
    bSession:SetPoint("TOPLEFT", 10, -312)

    -- аукцион
    local h2 = Header(p, "Аукцион")
    h2:SetPoint("TOPLEFT", 356, -4)
    local profit = Slider(p, "Минимальная прибыль сделки", 10, 5000, 10,
        function() return math.floor(S().flipMinProfit / 10000) end,
        function(v) S().flipMinProfit = v * 10000 end,
        function(v) return v .. " з" end)
    profit:SetPoint("TOPLEFT", 360, -50)
    local cheap = Slider(p, "Ресурс дешёвый, если ниже рынка на", 10, 60, 5, getter("cheapPct"),
        function(v) S().cheapPct = v end, function(v) return v .. "%" end)
    cheap:SetPoint("TOPLEFT", 360, -94)
    local flip = Slider(p, "Предмет — сделка, если дешевле на", 20, 80, 5, getter("flipPct"),
        function(v) S().flipPct = v end, function(v) return v .. "%" end)
    flip:SetPoint("TOPLEFT", 360, -138)
    w[#w + 1] = profit; w[#w + 1] = cheap; w[#w + 1] = flip

    local note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 360, -166)
    note:SetWidth(300)
    note:SetJustifyH("LEFT")
    note:SetText("Пороги применяются при следующем скане. Сканы запускаются кнопками на панели у окна аукциона.")

    local bScanR = Button(p, "Скан ресурсов", 148, function()
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then ns.ScanResources()
        else ns.Print("сначала откройте аукцион у аукциониста.") end
    end)
    bScanR:SetPoint("TOPLEFT", 358, -200)
    local bScanF = Button(p, "Полный скан", 148, function()
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then ns.FullScan()
        else ns.Print("сначала откройте аукцион у аукциониста.") end
    end)
    bScanF:SetPoint("LEFT", bScanR, "RIGHT", 6, 0)

    local reset = ns.ConfirmButton(p, "Сбросить все настройки", 220, function()
        ns.ResetSettings()
        ns.ApplyHUDSettings()
        ns.ApplyMainScale()
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
        ns.RefreshSettingsPanel()
    end)
    reset:SetPoint("BOTTOMRIGHT", -8, 4)
end

function ns.RefreshSettingsPanel()
    for _, wdg in ipairs(setWidgets) do wdg:Refresh() end
    refreshFilters()
end

--------------------------------------------------------------------
-- Кнопка у мини-карты
--------------------------------------------------------------------
local mmButton

local function updatePosition()
    local a = math.rad(S().minimapAngle)
    local r = Minimap:GetWidth() / 2 + 5
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function onClick(_, btn)
    if btn == "RightButton" then
        ns.OpenTab(5)
    elseif IsShiftKeyDown() or btn == "MiddleButton" then
        ns.ToggleHUD()
    else
        ns.ToggleMain()
    end
end

local function tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddDoubleLine("|cff33ff99FarmGuide|r", ns.credit)
    local mapID = ns.GetZonePos()
    if mapID then
        local m = ns.db.maps[mapID]
        GameTooltip:AddLine(ns.MapName(mapID) .. ": точек " .. (m and #m.nodes or 0), 1, 1, 1)
    end
    local s = ns.session
    GameTooltip:AddLine("Сессия: " .. ns.Money(ns.SessionValue()) .. " · " ..
        ns.Money(ns.PerHour(ns.SessionValue(), s.active)) .. "/ч", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("ЛКМ — окно", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("ПКМ — настройки HUD", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift+ЛКМ или колесо — HUD вкл/выкл", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Перетащите, чтобы передвинуть", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function createMinimapButton()
    mmButton = CreateFrame("Button", "FarmGuideMinimapButton", Minimap)
    mmButton:SetSize(31, 31)
    mmButton:SetFrameStrata("MEDIUM")
    mmButton:SetFrameLevel(8)
    mmButton:RegisterForClicks("AnyUp")
    mmButton:RegisterForDrag("LeftButton")
    mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = mmButton:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = mmButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = mmButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    mmButton:SetScript("OnClick", onClick)
    mmButton:SetScript("OnEnter", tooltip)
    mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mmButton:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            cx, cy = cx / sc, cy / sc
            S().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            updatePosition()
        end)
    end)
    mmButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    updatePosition()
end

function ns.UpdateMinimapButton()
    if not mmButton then createMinimapButton() end
    mmButton:SetShown(not S().minimapHide)
    updatePosition()
end

--------------------------------------------------------------------
-- Меню аддонов Blizzard и системные настройки
--------------------------------------------------------------------
function FarmGuide_OnAddonCompartmentClick(_, btn)
    onClick(nil, btn)
end

function FarmGuide_OnAddonCompartmentEnter(_, frame)
    tooltip(frame)
end

function FarmGuide_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local function registerBlizzardSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FarmGuide")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetText("Версия " .. ns.version .. " · " .. ns.credit .. "\nВсе настройки находятся в окне аддона.")
    text:SetJustifyH("LEFT")
    local b = Button(panel, "Открыть настройки FarmGuide", 260, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.OpenTab(6)
    end)
    b:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "FarmGuide")
    Settings.RegisterAddOnCategory(cat)
end

table.insert(ns.onLogin, function()
    ns.UpdateMinimapButton()
    local ok, err = pcall(registerBlizzardSettings)
    if not ok then geterrorhandler()(err) end
end)
