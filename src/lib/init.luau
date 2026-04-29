--@maneetoo

--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")

local Buffer = require("@self/modules/Buffer")
local Types = require("@self/Types")
local Version = require("@self/utils/Version")

local Wisp = {
	Client = require("@self/Client"),
	Server = require("@self/Server"),
	Types = Buffer.Types,
	CreateType = Buffer.Types,
}

if RunService:IsServer() then
	task.defer(function()
		local completed: boolean, version: string? = Version.getLatestRelease()
		if completed then
			if version ~= Version.getCurrentVersion() then
				warn(`[Wisp]: New version is available: {version} (Current: {Version.getCurrentVersion()})`)
			end
		end
	end)
end

export type Schema = Types.Schema
export type SchemaType = Types.SchemaType
export type MigrationMap = Types.MigrationMap
export type CompressionMode = Types.CompressionMode
export type Priority = Types.Priority
export type EncodeConfig = Types.EncodeConfig
export type BatchMode = Types.BatchMode
export type RemoteConfig = Types.RemoteConfig
export type BatchPacket = Types.BatchPacket
export type DeltaSyncPacket = Types.DeltaSyncPacket
export type InvokeCallback = Types.InvokeCallback
export type ClientInvokeCallback = Types.ClientInvokeCallback

return Wisp
