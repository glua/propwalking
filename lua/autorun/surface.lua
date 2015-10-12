local surface_enable = CreateConVar( "surface_enabled", "1" )
local sv_gravity, sv_accelerate, sv_friction, sv_stopspeed = GetConVar( "sv_gravity" ), GetConVar( "sv_accelerate" ), GetConVar( "sv_friction" ), GetConVar( "sv_stopspeed" )
local sv_airaccelerate = GetConVar( "sv_airaccelerate" )

local MAX_CLIP_PLANES = 5

local function StepCalculate( ply, pos )

	local mins, maxs = ply:GetCollisionBounds()

	-- Are we in empty space?
	local tr = util.TraceHull {
		start = pos,
		endpos = pos,
		filter = ply,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID
	}

	local old = tr.HitPos

	if tr.Hit then
		-- Not in empty space, try stepping upwards

		local tr = util.TraceHull {
			start = pos + vector_up * ply:GetStepSize(),
			endpos = pos,
			filter = ply,
			mins = mins,
			maxs = maxs,
			mask = MASK_PLAYERSOLID
		}

		-- We are stuck or floating
		if tr.StartSolid or not tr.Hit then return false end

		return tr.HitPos
	end

	-- In empty space, step down and return happy
	local tr = util.TraceHull {
		start = pos,
		endpos = pos - vector_up * ply:GetStepSize(),
		filter = ply,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID
	}

	return tr.HitPos

end

local function ApplyFriction( vel )

	local speed = vel:Length()

	-- Friction is not applied if we are moving at less than 0.1 units per second
	if speed < 0.1 then return end

	-- Calculate how much speed to reduce the velocity by
	local friction = math.max( speed, sv_stopspeed:GetFloat() ) * sv_friction:GetFloat() * FrameTime()

	-- Reduce the velocity's magnitude
	vel:Normalize(); vel:Mul( math.max( speed - friction, 0 ) )

end

local function ApplyGravity( vel )

	vel.z = vel.z - sv_gravity:GetFloat() * FrameTime()

end

local function TestPos( ply, pos )

	local mins, maxs = ply:GetCollisionBounds()

	-- Are we in empty space?
	local tr = util.TraceHull {
		start = pos,
		endpos = pos,
		filter = ply,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID
	}

	return not tr.Hit

end

local function TryMove( ply, pos, vel )

	-- TODO: Push off of planes, allow partial movement, etc.
	local pos = StepCalculate( ply, pos + vel * FrameTime() )

	if pos and not TestPos( ply, pos ) then
		return false
	end

	return pos

end

local function WalkMove( ply, mv, cmd, vel )

	local ang = cmd:GetViewAngles(); ang.p = 0; ang.r = 0

	-- Calcualte acceleration direction and speed
	local accel = ang:Forward() * cmd:GetForwardMove() + ang:Right() * cmd:GetSideMove()
	local accel_speed = math.min( accel:Length(), mv:GetMaxClientSpeed() )

	if ply:Crouching() then
		accel_speed = accel_speed * ply:GetCrouchedWalkSpeed()
	end

	accel:Normalize()

	-- Apply acceleration
	local add_speed = accel_speed - vel:Dot( accel )

	if add_speed > 0 then
		local accel_speed = sv_accelerate:GetFloat() * FrameTime() * accel_speed

		if accel_speed > add_speed then
			accel_speed = add_speed
		end

		accel:Mul( accel_speed )
		vel:Add( accel )
	end

	--CalculateStep

end

local function AirMove( ply, mv, cmd, vel )

	-- TODO: Air Acceleration

	return WalkMove( ply, mv, cmd, vel )

end

