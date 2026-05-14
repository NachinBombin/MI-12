--DO NOT EDIT OR REUPLOAD THIS FILE
-- Ported vapor follow + pulsing cargo light from ent_bombin_c17

include("shared.lua")

-- ============================================================
-- VAPOR SYSTEM  (ported from ent_bombin_c17/cl_init.lua)
-- ParticleEmitter is re-created on each door-open event.
-- LocalToWorld() is called every frame so particles always
-- emit from the correct world position as the heli moves.
-- ============================================================
local VAPOR_DURATION   = 1.5
local VAPOR_LOCAL      = Vector( 500, 0, -80 )   -- rear cargo ramp (Mi-12 local space; tune if needed)
local VAPOR_PER_FRAME  = 6
local VAPOR_LIFETIME   = 0.9
local VAPOR_SIZE_START = 18
local VAPOR_SIZE_END   = 55
local VAPOR_SPEED      = 90
local VAPOR_SPRITE     = "particle/particle_smokegrenade"

-- ============================================================
-- CARGO LIGHT  (ported from ent_bombin_c17/cl_init.lua)
-- Pulsing DynamicLight active only when CargoDoorOpen == true.
-- ============================================================
local CARGO_LIGHT_LOCAL    = Vector( 500, 0, -60 )
local CARGO_LIGHT_RADIUS   = 1400
local CARGO_LIGHT_DECAY    = 1200
local CARGO_LIGHT_MIN_BRIG = 0.35
local CARGO_LIGHT_MAX_BRIG = 1.0
local CARGO_LIGHT_PULSE_HZ = 0.6

-- ============================================================
-- ENGINE SOUND
-- ============================================================
function ENT:CalcEngineSound( RPM, Pitch, Doppler )
	local THR = RPM / self:GetLimitRPM()
	
	if self.ENG then
		self.ENG:ChangePitch( math.Clamp(math.min(RPM / self:GetIdleRPM(),1) * 100 + Doppler + THR * 20,0,255) )
		self.ENG:ChangeVolume( math.Clamp(THR,0.8,1) )
	end
end

function ENT:EngineActiveChanged( bActive )
	if bActive then
		self.ENG = CreateSound( self, "tfre_mi12" )
		self.ENG:PlayEx(0,0)
	else
		self:SoundStop()
	end
end

function ENT:OnRemove()
	self:SoundStop()
	if self._VaporEmitter then
		self._VaporEmitter:Finish()
		self._VaporEmitter = nil
	end
end

function ENT:SoundStop()
	if self.ENG then
		self.ENG:Stop()
	end
end

-- ============================================================
-- VAPOR
-- ============================================================
function ENT:StartVapor()
	if self._VaporEmitter then
		self._VaporEmitter:Finish()
		self._VaporEmitter = nil
	end
	local worldPos         = self:LocalToWorld( VAPOR_LOCAL )
	self._VaporEmitter     = ParticleEmitter( worldPos, true )
	self._VaporUntil       = CurTime() + VAPOR_DURATION
end

function ENT:UpdateVapor()
	if not self._VaporEmitter then return end
	local ct = CurTime()
	if ct >= self._VaporUntil then
		self._VaporEmitter:Finish()
		self._VaporEmitter = nil
		return
	end
	-- Re-compute world position every frame so particles follow the helicopter.
	local worldPos = self:LocalToWorld( VAPOR_LOCAL )
	local rearDir  = self:LocalToWorldAngles( Angle( 5, 180, 0 ) ):Forward()
	for _ = 1, VAPOR_PER_FRAME do
		local p = self._VaporEmitter:Add( VAPOR_SPRITE, worldPos )
		if p then
			local shade = math.random( 210, 255 )
			p:SetColor( shade, shade, shade )
			p:SetStartAlpha( math.random( 160, 200 ) )
			p:SetEndAlpha( 0 )
			p:SetStartSize( VAPOR_SIZE_START + math.Rand( -4, 4 ) )
			p:SetEndSize( VAPOR_SIZE_END + math.Rand( -8, 8 ) )
			p:SetLifeTime( 0 )
			p:SetDieTime( VAPOR_LIFETIME + math.Rand( -0.2, 0.3 ) )
			p:SetLighting( false )
			local scatter = Vector(
				math.Rand( -25, 25 ),
				math.Rand( -25, 25 ),
				math.Rand(  -8, 15 )
			)
			p:SetVelocity( rearDir * VAPOR_SPEED + scatter )
			p:SetGravity( Vector( 0, 0, 18 ) )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -1.5, 1.5 ) )
		end
	end
