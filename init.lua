--DO NOT EDIT OR REUPLOAD THIS FILE
-- SetNWBool("CargoDoorOpen") added so cl_init vapor/light effects
-- receive reliable open/close signals from the server.

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include("shared.lua")

function ENT:SpawnFunction( ply, tr, ClassName )
	if not tr.Hit then return end

	local ent = ents.Create( ClassName )
	ent.dOwnerEntLFS = ply
	ent:SetPos( tr.HitPos + tr.HitNormal * 80 )
	ent:Spawn()
	ent:Activate()
	
	ent.doornum = 1
	ent:SetNWBool( "CargoDoorOpen", false )  -- init networked door state
	
	ent.doormdl = ents.Create( "prop_physics" )
	ent.doormdl:SetModel( "models/tfre/vehicles/Mi12_Homer_Door_Closed.mdl" )
	
	ent.doormdl2 = ents.Create( "prop_physics" )
	ent.doormdl2:SetModel( "models/tfre/vehicles/Mi12_Homer_Door_Open.mdl" )
	
	ent.doormdl:SetPos( ent:GetPos() )
	ent.doormdl:SetAngles( ent:GetAngles() )
	ent.doormdl.DoNotDuplicate = true
	ent.doormdl:SetParent( ent )
	ent.doormdl:Spawn()
	
	ent.doormdl2:SetPos( ent:GetPos() )
	ent.doormdl2:SetAngles( ent:GetAngles() )
	ent.doormdl2.DoNotDuplicate = true
	ent.doormdl2:SetParent( ent )
	ent.doormdl2:Spawn()
	
	ent.doormdl:SetNotSolid(true)
	ent.doormdl2:SetNotSolid(false)
	
	--ent.doorweld = constraint.Weld( ent.doormdl, ent, 0, 0, 0, 1, 1) --old method
	
	ent:CallOnRemove("RemoveDoorBlocker",function(ent)
			ent.doormdl:Remove()
			ent.doormdl2:Remove()
		end)
	
	return ent
end

function ENT:OnTick()
end

function ENT:RunOnSpawn()
	self:SetNWBool( "CargoDoorOpen", false )  -- safety: ensure NW var exists on server ent
	local PassengerSeats = {
		{
			pos = Vector(660,27,126),
			ang = Angle(0,-90,10)
		},
		{
			pos = Vector(611.21,0,210),
			ang = Angle(0,-90,10)
		},
	}
	
	for num, v in pairs( PassengerSeats ) do
		local Pod = self:AddPassengerSeat( v.pos, v.ang )

		if num == 1 then
			self:SetGunnerSeat( Pod )
		end
	end
end

function ENT:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	
	self:SetNextPrimary( 1 )
	
	if self.doornum == 0 then
		-- Doors are closing -> open them
		self:PlayAnimation("Open")
		self.doormdl:SetNotSolid(true)
		self.doornum = 1
		self:SetNWBool( "CargoDoorOpen", true )   -- signal clients: trigger vapor + light
	else
		-- Doors are open -> close them
		self:PlayAnimation("Close")
		self.doormdl:SetNotSolid(false)
		self.doornum = 0
		self:SetNWBool( "CargoDoorOpen", false )  -- signal clients: stop effects
	end
end

function ENT:SecondaryAttack()
end

function ENT:HandleWeapons(Fire1)
	local Driver = self:GetDriver()
	
	if IsValid( Driver ) then
		Fire1 = Driver:KeyDown( IN_ATTACK )
	end
	
	if Fire1 then
		self:PrimaryAttack()
	end
end

function ENT:CreateAI()
	self:SetBodygroup( 1, 1 ) 
end

function ENT:RemoveAI()
	self:SetBodygroup( 1, 0 ) 
end

function ENT:OnEngineStarted()
	self:SetSkin(1)
end

function ENT:OnEngineStopped()
	self:SetSkin(0)
end

function ENT:OnEngineStartInitialized()
	self:EmitSound( "lfs/heli_start_generic.ogg")
end

--[[
function ENT:OnEngineStopInitialized()
end

function ENT:OnRotorCollide( Pos, Dir )
	local effectdata = EffectData()
		effectdata:SetOrigin( Pos )
		effectdata:SetNormal( Dir )
	util.Effect( "manhacksparks", effectdata, true, true )

	self:EmitSound( "ambient/materials/roust_crash"..math.random(1,2)..".wav" )
end
]]

function ENT:OnRotorDestroyed()
	self:EmitSound( "physics/metal/metal_box_break2.wav" )
	
	self:SetBodygroup( 2, 2 )
	self:SetBodygroup( 3, 2 ) 
	
	self:SetHP(1)
	
	timer.Simple(2, function()
		if not IsValid( self ) then return end
		self:Destroy()
	end)
end
