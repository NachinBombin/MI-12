-- ============================================================
--  MI-12 Homer — Client FX + Rotor Animation
--  lua/entities/ent_mi12_heli/cl_init.lua
--
--  PORT from C-17 Globemaster III:
--    • Persistent vapor emitter that follows the craft every frame
--      (replaces the one-shot EmitCondensationCloud snapshot)
--    • Dynamic pulsing cargo light during door open (UpdateCargoLight)
-- ============================================================

include("shared.lua")
include("cl_trailsystem.lua")

game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- ============================================================
--  DAMAGE TIER FIRE OFFSETS
-- ============================================================
local TIER_OFFSETS = {
    [1] = { Vector(0, 0, 60) },
    [2] = { Vector(0, 0, 60), Vector(110, 0, 20), Vector(-110, 0, 20) },
    [3] = { Vector(0, 0, 60), Vector(100, 0, 20), Vector(-100, 0, 20),
            Vector(0, 160, 30), Vector(0, -160, 30), Vector(0, 0, -20) },
}
local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local PlaneStates = {}

-- ============================================================
--  VAPOR / CONDENSATION CONFIG  (ported from C-17)
--  Emitter is kept alive and fed new particles every frame while
--  the door is open, so the origin always follows the helicopter.
-- ============================================================
local VAPOR_DURATION   = 1.8   -- seconds vapor lasts after door opens
local VAPOR_LOCAL      = Vector(-700, 0, -60)  -- tail ramp local offset
local VAPOR_PER_FRAME  = 5
local VAPOR_LIFETIME   = 1.6
local VAPOR_SIZE_START = 70
local VAPOR_SIZE_END   = 220
local VAPOR_SPEED      = 60    -- rearward m/s
local VAPOR_SPRITE     = "particle/particle_smokegrenade"

-- ============================================================
--  CARGO DOOR DYNAMIC LIGHT  (ported from C-17)
-- ============================================================
local CARGO_LIGHT_LOCAL    = Vector(-700, 0, -60)  -- same as vapor origin
local CARGO_LIGHT_RADIUS   = 1200
local CARGO_LIGHT_DECAY    = 1000
local CARGO_LIGHT_MIN_BRIG = 0.3
local CARGO_LIGHT_MAX_BRIG = 1.0
local CARGO_LIGHT_PULSE_HZ = 0.5  -- pulses per second

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
--  NET — door event
--  On open:  start persistent vapor emitter (follows craft each frame)
--  On close: stop emitter
-- ============================================================
net.Receive("MI12_DoorEvent", function()
    local ent    = net.ReadEntity()
    local isOpen = net.ReadBool()
    if not IsValid(ent) then return end

    if isOpen then
        -- Start (or restart) the persistent vapor emitter
        if ent._MI12VaporEmitter then
            ent._MI12VaporEmitter:Finish()
        end
        local worldPos = LocalToWorld(VAPOR_LOCAL, Angle(0, 0, 0), ent:GetPos(), ent:GetAngles())
        ent._MI12VaporEmitter = ParticleEmitter(worldPos, true)
        ent._MI12VaporUntil   = CurTime() + VAPOR_DURATION
        ent._MI12DoorOpen     = true
    else
        ent._MI12DoorOpen = false
        -- Let the emitter drain naturally; stop feeding it in Think
    end
end)

