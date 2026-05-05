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
--  ORBIT MATH HELPERS
-- ============================================================
local TWO_PI = math.pi * 2

local function RandomFlatDir()
    local a = math.Rand(0, TWO_PI)
    return Vector(math.cos(a), math.sin(a), 0)
end

-- Fire 8 raycasts at sky height, return max unobstructed radius
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
    self:SetModel(ENT.ModelPath)
    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:DrawShadow(false)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(ENT.Mass)
        phys:EnableGravity(false)
    end

    -- Retrieve spawn params written by the spawner
    local center  = self:GetVar("CenterPos",    self:GetPos())
    local dir     = self:GetVar("CallDir",      RandomFlatDir())
    local speed   = self:GetVar("Speed",        280)
    local radius  = self:GetVar("OrbitRadius",  3000)
    local skyAdd  = self:GetVar("SkyHeightAdd", 5000)
    local life    = self:GetVar("Lifetime",     40)

    -- Resolve flight altitude
    local skyZ = SkyHeight(center, skyAdd)
    radius     = ProbeOrbitRadius(center, radius, skyZ)

    -- Entry position: tangent to orbit circle in the call direction
    local perp = Vector(-dir.y, dir.x, 0)   -- 90° from call dir
    local entryPos = Vector(
        center.x + perp.x * radius,
        center.y + perp.y * radius,
        skyZ
    )

    self:SetPos(entryPos)

    -- Internal flight state
    self.orbitCenter = Vector(center.x, center.y, skyZ)
    self.orbitRadius = radius
    self.orbitSpeed  = speed
    self.orbitAngle  = math.atan2(perp.y, perp.x)   -- radians, matches entry pos
    self.angularVel  = speed / radius                -- rad/s
    self.targetAlt   = skyZ
    self.currentAlt  = skyZ
    self.altPhase    = math.Rand(0, TWO_PI)
    self.HP          = ENT.MaxHP
    self.dmgTier     = 0
    self.isTumbling  = false
    self.fadeAlpha   = 0
    self.spawnTime   = CurTime()
    self.lifetime    = life
    self.lastAlert   = 0

    -- Fade-in render
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    -- Always-open doors
    self:SpawnDoors()

    -- Bodygroups: no AI seat, always full-RPM blur
    self:SetBodygroup(1, 0)
    self:SetBodygroup(2, 1)
    self:SetBodygroup(3, 1)

    -- Engine sound
    self.engineSound = CreateSound(self, "tfre_mi12")
    if self.engineSound then
        self.engineSound:Play()
        self.engineSound:ChangePitch(110, 0)   -- locked at full-RPM pitch
        self.engineSound:ChangeVolume(1.0, 0.5)
    end

    -- Auto-remove after lifetime
    timer.Simple(life, function()
        if IsValid(self) then self:DestroyHeli() end
    end)
end

-- ============================================================
--  DOORS — always open on spawn, never toggled
-- ============================================================
function ENT:SpawnDoors()
    -- Closed mesh: hidden and non-solid permanently
    local dClosed = ents.Create("prop_physics")
    if IsValid(dClosed) then
        dClosed:SetModel(ENT.DoorModelClosed)
        dClosed:SetPos(self:GetPos())
        dClosed:SetAngles(self:GetAngles())
        dClosed:Spawn()
        dClosed:SetParent(self)
        dClosed:SetNotSolid(true)
        dClosed:SetNoDraw(true)
        dClosed:GetPhysicsObject():EnableMotion(false)
        self.doorClosed = dClosed
    end

    -- Open mesh: solid and visible permanently
    local dOpen = ents.Create("prop_physics")
    if IsValid(dOpen) then
        dOpen:SetModel(ENT.DoorModelOpen)
        dOpen:SetPos(self:GetPos())
        dOpen:SetAngles(self:GetAngles())
        dOpen:Spawn()
        dOpen:SetParent(self)
        dOpen:SetNotSolid(false)
        dOpen:SetNoDraw(false)
        dOpen:GetPhysicsObject():EnableMotion(false)
        self.doorOpen = dOpen
    end
end

