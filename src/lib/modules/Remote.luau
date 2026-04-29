local Players = game:GetService("Players")
local Buffer = require("./Buffer")
local Pool = require("./Pool")
local Trove = require("../../helpful_modules/Trove")
local Types = require("../Types")
local XOR = require("./XOR")

type EncodeConfig = Types.EncodeConfig
type RemoteConfig = Types.RemoteConfig

local Remote = {}
Remote.__index = Remote

export type Remote = typeof(setmetatable(
	{} :: {
		_trove: any,
		_remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction,
		_config: RemoteConfig,
		_lastSend: { [Player]: number },
		_deltaCache: { [any]: any },
		_deltaCacheHash: { [any]: string },
		_deltaCacheVersion: { [any]: number },
		_isServer: boolean,
		_sequence: number,
	},
	Remote
))

--[[
	Create a new Remote wrapper around a Roblox remote object
	
	This wrapper adds encoding, compression, delta processing, rate limiting,
	and schema validation on top of standard RemoteEvents and RemoteFunctions.
]]
--
function Remote.new(
	remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction,
	config: RemoteConfig?,
	isServer: boolean
): Remote
	local self: Remote = setmetatable({}, Remote) :: Remote

	self._trove = Trove.new()
	self._remote = remote
	self._config = config
		or {
			encode = { mode = "basic" },
			batching = "unreliable",
			unreliable = false,
			syncDeltaCache = false,
		}
	self._lastSend = {}
	self._deltaCache = {}
	self._deltaCacheHash = {}
	self._deltaCacheVersion = {}
	self._isServer = isServer
	self._sequence = 0

	if isServer then
		self._trove:Connect(Players.PlayerRemoving, function(player: Player)
			self:ClearPlayer(player)
		end)
	end

	return self
end

--[[
	Apply schema migrations to upgrade data between versions
	
	When data structures change between game updates, migrations allow automatic
	conversion from old formats to new ones during decoding.
]]
--
function Remote:_migrateSchema(data: any, fromVersion: number, toVersion: number): any?
	local config = self._config.encode
	if not config or not config.migrations then
		return data
	end

	local migrated, err = Buffer.MigrateSchema(data, fromVersion, toVersion, config.migrations)
	if not migrated then
		warn(`[Wisp] Schema migration failed: {err}`)
		return nil
	end

	return migrated
end

