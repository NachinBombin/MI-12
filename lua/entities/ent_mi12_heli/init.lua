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
-- ============================================================
local MODEL_PATH      = ENT.ModelPath
local GIB_MODELS      = ENT.GibModels
local MAX_HP          = ENT.MaxHP
local FADE_DURATION   = ENT.FadeDuration
local ALT_DRIFT_RANGE = ENT.AltDriftRange
local ALT_DRIFT_LERP  = ENT.AltDriftLerp
local JITTER_AMP      = ENT.JitterAmplitude
local ALERT_INTERVAL  = ENT.AlertInterval

-- ============================================================
--  FLIGHT CONSTANTS
-- ============================================================
local PASS_SOUND_A = "vehicles/apc/apc_engine_start.wav"
local PASS_SOUND_B = "vehicles/apc/apc_idle1.wav"

local MODEL_YAW_OFFSET    = 0
local ROLL_SUSTAINED_GAIN = 1.8
local ROLL_TRANSIENT_GAIN = 45.0
local ROLL_MAX            = 18.0
local ROLL_LERP_IN        = 0.06
local ROLL_LERP_OUT       = 0.01
local GIB_LIFETIME        = 40

local TWO_PI = math.pi * 2

-- ============================================================
--  MANHACK ABILITY CONSTANTS
-- ============================================================
local MANHACK_CAP        = 20
local MANHACK_BURST      = 2
local MANHACK_INTERVAL   = 0.25
local MANHACK_COUNT_INT  = 5
local MANHACK_LAUNCH_SPD = 1200
local DOOR_OPEN_TIME     = 1.5
local TAIL_LOCAL_OFFSET  = Vector(-700, 0, -60)

-- ─── Door bodygroup ───────────────────────────────────────────────────────────
--  The Mi-12 Homer model bakes the door into bodygroup index 1.
--  Value 0 = closed (default).  Value 1 = open.
local DOOR_BG_INDEX  = 1
local DOOR_BG_CLOSED = 0
local DOOR_BG_OPEN   = 1

-- ============================================================
--  HELPERS
-- ============================================================
local PROBE_DIRS = {}
for i = 0, 7 do
    local a = math.rad(i * 45)
    PROBE_DIRS[i+1] = Vector(math.cos(a), math.sin(a), 0)
end
local PROBE_DIST   = 8192
local PROBE_MARGIN = 300

