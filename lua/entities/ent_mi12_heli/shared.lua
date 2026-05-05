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
ENT.EngineSound    = "^lfs/tfre_mi12/engine.wav"

-- ─── Health & Damage ──────────────────────────────────────
ENT.MaxHP          = 3800

-- ─── Rotor ────────────────────────────────────────────────
ENT.LimitRPM       = 3000
ENT.IdleRPM        = 700

-- ─── Physics ──────────────────────────────────────────────
ENT.Mass           = 15000

-- ─── Flight tuning ────────────────────────────────────────
-- Movement is driven from Think() via SetPos/SetAngles (MOVETYPE_NONE).
-- PhysicsUpdate is NOT used because MOVETYPE_NOCLIP/NONE with SOLID_NONE
-- never fires PhysicsUpdate callbacks in GMod.
ENT.FadeDuration    = 1.2    -- seconds to fade in (was 4.0 — too slow)
ENT.AltDriftRange   = 40     -- HU amplitude of altitude sine-drift
ENT.AltDriftLerp    = 0.015  -- smoothing factor per Think tick
ENT.JitterAmplitude = 2.5    -- per-tick altitude noise
ENT.AlertInterval   = 18

-- ─── Rotor geometry ───────────────────────────────────────
ENT.RotorPos    = Vector(95.991, 0, 390.62)
ENT.RotorRadius = 710

-- ─── Gib models ───────────────────────────────────────────
ENT.GibModels = {
    "models/tfre/vehicles/Mi12_Homer_Dead.mdl",
    "models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
    "models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
}

-- ─── Door models ──────────────────────────────────────────
ENT.DoorModelClosed = "models/tfre/vehicles/Mi12_Homer_Door_Closed.mdl"
ENT.DoorModelOpen   = "models/tfre/vehicles/Mi12_Homer_Door_Open.mdl"

-- ─── Sound registration ───────────────────────────────────
if not sound.GetProperties("tfre_mi12") then
    sound.Add({
        name    = "tfre_mi12",
        channel = CHAN_STATIC,
        volume  = 1.0,
        level   = 125,
        sound   = ENT.EngineSound,
    })
end
