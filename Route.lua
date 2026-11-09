local ADDON, ns = ...

local MAX_POINTS = 400
local cache = {}

local function filtered(m, filter)
    local pts = {}
    for _, n in ipairs(m.nodes) do
        if filter == "both" or n.k == filter then pts[#pts + 1] = n end
    end
    -- если точек слишком много — оставляем самые «урожайные»
    if #pts > MAX_POINTS then
        table.sort(pts, function(a, b) return a.c > b.c end)
        for i = #pts, MAX_POINTS + 1, -1 do pts[i] = nil end
    end
    return pts
end

-- кратчайший замкнутый маршрут: ближайший сосед + 2-opt
local function solve(pts, W, H, sx, sy)
    local n = #pts
    if n < 3 then return pts end
    local function d(a, b)
        local dx, dy = (a.x - b.x) * W, (a.y - b.y) * H
        return math.sqrt(dx * dx + dy * dy)
    end

    local start, bestD = 1, math.huge
    for i, p in ipairs(pts) do
        local dx, dy = (p.x - sx) * W, (p.y - sy) * H
        local dd = dx * dx + dy * dy
        if dd < bestD then start, bestD = i, dd end
    end

    local used, order = {}, { pts[start] }
    used[start] = true
    for _ = 2, n do
        local last = order[#order]
        local bi, bd = nil, math.huge
        for i, p in ipairs(pts) do
            if not used[i] then
                local dd = d(last, p)
                if dd < bd then bi, bd = i, dd end
            end
        end
        used[bi] = true
        order[#order + 1] = pts[bi]
    end

    for _ = 1, 8 do
        local improved = false
        for i = 1, n - 2 do
            for j = i + 2, n do
                if not (i == 1 and j == n) then
                    local a, b = order[i], order[i + 1]
                    local c, e = order[j], order[j % n + 1]
                    if d(a, c) + d(b, e) < d(a, b) + d(c, e) - 0.01 then
                        local lo, hi = i + 1, j
                        while lo < hi do
                            order[lo], order[hi] = order[hi], order[lo]
                            lo, hi = lo + 1, hi - 1
                        end
                        improved = true
                    end
                end
            end
        end
        if not improved then break end
    end
    return order
end

function ns.RouteLength(route, mapID)
    local n, len = #route, 0
    if n < 2 then return 0 end
    for i = 1, n do
        local a, b = route[i], route[i % n + 1]
        len = len + ns.Yards(mapID, a.x, a.y, b.x, b.y)
    end
    return len
end

function ns.IsRouteDirty(mapID)
    local c = cache[mapID]
    return not c or ns.routeDirty[mapID] or c.filter ~= ns.settings.filter
end

function ns.GetRoute(mapID, px, py)
    local c = cache[mapID]
    if c and not ns.IsRouteDirty(mapID) then return c.route end
    local m = ns.GetMap(mapID)
    local W, H = ns.MapSize(mapID)
    local route = solve(filtered(m, ns.settings.filter), W, H, px or 0.5, py or 0.5)
    cache[mapID] = { route = route, filter = ns.settings.filter }
    ns.routeDirty[mapID] = nil
    return route
end

function ns.InvalidateRoute(mapID)
    if mapID then cache[mapID] = nil else wipe(cache) end
end

function ns.NearestIndex(route, mapID, px, py)
    local bi, bd = 1, math.huge
    for i, p in ipairs(route) do
        local dd = ns.Yards(mapID, px, py, p.x, p.y)
        if dd < bd then bi, bd = i, dd end
    end
    return bi
end