local function ProbeOrbitRadius(centerPos, skyZ, requestedRadius)
    local origin  = Vector(centerPos.x, centerPos.y, skyZ)
    local minDist = PROBE_DIST
    for _, dir in ipairs(PROBE_DIRS) do
        local tr = util.TraceLine({
            start  = origin,
            endpos = origin + dir * PROBE_DIST,
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            local d = (tr.HitPos - origin):Length2D()
            if d < minDist then minDist = d end
        end
    end
    local safe = math.max(200, minDist - PROBE_MARGIN)
    return math.min(requestedRadius, safe)
end

local function FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = {}
    local trace      = { start = startPos, endpos = endPos, filter = filterList }
    for _ = 1, 100 do
        local tr = util.TraceLine(trace)
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else
            break
        end
    end
    return -1
end

local function FindSafeCrashOrigin(rawPos, centerPos)
    if util.IsInWorld(rawPos) then return rawPos end
    local target = Vector(centerPos.x, centerPos.y, rawPos.z)
    local dir    = target - rawPos
    local dist   = dir:Length()
    if dist < 1 then
        local c = Vector(centerPos.x, centerPos.y, rawPos.z)
        return util.IsInWorld(c) and c or centerPos
    end
    dir = dir / dist
    for i = 1, math.ceil(dist / 200) do
        local c = rawPos + dir * (i * 200)
        if util.IsInWorld(c) then return c end
    end
    local c = Vector(centerPos.x, centerPos.y, rawPos.z)
    return util.IsInWorld(c) and c or centerPos
end

local function SpawnGibs(origin)
    for idx, mdl in ipairs(GIB_MODELS) do
        timer.Simple((idx - 1) * 0.1, function()
            local pos = origin + Vector(
                math.Rand(-150, 150),
                math.Rand(-150, 150),
                math.Rand(  20, 100)
            )
            if not util.IsInWorld(pos) then pos = origin end

            local gib = ents.Create("prop_physics")
            if not IsValid(gib) then return end
            gib:SetModel(mdl)
            gib:SetPos(pos)
            gib:SetAngles(Angle(math.Rand(0,360), math.Rand(0,360), math.Rand(0,360)))
            gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            gib:Spawn()
            gib:Activate()

            local ph = gib:GetPhysicsObject()
            if IsValid(ph) then
                ph:SetMass(2000)
                ph:SetDragCoefficient(0)
                ph:SetAngleDragCoefficient(0)
                ph:EnableGravity(true)
                ph:Wake()
                ph:ApplyForceCenter(Vector(
                    math.Rand(-400, 400),
                    math.Rand(-400, 400),
                    math.Rand( 300, 900)
                ) * 2000)
                ph:ApplyTorqueCenter(Vector(
                    math.Rand(-2000, 2000),
                    math.Rand(-2000, 2000),
                    math.Rand(-2000, 2000)
                ))
            end

            timer.Simple(0, function()
                if IsValid(gib) then gib:Ignite(GIB_LIFETIME, 0) end
            end)
            timer.Simple(GIB_LIFETIME, function()
                if IsValid(gib) then gib:Remove() end
            end)
        end)
    end
end

-- ============================================================
--  DOOR  (bodygroup on the main model — no separate props needed)
-- ============================================================
function ENT:OpenDoors()
    self:SetBodygroup(DOOR_BG_INDEX, DOOR_BG_OPEN)
end

function ENT:CloseDoors()
    self:SetBodygroup(DOOR_BG_INDEX, DOOR_BG_CLOSED)
end

-- ============================================================
--  MANHACK ABILITY
-- ============================================================
local function FindNearestTarget(origin)
    local bestDistSq = math.huge
    local bestEnt    = nil

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local d = origin:DistToSqr(ply:GetPos())
            if d < bestDistSq then
                bestDistSq = d
                bestEnt    = ply
            end
        end
    end

    for _, npc in ipairs(ents.FindByClass("npc_citizen")) do
        if IsValid(npc) and npc:Health() > 0 then
            local d = origin:DistToSqr(npc:GetPos())
            if d < bestDistSq then
                bestDistSq = d
                bestEnt    = npc
            end
        end
    end

    return bestEnt
end

local function GetTailPos(heli)
    local ang = heli:GetAngles()
    local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
    local o = TAIL_LOCAL_OFFSET
    return heli:GetPos() + fwd * o.x + right * o.y + up * o.z
end

local function LaunchManhack(spawnPos, target)
    local mh = ents.Create("npc_manhack")
    if not IsValid(mh) then return end

    mh:SetPos(spawnPos)
    local toTarget = target:GetPos() - spawnPos
    toTarget.z = 0
    if toTarget:LengthSqr() > 1 then
        mh:SetAngles(toTarget:Angle())
    end

    mh:Spawn()
    mh:Activate()

    mh:SetEnemy(target)
    if mh.UpdateEnemyMemory then
        mh:UpdateEnemyMemory(target, target:GetPos())
    end

    local ph = mh:GetPhysicsObject()
    if IsValid(ph) then
        ph:Wake()
        local vel = target:GetPos() - spawnPos
        if vel:LengthSqr() > 1 then vel:Normalize() else vel = Vector(0, 0, -1) end
        ph:SetVelocity(vel * MANHACK_LAUNCH_SPD)
    end
end

function ENT:ManhackBurst()
    if self.IsDestroyed then return end
    local tailPos = GetTailPos(self)
    local target  = FindNearestTarget(tailPos)
    if not IsValid(target) then return end

    self:OpenDoors()

    for i = 1, MANHACK_BURST do
        local spread = Vector(
            math.Rand(-30, 30),
            math.Rand(-30, 30),
            math.Rand(-20, 20)
        )
        LaunchManhack(tailPos + spread, target)
    end

    local closeTimer = "mi12_door_close_" .. self:EntIndex()
    timer.Remove(closeTimer)
    timer.Simple(DOOR_OPEN_TIME, function()
        if IsValid(self) and not self.IsDestroyed then
            self:CloseDoors()
        end
    end)
end

function ENT:ManhackBurstStart()
    if timer.Exists(self.ManhackBurstName) then return end
    timer.Create(self.ManhackBurstName, MANHACK_INTERVAL, 0, function()
        if not IsValid(self) then
            timer.Remove(self.ManhackBurstName)
            return
        end
        self:ManhackBurst()
    end)
end

function ENT:ManhackBurstStop()
    if timer.Exists(self.ManhackBurstName) then
        timer.Remove(self.ManhackBurstName)
    end
end

function ENT:ManhackCountCheck()
    if not IsValid(self) then return end
    if self.IsDestroyed    then return end
    local count = #ents.FindByClass("npc_manhack")
    if count < MANHACK_CAP then
        self:ManhackBurstStart()
    else
        self:ManhackBurstStop()
    end
end

function ENT:StartManhackSystem()
    local idx = self:EntIndex()
    self.ManhackBurstName = "mi12_manhack_burst_" .. idx
    self.ManhackCountName = "mi12_manhack_count_" .. idx

    self:ManhackCountCheck()
    timer.Create(self.ManhackCountName, MANHACK_COUNT_INT, 0, function()
        if not IsValid(self) then
            timer.Remove(self.ManhackCountName)
            timer.Remove(self.ManhackBurstName)
            return
        end
        self:ManhackCountCheck()
    end)
end

function ENT:StopManhackSystem()
    if self.ManhackBurstName then timer.Remove(self.ManhackBurstName) end
    if self.ManhackCountName  then timer.Remove(self.ManhackCountName) end
    timer.Remove("mi12_door_close_" .. self:EntIndex())
end

-- ============================================================
--  SOUND HELPERS
-- ============================================================
function ENT:StopAllSounds()
    if self.EngineLoop then self.EngineLoop:Stop() self.EngineLoop = nil end
    if self.PassSoundA  then self.PassSoundA:Stop()  self.PassSoundA  = nil end
    if self.PassSoundB  then self.PassSoundB:Stop()  self.PassSoundB  = nil end
end

function ENT:FadeAndStopSounds(fadeTime)
    local t = fadeTime or 0.5
    local e, a, b = self.EngineLoop, self.PassSoundA, self.PassSoundB
    self.EngineLoop, self.PassSoundA, self.PassSoundB = nil, nil, nil
    if e then e:ChangeVolume(0, t) end
    if a then a:ChangeVolume(0, t) end
    if b then b:ChangeVolume(0, t) end
    timer.Simple(t + 0.15, function()
        if e then e:Stop() end
        if a then a:Stop() end
        if b then b:Stop() end
    end)
end

-- ============================================================
--  ENT:Initialize
-- ============================================================
function ENT:Initialize()
    local center = self:GetVar("CenterPos",    self:GetPos())
    local dir    = self:GetVar("CallDir",      Vector(1, 0, 0))
    local speed  = self:GetVar("Speed",        280)
    local radius = self:GetVar("OrbitRadius",  3000)
    local skyAdd = self:GetVar("SkyHeightAdd", 5000)
    local life   = self:GetVar("Lifetime",     40)

    if dir:LengthSqr() <= 0.01 then dir = Vector(1, 0, 0) end
    dir.z = 0 ; dir:Normalize()

    local groundZ = FindGround(center)
    if groundZ == -1 then
        print("[MI-12] FindGround failed, removing")
        self:Remove() return
    end
    local skyZ = groundZ + skyAdd

    radius = ProbeOrbitRadius(center, skyZ, radius)

    self:SetModel(MODEL_PATH)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-350, -700, -80), Vector(350, 700, 420))
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))
    self:SetHealth(MAX_HP)

    local right    = Vector(-dir.y, dir.x, 0)
    local orbitDir = (math.random(2) == 1) and 1 or -1
    local tangent  = Vector(right.x * orbitDir, right.y * orbitDir, 0)
    tangent:Normalize()
    local spawnOffset = tangent * (-radius * math.Rand(0.55, 0.95))
    local spawnPos    = Vector(
        center.x + spawnOffset.x,
        center.y + spawnOffset.y,
        skyZ
    )
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(center.x, center.y, skyZ)
    end
    if not util.IsInWorld(spawnPos) then
        print("[MI-12] Spawn OOB, removing")
        self:Remove() return
    end
    self:SetPos(spawnPos)

    self.CenterPos      = Vector(center.x, center.y, skyZ)
    self.OrbitRadius    = radius
    self.OrbitDirection = orbitDir
    self.Speed          = speed
    self.sky            = skyZ
    self.SpawnTime      = CurTime()
    self.DieTime        = CurTime() + life
    self.NextAlertTime  = CurTime()
    self.IsDestroyed    = false
    self.DamageTier     = 0
    self.HP             = MAX_HP
    self.fadeAlpha      = 0

    self.flightYaw       = tangent:Angle().y
    self.PrevFlightYaw   = self.flightYaw
    self.ang             = Angle(0, self.flightYaw + MODEL_YAW_OFFSET, 0)
    self.SmoothedRoll    = 0
    self.SmoothedPitch   = 0
    self.PrevTurnRate    = 0
    self.RadialGain      = 0.5
    self.MaxTurnRate     = 22

    self.AltDriftCurrent  = skyZ
    self.AltDriftTarget   = skyZ
    self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    self.JitterPhase      = math.Rand(0, TWO_PI)

    self.IsTumbling        = false
    self.TumbleCrashed     = false
    self.TumbleGroundZ     = groundZ
    self.TumbleVelocity    = Vector(0, 0, 0)
    self.TumbleAngVelocity = Vector(0, 0, 0)

    -- Bodygroups: door closed at spawn, rotors at full-RPM blur disc
    self:SetBodygroup(DOOR_BG_INDEX, DOOR_BG_CLOSED)
    self:SetBodygroup(2, 1)
    self:SetBodygroup(3, 1)

    self:StartManhackSystem()

    -- Engine sounds
    self.EngineLoop = CreateSound(self, "tfre_mi12")
    if self.EngineLoop then
        self.EngineLoop:SetSoundLevel(140)
        self.EngineLoop:ChangePitch(110, 0)
        self.EngineLoop:ChangeVolume(1.0, 0)
        self.EngineLoop:Play()
    end
    self.PassSoundA = CreateSound(self, PASS_SOUND_A)
    if self.PassSoundA then
        self.PassSoundA:SetSoundLevel(140)
        self.PassSoundA:ChangePitch(90, 0)
        self.PassSoundA:ChangeVolume(1.0, 0)
        self.PassSoundA:Play()
    end
    self.PassSoundB = CreateSound(self, PASS_SOUND_B)
    if self.PassSoundB then
        self.PassSoundB:SetSoundLevel(140)
        self.PassSoundB:ChangePitch(85, 0)
        self.PassSoundB:ChangeVolume(1.0, 0)
        self.PassSoundB:Play()
    end

    self:SetNWInt("HP",    MAX_HP)
    self:SetNWInt("MaxHP", MAX_HP)

    timer.Simple(life, function()
        if IsValid(self) then self:Remove() end
    end)

    self:NextThink(CurTime())
