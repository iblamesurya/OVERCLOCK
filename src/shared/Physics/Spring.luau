--!strict
local Spring = {}
Spring.__index = Spring

export type Spring = typeof(setmetatable({} :: {
    Target: Vector3,
    Position: Vector3,
    Velocity: Vector3,
    Mass: number,
    Stiffness: number,
    Damping: number,
}, Spring))

function Spring.new(mass: number, stiffness: number, damping: number, initialPosition: Vector3?): Spring
    local self = setmetatable({}, Spring)
    self.Target = Vector3.zero
    self.Position = initialPosition or Vector3.zero
    self.Velocity = Vector3.zero
    self.Mass = mass or 1
    self.Stiffness = stiffness or 50
    self.Damping = damping or 4
    return self
end

function Spring:Impulse(velocity: Vector3)
    self.Velocity += velocity
end

function Spring:SetTarget(target: Vector3)
    self.Target = target
end

function Spring:SetPosition(position: Vector3)
    self.Position = position
end

function Spring:SetVelocity(velocity: Vector3)
    self.Velocity = velocity
end

function Spring:Reset()
    self.Position = Vector3.zero
    self.Velocity = Vector3.zero
    self.Target = Vector3.zero
end

-- Closed-form exact damped harmonic oscillator (frame-rate independent)
function Spring:Update(dt: number)
    local m = self.Mass
    local k = self.Stiffness
    local d = self.Damping

    local p0 = self.Position - self.Target
    local v0 = self.Velocity

    local c = d / (2 * m)
    local w0 = math.sqrt(k / m)

    if c < w0 then
        -- Under-damped (oscillatory)
        local w = math.sqrt(w0*w0 - c*c)
        local expTerm = math.exp(-c * dt)
        local cosTerm = math.cos(w * dt)
        local sinTerm = math.sin(w * dt)

        local c1 = p0
        local c2 = (v0 + c * p0) / w

        self.Position = self.Target + expTerm * (c1 * cosTerm + c2 * sinTerm)
        self.Velocity = -c * expTerm * (c1 * cosTerm + c2 * sinTerm) + expTerm * (-c1 * w * sinTerm + c2 * w * cosTerm)
    elseif c == w0 then
        -- Critically damped
        local expTerm = math.exp(-c * dt)
        local c1 = p0
        local c2 = v0 + c * p0

        self.Position = self.Target + (c1 + c2 * dt) * expTerm
        self.Velocity = (c2 - c * (c1 + c2 * dt)) * expTerm
    else
        -- Over-damped
        local w = math.sqrt(c*c - w0*w0)
        local r1 = -c + w
        local r2 = -c - w
        local c2 = (v0 - r1 * p0) / (r2 - r1)
        local c1 = p0 - c2

        local exp1 = math.exp(r1 * dt)
        local exp2 = math.exp(r2 * dt)

        self.Position = self.Target + c1 * exp1 + c2 * exp2
        self.Velocity = c1 * r1 * exp1 + c2 * r2 * exp2
    end
	return self.Position
end

return Spring
