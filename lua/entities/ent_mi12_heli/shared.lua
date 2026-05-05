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

-- Same model as LFS (ENT.MDL in shared.lua on main branch)
ENT.ModelPath = "models/tfre/vehicles/Mi12_Homer.mdl"

-- Door prop models — same TF:RE pack, same folder.
-- LFS SpawnFunction spawn state:
--   doormdl  (Door_Closed) = SetNotSolid(true)  — non-solid at spawn (hidden behind Door_Open)
--   doormdl2 (Door_Open)   = SetNotSolid(false) — solid at spawn (always visible)
-- Only doormdl is ever toggled. doormdl2 is never touched again.
-- doornum=1 at spawn = closed state (Door_Closed non-solid, Door_Open showing)
-- PrimaryAttack doornum==1 (else): SetNotSolid(false) on doormdl → Door_Closed slides in, hides Door_Open
-- PrimaryAttack doornum==0:        SetNotSolid(true)  on doormdl → Door_Closed hidden, Door_Open shows
ENT.DoorModelClosed = "models/tfre/vehicles/Mi12_Homer_Door_Closed.mdl"
ENT.DoorModelOpen   = "models/tfre/vehicles/Mi12_Homer_Door_Open.mdl"

-- Health
ENT.MaxHP = 3800

-- Rotor
ENT.LimitRPM = 3000

-- Flight tuning
ENT.FadeDuration    = 1.2
ENT.AltDriftRange   = 40
ENT.AltDriftLerp    = 0.015
ENT.JitterAmplitude = 2.5
ENT.AlertInterval   = 18

-- Gib models
ENT.GibModels = {
    "models/tfre/vehicles/Mi12_Homer_Dead.mdl",
    "models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
    "models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
}

-- Engine sound
sound.Add({
    name    = "mi12_engine_loop",
    channel = CHAN_STATIC,
    volume  = 1.0,
    level   = 140,
    sound   = "lfs/tfre_mi12/engine.wav",
})