end

-- ============================================================
--  Think
-- ============================================================
function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime() + 0.1)
        return true
    end

    local ct = CurTime()
    local dt = FrameTime()
    if dt <= 0 then dt = 0.01 end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha
    if age < FADE_DURATION then
        alpha = math.Clamp(255 * (age  / FADE_DURATION), 0, 255)
    elseif left < FADE_DURATION then
        alpha = math.Clamp(255 * (left / FADE_DURATION), 0, 255)
    else
        alpha = 255
    end
    self:SetColor(Color(255, 255, 255, math.Round(alpha)))

    if ct >= self.NextAlertTime then
        local plys = player.GetAll()
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent:IsNPC() and ent.UpdateEnemyMemory then
                for _, ply in ipairs(plys) do
                    if IsValid(ply) and ply:Alive() then
                        ent:UpdateEnemyMemory(ply, ply:GetPos())
                    end
                end
            end
        end
        self.NextAlertTime = ct + ALERT_INTERVAL
    end

    if self.IsTumbling and not self.TumbleCrashed then
        local pos     = self:GetPos()
        local groundZ = self.TumbleGroundZ or -16384
        if pos.z <= groundZ + 150 then self:CrashExplode() return end
        local tr = util.TraceLine({
            start  = pos,
            endpos = pos + Vector(0, 0, -200),
            filter = self,
        })
        if tr.HitWorld then self:CrashExplode() return end
        local grav = physenv.GetGravity().z
        self.TumbleVelocity.z = self.TumbleVelocity.z + grav * dt
        local av = self.TumbleAngVelocity
        self.ang = Angle(
            self.ang.p + av.x * dt,
            self.ang.y + av.y * dt,
            self.ang.r + av.z * dt
        )
        self:SetPos(pos + self.TumbleVelocity * dt)
        self:SetAngles(self.ang)
        self:NextThink(ct)
        return true
    end

    local pos = self:GetPos()

    if ct >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky - math.Rand(0, ALT_DRIFT_RANGE)
        self.AltDriftNextPick = ct + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(ALT_DRIFT_LERP, self.AltDriftCurrent, self.AltDriftTarget)
    self.JitterPhase     = self.JitterPhase + 0.02
    local liveAlt = math.Clamp(
        self.AltDriftCurrent + math.sin(self.JitterPhase) * JITTER_AMP,
        self.sky - ALT_DRIFT_RANGE,
        self.sky
    )

    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local toCenter   = flatCenter - flatPos
    local dist       = toCenter:Length()
    local radialDir  = (dist > 1) and (toCenter / dist) or Vector(0, 0, 0)

    local tangentDir = Vector(
        -radialDir.y * self.OrbitDirection,
         radialDir.x * self.OrbitDirection,
        0
    )
    if tangentDir:LengthSqr() < 0.001 then
        tangentDir = Angle(0, self.flightYaw, 0):Forward()
        tangentDir.z = 0
    end
    tangentDir:Normalize()

    local radialError = 0
    if self.OrbitRadius > 0 then
        radialError = math.Clamp((dist - self.OrbitRadius) / self.OrbitRadius, -1, 1)
    end

    local desired2 = Vector(
        tangentDir.x + radialDir.x * radialError * self.RadialGain,
        tangentDir.y + radialDir.y * radialError * self.RadialGain,
        0
    )
    if desired2:LengthSqr() < 0.001 then desired2 = tangentDir end
    desired2:Normalize()

    local fwdAngle = Angle(0, self.flightYaw, 0)
    local fwd3     = fwdAngle:Forward()
    local fwd2     = Vector(fwd3.x, fwd3.y, 0) ; fwd2:Normalize()

    local cross    = fwd2.x * desired2.y - fwd2.y * desired2.x
    local dot      = fwd2.x * desired2.x + fwd2.y * desired2.y
    local urgency  = (1 - dot) * 0.5
    local turnRate = math.Clamp(cross * urgency * self.MaxTurnRate * 2,
                                -self.MaxTurnRate, self.MaxTurnRate)

    self.flightYaw = self.flightYaw + turnRate * dt

    local turnRateDelta = turnRate - self.PrevTurnRate
    self.PrevTurnRate   = turnRate
    local sustained     = math.Clamp(turnRate      * ROLL_SUSTAINED_GAIN, -ROLL_MAX, ROLL_MAX)
    local transient     = math.Clamp(turnRateDelta * ROLL_TRANSIENT_GAIN, -12, 12)
    local rollTarget    = -math.Clamp(sustained + transient, -ROLL_MAX, ROLL_MAX)
    local building      = (rollTarget * self.SmoothedRoll >= 0)
                          and (math.abs(rollTarget) > math.abs(self.SmoothedRoll))
    self.SmoothedRoll   = Lerp(building and ROLL_LERP_IN or ROLL_LERP_OUT, self.SmoothedRoll, rollTarget)

    local climbDelta   = math.Clamp((liveAlt - pos.z) / 400, -1, 1)
    self.SmoothedPitch = Lerp(0.03, self.SmoothedPitch, math.Clamp(climbDelta * 6, -8, 8))

    self.ang = Angle(
        self.SmoothedPitch,
        self.flightYaw + MODEL_YAW_OFFSET,
        self.SmoothedRoll
    )

    local newPos = pos + fwdAngle:Forward() * self.Speed * dt
    newPos.z     = Lerp(0.07, pos.z, liveAlt)

    if not util.IsInWorld(newPos) then
        local toC = flatCenter - flatPos
        toC.z = 0
        if toC:LengthSqr() < 0.001 then toC = Vector(-fwd2.x, -fwd2.y, 0) end
        toC:Normalize()
        local sCross = fwd2.x * toC.y - fwd2.y * toC.x
        self.flightYaw = self.flightYaw
            + math.Clamp(sCross * self.MaxTurnRate, -self.MaxTurnRate, self.MaxTurnRate) * dt
        self:SetAngles(Angle(self.SmoothedPitch, self.flightYaw + MODEL_YAW_OFFSET, self.SmoothedRoll))
        self:NextThink(ct)
        return true
    end

    self:SetPos(newPos)
    self:SetAngles(self.ang)
    self:NextThink(ct)
    return true
