-- ============================================================
--  MI-12 Homer — Trail System
--  lua/entities/ent_mi12_heli/cl_trailsystem.lua
--
--  4 emission points tuned to Mi12_Homer.mdl proportions:
--    Nacelle centers  ≈ Y ±675 at Z 345 (from navigation light positions)
--    Rotor tips       ≈ Y ±710 (RotorRadius) at Z 390 (RotorPos.z)
-- ============================================================

local TRAIL_MATERIAL = Material("trails/smoke")
local SAMPLE_RATE    = 0.025   -- seconds between world-pos samples

local TRAIL_POSITIONS = {
    Vector(109,  675, 345),    -- right nacelle exhaust
    Vector(109, -675, 345),    -- left  nacelle exhaust
    Vector(  0,  710, 390),    -- right rotor tip
    Vector(  0, -710, 390),    -- left  rotor tip
}

-- Tier config: healthy = white vapor, damage = dark smoke
local TIER_CONFIG = {
    [0] = { r = 255, g = 255, b = 255, a = 110, startSize = 24, endSize =  5, lifetime = 4 },
    [1] = { r = 170, g = 170, b = 170, a = 150, startSize = 36, endSize =  9, lifetime = 5 },
    [2] = { r =  55, g =  55, b =  55, a = 195, startSize = 52, endSize = 15, lifetime = 6 },
    [3] = { r =  12, g =  12, b =  12, a = 225, startSize = 72, endSize = 24, lifetime = 8 },
}

local PlaneTrails = {}

-- PUBLIC: called from cl_init.lua net.Receive
function TrailSystem_SetTier(entIndex, tier)
    local state = PlaneTrails[entIndex]
    if state then state.tier = tier end
end

local function EnsureRegistered(entIndex)
    if PlaneTrails[entIndex] then return end
    local trails = {}
    for i = 1, #TRAIL_POSITIONS do
        trails[i] = { positions = {} }
    end
    PlaneTrails[entIndex] = {
        tier       = 0,
        nextSample = 0,
        trails     = trails,
    }
end

local function DrawBeam(positions, cfg)
    local n    = #positions
    if n < 2 then return end
    local Time = CurTime()
    local lt   = cfg.lifetime

    -- Prune expired samples
    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove(positions, i)
        end
    end

    n = #positions
    if n < 2 then return end

    render.SetMaterial(TRAIL_MATERIAL)
    render.StartBeam(n)
    for _, pd in ipairs(positions) do
        local scale = math.Clamp((pd.time + lt - Time) / lt, 0, 1)
        local size  = cfg.startSize * scale + cfg.endSize * (1 - scale)
        render.AddBeam(pd.pos, size, pd.time * 50,
            Color(cfg.r, cfg.g, cfg.b, cfg.a * scale * scale))
    end
    render.EndBeam()
end

-- Sample world positions each SAMPLE_RATE
hook.Add("Think", "bombin_mi12_trails_update", function()
    local Time = CurTime()

    for _, ent in ipairs(ents.FindByClass("ent_mi12_heli")) do
        EnsureRegistered(ent:EntIndex())
    end

    for entIndex, state in pairs(PlaneTrails) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            PlaneTrails[entIndex] = nil
            continue
        end
        if Time < state.nextSample then continue end
        state.nextSample = Time + SAMPLE_RATE

        local pos = ent:GetPos()
        local ang = ent:GetAngles()
        for i, trail in ipairs(state.trails) do
            local wpos = LocalToWorld(TRAIL_POSITIONS[i], Angle(0, 0, 0), pos, ang)
            table.insert(trail.positions, 1, { time = Time, pos = wpos })
        end
    end
end)

-- Render beams
hook.Add("PostDrawTranslucentRenderables", "bombin_mi12_trails_draw", function(bDepth, bSkybox)
    if bSkybox then return end
    for _, state in pairs(PlaneTrails) do
        local cfg = TIER_CONFIG[state.tier] or TIER_CONFIG[0]
        for _, trail in ipairs(state.trails) do
            DrawBeam(trail.positions, cfg)
        end
    end
end)