end

-- ============================================================
-- CARGO DOOR LIGHT
-- ============================================================
function ENT:UpdateCargoLight()
	if not self:GetNWBool( "CargoDoorOpen", false ) then return end
	local dl = DynamicLight( self:EntIndex() + 4096 )
	if not dl then return end
	local t      = CurTime() * CARGO_LIGHT_PULSE_HZ * math.pi * 2
	local frac   = ( math.sin( t ) + 1 ) * 0.5
	local bright = CARGO_LIGHT_MIN_BRIG + frac * ( CARGO_LIGHT_MAX_BRIG - CARGO_LIGHT_MIN_BRIG )
	dl.pos        = self:LocalToWorld( CARGO_LIGHT_LOCAL )
	dl.r          = 255
	dl.g          = 20
	dl.b          = 10
	dl.brightness = bright * 10
	dl.decay      = CARGO_LIGHT_DECAY
	dl.size       = CARGO_LIGHT_RADIUS
	dl.dietime    = CurTime() + 0.1
end

-- ============================================================
-- DOOR OPEN NW TRACKING (rising-edge trigger for vapor)
-- ============================================================
function ENT:Initialize()
	self._DoorWasOpen  = false
	self._VaporEmitter = nil
	self._VaporUntil   = 0
end

-- ============================================================
-- FINS / ROTORS / CABIN  (original code, unchanged)
-- ============================================================
function ENT:AnimFins()
	local FT = FrameTime() * 10
	local Pitch = self:GetRotPitch()
	local Yaw = self:GetRotYaw()
	local Roll = -self:GetRotRoll()
	self.smPitch = self.smPitch and self.smPitch + (Pitch - self.smPitch) * FT or 0
	self.smYaw = self.smYaw and self.smYaw + (Yaw - self.smYaw) * FT or 0
	self.smRoll = self.smRoll and self.smRoll + (Roll - self.smRoll) * FT or 0
	
	self:ManipulateBoneAngles( 11, Angle( self.smRoll*60,0,0) )
	self:ManipulateBoneAngles( 14, Angle( self.smRoll*60,0,0) )
	
	self:ManipulateBoneAngles( 15, Angle( self.smPitch*75,0,0) )
	self:ManipulateBoneAngles( 16, Angle( self.smPitch*75,0,0) )
	self:ManipulateBoneAngles( 17, Angle( -self.smPitch*75,0,0) )
	self:ManipulateBoneAngles( 18, Angle( -self.smPitch*75,0,0) )
	
	self:ManipulateBoneAngles( 19, Angle( -self.smYaw*60,0,0 ) )
	self:ManipulateBoneAngles( 20, Angle( -self.smYaw*60,0,0 ) )
end

function ENT:AnimRotor()
	local RotorBlown = self:GetRotorDestroyed()
	
	if not RotorBlown then
		local RPM = self:GetRPM()
		local RPMMax = self.LimitRPM
		local PhysRot = RPM < 700
		local Bend1 = math.Remap( RPM , 0, RPMMax, 0, 10)
		local Bend2 = math.Remap( RPM , 0, RPMMax, 0, 4)
		local Bend3 = math.Remap( RPM , 0, RPMMax, 55, 0)
		self.RPM = self.RPM and (self.RPM + RPM * FrameTime() * (PhysRot and 3 or 1.5)) or 0

		self:ManipulateBoneAngles( 33, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 34, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 35, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 36, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 37, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 38, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 39, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 40, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 41, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 42, Angle(0,0,Bend2) )
		
		self:ManipulateBoneAngles( 45, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 46, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 47, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 48, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 49, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 50, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 51, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 52, Angle(0,0,Bend2) )
		self:ManipulateBoneAngles( 53, Angle(0,0,Bend1) )
		self:ManipulateBoneAngles( 54, Angle(0,0,Bend2) )
		
		self:ManipulateBoneAngles( 12, Angle(Bend3,0,0) )
		self:ManipulateBoneAngles( 13, Angle(-Bend3,0,0) )
		
		self:SetBodygroup( 2, PhysRot and 0 or 1 ) 
		self:SetBodygroup( 3, PhysRot and 0 or 1 ) 
		
		self:SetPoseParameter("rotor_spin", self.RPM )		
		self:InvalidateBoneCache()
	end