hook.Add( "SetupMove", "Surface", function( ply, mv, cmd )

	if ply:GetMoveType() ~= MOVETYPE_WALK or not surface_enable:GetBool() then
		ply:SetSurface( NULL )

		return
	end

	-- If we don't have a surface and aren't on the ground, what we doing here?
	if not ply:OnGround() and not ply:HasSurface() then
		return
	end

	local surface = ply:CheckSurface()

	-- Keep the player's surface up to date
	if not ply:HasSurface() then -- and surface ~= ply:GetSurface() then
		ply:SetSurface( surface )

		if IsValid( surface ) then
			ply:SetSurfaceVelocity( ply:GetAbsVelocity() )
		end
	end

	if not ply:HasSurface() then return end

	local vel = ply:GetSurfaceVelocity()

	ApplyFriction( vel )
	WalkMove( ply, mv, cmd, vel )

	ply:SetGroundEntity( surface )
	ply:SetSurfaceVelocity( vel )
	mv:SetVelocity( vel )

end )

hook.Add( "FinishMove", "Surface", function( ply, mv )

	if not ply:HasSurface() or not surface_enable:GetBool() then return end

	-- Reset this to avoid gravity pulling us down
	mv:SetVelocity( ply:GetSurfaceVelocity() )

	local ent, pos, ang = ply:GetSurface()

	pos = TryMove( ply, pos, mv:GetVelocity() )

	if pos then
		ply:SetPos( pos )
		ply:SetLocalPos( pos )
		ply:SetNetworkOrigin( pos )
		mv:SetOrigin( pos )
	end

	-- TODO: Not use SetLocalVelocity when SetAbsVelocity is fixed.
	ply:SetLocalVelocity( mv:GetVelocity() )
	ply:SetAbsVelocity( mv:GetVelocity() )
	ply:SetLocalAngles( mv:GetAngles() )

	-- Re-update our offset if we have tried to move, checking for any new surfaces
	-- This means you'll never fall off if you are not moving, remove the check if you want to fix that.
	if mv:GetVelocity():Length() > 0 then
		ply:SetSurface( ply:CheckSurface() )
	end

	-- We don't want the engine to change our positions
	return true

end )

-- A relative vector is passed for when the origin is different to the targetted pos (Viewmodel sway)
local function SetSurfaceViewOrigin( ply, origin, relative )
	if not ply:HasSurface() then return end
	if ply:GetViewEntity() ~= ply then return end

	local ent, pos = ply:GetSurface()
	pos:Add( ply:GetCurrentViewOffset() )

	if relative then
		relative:Sub( origin )
	end

	origin:Set( pos )

	if relative then
		origin:Sub( relative )
		relative:Add( origin )
	end
end

hook.Add( "CalcView", "Surface Anti-Interpolation", function( ply, origin )
	SetSurfaceViewOrigin( ply, origin )
end )

hook.Add( "CalcViewModelView", "Surface Anti-Interpolation", function( wep, _, relative, _, origin, _ )
	SetSurfaceViewOrigin( wep:GetOwner(), origin, relative )
end )

local DRAWING = false

hook.Add( "PrePlayerDraw", "Surface Anti-Interpolation", function( ply )
	if not ply:HasSurface() or DRAWING then return end

	local ent, pos = ply:GetSurface()

	ply:SetNetworkOrigin( pos )
	ply:SetLocalPos( pos )
	ply:SetPos( pos )

	local vel = ply:GetSurfaceVelocity()

	ply:SetLocalVelocity( vel )
	ply:SetAbsVelocity( vel )

	local ang = ply:EyeAngles(); ang.p = 0
	local move_x, move_y = vel:Dot( ang:Forward() ), vel:Dot( ang:Right() )

	--ply:ClearPoseParameters()
	ply:SetPoseParameter( "move_x", move_x * ply:GetPlaybackRate() / ply:GetMaxGroundSpeed() )
	ply:SetPoseParameter( "move_y", move_y * ply:GetPlaybackRate() / ply:GetMaxGroundSpeed() )

	ply:InvalidateBoneCache()
	ply:SetupBones()

	local wep = ply:GetActiveWeapon()

	DRAWING = true
		if IsValid( wep ) then
			wep:InvalidateBoneCache()
			wep:SetupBones()

			wep:DrawModel()
		end

		ply:DrawModel()
	DRAWING = false

	return true

end )
