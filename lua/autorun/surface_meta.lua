local META = FindMetaTable( "Player" )

function META:SetSurface( ent )

	if self:GetSurface() ~= ent then
		self:SetNWEntity( "Surface", ent )
	end

	if SERVER then
		local phys = self:GetPhysicsObject()

		if IsValid( phys ) then
			phys:EnableCollisions( not IsValid( ent ) )
		end
	end

	if IsValid( ent ) then
		self:SetNWVector( "Surface Offset", ent:WorldToLocal( self:GetPos() ) )
		self:SetNWAngle( "Surface Angle", ent:GetAngles() )
	end

end

function META:GetSurface()

	local ent = self:GetNWEntity( "Surface", ent )

	if IsValid( ent ) then
		return ent, ent:LocalToWorld( self:GetNWVector( "Surface Offset", vector_origin ) ), self:GetNWAngle( "Surface Angle", angle_zero )
	end

	return ent, vector_origin

end

function META:HasSurface()

	return IsValid( self:GetSurface() )

end

function META:SetSurfaceVelocity( vel )

	self:SetNWVector( "Surface Velocity", vel )

end

function META:GetSurfaceVelocity( vel )

	return self:GetNWVector( "Surface Velocity", vector_origin )

end

function META:CheckSurface()

	local pos = self:GetPos()
	local mins, maxs = self:GetCollisionBounds()

	local tr = util.TraceHull( {
		start = pos,
		endpos = pos - vector_up * self:GetStepSize(),
		filter = self,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID
	} )

	if tr.Entity:IsPlayer() or tr.Entity:IsWorld() then
		return NULL
	end

	return tr.Entity, tr.HitNormal.z

end

function META:GetMaxGroundSpeed()

	local speed = self:GetSequenceGroundSpeed( self:GetSequence() )

	if speed <= 1 then
		return 1
	end

	return speed

end
