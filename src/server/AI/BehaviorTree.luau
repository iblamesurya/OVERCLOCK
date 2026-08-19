--!strict
--[=[
    Project OVERCLOCK: Behavior Tree Engine
    Scalable, modular decision-making engine for Bot AI.
]=]

local BehaviorTree = {}

export type NodeStatus = "Success" | "Failure" | "Running"

export type Node = {
    Tick: (self: Node, context: any) -> NodeStatus,
}

-- ----------------------------------------------------------------------------
-- Base Action Node
-- ----------------------------------------------------------------------------

local ActionNode = {}
ActionNode.__index = ActionNode

function BehaviorTree.Action(actionFunc: (context: any) -> NodeStatus): Node
    local self = setmetatable({}, ActionNode)
    self.actionFunc = actionFunc
    return self :: any
end

function ActionNode:Tick(context: any): NodeStatus
    return self.actionFunc(context)
end

-- ----------------------------------------------------------------------------
-- Sequence Node (AND)
-- ----------------------------------------------------------------------------

local Sequence = {}
Sequence.__index = Sequence

function BehaviorTree.Sequence(children: {Node}): Node
    local self = setmetatable({}, Sequence)
    self.children = children
    return self :: any
end

function Sequence:Tick(context: any): NodeStatus
    for _, child in ipairs(self.children) do
        local status = child:Tick(context)
        if status ~= "Success" then
            return status
        end
    end
    return "Success"
end

-- ----------------------------------------------------------------------------
-- Selector Node (OR)
-- ----------------------------------------------------------------------------

local Selector = {}
Selector.__index = Selector

function BehaviorTree.Selector(children: {Node}): Node
    local self = setmetatable({}, Selector)
    self.children = children
    return self :: any
end

function Selector:Tick(context: any): NodeStatus
    for _, child in ipairs(self.children) do
        local status = child:Tick(context)
        if status ~= "Failure" then
            return status
        end
    end
    return "Failure"
end

-- ----------------------------------------------------------------------------
-- Inverter Decorator
-- ----------------------------------------------------------------------------

local Inverter = {}
Inverter.__index = Inverter

function BehaviorTree.Invert(child: Node): Node
    local self = setmetatable({}, Inverter)
    self.child = child
    return self :: any
end

function Inverter:Tick(context: any): NodeStatus
    local status = self.child:Tick(context)
    if status == "Success" then
        return "Failure"
    elseif status == "Failure" then
        return "Success"
    end
    return "Running"
end

return BehaviorTree