end

local mat = Material( "tfre/corona_heli" )

function ENT:Draw()
	self:DrawModel()

	-- ---- ported cargo effects ----
	self:UpdateCargoLight()

	local wantOpen = self:GetNWBool( "CargoDoorOpen", false )
	if wantOpen and not self._DoorWasOpen then
		self._DoorWasOpen = true
		self:StartVapor()
	elseif not wantOpen then
		self._DoorWasOpen = false
	end
	self:UpdateVapor()
	-- ---- end ported effects ----

	if self:GetEngineActive() then
		local Alpha = ( -( CurTime() % 2 ) + 1) * 255
		local Alpha2 = ( -( CurTime() % 0.5 ) + 1) * 150
		render.SetMaterial( mat )
		render.DrawSprite( self:LocalToWorld( Vector(-727.8,0,275.55) ), 70, 70, Color( 255, 255, 255, Alpha) )
		render.DrawSprite( self:LocalToWorld( Vector(242,0,284) ), 70, 70, Color( 255, 93, 0, Alpha) )
		render.DrawSprite( self:LocalToWorld( Vector(557.4,0,77.7) ), 70, 70, Color( 255, 93, 0, Alpha) )
		render.DrawSprite( self:LocalToWorld( Vector(109.74,675,345.42) ), 70, 70, Color( 255, 0, 0, Alpha) )
		render.DrawSprite( self:LocalToWorld( Vector(109.74,-675,345.42) ), 70, 70, Color( 0, 255, 0, Alpha) )
	end

end

function ENT:AnimCabin()
	local FT = FrameTime() * 10
	local Pitch = self:GetRotPitch()
	local Yaw = self:GetRotYaw()
	local Roll = -self:GetRotRoll()
	local RPM = (math.max( math.Round( ((self:GetRPM() - self:GetIdleRPM()) / (self:GetMaxRPM() - self:GetIdleRPM())) * 8, 0)))
	self.smPitch = self.smPitch and self.smPitch + (Pitch - self.smPitch) * FT or 0
	self.smYaw = self.smYaw and self.smYaw + (Yaw - self.smYaw) * FT or 0
	self.smRoll = self.smRoll and self.smRoll + (Roll - self.smRoll) * FT or 0
	self.smRPM = self.smRPM and self.smRPM + (RPM - self.smRPM) * FT or 0

	self:ManipulateBoneAngles(1,Angle(0,-self.smRoll*7,self.smPitch*15))
	self:ManipulateBoneAngles(2,Angle(0,-self.smRoll*7,self.smPitch*15))
	self:ManipulateBoneAngles(4,Angle(0,0,self.smRPM*5))
	self:ManipulateBoneAngles(3,Angle(0,0,self.smRPM*5))
	self:ManipulateBoneAngles(5,Angle(0,0,-self.smRPM*1))
	self:ManipulateBoneAngles(6,Angle(0,0,-self.smRPM*1))
	self:ManipulateBoneAngles(27, Angle( 0,0,self.smYaw*25 ) )
	self:ManipulateBoneAngles(28, Angle( 0,0,-self.smYaw*25 ) )
	self:ManipulateBoneAngles(29, Angle( 0,0,self.smYaw*25 ) )
	self:ManipulateBoneAngles(30, Angle( 0,0,-self.smYaw*25 ) )
	self:ManipulateBoneAngles(43, Angle( 0,0,self.smYaw*5 ) )
	self:ManipulateBoneAngles(31, Angle( 0,0,-self.smYaw*5 ) )
end

function ENT:AnimLandingGear()
end

function ENT:ExhaustFX()
end
