-- ============================================================
--  MI-12 Homer — Server Entity Logic
--  lua/entities/ent_mi12_heli/init.lua
-- ============================================================

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_trailsystem.lua")
include("shared.lua")

util.AddNetworkString("bombin_mi12_damage_tier")

-- ============================================================
--  CACHE SHARED CONSTANTS
--  ENT global is only valid during file execution, not at
--  method call time. Cache everything here.
-- ============================================================
local MODEL_PATH      = ENT.ModelPath
local DOOR_MDL_CLOSED = ENT.DoorModelClosed
local DOOR_MDL_OPEN   = ENT.DoorModelOpen
local GIB_MODELS      = ENT.GibModels
local MAX_HP          = ENT.MaxHP
local ENT_MASS        = ENT.Mass
local FADE_DURATION   = ENT.FadeDuration
local ALT_DRIFT_RANGE = ENT.AltDriftRange
local ALT_DRIFT_LERP  = ENT.AltDriftLerp
local JITTER_AMP      = ENT.JitterAmplitude

-- ============================================================
--  HELPERS
-- ============================================================
local TWO_PI = math.pi * 2

local function RandomFlatDir()
    local a = math.Rand(0, TWO_PI)
    return Vector(math.cos(a), math.sin(a), 0)
end

local function ProbeOrbitRadius(center, requestedRadius, skyZ)
    local radius = requestedRadius
    for i = 0, 7 do
        local a   = (i / 8) * TWO_PI
        local dir = Vector(math.cos(a), math.sin(a), 0)
        local tr  = util.TraceLine({
            start  = Vector(center.x, center.y, skyZ),
            endpos = Vector(center.x + dir.x * radius, center.y + dir.y * radius, skyZ),
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            local safe = (tr.HitPos - Vector(center.x, center.y, skyZ)):Length() * 0.85
            radius = math.min(radius, safe)
        end
    end
    return math.max(radius, 400)
end

local function SkyHeight(pos, desiredAdd)
    local tr = util.TraceLine({
        start  = pos + Vector(0, 0, 64),
        endpos = pos + Vector(0, 0, desiredAdd + 3000),
        mask   = MASK_SOLID_BRUSHONLY,
    })
    local ceiling = tr.Hit and (tr.HitPos.z - 120) or (pos.z + desiredAdd + 200)
    return math.min(pos.z + desiredAdd, ceiling)
end

-- ============================================================
--  ENT:Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel(MODEL_PATH)

    -- MOVETYPE_NONE: we drive all movement manually from Think.
    -- PhysicsUpdate does NOT fire for MOVETYPE_NOCLIP/NONE in GMod.
    self:SetMoveType(MOVETYPE_NONE)

    -- SOLID_BBOX is required for OnTakeDamage to receive hits.
    -- SOLID_NONE causes bullets and explosions to pass through entirely.
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-350, -700, -80), Vector(350, 700, 420))

    -- IN_VEHICLE: players walk through the hull, but damage traces still land.
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:DrawShadow(false)
    self:SetHealth(MAX_HP)

    -- Retrieve spawn params
    local center = self:GetVar("CenterPos",    self:GetPos())
    local dir    = self:GetVar("CallDir",      RandomFlatDir())
    local speed  = self:GetVar("Speed",        280)
    local radius = self:GetVar("OrbitRadius",  3000)
    local skyAdd = self:GetVar("SkyHeightAdd", 5000)
    local life   = self:GetVar("Lifetime",     40)

    local skyZ = SkyHeight(center, skyAdd)
    radius     = ProbeOrbitRadius(center, radius, skyZ)

    -- Entry position: tangent to the orbit circle
    local perp = Vector(-dir.y, dir.x, 0)
    self:SetPos(Vector(
        center.x + perp.x * radius,
        center.y + perp.y * radius,
        skyZ
    ))

    -- Flight state
    self.orbitCenter  = Vector(center.x, center.y, skyZ)
    self.orbitRadius  = radius
    self.orbitSpeed   = speed
    self.orbitAngle   = math.atan2(perp.y, perp.x)
    self.angularVel   = speed / radius
    self.targetAlt    = skyZ
    self.currentAlt   = skyZ
    self.prevAlt      = skyZ
    self.altPhase     = math.Rand(0, TWO_PI)
    self.HP           = MAX_HP
    self.dmgTier      = 0
    self.isTumbling   = false
    self.tumbleVel    = Vector(0, 0, 0)
    self.tumbleAV     = Angle(0, 0, 0)
    self.fadeAlpha    = 0
    self.currentBank  = 0
    self.currentPitch = 0
    self.spawnTime    = CurTime()
    self.lifetime     = life

    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    self:SpawnDoors()

    self:SetBodygroup(1, 0)  -- no AI seat
    self:SetBodygroup(2, 1)  -- rotor A: blur disc
    self:SetBodygroup(3, 1)  -- rotor B: blur disc

    self.engineSound = CreateSound(self, "tfre_mi12")
    if self.engineSound then
        self.engineSound:Play()
        self.engineSound:ChangePitch(110, 0)
        self.engineSound:ChangeVolume(1.0, 0.5)
    end

    -- Think must be explicitly scheduled for the first call
    self:NextThink(CurTime())

    timer.Simple(life, function()
        if IsValid(self) then self:DestroyHeli() end
    end)