end

-- ============================================================
--  Damage
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    self.HP = self.HP - dmginfo:GetDamage()
    self:SetNWInt("HP", self.HP)

    local pct  = self.HP / MAX_HP
    local tier = (pct > 0.66) and 0
             or (pct > 0.33)  and 1
             or (self.HP > 0) and 2
             or 3

    if tier ~= self.DamageTier then
        self.DamageTier = tier
        net.Start("bombin_mi12_damage_tier")
            net.WriteUInt(self:EntIndex(), 16)
            net.WriteUInt(tier, 2)
        net.Broadcast()
    end

    if self.HP <= 0 then self:DestroyHeli() end
end

-- ============================================================
--  Destruction chain
-- ============================================================
function ENT:StartTumble()
    self.IsTumbling    = true
    self.TumbleCrashed = false

    local gnd = FindGround(self:GetPos())
    if gnd ~= -1 then self.TumbleGroundZ = gnd end

    local travelFwd = Angle(0, self.flightYaw, 0):Forward()
    local spd       = self.Speed or 280
    self.TumbleVelocity    = Vector(travelFwd.x * spd, travelFwd.y * spd, -200)
    local sign = function() return (math.random(2) == 1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand( 80, 200) * sign(),
        math.Rand( 20,  80) * sign(),
        math.Rand(150, 400) * sign()
    )

    local ed = EffectData()
    ed:SetOrigin(self:GetPos()) ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_4.wav", self:GetPos(), 135, 95, 1.0)
