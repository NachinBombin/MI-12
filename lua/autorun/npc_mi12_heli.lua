-- ============================================================
--  MI-12 spawner + NPC trigger loop
--  lua/autorun/npc_mi12_heli.lua
--
--  Same architecture as npc_an71_plane.lua.
--  All AN-71 identifiers replaced with mi12 equivalents.
-- ============================================================

if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("MI12_FlareSpawned")
    util.AddNetworkString("MI12_ManualSpawn")

    local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

    local cv_enabled    = CreateConVar("npc_mi12_enabled",    "1",    SHARED_FLAGS, "Enable/disable MI-12 flyovers.")
    local cv_chance     = CreateConVar("npc_mi12_chance",     "0.12", SHARED_FLAGS, "Probability per check.")
    local cv_interval   = CreateConVar("npc_mi12_interval",   "12",   SHARED_FLAGS, "Check interval (s).")
    local cv_cooldown   = CreateConVar("npc_mi12_cooldown",   "60",   SHARED_FLAGS, "Cooldown (s).")
    local cv_max_dist   = CreateConVar("npc_mi12_max_dist",   "3000", SHARED_FLAGS, "Max NPC-target distance.")
    local cv_min_dist   = CreateConVar("npc_mi12_min_dist",   "400",  SHARED_FLAGS, "Min NPC-target distance.")
    local cv_delay      = CreateConVar("npc_mi12_delay",      "5",    SHARED_FLAGS, "Delay after flare (s).")
    local cv_life       = CreateConVar("npc_mi12_lifetime",   "50",   SHARED_FLAGS, "Heli lifetime (s).")
    local cv_speed      = CreateConVar("npc_mi12_speed",      "220",  SHARED_FLAGS, "Heli speed (HU/s).")
    local cv_radius     = CreateConVar("npc_mi12_radius",     "3000", SHARED_FLAGS, "Orbit radius (HU).")
    local cv_height     = CreateConVar("npc_mi12_height",     "5000", SHARED_FLAGS, "Height above ground (HU).")
    local cv_announce   = CreateConVar("npc_mi12_announce",   "0",    SHARED_FLAGS, "Debug prints.")

    local CALLERS = {
        ["npc_combine_s"]     = true,
        ["npc_metropolice"]   = true,
        ["npc_combine_elite"] = true,
    }

    local function MI12_Debug(msg)
        if not cv_announce:GetBool() then return end
        local full = "[MI-12] " .. msg
        print(full)
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, full) end
        end
    end

    local function RandomFlatDir()
        local ang = math.Rand(0, 360)
        return Vector(math.cos(math.rad(ang)), math.sin(math.rad(ang)), 0)
    end

    local function CheckSkyAbove(pos)
        local tr = util.TraceLine({
            start  = pos + Vector(0, 0, 50),
            endpos = pos + Vector(0, 0, 1050),
        })
        if tr.Hit and not tr.HitSky then
            tr = util.TraceLine({
                start  = tr.HitPos + Vector(0, 0, 50),
                endpos = tr.HitPos + Vector(0, 0, 1000),
            })
        end
        return not (tr.Hit and not tr.HitSky)
    end

    local function ThrowSupportFlare(npc, targetPos)
        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()

        local flare = ents.Create("ent_bombin_flare_blue")
        if not IsValid(flare) then
            MI12_Debug("Flare spawn failed: ent_bombin_flare_blue invalid")
            return nil
        end

        flare:SetPos(npcEyePos + toTarget * 52)
        flare:SetAngles(npc:GetAngles())
        flare:Spawn()
        flare:Activate()

        local dir  = targetPos - flare:GetPos()
        local dist = dir:Length()
        dir:Normalize()

        timer.Simple(0, function()
            if not IsValid(flare) then return end
            local phys = flare:GetPhysicsObject()
            if not IsValid(phys) then
                MI12_Debug("Flare physics invalid after spawn")
                return
            end
            phys:SetVelocity(dir * 700 + Vector(0, 0, dist * 0.25))
            phys:Wake()
        end)

        net.Start("MI12_FlareSpawned")
        net.WriteEntity(flare)
        net.Broadcast()

        MI12_Debug("Flare thrown successfully")
        return flare
    end

    local function SpawnMI12AtPos(centerPos)
        if not scripted_ents.GetStored("ent_mi12_heli") then
            MI12_Debug("Heli spawn failed: ent_mi12_heli is not registered")
            return false
        end

        local heli = ents.Create("ent_mi12_heli")
        if not IsValid(heli) then
            MI12_Debug("Heli spawn failed: ents.Create returned invalid entity")
            return false
        end

        local randomDir = RandomFlatDir()

        heli:SetPos(centerPos)
        heli:SetAngles(randomDir:Angle())
        heli:SetVar("CenterPos",    centerPos)
        heli:SetVar("CallDir",      randomDir)
        heli:SetVar("Lifetime",     cv_life:GetFloat())
        heli:SetVar("Speed",        cv_speed:GetFloat())
        heli:SetVar("OrbitRadius",  cv_radius:GetFloat())
        heli:SetVar("SkyHeightAdd", cv_height:GetFloat())
        heli:Spawn()
        heli:Activate()

        if not IsValid(heli) then
            MI12_Debug("Heli invalid after Spawn()")
            return false
        end

        MI12_Debug("Heli entity created with random orbit dir " .. tostring(randomDir))
        return true
    end

    local function FireMI12(npc, target)
        if not IsValid(npc) then
            MI12_Debug("Call rejected: npc invalid") return false
        end
        if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
            MI12_Debug("Call rejected: target invalid") return false
        end

        local targetPos = target:GetPos() + Vector(0, 0, 36)
        if not CheckSkyAbove(targetPos) then
            MI12_Debug("Call rejected: no open sky above target") return false
        end

        local flare = ThrowSupportFlare(npc, targetPos)
        if not IsValid(flare) then
            MI12_Debug("Call rejected: flare could not be created") return false
        end

        local fallbackPos = Vector(targetPos.x, targetPos.y, targetPos.z)

        MI12_Debug("Flare deployed, waiting " .. cv_delay:GetFloat() .. "s")

        timer.Simple(cv_delay:GetFloat(), function()
            local centerPos = IsValid(flare) and flare:GetPos() or fallbackPos
            MI12_Debug("Attempting heli spawn at " .. tostring(centerPos))
            SpawnMI12AtPos(centerPos)
        end)

        return true
    end

    -- Manual spawn via Q-menu button
    net.Receive("MI12_ManualSpawn", function(len, ply)
        if not IsValid(ply) then return end
        local eyePos = ply:EyePos()
        SpawnMI12AtPos(eyePos)
        MI12_Debug("Manual spawn by " .. ply:Nick())
    end)

    -- NPC trigger loop
    timer.Create("MI12_Think", 0.5, 0, function()
        if not cv_enabled:GetBool() then return end

        local now      = CurTime()
        local interval = math.max(1, cv_interval:GetFloat())

        for _, npc in ipairs(ents.GetAll()) do
            if not IsValid(npc) or not CALLERS[npc:GetClass()] then continue end

            if not npc.__mi12_hooked then
                npc.__mi12_hooked    = true
                npc.__mi12_nextCheck = now + math.Rand(1, interval)
                npc.__mi12_lastCall  = 0
            end

            if now < npc.__mi12_nextCheck then continue end

            local jitter = math.min(2, interval * 0.5)
            npc.__mi12_nextCheck = now + interval + math.Rand(-jitter, jitter)

            if now - npc.__mi12_lastCall < cv_cooldown:GetFloat() then continue end
            if npc:Health() <= 0 then continue end

            local enemy = npc:GetEnemy()
            if not IsValid(enemy) or not enemy:IsPlayer() or not enemy:Alive() then continue end

            local dist = npc:GetPos():Distance(enemy:GetPos())
            if dist > cv_max_dist:GetFloat() or dist < cv_min_dist:GetFloat() then continue end
            if math.random() > cv_chance:GetFloat() then continue end

            if FireMI12(npc, enemy) then
                npc.__mi12_lastCall = now
                MI12_Debug("Flyover accepted for " .. tostring(enemy))
            end
        end
    end)
end

if CLIENT then
    local activeFlares = {}

    net.Receive("MI12_FlareSpawned", function()
        local flare = net.ReadEntity()
        if IsValid(flare) then
            activeFlares[flare:EntIndex()] = flare
        end
    end)

    hook.Add("Think", "MI12_FlareLight", function()
        for idx, flare in pairs(activeFlares) do
            if not IsValid(flare) then
                activeFlares[idx] = nil
                continue
            end
            local dlight = DynamicLight(flare:EntIndex())
            if dlight then
                dlight.Pos        = flare:GetPos()
                dlight.r          = 0
                dlight.g          = 80
                dlight.b          = 255
                dlight.Brightness = (math.random() > 0.4) and math.Rand(4.0, 6.0) or math.Rand(0.0, 0.2)
                dlight.Size       = 55
                dlight.Decay      = 3000
                dlight.DieTime    = CurTime() + 0.05
            end
        end
    end)
end
