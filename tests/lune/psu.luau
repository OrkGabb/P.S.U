--!nocheck
-- tests/lune/psu.luau
--
-- Roblox->Lune compatibility shim for the P.S.U. unit spec suite.
--
-- The framework's shared modules are authored for the Roblox VM: at module
-- scope they call `game:GetService("ReplicatedStorage")` and then
-- `require(ReplicatedStorage.Shared.Modules.X)` (require of an *instance*, not
-- a path string), and FeatureToggles constructs Vector3/Color3/Enum values.
-- Lune's own `require` is path-string based and has no `game`, so those
-- modules cannot be required directly.
--
-- This shim loads a module from disk under a controlled global environment:
--   * `game`            -- stub exposing GetService for ReplicatedStorage /
--                          RunService and a PlaceId of 0 (keeps FeatureToggles'
--                          Studio-safety block a no-op).
--   * `ReplicatedStorage` proxy -- a filesystem-backed instance tree rooted at
--                          src/Shared, so `.Shared.Modules.Foo` resolves to
--                          src/Shared/Modules/Foo.luau.
--   * a custom `require` -- accepts those instance proxies and evaluates the
--                          target file under this same environment, cached per
--                          load context so singletons (e.g. FeatureResolver's
--                          cached genre resolution) behave as they do in-engine.
--   * inert Vector3/Color3/Enum stubs -- constructed but never inspected by the
--                          specs; just enough for FeatureToggles to load.
--
-- Two entry points:
--   psu.load(rel)              -- fresh context, real on-disk dependencies.
--   psu.loadWith(rel, overrides) -- fresh context where require of a given
--                                   relative module key returns a supplied
--                                   stub instead of the real file (used to feed
--                                   FeatureResolver synthetic FeatureToggles).
--
-- `rel` is a src-relative module path without extension, e.g.
-- "Shared/Modules/RollEngine". Override keys use the same form.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local psu = {}

-- ── Repo layout ──────────────────────────────────────────────────────────────
local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end
local SRC = ROOT .. "src/"

-- src-relative module key (no extension) for a shim path, e.g.
-- ".../src/Shared/Modules/Foo" -> "Shared/Modules/Foo". Used for override lookup.
local function relKeyOf(psuPath: string): string
	return string.sub(psuPath, #SRC + 1)
end

-- ── Inert Roblox datatype stubs ──────────────────────────────────────────────
-- Values are constructed by FeatureToggles but never read by the specs, so a
-- tagged empty table is sufficient. Constructors must simply not error.
local function dt(kind: string)
	return function()
		return { __psuDatatype = kind }
	end
end

local Vector3Stub = { new = dt("Vector3"), zero = { __psuDatatype = "Vector3" }, one = { __psuDatatype = "Vector3" } }
local Color3Stub = { new = dt("Color3"), fromRGB = dt("Color3"), fromHSV = dt("Color3") }
local EnumStub = setmetatable({}, {
	__index = function(_, enumName: string)
		return setmetatable({}, {
			__index = function(_, item: string)
				return { __psuEnum = enumName .. "." .. tostring(item) }
			end,
		})
	end,
})

-- math with a guaranteed `pow` (UpgradeRegistry uses math.pow, deprecated in
-- newer Luau stdlibs) layered over the real math table.
local mathStub = setmetatable({
	pow = (math :: any).pow or function(a: number, b: number): number
		return a ^ b
	end,
}, { __index = math })

-- ── Instance proxies (pure string path-building; NO filesystem access) ────────
-- CRITICAL: __index must never call a yielding function. Lune's fs.* calls
-- yield, and a module's `require(ReplicatedStorage.Shared. ...)` evaluates this
-- __index chain — when that evaluation happens inside a pcall (e.g. a module
-- loaded from within a test case), a yielding fs call raises "attempt to yield
-- across metamethod/C-call boundary". So __index only concatenates path
-- segments; the single fs.readFile happens later in contextRequire, which is
-- not a metamethod and is yield-safe under Luau's pcall.
--
-- A node carries __psuPath = the on-disk path WITHOUT the .luau extension.
-- Indexing extends the path; require() appends .luau and reads the file.
local function makePathNode(psuPath: string)
	return setmetatable({ __psuPath = psuPath }, {
		__index = function(_, key: string)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, childName: string)
					return makePathNode(psuPath .. "/" .. childName)
				end
			end
			return makePathNode(psuPath .. "/" .. tostring(key))
		end,
	})
