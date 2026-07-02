--!strict
-- @Author @OrkGabb
-- src/Shared/Modules/RollEngine.luau
-- Generic weighted-random roll core shared by every RNG genre (Aura rolls,
-- Pet egg hatches, …). Registries pass an array of weights (index-aligned
-- with their own definition arrays) and get back O(log N) rolls via a
-- cumulative-weight binary search — fast enough for auto-rollers.
--
-- Luck semantics: a luck multiplier > 1 shrinks the effective total weight,
-- pushing the roll toward the low indices. Callers should therefore order
-- their entries rarest-first (ascending weight) before building an engine.
--
-- Server rolls and client odds displays must resolve through the SAME engine
-- instance source so displayed odds can never disagree with real rolls.

export type RollEngine = {
	-- Index (1-based) into the weights array this engine was built from.
	Roll: (self: RollEngine, luckMultiplier: number?) -> number,
	-- Chance per index (Weight / TotalWeight), index-aligned with the input.
	GetChances: (self: RollEngine) -> {number},
	TotalWeight: number,
}

local Engine = {}
Engine.__index = Engine

function Engine.Roll(self: any, luckMultiplier: number?): number
	local luck: number = math.max(1, luckMultiplier or 1)
	local target: number = math.random() * (self.TotalWeight / luck)

	local cumulative: {number} = self._cumulative
	local low: number, high: number = 1, #cumulative
	local bestIdx: number = #cumulative

	while low <= high do
		local mid = (low + high) // 2
		if target <= cumulative[mid] then
			bestIdx = mid
			high = mid - 1
		else
			low = mid + 1
		end
	end

	return bestIdx
end

function Engine.GetChances(self: any): {number}
	local weights: {number} = self._weights
	local out: {number} = table.create(#weights)
	if self.TotalWeight <= 0 then
		for i = 1, #weights do
			out[i] = 0
		end
		return out
	end
	for i, weight in ipairs(weights) do
		out[i] = weight / self.TotalWeight
	end
	return out
end

local RollEngineModule = {}

function RollEngineModule.New(weights: {number}): RollEngine
	local cumulative: {number} = table.create(#weights)
	local total = 0
	for i, weight in ipairs(weights) do
		total += weight
		cumulative[i] = total
	end

	local self = setmetatable({
		_weights = table.clone(weights),
		_cumulative = cumulative,
		TotalWeight = total,
	}, Engine)

	return (self :: any) :: RollEngine
end

return RollEngineModule
