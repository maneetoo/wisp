--@maneetoo

--!strict

local HttpService = game:GetService("HttpService")

export type Version = {
	major: number,
	minor: number,
	patch: number,
}

export type ComparisonResult = {
	current: string,
	latest: string,
	isOutdated: boolean,
	comparison: number,
}

local GITHUB_API_URL: string = "https://api.github.com/repos/maneetoo/wisp/releases"
local CURRENT_VERSION: string = "v0.1.0"

local Version = {}

function Version.parseVersion(versionString: string): Version?
	local pattern: string = "v?(%d+)%.(%d+)%.(%d+)"
	local major: string?, minor: string?, patch: string? = versionString:match(pattern)

	if not major or not minor or not patch then
		warn(`[Wisp] Cannot parse version: {versionString}`)
		return nil
	end

	return {
		major = tonumber(major) :: number,
		minor = tonumber(minor) :: number,
		patch = tonumber(patch) :: number,
	}
end

function Version.compareVersions(v1: Version, v2: Version): number
	if v1.major ~= v2.major then
		return v1.major < v2.major and -1 or 1
	end

	if v1.minor ~= v2.minor then
		return v1.minor < v2.minor and -1 or 1
	end

	if v1.patch ~= v2.patch then
		return v1.patch < v2.patch and -1 or 1
	end

	return 0
end

function Version.getLatestRelease(): (boolean, string?)
	return xpcall(function()
		local gitResponse: any = HttpService:GetAsync(GITHUB_API_URL, true)
		local releases: { any }? = HttpService:JSONDecode(gitResponse)

		for _, release in ipairs(releases :: { any }) do
			if typeof(release) == "table" and release.prerelease == false and typeof(release.tag_name) == "string" then
				return release.tag_name
			end
		end

		error("No stable releases found")
	end, function(err: any)
		warn("[Wisp] Error while getting latest release:", err)
		return err
	end)
end

function Version.checkForUpdates(): (boolean, ComparisonResult | string)
	local success: boolean, latestTagOrError: string? = Version.getLatestRelease()
	if not success then
		return false, latestTagOrError :: string
	end

	local latestTag: string = latestTagOrError :: string
	local currentVersion: Version? = Version.parseVersion(CURRENT_VERSION)
	local latestVersion: Version? = Version.parseVersion(latestTag)

	if not currentVersion then
		return false, `Incorrect format for current version: {CURRENT_VERSION}`
	end

	if not latestVersion then
		return false, `Incorrect format for latest version: {latestTag}`
	end

	local comparison: number = Version.compareVersions(currentVersion, latestVersion)
	local result: ComparisonResult = {
		current = CURRENT_VERSION,
		latest = latestTag,
		isOutdated = comparison == -1,
		comparison = comparison,
	}

	return true, result
end

function Version.getCurrentVersion(): string
	return CURRENT_VERSION
end

return Version
