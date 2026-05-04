-- ============================================================
--  MI-12 shared constants
--  Must live here so ENT is populated on BOTH client and server.
-- ============================================================
ENT.Type   = "anim"
ENT.Base   = "base_anim"

ENT.PrintName      = "MI-12 Helicopter"
ENT.Author         = "Bombin Addons"
ENT.Spawnable      = false
ENT.AdminSpawnable = false
ENT.RenderGroup    = RENDERGROUP_OPAQUE

-- ── Tuning constants ─────────────────────────────────────────
-- TODO: replace placeholder values once MI-12 assets are final.
ENT.FadeDuration    = 2.0
ENT.ModelPath       = "models/mi12/mi12.mdl"   -- TODO: replace with real model path
ENT.EngineSound     = "vehicles/apc/apc_idle1.wav" -- TODO: replace with MI-12 rotor sound
ENT.MaxHP           = 10000   -- heavier airframe than AN-71
ENT.AltDriftRange   = 250
ENT.AltDriftLerp    = 0.001
ENT.JitterAmplitude = 4
ENT.AlertInterval   = 0.3
