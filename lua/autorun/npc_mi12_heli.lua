-- ============================================================
--  MI-12 Homer — Spawner / NPC Trigger Loop
--  lua/autorun/npc_mi12_heli.lua
-- ============================================================

if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("MI12_FlareSpawned")
    util.AddNetworkString("MI12_ManualSpawn")

    local F = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

    local cv_enabled  = CreateConVar("npc_mi12_enabled",  "1",    F, "Enable MI-12 flyovers.")
    local cv_chance   = CreateConVar("npc_mi12_chance",   "0.12", F, "Probability per check (0-1).")
    local cv_interval = CreateConVar("npc_mi12_interval", "12",   F, "Check interval in seconds.")
    local cv_cooldown = CreateConVar("npc_mi12_cooldown", "50",   F, "Per-NPC cooldown in seconds.")
    local cv_max_dist = CreateConVar("npc_mi12_max_dist", "3000", F, "Max NPC-to-player distance.")
    local cv_min_dist = CreateConVar("npc_mi12_min_dist", "400",  F, "Min NPC-to-player distance.")
    local cv_delay    = CreateConVar("npc_mi12_delay",    "5",    F, "Delay after flare (seconds).")
    local cv_life     = CreateConVar("npc_mi12_lifetime", "40",   F, "Heli lifetime in seconds.")
    local cv_speed    = CreateConVar("npc_mi12_speed",    "280",  F, "Heli orbit speed (HU/s).")
    local cv_radius   = CreateConVar("npc_mi12_radius",   "3000", F, "Orbit radius (HU).")
    local cv_height   = CreateConVar("npc_mi12_height",   "5000", F, "Height above ground (HU).")
    local cv_debug    = CreateConVar("npc_mi12_announce", "0",    F, "Enable debug prints.")

    local CALLERS = {
        ["npc_combine_s"]     = true,
        ["npc_metropolice"]   = true,
        ["npc_combine_elite"] = true,
    }

    -- ─── Helpers ────────────────────────────────────────────
    local function Dbg(msg)
        if not cv_debug:GetBool() then return end
        local s = "[MI-12] " .. msg
        print(s)
        for _, p in ipairs(player.GetHumans()) do
            if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, s) end
        end
    end

    local function RandomFlatDir()
        local a = math.Rand(0, math.pi * 2)
        return Vector(math.cos(a), math.sin(a), 0)
    end

    local function CheckOpenSky(pos)
        local tr = util.TraceLine({
            start  = pos + Vector(0, 0, 50),
            endpos = pos + Vector(0, 0, 1200),
        })
        return not (tr.Hit and not tr.HitSky)
    end

    -- ─── Flare ──────────────────────────────────────────────
    local function ThrowFlare(npc, targetPos)
        local eyePos = npc:EyePos()
        local dir    = (targetPos - eyePos):GetNormalized()

        local flare = ents.Create("ent_bombin_flare_blue")
        if not IsValid(flare) then
            Dbg("Flare spawn failed: ent_bombin_flare_blue invalid")
            return nil
        end

        flare:SetPos(eyePos + dir * 52)
        flare:SetAngles(npc:GetAngles())
        flare:Spawn()
        flare:Activate()

        timer.Simple(0, function()
            if not IsValid(flare) then return end
            local phys = flare:GetPhysicsObject()
            if not IsValid(phys) then return end
            local toTarget = targetPos - flare:GetPos()
            local dist     = toTarget:Length()
            toTarget:Normalize()
            phys:SetVelocity(toTarget * 700 + Vector(0, 0, dist * 0.25))
            phys:Wake()
        end)

        net.Start("MI12_FlareSpawned")
        net.WriteEntity(flare)
        net.Broadcast()

        Dbg("Flare deployed")
        return flare
    end

    -- ─── Heli spawn ─────────────────────────────────────────
    --  IMPORTANT: base_anim has no SetVar/GetVar (those are LFS-only).
    --  We pass parameters via entity.SpawnParams before Spawn().
    --  init.lua reads them with ReadParam() in ENT:Initialize().
    local function SpawnHeliAt(centerPos)
        if not scripted_ents.GetStored("ent_mi12_heli") then
            Dbg("ent_mi12_heli is not registered")
            return false
        end

        local heli = ents.Create("ent_mi12_heli")
        if not IsValid(heli) then
            Dbg("ents.Create returned invalid")
            return false
        end

        local dir = RandomFlatDir()

        -- Set params on the table BEFORE Spawn() so Initialize() can read them.
        heli.SpawnParams = {
            CenterPos    = centerPos,
            CallDir      = dir,
            Lifetime     = cv_life:GetFloat(),
            Speed        = cv_speed:GetFloat(),
            OrbitRadius  = cv_radius:GetFloat(),
            SkyHeightAdd = cv_height:GetFloat(),
        }

        heli:SetPos(centerPos)
        heli:SetAngles(dir:Angle())
        heli:Spawn()
        heli:Activate()

        if not IsValid(heli) then
            Dbg("Heli invalid after Spawn()")
            return false
        end

        Dbg("MI-12 spawned at " .. tostring(centerPos))
        return true
    end

    -- ─── Manual spawn via Q-menu ─────────────────────────────
    net.Receive("MI12_ManualSpawn", function(_, ply)
        if not IsValid(ply) then return end
        SpawnHeliAt(ply:EyePos())
        Dbg("Manual spawn by " .. ply:Nick())
    end)

    -- ─── NPC trigger loop ────────────────────────────────────
    timer.Create("MI12_Think", 0.5, 0, function()
        if not cv_enabled:GetBool() then return end

        local now      = CurTime()
        local interval = math.max(1, cv_interval:GetFloat())

        for _, npc in ipairs(ents.GetAll()) do
            if not IsValid(npc) then continue end
            if not CALLERS[npc:GetClass()] then continue end

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
            if dist > cv_max_dist:GetFloat() then continue end
            if dist < cv_min_dist:GetFloat() then continue end
            if math.random() > cv_chance:GetFloat() then continue end

            if CallMI12(npc, enemy) then
                npc.__mi12_lastCall = now
            end
        end
    end)

    -- ─── Full call sequence ──────────────────────────────────
    function CallMI12(npc, target)
        if not IsValid(npc) then return false end
        if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return false end

        local targetPos = target:GetPos() + Vector(0, 0, 36)

        if not CheckOpenSky(targetPos) then
            Dbg("Rejected: no open sky")
            return false
        end

        local flare = ThrowFlare(npc, targetPos)
        if not IsValid(flare) then return false end

        local fallback = Vector(targetPos.x, targetPos.y, targetPos.z)
        Dbg("Flare out, waiting " .. cv_delay:GetFloat() .. "s")

        timer.Simple(cv_delay:GetFloat(), function()
            local spawnPos = IsValid(flare) and flare:GetPos() or fallback
            SpawnHeliAt(spawnPos)
        end)

        return true
    end
end

-- ─── CLIENT ─────────────────────────────────────────────────
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
            local dl = DynamicLight(flare:EntIndex())
            if dl then
                dl.Pos        = flare:GetPos()
                dl.r          = 0
                dl.g          = 80
                dl.b          = 255
                dl.Brightness = math.random() > 0.4
                    and math.Rand(4.0, 6.0)
                    or  math.Rand(0.0, 0.2)
                dl.Size       = 55
                dl.Decay      = 3000
                dl.DieTime    = CurTime() + 0.05
            end
        end
    end)
end
