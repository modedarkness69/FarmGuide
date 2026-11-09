local ADDON, ns = ...

local MAX_LINES = 450

local ICONS = {
    ore = "Interface\\Icons\\Trade_Mining",
    herb = "Interface\\Icons\\Trade_Herbalism",
}
local KIND_NAME = { ore = "Руда", herb = "Трава" }

local hud, canvas, textFrame
local lines, dots = {}, {}
local lineIdx, dotIdx = 0, 0
local route, routeMap, target = nil, nil, 1
local acc = 0

local function getLine()
    lineIdx = lineIdx + 1
    local l = lines[lineIdx]
    if not l then
        l = hud:CreateLine(nil, "ARTWORK")
        lines[lineIdx] = l
    end
    l:Show()
    return l
end

local function drawLine(x1, y1, x2, y2, r, g, b, a, th)
    if lineIdx >= MAX_LINES then return end
    local l = getLine()
    l:SetColorTexture(r, g, b, a)
    l:SetThickness(th)
    l:SetStartPoint("CENTER", canvas, x1, y1)
    l:SetEndPoint("CENTER", canvas, x2, y2)
end

local function getDot()
    dotIdx = dotIdx + 1
    local t = dots[dotIdx]
    if not t then
        t = hud:CreateTexture(nil, "OVERLAY")
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dots[dotIdx] = t
    end
    t:Show()
    return t
end

local function drawDot(kind, x, y, size, alpha)
    local t = getDot()
    t:SetTexture(ICONS[kind] or ICONS.ore)
    t:SetSize(size, size)
    t:SetAlpha(alpha or 1)
    t:ClearAllPoints()
    t:SetPoint("CENTER", canvas, "CENTER", x, y)
end

local function hideUnused()
    for i = lineIdx + 1, #lines do lines[i]:Hide() end
    for i = dotIdx + 1, #dots do dots[i]:Hide() end
end

local function drawArrow(x1, y1, x2, y2, r, g, b, th)
    drawLine(x1, y1, x2, y2, r, g, b, 0.95, th)
    local ang = math.atan2(y2 - y1, x2 - x1)
    local len = 12 + th * 2
    for _, off in ipairs({ 2.6, -2.6 }) do
        drawLine(x2, y2, x2 + math.cos(ang + off) * len, y2 + math.sin(ang + off) * len, r, g, b, 0.95, th)
    end
end

local function setText(a, b, c)
    hud.title:SetText(a or "")
    hud.sub:SetText(b or "")
    hud.tip:SetText(c or "")
end

function ns.HUDTip()
    local free = ns.FreeBagSlots()
    if free <= 3 then return "|cffff4040Сумки почти полные: свободно " .. free .. "|r" end
    local tips = ns.GetTips and ns.GetTips(true)
    return tips and tips[1] or ""
end

