--DO NOT EDIT OR REUPLOAD THIS FILE

include("shared.lua")

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
end

function ENT:SoundStop()
	if self.ENG then
		self.ENG:Stop()
	end
end

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

		self:ManipulateBoneAngles( 33, Angle(0,0,Bend1) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 34, Angle(0,0,Bend2) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 35, Angle(0,0,Bend1) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 36, Angle(0,0,Bend2) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 37, Angle(0,0,Bend1) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 38, Angle(0,0,Bend2) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 39, Angle(0,0,Bend1) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 40, Angle(0,0,Bend2) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 41, Angle(0,0,Bend1) ) --handle rotor arm "A" bend
		self:ManipulateBoneAngles( 42, Angle(0,0,Bend2) ) --handle rotor arm "A" bend
		
		self:ManipulateBoneAngles( 45, Angle(0,0,Bend1) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 46, Angle(0,0,Bend2) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 47, Angle(0,0,Bend1) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 48, Angle(0,0,Bend2) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 49, Angle(0,0,Bend1) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 50, Angle(0,0,Bend2) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 51, Angle(0,0,Bend1) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 52, Angle(0,0,Bend2) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 53, Angle(0,0,Bend1) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 54, Angle(0,0,Bend2) ) --handle rotor arm "B" bend
		
		self:ManipulateBoneAngles( 12, Angle(Bend3,0,0) ) --handle rotor arm "B" bend
		self:ManipulateBoneAngles( 13, Angle(-Bend3,0,0) ) --handle rotor arm "B" bend
		
		self:SetBodygroup( 2, PhysRot and 0 or 1 ) 
		self:SetBodygroup( 3, PhysRot and 0 or 1 ) 
		
		self:SetPoseParameter("rotor_spin", self.RPM )		
		self:InvalidateBoneCache()
	end
end

local mat = Material( "tfre/corona_heli" )

function ENT:Draw()
	self:DrawModel()
	
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
