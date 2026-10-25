--!strict
--[[
	HitValidation
	Pure rules for server-authoritative melee. No Roblox services are used here,
	so every rule is unit-tested outside Studio.

	The client only says "I want to swing, aiming here". The server:
	  1. checks the swing is allowed now (cooldown + combo state),   -> tryStartSwing
	  2. decides the facing direction, using the client aim only
	     if it is close to the server's own view of the character,   -> resolveAim
	  3. finds targets with its own positions and this cone test.    -> isInSwingCone

	Positions and directions only need .X/.Y/.Z, so both Roblox Vector3 and
	plain tables work. Height (Y) is ignored: swings are flat cones.
]]

export type Vec = { X: number, Y: number, Z: number }

export type WeaponRules = {
	ComboDamage: { number },
	Range: number,
	ArcDegrees: number,
	Cooldown: number,
	ComboWindow: number,
	ComboEndLag: number,
}

export type SwingState = {
	nextSwingAt: number, -- earliest server time the next swing is allowed
	comboIndex: number, -- index of the LAST swing performed; 0 = none
	comboExpiresAt: number, -- after this time the combo restarts at 1
}

export type SwingResult = {
	ok: boolean,
	reason: string?, -- "cooldown" when ok == false
	comboIndex: number, -- which hit of the combo this swing is (1-based)
	damage: number,
	isFinisher: boolean,
}

local HitValidation = {}

function HitValidation.newState(): SwingState
	return { nextSwingAt = 0, comboIndex = 0, comboExpiresAt = 0 }
end

-- Decides whether a swing may start at server time `now`.
-- On success, mutates `state` to record the swing.
-- `tolerance` forgives tiny timing differences (frame jitter), not lag abuse.
function HitValidation.tryStartSwing(
	state: SwingState,
	weapon: WeaponRules,
	now: number,
	tolerance: number?
): SwingResult
	local slack = tolerance or 0
	if now + slack < state.nextSwingAt then
		return {
			ok = false,
			reason = "cooldown",
			comboIndex = state.comboIndex,
			damage = 0,
			isFinisher = false,
		}
	end

	local comboLength = #weapon.ComboDamage
	local index: number
	if state.comboIndex == 0 or now > state.comboExpiresAt or state.comboIndex >= comboLength then
		index = 1
	else
		index = state.comboIndex + 1
	end

	local isFinisher = index == comboLength
	state.comboIndex = index
	state.comboExpiresAt = now + weapon.ComboWindow
	state.nextSwingAt = now + weapon.Cooldown + (if isFinisher then weapon.ComboEndLag else 0)

	return {
		ok = true,
		reason = nil,
		comboIndex = index,
		damage = weapon.ComboDamage[index],
		isFinisher = isFinisher,
	}
end

local function flatUnit(v: Vec): (number, number, number)
	local length = math.sqrt(v.X * v.X + v.Z * v.Z)
	if length < 1e-6 then
		return 0, 0, 0
	end
	return v.X / length, v.Z / length, length
end

-- Angle in degrees between two directions on the flat (XZ) plane.
-- Returns 180 when either vector has no flat component.
function HitValidation.flatAngleDegrees(a: Vec, b: Vec): number
	local ax, az, la = flatUnit(a)
	local bx, bz, lb = flatUnit(b)
	if la < 1e-6 or lb < 1e-6 then
		return 180
	end
	local dot = math.clamp(ax * bx + az * bz, -1, 1)
	return math.deg(math.acos(dot))
end

-- Picks the facing direction for the swing.
-- The client's aim is trusted only within `maxDeviationDegrees` of the
-- server's view of the character's look direction. Otherwise the server view wins.
function HitValidation.resolveAim(
	serverLook: Vec,
	clientAim: Vec?,
	maxDeviationDegrees: number
): (Vec, boolean)
	if clientAim == nil then
		return serverLook, false
	end
	if HitValidation.flatAngleDegrees(serverLook, clientAim) <= maxDeviationDegrees then
		return clientAim, true
	end
	return serverLook, false
end

-- True when `target` lies inside the swing cone in front of `origin`.
-- `latencySlack` adds a small, capped amount of extra range for moving targets.
function HitValidation.isInSwingCone(
	origin: Vec,
	facing: Vec,
	target: Vec,
	weapon: WeaponRules,
	latencySlack: number?
): boolean
	local dx = target.X - origin.X
	local dz = target.Z - origin.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local maxRange = weapon.Range + (latencySlack or 0)
	if distance > maxRange then
		return false
	end
	-- A target standing inside the attacker counts as a hit.
	if distance < 0.5 then
		return true
	end
	local toTarget = { X = dx, Y = 0, Z = dz }
	return HitValidation.flatAngleDegrees(facing, toTarget) <= weapon.ArcDegrees / 2
end

-- Sorts candidate targets by distance and keeps at most `maxTargets` inside the cone.
-- `candidates` is a list of { id = any, position = Vec }.
function HitValidation.selectTargets(
	origin: Vec,
	facing: Vec,
	candidates: { { id: any, position: Vec } },
	weapon: WeaponRules,
	maxTargets: number,
	latencySlack: number?
): { any }
	local hits = {}
	for _, candidate in candidates do
		if HitValidation.isInSwingCone(origin, facing, candidate.position, weapon, latencySlack) then
			local dx = candidate.position.X - origin.X
			local dz = candidate.position.Z - origin.Z
			table.insert(hits, { id = candidate.id, distanceSq = dx * dx + dz * dz })
		end
	end
	table.sort(hits, function(a, b)
		return a.distanceSq < b.distanceSq
	end)
	local result = {}
	for i = 1, math.min(maxTargets, #hits) do
		result[i] = hits[i].id
	end
	return result
end

return HitValidation
