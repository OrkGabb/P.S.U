--!strict
--@author OrkGabb
--@module BootTelemetry.luau
--@version 1.0
-- Optional observability layer for the server boot sequence. Wraps Init/Start
-- calls with timing + success/failure capture without altering lifecycle
-- order, phase boundaries, or SafeCall's error-swallowing contract in
-- ServerMain. Purely additive — nothing else needs to change for this to work.

local BootTelemetry = {}

export type PhaseRecord = {
	Name: string,
	Method: string,
	DurationMs: number,
	Success: boolean,
	Error: string?,
}

local records: { PhaseRecord } = {}
local sequenceStartClock: number? = nil

-- Call once, before the first tracked call.
function BootTelemetry.BeginSequence(): ()
	records = {}
	sequenceStartClock = os.clock()
end

-- Mirrors ServerMain's SafeCall contract exactly (never raises to the
-- caller), so it can be dropped in as a direct SafeCall replacement without
-- changing failure semantics for any existing service.
function BootTelemetry.TrackedCall(mod: any, method: string, name: string): ()
	if typeof(mod) ~= "table" or type(mod[method]) ~= "function" then
		return
	end

	local startClock = os.clock()
	local ok: boolean, err: any = pcall(mod[method])
	local durationMs = (os.clock() - startClock) * 1000

	table.insert(records, {
		Name = name,
		Method = method,
		DurationMs = durationMs,
		Success = ok,
		Error = if ok then nil else tostring(err),
	})

	if not ok then
		warn(("[BootTelemetry] %s.%s() failed: %s"):format(name, method, tostring(err)))
	end
end

function BootTelemetry.GetRecords(): { PhaseRecord }
	return records
end

-- Intended for manual invocation after ServerMain completes its boot
-- sequence — never required by ServerMain itself, so telemetry can be
-- removed at any time with zero blast radius on boot logic.
function BootTelemetry.PrintSummary(): ()
	local totalMs = 0
	local failures = 0

	for _, record: PhaseRecord in records do
		totalMs += record.DurationMs
		if not record.Success then
			failures += 1
		end
	end

	print(("[BootTelemetry] %d call(s) tracked, %.2fms total, %d failure(s)."):format(
		#records, totalMs, failures))

	local sorted = table.clone(records)
	table.sort(sorted, function(a: PhaseRecord, b: PhaseRecord): boolean
		return a.DurationMs > b.DurationMs
	end)

	local topCount = math.min(5, #sorted)
	for i = 1, topCount do
		local record = sorted[i]
		print(("[BootTelemetry]   %d) %s.%s — %.2fms%s"):format(
			i, record.Name, record.Method, record.DurationMs,
			if record.Success then "" else " [FAILED]"))
	end

	if sequenceStartClock then
		local wallClockMs = (os.clock() - sequenceStartClock) * 1000
		local untrackedMs = wallClockMs - totalMs
		print(("[BootTelemetry] %.2fms wall-clock since BeginSequence (%.2fms untracked: requires, prints, GC)."):format(
			wallClockMs, untrackedMs))
	end
end

return BootTelemetry
