-- ============================================================
--  MI-12 Homer — Shared Constants
--  lua/entities/ent_mi12_heli/shared.lua
-- ============================================================

ENT.Type           = "anim"
ENT.Base           = "base_anim"
ENT.PrintName      = "MI-12 Homer"
ENT.Author         = "Bombin Addons"
ENT.Category       = "Bombin Support"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- ─── Model ────────────────────────────────────────────────
ENT.ModelPath      = "models/tfre/vehicles/Mi12_Homer.mdl"

-- ─── Sound ────────────────────────────────────────────────
-- Stereo loop; ^ prefix = positional stereo in GMod
ENT.EngineSound    = "^lfs/tfre_mi12/engine.wav"

-- ─── Health & Damage ──────────────────────────────────────
ENT.MaxHP          = 3800

-- ─── Rotor ────────────────────────────────────────────────
ENT.LimitRPM       = 3000    -- RPM at which rotor is at 100% disc blur
ENT.IdleRPM        = 700     -- RPM below which blades droop (we never go here)

-- ─── Physics ──────────────────────────────────────────────
ENT.Mass           = 15000

-- ─── Flight tuning ────────────────────────────────────────
ENT.FadeDuration   = 4.0     -- seconds to fade in on spawn
ENT.AltDriftRange  = 40      -- HU amplitude of altitude sine-drift
ENT.AltDriftLerp   = 0.015   -- smoothing toward target altitude
ENT.JitterAmplitude= 2.5     -- per-tick altitude noise
ENT.AlertInterval  = 18      -- seconds between NPC alert pulses

-- ─── Rotor geometry (Mi-12 Homer mesh) ───────────────────
ENT.RotorPos       = Vector(95.991, 0, 390.62)  -- local center between both rotors
ENT.RotorRadius    = 710                         -- HU tip-to-center on each rotor

-- ─── Gib models ───────────────────────────────────────────
ENT.GibModels = {
    "models/tfre/vehicles/Mi12_Homer_Dead.mdl",
    "models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
    "models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
}

-- ─── Door models ──────────────────────────────────────────
ENT.DoorModelClosed = "models/tfre/vehicles/Mi12_Homer_Door_Closed.mdl"
ENT.DoorModelOpen   = "models/tfre/vehicles/Mi12_Homer_Door_Open.mdl"

-- ─── Sound registration (runs on both realms) ─────────────
if not sound.GetProperties("tfre_mi12") then
    sound.Add({
        name    = "tfre_mi12",
        channel = CHAN_STATIC,
        volume  = 1.0,
        level   = 125,
        sound   = ENT.EngineSound,
    })
end
