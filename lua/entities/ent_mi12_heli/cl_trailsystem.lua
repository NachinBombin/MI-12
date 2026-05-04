-- ============================================================
-- TRAIL SYSTEM  --  MI-12 framework
-- Ported from AN-71. Same algorithm; emission points updated
-- to match dual-rotor helicopter layout.
-- TODO: re-tune TRAIL_POSITIONS once MI-12 model is imported.
-- ============================================================

local TRAIL_MATERIAL = Material( "trails/smoke" )

local SAMPLE_RATE = 0.025

-- Emission points in model-local space.
-- MI-12 has two large rotor hubs + two engine exhausts on the fuselage.
-- Placeholder values -- MUST be updated after model import.
local TRAIL_POSITIONS = {
    Vector( 200,    0,   50 ),  -- front rotor hub
    Vector(-200,    0,   50 ),  -- rear rotor hub (MI-12 tandem layout)
    Vector(  50,  -80,   -5 ),  -- right engine exhaust
    Vector( -50,  -80,   -5 ),  -- left engine exhaust
}

local TIER_CONFIG = {
    [0] = { r = 255, g = 255, b = 255, a = 100, startSize = 20, endSize =  4, lifetime = 4 },
    [1] = { r = 170, g = 170, b = 170, a = 150, startSize = 32, endSize =  8, lifetime = 5 },
    [2] = { r =  55, g =  55, b =  55, a = 195, startSize = 48, endSize = 14, lifetime = 6 },
    [3] = { r =  12, g =  12, b =  12, a = 225, startSize = 68, endSize = 22, lifetime = 8 },
}

local PlaneTrails = {}

function TrailSystem_SetTier( entIndex, tier )
    local state = PlaneTrails[entIndex]
    if not state then return end
    state.tier = tier
end

local function EnsureRegistered( entIndex )
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

local function DrawBeam( positions, cfg )
    local n = #positions
    if n < 2 then return end

    local Time = CurTime()
    local lt   = cfg.lifetime

    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove( positions, i )
        end
    end

    n = #positions
    if n < 2 then return end

    render.SetMaterial( TRAIL_MATERIAL )
    render.StartBeam( n )
    for _, pd in ipairs( positions ) do
        local Scale = math.Clamp( (pd.time + lt - Time) / lt, 0, 1 )
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam( pd.pos, size, pd.time * 50,
            Color( cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale ) )
    end
    render.EndBeam()
end

hook.Add( "Think", "bombin_mi12_trails_update", function()
    local Time = CurTime()

    for _, ent in ipairs( ents.FindByClass( "ent_mi12_heli" ) ) do
        EnsureRegistered( ent:EntIndex() )
    end

    for entIndex, state in pairs( PlaneTrails ) do
        local ent = Entity( entIndex )
        if not IsValid( ent ) then
            PlaneTrails[entIndex] = nil
            continue
        end

        if Time < state.nextSample then continue end
        state.nextSample = Time + SAMPLE_RATE

        local pos = ent:GetPos()
        local ang = ent:GetAngles()

        for i, trail in ipairs( state.trails ) do
            local wpos = LocalToWorld( TRAIL_POSITIONS[i], Angle(0,0,0), pos, ang )
            table.insert( trail.positions, { time = Time, pos = wpos } )
            table.sort( trail.positions, function( a, b ) return a.time > b.time end )
        end
    end
end )

hook.Add( "PostDrawTranslucentRenderables", "bombin_mi12_trails_draw", function( bDepth, bSkybox )
    if bSkybox then return end

    for _, state in pairs( PlaneTrails ) do
        local cfg = TIER_CONFIG[ state.tier ] or TIER_CONFIG[0]
        for _, trail in ipairs( state.trails ) do
            DrawBeam( trail.positions, cfg )
        end
    end
end )