end

-- ============================================================
--  DOORS — always open, never toggled
-- ============================================================
function ENT:SpawnDoors()
    local function MakeDoor(mdl, hidden)
        local d = ents.Create("prop_physics")
        if not IsValid(d) then return nil end
        d:SetModel(mdl)
        d:SetPos(self:GetPos())
        d:SetAngles(self:GetAngles())
        d:Spawn()
        d:SetParent(self)
        d:SetNotSolid(hidden)
        d:SetNoDraw(hidden)
        local ph = d:GetPhysicsObject()
        if IsValid(ph) then ph:EnableMotion(false) end
        return d
    end

    self.doorClosed = MakeDoor(DOOR_MDL_CLOSED, true)   -- hidden
    self.doorOpen   = MakeDoor(DOOR_MDL_OPEN,   false)  -- visible
end

-- ============================================================
--  Think — ALL movement + fade + tumble
-- ============================================================
function ENT:Think()
    local ct = CurTime()
    local dt = FrameTime()
    if dt <= 0 then dt = 0.01 end

    -- ─── Fade in ──────────────────────────────────────
    if self.fadeAlpha < 255 then
        self.fadeAlpha = math.min(255, self.fadeAlpha + (255 / FADE_DURATION) * dt)
        self:SetColor(Color(255, 255, 255, math.floor(self.fadeAlpha)))
    end

    -- ─── Tumble mode ─────────────────────────────────
    if self.isTumbling then
        -- Apply gravity manually
        self.tumbleVel = self.tumbleVel + Vector(0, 0, -600 * dt)

        local newPos = self:GetPos() + self.tumbleVel * dt
        local newAng = self:GetAngles() + self.tumbleAV * dt

        -- Ground hit detection
        local tr = util.TraceLine({
            start  = self:GetPos(),
            endpos = newPos - Vector(0, 0, 60),
            filter = self,
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            self:CrashExplode()
            return
        end

        self:SetPos(newPos)
        self:SetAngles(newAng)
        self:NextThink(ct)
        return true
    end

    -- ─── Orbit flight ────────────────────────────────
    self.orbitAngle = self.orbitAngle + self.angularVel * dt
    if self.orbitAngle > TWO_PI then self.orbitAngle = self.orbitAngle - TWO_PI end

    local cx = self.orbitCenter.x
    local cy = self.orbitCenter.y
    local tx = cx + math.cos(self.orbitAngle) * self.orbitRadius
    local ty = cy + math.sin(self.orbitAngle) * self.orbitRadius

    -- Altitude drift
    self.altPhase   = self.altPhase + dt * 0.18
    local altTarget = self.targetAlt
        + math.sin(self.altPhase) * ALT_DRIFT_RANGE
        + math.Rand(-1, 1) * JITTER_AMP
    self.currentAlt = Lerp(ALT_DRIFT_LERP, self.currentAlt, altTarget)

    local newPos = Vector(tx, ty, self.currentAlt)

    -- OOB clamp
    if (newPos - self.orbitCenter):Length2D() > self.orbitRadius * 1.2 then
        local clampDir = (newPos - self.orbitCenter):GetNormalized()
        newPos = self.orbitCenter + clampDir * self.orbitRadius
        newPos.z = self.currentAlt
    end

    -- Yaw: face tangent
    local yawDeg = math.deg(self.orbitAngle + math.pi * 0.5)

    -- Bank
    self.currentBank  = Lerp(0.04, self.currentBank, -22)

    -- Pitch
    local altDelta    = self.currentAlt - self.prevAlt
    self.prevAlt      = self.currentAlt
    self.currentPitch = Lerp(0.06, self.currentPitch, math.Clamp(-altDelta * 0.6, -12, 12))

    self:SetPos(newPos)
    self:SetAngles(Angle(self.currentPitch, yawDeg, self.currentBank))

    -- Run every tick during flight
    self:NextThink(ct)
    return true
end

-- ============================================================
--  Damage — requires SOLID_BBOX to receive hits
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    self.HP = math.max(0, self.HP - dmginfo:GetDamage())

    local pct  = self.HP / MAX_HP
    local tier = (pct > 0.65) and 0
             or (pct > 0.35)  and 1
             or (pct > 0.10)  and 2
             or 3

    if tier ~= self.dmgTier then
        self.dmgTier = tier
        net.Start("bombin_mi12_damage_tier")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteUInt(tier, 2)
        net.Broadcast()
    end

    if self.HP <= 0 and not self.isTumbling then
        self:DestroyHeli()
    end
end

-- ============================================================
--  Destruction chain
-- ============================================================
function ENT:DestroyHeli()
    if self.isTumbling then return end
    self.isTumbling = true

    if self.engineSound then
        self.engineSound:ChangeVolume(0, 1.5)
        timer.Simple(1.5, function()
            if self.engineSound then self.engineSound:Stop() end
        end)
    end

    if IsValid(self.doorClosed) then self.doorClosed:Remove() end
    if IsValid(self.doorOpen)   then self.doorOpen:Remove() end

    -- Store tumble kinematics for Think to integrate
    self.tumbleVel = Vector(
        math.Rand(-120, 120),
        math.Rand(-120, 120),
        math.Rand(-60, 60)
    )
    self.tumbleAV  = Angle(
        math.Rand(-30, 30),
        math.Rand(-60, 60),
        math.Rand(-45, 45)
    )
end

function ENT:CrashExplode()
    local pos = self:GetPos()

    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetScale(3.5)
    util.Effect("Explosion", ed)

    for idx, mdl in ipairs(GIB_MODELS) do
        timer.Simple((idx - 1) * 0.1, function()
            local g = ents.Create("prop_physics")
            if not IsValid(g) then return end
            g:SetModel(mdl)
            g:SetPos(pos + VectorRand() * 80)
            g:SetAngles(AngleRand())
            g:Spawn()
            g:Activate()
            local ph = g:GetPhysicsObject()
            if IsValid(ph) then
                ph:SetVelocity(VectorRand() * 400 + Vector(0, 0, 200))
                ph:ApplyTorqueCenter(VectorRand() * 4000)
            end
            timer.Simple(12, function() if IsValid(g) then g:Remove() end end)
        end)
    end

    self:EmitSound("ambient/explosions/explode_" .. math.random(1, 9) .. ".wav", 175, 80)
    self:Remove()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    if self.engineSound then self.engineSound:Stop() end
    if IsValid(self.doorClosed) then self.doorClosed:Remove() end
    if IsValid(self.doorOpen)   then self.doorOpen:Remove() end
end
