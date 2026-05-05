--DO NOT EDIT OR REUPLOAD THIS FILE

ENT.Type            = "anim"
DEFINE_BASECLASS( "lunasflightschool_basescript_heli" )

ENT.PrintName = "Mi V-12"
ENT.Author = "Luna"
ENT.Information = ""
ENT.Category = "[LFS] TF:RE"

ENT.Spawnable		= true
ENT.AdminSpawnable	= false

ENT.MDL = "models/tfre/vehicles/Mi12_Homer.mdl"

ENT.GibModels = {
	"models/tfre/vehicles/Mi12_Homer_Dead.mdl",
	"models/tfre/vehicles/Mi12_Homer_Dead_Wing.mdl",
}

ENT.AITEAM = 0

ENT.Mass = 15000
ENT.Inertia = Vector(50000,50000,50000)
ENT.Drag = 1

ENT.SeatPos = Vector(660,-27,126)
ENT.SeatAng = Angle(0,-90,10)

ENT.WheelAutoRetract = true
ENT.WheelMass = 150
ENT.WheelRadius = 13
ENT.WheelPos_L = Vector(15.669,261.73,5.85)
ENT.WheelPos_R = Vector(15.669,-261.73,5.85)
ENT.WheelPos_C = Vector(485.23,0,10.715)

ENT.MaxThrustHeli = 15
ENT.MaxTurnPitchHeli = 40
ENT.MaxTurnYawHeli = 40
ENT.MaxTurnRollHeli = 40

ENT.ThrustEfficiencyHeli = 5

ENT.RotorPos = Vector(95.991,0,390.62)
ENT.RotorAngle = Angle(2,0,0)
ENT.RotorRadius = 710

ENT.MaxHealth = 3800

ENT.MaxPrimaryAmmo = -1
ENT.MaxSecondaryAmmo = -1

sound.Add( {
	name = "tfre_mi12",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 125,
	sound = "^lfs/tfre_mi12/engine.wav"
} )
