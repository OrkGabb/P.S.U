--!strict
--@author OrkGabb
--@module ConfigAudit.luau
--@version 1.0
-- src/Shared/Modules/ConfigAudit.luau
-- Read-only static analysis over FeatureToggles and the Shared module tree.
-- Detects config drift and structural duplication WITHOUT mutating anything.
-- Does not require, alter, or depend on FeatureResolver's resolution logic —
-- safe to run before, during, or after genre resolution.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FeatureToggles = require(ReplicatedStorage.Shared.Config.FeatureToggles)

local ConfigAudit = {}

export type AuditIssue = {
	Severity: "Warning" | "Error",
	Category: string,
	Message: string,
}

export type AuditReport = {
	Issues: { AuditIssue },
	GenreCount: number,
	CheckedAt: number,
}

local function NewIssue(severity: "Warning" | "Error", category: string, message: string): AuditIssue
	return {
		Severity = severity,
		Category = category,
		Message = message,
	}
end

--------------------------------------------------------------------------------
-- Genre structural checks
--------------------------------------------------------------------------------

-- Verifies every genre entry exposes a boolean `Enabled` field and, when
-- present, a well-formed `Currencies` table. Generic over whatever keys
-- exist in FeatureToggles.Genres — no genre name is hardcoded here, so new
-- genres are audited automatically (OCP).
local function auditGenres(issues: { AuditIssue }): number
	local genres: any = (FeatureToggles :: any).Genres
	local count = 0

	if type(genres) ~= "table" then
		table.insert(issues, NewIssue("Error", "Genres", "FeatureToggles.Genres is missing or not a table."))
		return 0
	end

	for key: string, cfg: any in pairs(genres) do
		count += 1

		if type(cfg) ~= "table" then
			table.insert(issues, NewIssue("Error", "Genres", ("Genre %q config is not a table."):format(key)))
			continue
		end

		if type(cfg.Enabled) ~= "boolean" then
			table.insert(issues, NewIssue("Error", "Genres", ("Genre %q is missing a boolean Enabled field."):format(key)))
		end

		if cfg.Currencies ~= nil then
			if type(cfg.Currencies) ~= "table" then
				table.insert(issues, NewIssue("Warning", "Genres", ("Genre %q Currencies field is not a table."):format(key)))
			else
				if type(cfg.Currencies.PrimaryName) ~= "string" then
					table.insert(issues, NewIssue("Warning", "Genres", ("Genre %q Currencies.PrimaryName is missing or not a string."):format(key)))
				end
				if type(cfg.Currencies.SecondaryName) ~= "string" then
					table.insert(issues, NewIssue("Warning", "Genres", ("Genre %q Currencies.SecondaryName is missing or not a string."):format(key)))
				end
			end
		end
	end

	return count
end

--------------------------------------------------------------------------------
-- GlobalFlags structural checks
--------------------------------------------------------------------------------

-- Ensures every GlobalFlags entry resolves to either a boolean or a table
-- with a boolean Enabled field — the two shapes FeatureResolver already
-- accepts. Anything else is silently coerced to `false` at read time, which
-- is exactly the kind of drift this audit exists to surface.
local function auditGlobalFlags(issues: { AuditIssue }): ()
	local flags: any = (FeatureToggles :: any).GlobalFlags
	if flags == nil then
		return
	end

	if type(flags) ~= "table" then
		table.insert(issues, NewIssue("Error", "GlobalFlags", "FeatureToggles.GlobalFlags exists but is not a table."))
		return
	end

	for key: string, value: any in pairs(flags) do
		local isBoolean = type(value) == "boolean"
		local isValidTable = type(value) == "table" and type(value.Enabled) == "boolean"
		if not isBoolean and not isValidTable then
			table.insert(issues, NewIssue("Warning", "GlobalFlags", ("GlobalFlags.%s is neither a boolean nor a table with a boolean Enabled field."):format(key)))
		end
	end
end

--------------------------------------------------------------------------------
-- Structural duplication scan (instance tree, not config)
--------------------------------------------------------------------------------

-- Scans a root Instance for ModuleScripts sharing the same Name across
-- different paths. Generic by design — flags ANY duplicate module name, not
-- just known offenders, so new duplication introduced later is still caught.
function ConfigAudit.FindDuplicateModuleNames(root: Instance): { [string]: { string } }
	local seen: { [string]: { string } } = {}

	for _, descendant: Instance in root:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			local name = descendant.Name
			if seen[name] == nil then
				seen[name] = {}
			end
			table.insert(seen[name], descendant:GetFullName())
		end
	end

	local duplicates: { [string]: { string } } = {}
	for name: string, paths: { string } in pairs(seen) do
		if #paths > 1 then
			duplicates[name] = paths
		end
	end

	return duplicates
end

local function auditDuplicateModules(issues: { AuditIssue }): ()
	local sharedRoot: Instance? = ReplicatedStorage:FindFirstChild("Shared")
	if sharedRoot == nil then
		return
	end

	local duplicates = ConfigAudit.FindDuplicateModuleNames(sharedRoot)
	for name: string, paths: { string } in pairs(duplicates) do
		table.insert(issues, NewIssue("Warning", "Duplication", ("ModuleScript %q exists at %d locations: %s"):format(
			name, #paths, table.concat(paths, " | "))))
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Runs the full audit and returns a structured report. Never raises — all
-- findings are collected as issues so callers decide severity handling.
function ConfigAudit.Run(): AuditReport
	local issues: { AuditIssue } = {}

	local genreCount = auditGenres(issues)
	auditGlobalFlags(issues)
	auditDuplicateModules(issues)

	return {
		Issues = issues,
		GenreCount = genreCount,
		CheckedAt = os.clock(),
	}
end

-- Convenience wrapper: runs the audit and prints a formatted report via
-- print/warn. Intended for manual invocation from a command bar or a
-- dedicated debug script — never auto-invoked by any bootstrap file.
function ConfigAudit.PrintReport(): AuditReport
	local report = ConfigAudit.Run()

	print(("[ConfigAudit] Checked %d genre(s), %d issue(s) found."):format(
		report.GenreCount, #report.Issues))

	for _, issue: AuditIssue in report.Issues do
		if issue.Severity == "Error" then
			warn(("[ConfigAudit][%s] %s"):format(issue.Category, issue.Message))
		else
			print(("[ConfigAudit][%s] %s"):format(issue.Category, issue.Message))
		end
	end

	return report
end

return ConfigAudit
