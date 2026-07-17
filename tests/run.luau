--!nocheck
-- tests/run.luau
-- Entry point for the P.S.U. unit spec suite. Run with:
--   lune run tests/run.luau
-- Requiring each spec registers and immediately runs its cases against the
-- shared harness singleton; the process exits non-zero if anything failed so
-- CI treats a red suite as a failed job.

local process = require("@lune/process")
local T = require("./lune/harness")

print("P.S.U. spec suite")

require("./specs/RollEngine.spec")
require("./specs/UpgradeRegistry.spec")
require("./specs/FeatureResolver.spec")
require("./specs/Smoke.spec")

local ok = T.finish()
process.exit(if ok then 0 else 1)
