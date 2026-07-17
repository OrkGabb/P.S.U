--!nocheck
-- tests/lune/harness.luau
--
-- Dependency-free spec harness. Tests run immediately when registered; results
-- are tallied and `finish()` returns whether everything passed (drives the
-- process exit code in tests/run.luau).

local harness = {}

harness.passed = 0
harness.failed = 0
harness.failures = {} :: { string }

-- Register + run a single test case. `fn` should raise (via the expectation
-- helpers below or a bare error) to signal failure.
function harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		harness.passed += 1
		print("  [PASS] " .. name)
	else
		harness.failed += 1
		local line = name .. " -> " .. tostring(err)
		table.insert(harness.failures, line)
		print("  [FAIL] " .. line)
	end
end

-- Group label for readable output only.
function harness.suite(name: string)
	print("\n" .. name)
end

-- ── Expectations (raise at level 2 so the failure points at the call site) ────
function harness.eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(expected), tostring(actual)), 2)
	end
end

function harness.truthy(value: any, msg: string?)
	if not value then
		error(msg or "expected a truthy value", 2)
	end
end

function harness.falsy(value: any, msg: string?)
	if value then
		error(string.format("%s: expected falsy, got %s", msg or "falsy", tostring(value)), 2)
	end
end

function harness.isNil(value: any, msg: string?)
	if value ~= nil then
		error(string.format("%s: expected nil, got %s", msg or "isNil", tostring(value)), 2)
	end
end

function harness.near(actual: number, expected: number, eps: number?, msg: string?)
	local tolerance = eps or 1e-9
	if math.abs(actual - expected) > tolerance then
		error(string.format("%s: expected ~%s (+/-%s), got %s", msg or "near", tostring(expected), tostring(tolerance), tostring(actual)), 2)
	end
end

-- Asserts `fn` raises. Returns nothing; failure means it did NOT raise.
function harness.throws(fn: () -> (), msg: string?)
	local ok = pcall(fn)
	if ok then
		error(msg or "expected the call to raise, but it returned", 2)
	end
end

function harness.finish(): boolean
	print(string.format("\n%d passed, %d failed", harness.passed, harness.failed))
	if harness.failed > 0 then
		print("\nFailures:")
		for _, line in ipairs(harness.failures) do
			print("  - " .. line)
		end
	end
	return harness.failed == 0
end

return harness