-- ============================================================
--  NET — damage tier
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
                        p:SetControlPoint(0, LocalToWorld(offsets[i], Angle(0,0,0), pos, ang))
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
--  THINK — persistent vapor emitter (follows craft each frame)
--          ported from C-17 ENT:UpdateVapor()
-- ============================================================
hook.Add("Think", "bombin_mi12_vapor_update", function()
    local ct = CurTime()
    for _, ent in ipairs(ents.FindByClass("ent_mi12_heli")) do
        if not IsValid(ent) then continue end
        local emitter = ent._MI12VaporEmitter
        if not emitter then continue end

        -- Let emitter expire naturally once VAPOR_DURATION has passed
        if ct >= (ent._MI12VaporUntil or 0) then
            emitter:Finish()
            ent._MI12VaporEmitter = nil
            continue
        end

        -- Re-evaluate world origin every frame so it sticks to the craft
        local worldPos = LocalToWorld(VAPOR_LOCAL, Angle(0, 0, 0), ent:GetPos(), ent:GetAngles())
        local rearDir  = ent:LocalToWorldAngles(Angle(5, 180, 0)):Forward()

        for _ = 1, VAPOR_PER_FRAME do
            local p = emitter:Add(VAPOR_SPRITE, worldPos)
            if p then
                local shade = math.random(210, 255)
                p:SetColor(shade, shade, shade)
                p:SetStartAlpha(math.random(160, 200))
                p:SetEndAlpha(0)
                p:SetStartSize(VAPOR_SIZE_START + math.Rand(-8, 8))
                p:SetEndSize(VAPOR_SIZE_END + math.Rand(-20, 20))
                p:SetLifeTime(0)
                p:SetDieTime(VAPOR_LIFETIME + math.Rand(-0.2, 0.4))
                p:SetLighting(false)
                local scatter = Vector(
                    math.Rand(-40, 40),
                    math.Rand(-40, 40),
                    math.Rand(-12, 20)
                )
                p:SetVelocity(rearDir * VAPOR_SPEED + scatter)
                p:SetGravity(Vector(0, 0, 14))
                p:SetRoll(math.Rand(0, 360))
                p:SetRollDelta(math.Rand(-1.2, 1.2))
                p:SetAirResistance(80)
            end
        end
    end
end)

-- ============================================================
--  THINK — dynamic pulsing cargo light during door open
--          ported from C-17 ENT:UpdateCargoLight()
-- ============================================================
hook.Add("Think", "bombin_mi12_cargo_light", function()
    for _, ent in ipairs(ents.FindByClass("ent_mi12_heli")) do
        if not IsValid(ent) then continue end
        if not ent._MI12DoorOpen then continue end

        local dl = DynamicLight(ent:EntIndex() + 4096)
        if not dl then continue end

        local t      = CurTime() * CARGO_LIGHT_PULSE_HZ * math.pi * 2
        local frac   = (math.sin(t) + 1) * 0.5
        local bright = CARGO_LIGHT_MIN_BRIG + frac * (CARGO_LIGHT_MAX_BRIG - CARGO_LIGHT_MIN_BRIG)

        local worldPos = LocalToWorld(CARGO_LIGHT_LOCAL, Angle(0, 0, 0), ent:GetPos(), ent:GetAngles())
        dl.pos        = worldPos
        dl.r          = 255
        dl.g          = 20
        dl.b          = 10
        dl.brightness = bright * 10
        dl.decay      = CARGO_LIGHT_DECAY
        dl.size       = CARGO_LIGHT_RADIUS
        dl.dietime    = CurTime() + 0.1
    end
end)

-- ============================================================
--  ROTOR ANIMATION
-- ============================================================
local RPM_FULL = ENT.LimitRPM or 3000
local RPM_MAX  = ENT.LimitRPM or 3000
local BEND1    = math.Remap(RPM_FULL, 0, RPM_MAX, 0, 10)
local BEND2    = math.Remap(RPM_FULL, 0, RPM_MAX, 0,  4)
local DROOP    = math.Remap(RPM_FULL, 0, RPM_MAX, 55, 0)
local RotorAcc = {}

local function AnimRotor(ent, idx)
    if not IsValid(ent) then return end
    RotorAcc[idx] = (RotorAcc[idx] or 0) + RPM_FULL * FrameTime() * 1.5
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
    ent:ManipulateBoneAngles(12, Angle( DROOP, 0, 0))
    ent:ManipulateBoneAngles(13, Angle(-DROOP, 0, 0))
    ent:SetBodygroup(2, 1)
    ent:SetBodygroup(3, 1)
    ent:SetPoseParameter("rotor_spin", RotorAcc[idx])
    ent:InvalidateBoneCache()
end

hook.Add("Think", "bombin_mi12_rotor_anim", function()
    for _, ent in ipairs(ents.FindByClass("ent_mi12_heli")) do
        local idx = ent:EntIndex()
        AnimRotor(ent, idx)
        if not IsValid(ent) then RotorAcc[idx] = nil end
    end
end)
