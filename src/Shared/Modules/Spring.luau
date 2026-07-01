--!strict
--@author OrkGabb
--@module Spring.luau
--@version 1.0
-- src/Shared/Modules/Spring.luau
-- Strictly typed physics spring utility for weapon sway, bobbing, and recoil.

export type Spring = {
	Target: Vector3,
	Position: Vector3,
	Velocity: Vector3,
	Mass: number,
	Force: number,
	Damping: number,
	Speed: number,
	shove: (self: Spring, force: Vector3) -> (),
	update: (self: Spring, dt: number) -> Vector3,
}

local SpringModule = {}

function SpringModule.create(mass: number?, force: number?, damping: number?, speed: number?): Spring
	local self: Spring = {
		Target = Vector3.zero,
		Position = Vector3.zero,
		Velocity = Vector3.zero,
		Mass = mass or 5,
		Force = force or 50,
		Damping = damping or 4,
		Speed = speed or 4,
		shove = nil :: any,
		update = nil :: any,
	}

	function self.shove(s: Spring, f: Vector3): ()
		local x, y, z = f.X, f.Y, f.Z
		if x ~= x or x == math.huge or x == -math.huge then x = 0 end
		if y ~= y or y == math.huge or y == -math.huge then y = 0 end
		if z ~= z or z == math.huge or z == -math.huge then z = 0 end
		s.Velocity = s.Velocity + Vector3.new(x, y, z)
	end

	function self.update(s: Spring, dt: number): Vector3
		local ITERATIONS = 8
		local scaledDeltaTime = (math.min(dt, 1) * s.Speed) / ITERATIONS
		for _ = 1, ITERATIONS do
			local iterationForce = s.Target - s.Position
			local acceleration = (iterationForce * s.Force) / s.Mass
			acceleration = acceleration - s.Velocity * s.Damping
			s.Velocity = s.Velocity + acceleration * scaledDeltaTime
			s.Position = s.Position + s.Velocity * scaledDeltaTime
		end
		return s.Position
	end

	return self
end

return SpringModule