local function update()
    lineIdx, dotIdx = 0, 0
    local S = ns.settings

    if S.hudHideCombat and UnitAffectingCombat("player") then
        setText()
        return hideUnused()
    end

    local mapID, px, py = ns.GetZonePos()
    if not mapID then
        setText("Нет позиции", "В подземельях и инстансах HUD не работает")
        return hideUnused()
    end

    if mapID ~= routeMap or ns.IsRouteDirty(mapID) then
        local old = route and route[target]
        route = ns.GetRoute(mapID, px, py)
        routeMap = mapID
        target = ns.NearestIndex(route, mapID, px, py)
        if old then
            for i, p in ipairs(route) do if p == old then target = i break end end
        end
    end

    local W, H = ns.MapSize(mapID)
    local half = hud:GetHeight() * S.hudSize * 0.5
    local scale = half / S.hudRadius
    local facing = (S.hudRotate and GetPlayerFacing()) or 0
    local cf, sf = math.cos(facing), math.sin(facing)
    local th = S.hudLine

    local function project(x, y)
        local e = (x - px) * W
        local n = -(y - py) * H
        return (e * cf + n * sf) * scale, (-e * sf + n * cf) * scale
    end
    local function visible(sx, sy)
        return sx * sx + sy * sy < (half * 1.15) ^ 2
    end

    -- игрок
    if S.hudRotate then
        drawArrow(0, -10, 0, 14, 1, 1, 1, math.max(2, th))
    else
        local f = GetPlayerFacing() or 0
        drawArrow(0, 0, -math.sin(f) * 16, math.cos(f) * 16, 1, 1, 1, math.max(2, th))
    end

    local n = #route
    local sess = ns.session
    local value = ns.SessionValue()
    local gph = ns.PerHour(value, sess.active)
    if n == 0 then
        setText("Маршрута пока нет — " .. ns.MapName(mapID),
            "Просто собирайте руду и травы: точки запомнятся, маршрут построится сам", ns.HUDTip())
        return hideUnused()
    end

    -- переключение на следующую точку
    for _ = 1, n do
        local t = route[target]
        if ns.Yards(mapID, px, py, t.x, t.y) < S.reachYards then
            target = target % n + 1
            if S.hudSound and n > 1 then PlaySound(SOUNDKIT.MAP_PING or 3175, "Master") end
        else
            break
        end
    end

    local proj = {}
    for i = 1, n do
        local p = route[i]
        proj[i] = { project(p.x, p.y) }
    end

    -- линия маршрута: ближайшие 6 отрезков после цели ярче
    for i = 1, n do
        local j = i % n + 1
        local a, b = proj[i], proj[j]
        if visible(a[1], a[2]) or visible(b[1], b[2]) then
            if (i - target) % n < 6 then
                drawLine(a[1], a[2], b[1], b[2], 0.2, 1, 0.4, 0.85, th + 1)
            else
                drawLine(a[1], a[2], b[1], b[2], 0.3, 0.75, 1, 0.45, th)
            end
        end
    end

    -- точки
    for i = 1, n do
        local a = proj[i]
        if i ~= target and visible(a[1], a[2]) then
            local p = route[i]
            local recent = p.last and (time() - p.last) < 90
            drawDot(p.k, a[1], a[2], S.hudIcon, recent and 0.35 or 0.9)
        end
    end

    -- цель
    local t = route[target]
    local tx, ty = proj[target][1], proj[target][2]
    local dist = ns.Yards(mapID, px, py, t.x, t.y)
    local d = math.sqrt(tx * tx + ty * ty)
    if d > half then tx, ty = tx / d * half, ty / d * half end
    drawArrow(0, 0, tx, ty, 1, 0.85, 0.1, th + 2)
    drawDot(t.k, tx, ty, S.hudIcon * 1.8, 1)

    if S.hudText then
        setText(string.format("%s · |cffffd200%d ярд|r", KIND_NAME[t.k] or "Точка", dist),
            string.format("Точка %d/%d · сборов: %d · %s · %s/ч", target, n, sess.nodes, ns.Money(value), ns.Money(gph)),
            ns.HUDTip())
    else
        setText()
    end
    hideUnused()
end

function ns.ApplyHUDSettings()
    if not hud then return end
    local S = ns.settings
    hud.bg:SetColorTexture(0, 0, 0, S.hudDim)
    hud:SetAlpha(S.hudAlpha)
    canvas:ClearAllPoints()
    canvas:SetPoint("CENTER", hud, "CENTER", S.hudX, S.hudY)
    textFrame:ClearAllPoints()
    textFrame:SetPoint("TOP", hud, "TOP", S.hudX / S.hudTextScale, S.hudTextY / S.hudTextScale)
    textFrame:SetScale(S.hudTextScale)
    textFrame:SetShown(S.hudText)
end

local function create()
    hud = CreateFrame("Frame", "FarmGuideHUD", UIParent)
    hud:SetAllPoints(UIParent)
    hud:SetFrameStrata("BACKGROUND")
    hud:EnableMouse(false)
    hud:Hide()

    hud.bg = hud:CreateTexture(nil, "BACKGROUND")
    hud.bg:SetAllPoints()

    canvas = CreateFrame("Frame", nil, hud)
    canvas:SetSize(2, 2)

    textFrame = CreateFrame("Frame", nil, hud)
    textFrame:SetSize(800, 90)
    hud.title = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    hud.title:SetPoint("TOP", 0, 0)
    hud.sub = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    hud.sub:SetPoint("TOP", hud.title, "BOTTOM", 0, -6)
    hud.tip = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.tip:SetPoint("TOP", hud.sub, "BOTTOM", 0, -6)

    hud:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.03 then return end
        acc = 0
        local ok, err = pcall(update)
        if not ok then
            hud:Hide()
            geterrorhandler()(err)
        end
    end)
    ns.ApplyHUDSettings()
end

function ns.IsHUDShown()
    return hud and hud:IsShown() or false
end

function ns.ToggleHUD(show)
    if not hud then create() end
    if show == nil then show = not hud:IsShown() end
    ns.ApplyHUDSettings()
    hud:SetShown(show)
    if ns.OnHUDToggled then ns.OnHUDToggled(show) end
end

function ns.HUDNext()
    if route and #route > 0 then target = target % #route + 1 end
end

function ns.ResetHUDRoute()
    route, routeMap = nil, nil
end