-- ============================================================
--  Think — fade-in + alert + tumble crash detection
-- ============================================================
function ENT:Think()
    local ct = CurTime()

    -- Fade in
    if self.fadeAlpha < 255 then
        self.fadeAlpha = math.min(255, self.fadeAlpha + (255 / ENT.FadeDuration) * FrameTime())
        self:SetColor(Color(255, 255, 255, math.floor(self.fadeAlpha)))
    end

    -- Tumble crash: detect ground impact
    if self.isTumbling then
        local tr = util.TraceLine({
            start  = self:GetPos(),
            endpos = self:GetPos() - Vector(0, 0, 80),
            filter = self,
        })
        if tr.Hit then
            self:CrashExplode()
            return
        end
    end

    self:NextThink(ct + 0.1)
    return true
end

-- ============================================================
--  PhysicsUpdate — orbit flight loop
-- ============================================================
function ENT:PhysicsUpdate(delta)
    if self.isTumbling then return end

    -- Advance orbit angle
    self.orbitAngle = self.orbitAngle + self.angularVel * delta
    if self.orbitAngle > TWO_PI then self.orbitAngle = self.orbitAngle - TWO_PI end

    -- Target XY from orbit math
    local cx = self.orbitCenter.x
    local cy = self.orbitCenter.y
    local tx = cx + math.cos(self.orbitAngle) * self.orbitRadius
    local ty = cy + math.sin(self.orbitAngle) * self.orbitRadius

    -- Altitude drift (sine wave + jitter)
    self.altPhase   = self.altPhase + delta * 0.18
    local altTarget = self.targetAlt
        + math.sin(self.altPhase) * ENT.AltDriftRange
        + math.Rand(-1, 1) * ENT.JitterAmplitude
    self.currentAlt = Lerp(ENT.AltDriftLerp, self.currentAlt, altTarget)

    local newPos = Vector(tx, ty, self.currentAlt)

    -- Out-of-bounds guard: if heli drifted >20% past orbit, clamp back
    local drift = (newPos - self.orbitCenter):Length2D()
    if drift > self.orbitRadius * 1.2 then
        local dir = (newPos - self.orbitCenter):GetNormalized()
        newPos = self.orbitCenter + dir * self.orbitRadius
        newPos.z = self.currentAlt
    end

    -- Yaw: face the flight direction (tangent to circle)
    local tangentAngle = self.orbitAngle + math.pi * 0.5
    local yawDeg = math.deg(tangentAngle)

    -- Smooth roll into the turn (bank angle)
    local bankTarget  = -22
    self.currentBank  = Lerp(0.04, self.currentBank or 0, bankTarget)

    -- Pitch based on altitude change
    local altDelta    = self.currentAlt - (self.prevAlt or self.currentAlt)
    self.prevAlt      = self.currentAlt
    local pitchTarget = math.Clamp(-altDelta * 0.6, -12, 12)
    self.currentPitch = Lerp(0.06, self.currentPitch or 0, pitchTarget)

    local finalAng = Angle(self.currentPitch, yawDeg, self.currentBank)
    self:SetPos(newPos)
    self:SetAngles(finalAng)
end

-- ============================================================
--  Damage
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    self.HP = math.max(0, self.HP - dmginfo:GetDamage())

    local tier
    local pct = self.HP / ENT.MaxHP
    if     pct > 0.65 then tier = 0
    elseif pct > 0.35 then tier = 1
    elseif pct > 0.10 then tier = 2
    else                    tier = 3
    end

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
        timer.Simple(1.5, function() if self.engineSound then self.engineSound:Stop() end end)
    end

    -- Kill doors
    if IsValid(self.doorClosed) then self.doorClosed:Remove() end
    if IsValid(self.doorOpen)   then self.doorOpen:Remove() end

    -- Begin tumble physics
    self:SetMoveType(MOVETYPE_FLYGRAVITY)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    local tumbleVel = Vector(
        math.Rand(-120, 120),
        math.Rand(-120, 120),
        math.Rand(-200, -80)
    )
    self:SetLocalVelocity(tumbleVel)
    self:SetLocalAngularVelocity(Angle(
        math.Rand(-30, 30),
        math.Rand(-60, 60),
        math.Rand(-45, 45)
    ))
end

function ENT:CrashExplode()
    local pos = self:GetPos()

    -- Explosion
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetScale(3.5)
    util.Effect("Explosion", ed)

    -- Gibs with staggered delay to prevent lag spike
    for idx, mdl in ipairs(ENT.GibModels) do
        timer.Simple((idx - 1) * 0.1, function()
            if not IsValid(self) then
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
            end
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
