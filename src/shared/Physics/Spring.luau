--!strict
--[=[
    Project OVERCLOCK: Damped Harmonic Oscillator Spring Physics Module
    Provides 3D mass-spring-damper physics simulation for procedural camera recoil,
    weapon sway, viewmodel bobbing, and spring-driven UI components.
]=]

export type Spring = {
    Mass: number,
    Stiffness: number,
    Damping: number,
    Position: Vector3,
    Velocity: Vector3,
    Target: Vector3,

    Update: (self: Spring, dt: number) -> Vector3,
    Impulse: (self: Spring, velocity: Vector3) -> (),
    SetTarget: (self: Spring, target: Vector3) -> (),
    SetPosition: (self: Spring, position: Vector3) -> (),
    SetVelocity: (self: Spring, velocity: Vector3) -> (),
    Reset: (self: Spring, position: Vector3?) -> (),
}

local Spring = {}
Spring.__index = Spring

function Spring.new(
    mass: number?,
    stiffness: number?,
    damping: number?,
    initialPosition: Vector3?
): Spring
    local self = setmetatable({}, Spring)
    self.Mass = mass or 1.0
    self.Stiffness = stiffness or 150.0
    self.Damping = damping or 15.0
    self.Position = initialPosition or Vector3.zero
    self.Velocity = Vector3.zero
    self.Target = initialPosition or Vector3.zero
    return (self :: any) :: Spring
end

function Spring.Update(self: Spring, dt: number): Vector3
    if dt <= 0 then
        return self.Position
    end

    -- Sub-stepping to guarantee numerical stability across varying frame rates
    local MAX_SUBSTEP = 1 / 120
    local remaining = dt

    while remaining > 0 do
        local step = math.min(remaining, MAX_SUBSTEP)
        remaining -= step

        -- Spring force: F_spring = -k * (x - x0)
        -- Damping force: F_damping = -c * v
        -- Acceleration: a = (F_spring + F_damping) / m
        local displacement = self.Position - self.Target
        local springForce = -displacement * self.Stiffness
        local dampingForce = -self.Velocity * self.Damping
        local acceleration = (springForce + dampingForce) / math.max(self.Mass, 0.0001)

        -- Semi-implicit Euler integration for symplectic energy stability
        self.Velocity += acceleration * step
        self.Position += self.Velocity * step
    end

    return self.Position
end

function Spring.Impulse(self: Spring, velocity: Vector3): ()
    -- Compounds given velocity impulse directly with existing momentum
    self.Velocity += velocity
end

function Spring.SetTarget(self: Spring, target: Vector3): ()
    self.Target = target
end

function Spring.SetPosition(self: Spring, position: Vector3): ()
    self.Position = position
end

function Spring.SetVelocity(self: Spring, velocity: Vector3): ()
    self.Velocity = velocity
end

function Spring.Reset(self: Spring, position: Vector3?): ()
    local pos = position or Vector3.zero
    self.Position = pos
    self.Target = pos
    self.Velocity = Vector3.zero
end

return Spring
