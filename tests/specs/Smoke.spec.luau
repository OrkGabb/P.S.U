--!nocheck
-- tests/specs/Smoke.spec.luau
-- Module-load smoke checks carried over from the retired
-- FrameworkTestRunner.server.luau (Studio-only diagnostics).
--
-- The runner smoke-checked three modules. Two move here cleanly:
--   * FeatureToggles -- loads, is a table, has the expected version + DashConfig
--   * VFXRegistry    -- loads and is a table
-- The third, AntiExploitService, could NOT be folded in: it hard-couples to the
-- Roblox VM at module scope (Players/Workspace services, RaycastParams.new(),
-- RemoteEvent creation, RemoteNames/DebugUtility requires), which is out of
-- scope for this Lune pass. It should be covered once its pure helpers (the
-- click-interval sigma / token-bucket math) are extracted in a later cut.

local T = require("../lune/harness")
local psu = require("../lune/psu")

T.suite("Smoke (folded from FrameworkTestRunner)")

T.test("FeatureToggles loads with the expected version and Dash config", function()
	local FeatureToggles = psu.load("Shared/Config/FeatureToggles")
	T.eq(type(FeatureToggles), "table")
	T.eq(FeatureToggles.FrameworkVersion, "ModularFramework Core v1.0.0")
	-- The retired runner probed `DashConfig`, which never existed (the key is
	-- `Dash`), so its Enabled check was a silent no-op. Assert the real config.
	T.eq(type(FeatureToggles.Dash), "table")
	T.truthy(FeatureToggles.Dash.Enabled ~= nil, "Dash.Enabled is nil")
end)

T.test("VFXRegistry loads and returns a table", function()
	local VFXRegistry = psu.load("Shared/Config/VFXRegistry")
	T.eq(type(VFXRegistry), "table")
end)

return {}
