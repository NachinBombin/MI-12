-- ============================================================
--  MI-12 Homer — Client FX + Rotor Animation
--  lua/entities/ent_mi12_heli/cl_init.lua
-- ============================================================

include("shared.lua")
include("cl_trailsystem.lua")

game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- ============================================================
--  DAMAGE TIER FIRE OFFSETS  (model-local, X=right, Y=fwd, Z=up)
-- ============================================================
local TIER_OFFSETS = {
    [1] = {
        Vector(0, 0, 60),
    },
    [2] = {
        Vector(0,    0,  60),
        Vector( 110,  0,  20),
        Vector(-110,  0,  20),
    },
    [3] = {
        Vector(0,    0,  60),
        Vector( 100,  0,  20),
        Vector(-100,  0,  20),
        Vector(0,   160,  30),
        Vector(0,  -160,  30),
        Vector(0,    0, -20),
    },
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local PlaneStates = {}

-- ============================================================
--  BURST EFFECTS
-- ============================================================
local function BurstAt(wPos, tier)
    local ed = EffectData()
    ed:SetOrigin(wPos)
    ed:SetScale(tier == 3 and math.Rand(0.8, 1.4) or math.Rand(0.4, 0.9))
    ed:SetMagnitude(1)
    ed:SetRadius(tier * 20)
    util.Effect("Explosion", ed)

    local ed2 = EffectData()
    ed2:SetOrigin(wPos)
    ed2:SetNormal(Vector(0, 0, 1))
    ed2:SetScale(tier * 0.3)
    ed2:SetMagnitude(tier * 0.4)
    ed2:SetRadius(18)
    util.Effect("ManhackSparks", ed2)

    if tier >= 2 then
        local ed3 = EffectData()
        ed3:SetOrigin(wPos)
        ed3:SetNormal(VectorRand())
        ed3:SetScale(0.6)
        util.Effect("ElectricSpark", ed3)
    end
end

local function SpawnBurstFX(ent, count, tier)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    for _ = 1, count do
        local wPos = LocalToWorld(
            Vector(math.Rand(-100, 100), math.Rand(-140, 80), math.Rand(0, 55)),
            Angle(0, 0, 0), pos, ang
        )
        BurstAt(wPos, tier)
    end
    if tier == 3 then
        for _, side in ipairs({ Vector(130, 0, 0), Vector(-130, 0, 0) }) do
            local wPos = LocalToWorld(side, Angle(0, 0, 0), pos, ang)
            local ed = EffectData()
            ed:SetOrigin(wPos) ed:SetScale(0.7) ed:SetMagnitude(1) ed:SetRadius(30)
            util.Effect("Explosion", ed)
        end
    end
end

-- ============================================================
--  PARTICLE MANAGEMENT
-- ============================================================
local function StopParticles(state)
    if not state.particles then return end
    for _, p in ipairs(state.particles) do
        if IsValid(p) then p:StopEmission() end
    end
    state.particles = {}
end

local function ApplyFlameParticles(ent, state, tier)
    StopParticles(state)
    state.tier = tier
    if not IsValid(ent) or tier == 0 then return end
    for _, off in ipairs(TIER_OFFSETS[tier]) do
        local p = ent:CreateParticleEffect("fire_medium_02", PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(off))
            table.insert(state.particles, p)
        end
    end
    state.nextBurst = CurTime() + (TIER_BURST_DELAY[tier] or 4)
end

-- ============================================================
--  NET — damage tier broadcast
-- ============================================================
net.Receive("bombin_mi12_damage_tier", function()
    local entIndex = net.ReadUInt(16)
    local tier     = net.ReadUInt(2)
    local ent      = Entity(entIndex)

    TrailSystem_SetTier(entIndex, tier)

    local state = PlaneStates[entIndex]
    if not state then
        state = { tier = 0, particles = {}, nextBurst = 0 }
        PlaneStates[entIndex] = state
    end

    if state.tier == tier then return end

    if IsValid(ent) then
        ApplyFlameParticles(ent, state, tier)
        if tier > 0 then SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1, tier) end
    else
        state.tier         = tier
        state.pendingApply = true
    end
end)

