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

-- Same model as the LFS vehicle
ENT.ModelPath = "models/tfre/vehicles/Mi12_Homer.mdl"

-- Door prop models (same TF:RE pack, same folder as main model)
-- LFS SpawnFunction spawns both as prop_physics parented to the heli.
-- Door_Closed is solid at spawn (doors shut). Door_Open is non-solid (hidden).
-- Swap solidity to open/close — exactly as LFS PrimaryAttack does.
ENT.DoorModelClosed = "models/tfre/vehicles/Mi12_Homer_Door_Closed.mdl"
ENT.DoorModelOpen   = "models/tfre/vehicles/Mi12_Homer_Door_Open.mdl"

-- Health
ENT.MaxHP = 3800

-- Rotor (used by cl_init for bone anim)
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