end

function ENT:DestroyHeli()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    self:StopManhackSystem()
    self:FadeAndStopSounds(0.3)
    self:StartTumble()
    timer.Simple(12, function()
        if IsValid(self) then self:CrashExplode() end
    end)
end

function ENT:CrashExplode()
    if self.TumbleCrashed then return end
    self.TumbleCrashed = true

    local safePos = FindSafeCrashOrigin(self:GetPos(), self.CenterPos)

    local function boom(origin, sc)
        local ed = EffectData()
        ed:SetOrigin(origin) ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc * 100)
        util.Effect("500lb_air", ed, true, true)
    end
    local ed1 = EffectData()
    ed1:SetOrigin(safePos) ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600)
    util.Effect("HelicopterMegaBomb", ed1, true, true)
    boom(safePos, 5)
    boom(safePos + Vector(0,0,80),  4)
    boom(safePos + Vector(0,0,180), 3)
    sound.Play("ambient/explosions/explode_8.wav", safePos, 140, 90, 1.0)
    sound.Play("weapon_AWP.Single",                safePos, 145, 60, 1.0)
    util.BlastDamage(self, self, safePos, 400, 200)

    SpawnGibs(safePos)
    self:Remove()
end

-- ============================================================
--  Cleanup
-- ============================================================
function ENT:OnRemove()
    self:StopAllSounds()
    self:StopManhackSystem()
end