--[[
	Encode data into a buffer using the configured encoding method
	
	Supports multiple encoding modes:
	- basic: Standard encoding with optional compression
	- compressed: Forced compression with specified algorithm
	- schema: Structured data with validation
	- safe: Cycle detection for untrusted data
	- delta: Only send changes since last transmission
]]
--
function Remote:_encode(value: any, player: Player?): buffer?
	local config = self._config.encode or { mode = "basic" }
	local result: buffer?
	local err: string?

	if config.mode == "basic" then
		if config.priority then
			result, err = Buffer.EncodeWith(value, config.priority)
		else
			result, err = Buffer.Encode(value)
		end
	elseif config.mode == "compressed" then
		result, err = Buffer.EncodeCompressed(value, config.compression)
	elseif config.mode == "schema" then
		if not config.schema then
			warn("[Wisp] Schema mode requires schema in config.encode")
			return nil
		end

		local schemaValue = value
		if type(value) == "table" and #value == 1 and type(value[1]) == "table" then
			schemaValue = value[1]
		end

		local currentVersion = config.schemaVersion or config.schema.version or 1
		if type(schemaValue) == "table" and schemaValue._version and schemaValue._version < currentVersion then
			schemaValue = self:_migrateSchema(schemaValue, schemaValue._version, currentVersion)
			if not schemaValue then
				return nil
			end
		end

		result, err = Buffer.EncodeSchema(schemaValue, config.schema)
	elseif config.mode == "safe" then
		result, err = Buffer.EncodeSafe(value)
	elseif config.mode == "delta" then
		--[[
			Delta encoding process:
			1. Check if we have cached data for this player/client
			2. If cache exists, create a patch containing only changes
			3. If no cache or delta fails, fall back to full encoding
			4. Update cache with new data for future delta operations
		]]
		--
		local cacheKey = if self._isServer then player else "__CLIENT__"

		local deltaValue = value
		if type(value) == "table" and #value == 1 and type(value[1]) == "table" then
			deltaValue = value[1]
		end

		if cacheKey and self._deltaCache[cacheKey] then
			if self._config.syncDeltaCache then
				local currentHash = Pool.hashData(self._deltaCache[cacheKey])
				if self._deltaCacheHash[cacheKey] ~= currentHash then
					warn(`[Wisp] Delta cache desync, resending full data`)
					self._deltaCache[cacheKey] = nil
				end
			end

			if self._deltaCache[cacheKey] then
				if config.schema then
					result, err = Buffer.EncodeSchemaDelta(self._deltaCache[cacheKey], deltaValue, config.schema)
				else
					result, err = Buffer.EncodeDelta(self._deltaCache[cacheKey], deltaValue)
				end

				if result then
					self._deltaCache[cacheKey] = deltaValue
					if self._config.syncDeltaCache then
						self._deltaCacheHash[cacheKey] = Pool.hashData(deltaValue)
						self._deltaCacheVersion[cacheKey] = (self._deltaCacheVersion[cacheKey] or 0) + 1
					end
				end
			end
		end

		if not result then
			if config.schema then
				result, err = Buffer.EncodeSchema(deltaValue, config.schema)
			else
				result, err = Buffer.Encode(deltaValue)
			end

			if result and cacheKey then
				self._deltaCache[cacheKey] = deltaValue
				if self._config.syncDeltaCache then
					self._deltaCacheHash[cacheKey] = Pool.hashData(deltaValue)
					self._deltaCacheVersion[cacheKey] = 1
				end
			end
		end
	end

	if not result then
		warn(`[Wisp] Encode failed: {err or "unknown error"}`)
		return nil
	end

	--[[
		Automatic compression for large payloads
		
		If the encoded data is larger than 1KB and not already compressed,
		try compressing it. Only use the compressed version if it's significantly smaller.
	]]
	--
	if buffer.len(result) > 1024 and config.mode ~= "compressed" then
		local compressed = Buffer.EncodeCompressed(value, "auto")
		if compressed and buffer.len(compressed) < buffer.len(result) * 0.8 then
			result = compressed
		end
	end

	-- Apply XOR pre-processing to improve compression ratios
	result = XOR.apply(result)

	return result
end

--[[
	Decode a buffer back into the original data structure
	
	This reverses the encoding process and handles delta patching,
	decompression, schema validation, and migration as needed.
]]
--
function Remote:_decode(data: buffer, player: Player?): any
	-- Reverse XOR pre-processing
	local result = XOR.apply(data)

	local config = self._config.encode or { mode = "basic" }
	local value: any
	local err: string?

	if config.mode == "schema" then
		if not config.schema then
			warn("[Wisp] Schema mode requires schema in config.encode")
			return nil
		end

		value, err = Buffer.DecodeSchema(result, config.schema)

		if value and config.migrations and type(value) == "table" then
			local valueVersion = value._version or 1
			local targetVersion = config.schemaVersion or config.schema.version or 1
			if valueVersion < targetVersion then
				value = self:_migrateSchema(value, valueVersion, targetVersion)
			end
		end

		if value ~= nil then
			value = { value }
		end
	elseif config.mode == "delta" then
		--[[
			Delta decoding process:
			1. Try to decode as a delta patch against cached data
			2. If cache exists, apply the patch to get current state
			3. If no cache or patch fails, decode as full data
			4. Update cache with the final result
		]]
		--
		local cacheKey = if self._isServer then player else "__CLIENT__"

		if cacheKey and self._deltaCache[cacheKey] then
			if config.schema then
				value, err = Buffer.DecodeSchemaDelta(result, self._deltaCache[cacheKey], config.schema)
			else
				local patch = Buffer.Decode(result)
				if patch and type(patch) == "table" then
					value = table.clone(self._deltaCache[cacheKey])

					for k, v in pairs(patch) do
						local actualKey = k
						if type(k) == "string" then
							local numKey = tonumber(k)
							if numKey then
								actualKey = numKey
							end
						end
						value[actualKey] = v
					end
				else
					value = nil
					err = "Invalid delta patch"
				end
			end

			if value then
				self._deltaCache[cacheKey] = value
				if self._config.syncDeltaCache then
					self._deltaCacheHash[cacheKey] = Pool.hashData(value)
					self._deltaCacheVersion[cacheKey] = (self._deltaCacheVersion[cacheKey] or 0) + 1
				end
			end
		end

		if not value then
			if config.schema then
				value, err = Buffer.DecodeSchema(result, config.schema)
			else
				value, err = Buffer.SafeDecode(result)
			end

			if value and cacheKey then
				self._deltaCache[cacheKey] = value
				if self._config.syncDeltaCache then
					self._deltaCacheHash[cacheKey] = Pool.hashData(value)
					self._deltaCacheVersion[cacheKey] = 1
				end
			end
		end

		if value ~= nil then
			value = { value }
		end
	else
		value, err = Buffer.SafeDecode(result)
	end

	if err then
		warn(`[Wisp] Decode failed: {err}`)
		return nil
	end

	return value
