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

-- Model
ENT.ModelPath    = "models/tfre/vehicles/Mi12_Homer.mdl"

-- Health
ENT.MaxHP        = 3800

-- Rotor (used by cl_init for bone anim)
ENT.LimitRPM     = 3000

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

-- Door bodygroup on the main model: index 1, value 0=closed, 1=open
-- There are NO separate door prop models — they never existed in the pack.
ENT.DoorBodygroupIndex = 1
ENT.DoorBodygroupOpen  = 1
ENT.DoorBodygroupClose = 0

-- Engine sound (standard GMod sound.Add name, no LFS prefix)
sound.Add({
    name    = "mi12_engine_loop",
    channel = CHAN_STATIC,
    volume  = 1.0,
    level   = 140,
    sound   = "lfs/tfre_mi12/engine.wav",
})