-- ============================================================
--  THINK — particle CP updates + burst scheduling
-- ============================================================
hook.Add("Think", "bombin_mi12_damage_fx", function()
    local ct = CurTime()
    for entIndex, state in pairs(PlaneStates) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            StopParticles(state)
            PlaneStates[entIndex] = nil
        else
            if state.pendingApply then
                state.pendingApply = false
                ApplyFlameParticles(ent, state, state.tier)
            end

            if state.tier > 0 then
                local pos     = ent:GetPos()
                local ang     = ent:GetAngles()
                local offsets = TIER_OFFSETS[state.tier]
                for i, p in ipairs(state.particles) do
                    if IsValid(p) and offsets[i] then
                        p:SetControlPoint(0, LocalToWorld(offsets[i], Angle(0, 0, 0), pos, ang))
                    end
                end
                if ct >= state.nextBurst then
                    SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1, state.tier)
                    state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
                end
            end
        end
    end
end)

-- ============================================================
--  ROTOR ANIMATION
--  RPM is locked to ENT.LimitRPM (3000) at all times.
--  Bone indices verified from LFS Mi-12 cl_init.lua.
-- ============================================================
local RPM_FULL  = ENT.LimitRPM or 3000
local RPM_MAX   = ENT.LimitRPM or 3000

-- At 100% RPM:
--   Bend1 = math.Remap(3000, 0, 3000, 0, 10) = 10
--   Bend2 = math.Remap(3000, 0, 3000, 0,  4) = 4
--   Bend3 (droop) = math.Remap(3000, 0, 3000, 55, 0) = 0
local BEND1  = math.Remap(RPM_FULL, 0, RPM_MAX, 0, 10)   -- = 10
local BEND2  = math.Remap(RPM_FULL, 0, RPM_MAX, 0,  4)   -- = 4
local DROOP  = math.Remap(RPM_FULL, 0, RPM_MAX, 55, 0)   -- = 0

local RotorAcc = {}   -- [entIndex] = accumulated rotor angle (for pose param)

local function AnimRotor(ent, idx)
    if not IsValid(ent) then return end

    RotorAcc[idx] = (RotorAcc[idx] or 0) + RPM_FULL * FrameTime() * 1.5

    -- Rotor A — 10 blade arm bones (33–42)
    -- Alternating: odd = BEND1, even = BEND2
    ent:ManipulateBoneAngles(33, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(34, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(35, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(36, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(37, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(38, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(39, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(40, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(41, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(42, Angle(0, 0, BEND2))

    -- Rotor B — 10 blade arm bones (45–54)
    ent:ManipulateBoneAngles(45, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(46, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(47, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(48, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(49, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(50, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(51, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(52, Angle(0, 0, BEND2))
    ent:ManipulateBoneAngles(53, Angle(0, 0, BEND1))
    ent:ManipulateBoneAngles(54, Angle(0, 0, BEND2))

    -- Hub droop arms (bones 12, 13) — 0 at full RPM
    ent:ManipulateBoneAngles(12, Angle( DROOP, 0, 0))
    ent:ManipulateBoneAngles(13, Angle(-DROOP, 0, 0))

    -- Bodygroups: always full-RPM blur disc
    ent:SetBodygroup(2, 1)
    ent:SetBodygroup(3, 1)

    -- Drive rotor spin pose parameter
    ent:SetPoseParameter("rotor_spin", RotorAcc[idx])
    ent:InvalidateBoneCache()
end

hook.Add("Think", "bombin_mi12_rotor_anim", function()
    for _, ent in ipairs(ents.FindByClass("ent_mi12_heli")) do
        local idx = ent:EntIndex()
        AnimRotor(ent, idx)
        if not IsValid(ent) then
            RotorAcc[idx] = nil
        end
    end
end)