end

local ReplicatedStorageProxy = setmetatable({}, {
	__index = function(_, key: string)
		if key == "Shared" then
			return makePathNode(SRC .. "Shared")
		end
		if key == "WaitForChild" or key == "FindFirstChild" then
			return function(_, childName: string)
				if childName == "Shared" then
					return makePathNode(SRC .. "Shared")
				end
				error(string.format("[psu shim] ReplicatedStorage has no child %q", tostring(childName)))
			end
		end
		error(string.format("[psu shim] ReplicatedStorage has no member %q", tostring(key)))
	end,
})

local RunServiceStub = {
	IsStudio = function()
		return false
	end,
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
}

local gameStub = setmetatable({ PlaceId = 0, JobId = "" }, {
	__index = function(_, key: string)
		if key == "GetService" then
			return function(_, serviceName: string)
				if serviceName == "ReplicatedStorage" then
					return ReplicatedStorageProxy
				end
				if serviceName == "RunService" then
					return RunServiceStub
				end
				error(string.format("[psu shim] game:GetService(%q) is not stubbed", tostring(serviceName)))
			end
		end
		error(string.format("[psu shim] game has no member %q", tostring(key)))
	end,
})

-- ── Load contexts ────────────────────────────────────────────────────────────
-- Each context has its own module cache (so a module required twice within one
-- load returns the same instance) and its own override map.
local function makeContext(overrides: { [string]: any })
	local cache: { [string]: any } = {}
	local env: { [string]: any }

	local function contextRequire(target: any): any
		-- rawget: path-node proxies extend their __index on any key, so never
		-- trip that metamethod while probing for the path marker.
		local psuPath = type(target) == "table" and rawget(target, "__psuPath")
		if psuPath then
			local key = relKeyOf(psuPath)
			if overrides[key] ~= nil then
				return overrides[key]
			end
			if cache[key] ~= nil then
				return cache[key]
			end
			-- fs.readFile yields; safe here (not inside a metamethod, and Luau
			-- pcall tolerates yields) but never from within __index.
			local source = fs.readFile(psuPath .. ".luau")
			local chunk = luau.load(source, {
				debugName = key,
				environment = env,
				injectGlobals = false,
			})
			local result = chunk()
			cache[key] = result
			return result
		end
		error("[psu shim] require() expected a ReplicatedStorage instance proxy")
	end

	-- Explicit, self-contained global environment (injectGlobals = false) so
	-- behaviour never depends on Lune's inject ordering. Only the globals the
	-- target graph actually touches are provided.
	env = {
		-- lua/luau standard surface
		print = print,
		warn = function() end, -- resolution logs are expected noise; silence them
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		select = select,
		type = type,
		typeof = type,
		tostring = tostring,
		tonumber = tonumber,
		ipairs = ipairs,
		pairs = pairs,
		next = next,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		unpack = table.unpack,
		math = mathStub,
		table = table,
		string = string,
		os = os,
		coroutine = coroutine,
		-- roblox surface
		game = gameStub,
		Vector3 = Vector3Stub,
		Color3 = Color3Stub,
		Enum = EnumStub,
		require = contextRequire,
	}
	env._G = env

	return function(rel: string): any
		return contextRequire(makePathNode(SRC .. rel))
	end
end

-- Load a module with its real on-disk dependencies.
function psu.load(rel: string): any
	return makeContext({})(rel)
end

-- Load a module, substituting supplied stubs for specific dependency modules.
-- `overrides` is keyed by src-relative module path, e.g.
-- { ["Shared/Config/FeatureToggles"] = fakeToggles }.
function psu.loadWith(rel: string, overrides: { [string]: any }): any
	return makeContext(overrides)(rel)
end

return psu