end

--[[
	Check if a player has exceeded the rate limit for this remote
	
	Rate limiting prevents spam by enforcing a minimum interval between
	calls from the same player. Helps protect against exploits and bugs.
]]
--
function Remote:_checkRateLimit(player: Player): boolean
	if not self._config.rateLimit then
		return true
	end

	local now = os.clock()
	local last = self._lastSend[player] or 0

	if now - last < self._config.rateLimit then
		return false
	end

	self._lastSend[player] = now
	return true
end

--[[
	Encode a batch of pre-encoded packets for efficient transmission
	
	Batches contain multiple packets with metadata like priority and sequence numbers.
	This function wraps the batch structure without re-encoding the packet contents.
]]
--
function Remote:EncodeBatch(packets: { Types.BatchPacket }): buffer?
	local batchData = {
		count = #packets,
		sequence = self._sequence,
		packets = {},
	}
	self._sequence += 1

	for i, packet in packets do
		batchData.packets[i] = {
			remoteName = packet.remoteName,
			encodedArgs = packet.encodedArgs,
			priority = packet.priority,
			reliable = packet.reliable,
		}
	end

	if #packets > 10 then
		return Pool.inlineEncode(batchData, true)
	end

	return Buffer.Encode(batchData)
end

--[[
	Decode a batch of packets back into individual packet structures
	
	The returned packets still contain encoded arguments that need to be
	decoded separately with each remote's specific configuration.
]]
--
function Remote:DecodeBatch(data: buffer, player: Player?): { Types.BatchPacket }?
	local batchData = Buffer.SafeDecode(data)

	if not batchData or type(batchData) ~= "table" then
		return nil
	end

	return batchData.packets
end

--[[
	Get the hash of the delta cache for a specific player
	
	Used for cache synchronization verification between client and server
	to detect when delta caches have become desynchronized.
]]
--
function Remote:GetDeltaCacheHash(player: Player): string?
	return self._deltaCacheHash[player]
end

--[[
	Get the version number of the delta cache for a specific player
	
	Cache versions increment with each successful delta operation and help
	track the progression of cache state over time.
]]
--
function Remote:GetDeltaCacheVersion(player: Player): number?
	return self._deltaCacheVersion[player]
end

--[[
	Verify that client and server delta caches are synchronized
	
	Compares the provided hash with the server's cache hash for the player.
	If they don't match, clears the cache to force a full resynchronization.
]]
--
function Remote:SyncDeltaCache(player: Player, hash: string, _version: number): boolean
	local currentHash = self._deltaCacheHash[player]
	if currentHash ~= hash then
		self._deltaCache[player] = nil
		self._deltaCacheHash[player] = nil
		self._deltaCacheVersion[player] = nil
		return false
	end
	return true
end

--[[
	Clear all cached data for a specific player
	
	Called automatically when players leave the server to prevent memory leaks.
	Can also be called manually to force cache invalidation.
]]
--
function Remote:ClearPlayer(player: Player)
	self._deltaCache[player] = nil
	self._deltaCacheHash[player] = nil
	self._deltaCacheVersion[player] = nil
	self._lastSend[player] = nil
end

--[[
	Clean up resources and disconnect all listeners
	
	Called automatically when the Remote wrapper is no longer needed.
]]
--
function Remote:Destroy()
	self._trove:Clean()
end

return Remote
