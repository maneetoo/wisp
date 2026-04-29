local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IsServer: boolean = RunService:IsServer()

local Buffer = require("./modules/Buffer")
local Pool = require("./modules/Pool")
local Remote = require("./modules/Remote")
local Trove = require("../helpful_modules/Trove")
local Types = require("./Types")
local t = require("../helpful_modules/t")

type RemoteConfig = Types.RemoteConfig
type BatchPacket = Types.BatchPacket
type InvokeCallback = Types.InvokeCallback
type MigrationMap = Types.MigrationMap

local Server = {}

--[[
	Internal state management
	
	The server maintains separate batch queues per player for targeted sends,
	plus global queues for broadcasts to all players.
]]
--
local _trove = Trove.new()
local _remotes: { [string]: Remote.Remote } = {}
local _remoteInstances: { [string]: RemoteEvent | UnreliableRemoteEvent } = {}
local _remoteFunctions: { [string]: RemoteFunction } = {}
local _listeners: { [string]: { (player: Player, ...any) -> () } } = {}
local _invokeCallbacks: { [string]: InvokeCallback } = {}
local _globalConfig: RemoteConfig? = nil
local _remoteConfigs: { [string]: RemoteConfig } = {}
local _container: Folder?
local _schemas: { [string]: Types.Schema } = {}
local _migrations: { [string]: MigrationMap } = {}

--[[
	Server batch processing system
	
	Maintains per-player queues for targeted messages and global queues for broadcasts.
	This allows efficient batching of both unicast and multicast communications.
]]
--
local _batchEnabled = true
local _unreliableBatchQueues: { [Player]: { BatchPacket } } = {}
local _reliableBatchQueues: { [Player]: { BatchPacket } } = {}
local _unreliableBatchAll: { BatchPacket } = {}
local _reliableBatchAll: { BatchPacket } = {}
local _unreliableBatchRemote: UnreliableRemoteEvent?
local _reliableBatchRemote: RemoteEvent?

local _deltaSyncRemote: RemoteEvent?

--[[
	Type validation helpers for server API functions
]]
--
local validateString = t.string
local validatePlayer = t.instanceIsA("Player")
local validatePlayerArray = t.array(t.instanceIsA("Player"))
local validateCallback = t.callback
local validateNumber = t.number
local validateBoolean = t.boolean
local validateBatchMode = t.union(t.literal("never"), t.literal("unreliable"), t.literal("reliable"))
local validateCompressionMode =
	t.union(t.literal("auto"), t.literal("lz4"), t.literal("deflate"), t.literal("zstd"), t.literal("none"))

--[[
	Create the WispRemotes container in ReplicatedStorage
	
	This folder holds all remote objects created by Wisp. It's created on
	the server and replicated to clients for them to discover remotes.
]]
--
local function getOrCreateContainer(): Folder
	if not _container then
		_container = ReplicatedStorage:FindFirstChild("WispRemotes") :: Folder
		if not _container then
			_container = Instance.new("Folder")
			_container.Name = "WispRemotes"
			_container.Parent = ReplicatedStorage
			_trove:Add(_container)
		end
	end
	return _container
end

--[[
	Create the unreliable batch remote for high-frequency data
	
	This handles batches of data that can tolerate packet loss, such as
	position updates, animation sync, or other frequently changing data.
]]
--
local function getOrCreateUnreliableBatchRemote(): UnreliableRemoteEvent
	if not _unreliableBatchRemote then
		_unreliableBatchRemote = Instance.new("UnreliableRemoteEvent")
		_unreliableBatchRemote.Name = "__WispBatchUnreliable"
		_unreliableBatchRemote.Parent = getOrCreateContainer()
		_trove:Add(_unreliableBatchRemote)
	end
	return _unreliableBatchRemote
end

--[[
	Create the reliable batch remote for important data
	
	This handles batches of critical data that must be delivered, such as
	player statistics, inventory changes, or purchase confirmations.
]]
--
local function getOrCreateReliableBatchRemote(): RemoteEvent
	if not _reliableBatchRemote then
		_reliableBatchRemote = Instance.new("RemoteEvent")
		_reliableBatchRemote.Name = "__WispBatchReliable"
		_reliableBatchRemote.Parent = getOrCreateContainer()
		_trove:Add(_reliableBatchRemote)
	end
	return _reliableBatchRemote
end

--[[
	Create the delta synchronization remote for cache verification
	
	This remote allows clients and server to verify their delta caches are
	synchronized and request full data resends when desynchronization is detected.
]]
--
local function getOrCreateDeltaSyncRemote(): RemoteEvent
	if not _deltaSyncRemote then
		_deltaSyncRemote = Instance.new("RemoteEvent")
		_deltaSyncRemote.Name = "__WispDeltaSync"
		_deltaSyncRemote.Parent = getOrCreateContainer()
		_trove:Add(_deltaSyncRemote)

		_trove:Connect(_deltaSyncRemote.OnServerEvent, function(player: Player, data: buffer)
			local decoded = Buffer.Decode(data)
			if type(decoded) ~= "table" then
				return
			end

			local remoteName = decoded.remoteName
			local hash = decoded.hash
			local version = decoded.version

			local remote = _remotes[remoteName]
			if remote and remote:SyncDeltaCache(player, hash, version) then
				_deltaSyncRemote:FireClient(
					player,
					Buffer.Encode({
						remoteName = remoteName,
						status = "ok",
					})
				)
			else
				_deltaSyncRemote:FireClient(
					player,
					Buffer.Encode({
						remoteName = remoteName,
						status = "resync",
					})
				)
			end
		end)
	end
	return _deltaSyncRemote
end

--[[
	Resolve the effective configuration for a specific remote
	
	Same priority system as client: remote-specific > global > defaults
]]
--
local function getConfigForRemote(name: string): RemoteConfig?
	local config = _remoteConfigs[name] or _globalConfig

	if not config then
		return nil
	end

	if _schemas[name] and not (config.encode and config.encode.schema) then
		config = table.clone(config)
		config.encode = config.encode or {}
		config.encode.mode = "schema"
		config.encode.schema = _schemas[name]

		if _migrations[name] then
			config.encode.migrations = _migrations[name]
		end
	end

	return config
end

--[[
	Create a Remote wrapper for client communication
	
	The server creates the actual RemoteEvent/UnreliableRemoteEvent instances
	and wraps them for encoding, rate limiting, and event handling.
]]
--
local function getOrCreateRemote(name: string): Remote.Remote
	if _remotes[name] then
		return _remotes[name]
	end

	local config = getConfigForRemote(name)
	local remote: RemoteEvent | UnreliableRemoteEvent

	if config and config.unreliable then
		remote = Instance.new("UnreliableRemoteEvent")
	else
		remote = Instance.new("RemoteEvent")
	end

	remote.Name = name
	remote.Parent = getOrCreateContainer()

	local wrapper = Remote.new(remote, config, true)

	_remotes[name] = wrapper
	_remoteInstances[name] = remote
	_trove:Add(function()
		wrapper:Destroy()
	end)
	_trove:Add(remote)

	_trove:Connect(remote.OnServerEvent, function(player: Player, data: buffer)
		if not wrapper:_checkRateLimit(player) then
			warn(`[Wisp] Rate limit exceeded for {player.Name} on "{name}"`)
			return
		end

		local decoded = wrapper:_decode(data, player)
		if not decoded then
			return
		end

		local callbacks = _listeners[name]
		if callbacks then
			for _, callback in callbacks do
				task.spawn(callback, player, table.unpack(decoded))
			end
		end
	end)

	return wrapper
end

--[[
	Create a RemoteFunction wrapper for request/response communication
	
	Similar to regular remotes but handles the invoke pattern where clients
	can send requests and wait for responses from the server.
]]
--
local function getOrCreateRemoteFunction(name: string): (RemoteFunction, Remote.Remote)
	if _remoteFunctions[name] then
		return _remoteFunctions[name], _remotes[name]
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = getOrCreateContainer()

	local config = getConfigForRemote(name)
	local wrapper = Remote.new(remote, config, true)

	_remoteFunctions[name] = remote
	_remotes[name] = wrapper
	_trove:Add(function()
		wrapper:Destroy()
	end)
	_trove:Add(remote)

	remote.OnServerInvoke = function(player: Player, data: buffer)
		if not wrapper:_checkRateLimit(player) then
			warn(`[Wisp] Rate limit exceeded for {player.Name} on "{name}"`)
			return nil
		end

		local decoded = wrapper:_decode(data, player)
		if not decoded or type(decoded) ~= "table" then
			return nil
		end

		local callback = _invokeCallbacks[name]
		if not callback then
			warn(`[Wisp] No invoke callback registered for "{name}"`)
			return nil
		end

		local results = { callback(player, table.unpack(decoded)) }
		local encoded = wrapper:_encode(results, player)

		return encoded
	end

	return remote, wrapper
end

--[[
	Send all queued batch data to a specific player
	
	Processes the player's individual batch queue and sends it as a single
	network packet to reduce overhead from multiple small messages.
]]
--
local function flushBatchForPlayer(player: Player, unreliable: boolean)
	local queue = if unreliable then _unreliableBatchQueues[player] else _reliableBatchQueues[player]
	if not queue or #queue == 0 then
		return
	end

	table.sort(queue, function(a, b)
		return (a.priority or 999) < (b.priority or 999)
	end)

	local encoded: buffer?
	if #queue > 10 then
		encoded = Pool.inlineEncode(queue, true)
	else
		-- Manual batch encoding
		local scratch = buffer.create(100000)
		local offset = 0

		-- Header: count + sequence
		buffer.writeu16(scratch, offset, #queue)
		offset += 2
		buffer.writeu32(scratch, offset, 0)
		offset += 4

		-- Packets
		for _, packet in queue do
			local nameLen = #packet.remoteName
			buffer.writeu8(scratch, offset, nameLen)
			offset += 1
			buffer.writestring(scratch, offset, packet.remoteName)
			offset += nameLen

			local argsLen = buffer.len(packet.encodedArgs)
			buffer.writeu32(scratch, offset, argsLen)
			offset += 4

			buffer.copy(scratch, offset, packet.encodedArgs, 0, argsLen)
			offset += argsLen
		end

		encoded = buffer.create(offset)
		buffer.copy(encoded, 0, scratch, 0, offset)
	end

	if encoded then
		local batchRemote = if unreliable then getOrCreateUnreliableBatchRemote() else getOrCreateReliableBatchRemote()
		batchRemote:FireClient(player, encoded)
	end

	if unreliable then
		_unreliableBatchQueues[player] = {}
	else
		_reliableBatchQueues[player] = {}
	end
end

--[[
	Send all queued broadcast data to all connected players
	
	Processes the global batch queue and broadcasts it to all clients
	simultaneously for efficient multicasting.
]]
--
local function flushBatchForAll(unreliable: boolean)
	local queue = if unreliable then _unreliableBatchAll else _reliableBatchAll
	if #queue == 0 then
		return
	end

	table.sort(queue, function(a, b)
		return (a.priority or 999) < (b.priority or 999)
	end)

	local encoded: buffer?
	if #queue > 10 then
		encoded = Pool.inlineEncode(queue, true)
	else
		-- Manual batch encoding
		local scratch = buffer.create(100000)
		local offset = 0

		buffer.writeu16(scratch, offset, #queue)
		offset += 2
		buffer.writeu32(scratch, offset, 0)
		offset += 4

		for _, packet in queue do
			local nameLen = #packet.remoteName
			buffer.writeu8(scratch, offset, nameLen)
			offset += 1
			buffer.writestring(scratch, offset, packet.remoteName)
			offset += nameLen

			local argsLen = buffer.len(packet.encodedArgs)
			buffer.writeu32(scratch, offset, argsLen)
			offset += 4

			buffer.copy(scratch, offset, packet.encodedArgs, 0, argsLen)
			offset += argsLen
		end

		encoded = buffer.create(offset)
		buffer.copy(encoded, 0, scratch, 0, offset)
	end

	if encoded then
		local batchRemote = if unreliable then getOrCreateUnreliableBatchRemote() else getOrCreateReliableBatchRemote()
		batchRemote:FireAllClients(encoded)
	end

	if unreliable then
		table.clear(_unreliableBatchAll)
	else
		table.clear(_reliableBatchAll)
	end
end

--[[
	Initialize the server-side batch processing system
	
	Sets up automatic batch flushing every frame and handlers for incoming
	batches from clients. Also cleans up player data when players leave.
]]
--
local function setupBatchFlushing()
	_trove:Connect(RunService.Heartbeat, function()
		for player in pairs(_unreliableBatchQueues) do
			flushBatchForPlayer(player, true)
		end
		flushBatchForAll(true)

		for player in pairs(_reliableBatchQueues) do
			flushBatchForPlayer(player, false)
		end
		flushBatchForAll(false)
	end)

	local unreliableBatch = getOrCreateUnreliableBatchRemote()
	local reliableBatch = getOrCreateReliableBatchRemote()

	--[[
		Handle incoming batch packets from clients
		
		Manually decodes batch structure and processes each packet with
		the appropriate remote's configuration for proper delta handling.
	]]
	--
	local function handleBatch(player: Player, data: buffer, unreliable: boolean)
		-- Decode batch manually
		local offset = 0

		-- Header
		local count = buffer.readu16(data, offset)
		offset += 2
		local sequence = buffer.readu32(data, offset)
		offset += 4

		for i = 1, count do
			-- Remote name
			local nameLen = buffer.readu8(data, offset)
			offset += 1
			local remoteName = buffer.readstring(data, offset, nameLen)
			offset += nameLen

			-- Size of encodedArgs
			local argsLen = buffer.readu32(data, offset)
			offset += 4

			-- encodedArgs
			local encodedArgs = buffer.create(argsLen)
			buffer.copy(encodedArgs, 0, data, offset, argsLen)
			offset += argsLen

			local remote = getOrCreateRemote(remoteName)
			if not remote then
				continue
			end

			local decodedArgs = remote:_decode(encodedArgs, player)
			if not decodedArgs or type(decodedArgs) ~= "table" then
				continue
			end

			local callbacks = _listeners[remoteName]
			if callbacks then
				for _, callback in callbacks do
					task.spawn(callback, player, table.unpack(decodedArgs))
				end
			end
		end
	end

	_trove:Connect(unreliableBatch.OnServerEvent, function(player, data)
		handleBatch(player, data, true)
	end)

	_trove:Connect(reliableBatch.OnServerEvent, function(player, data)
		handleBatch(player, data, false)
	end)

	_trove:Connect(Players.PlayerRemoving, function(player: Player)
		_unreliableBatchQueues[player] = nil
		_reliableBatchQueues[player] = nil
	end)

	if _globalConfig and _globalConfig.syncDeltaCache then
		getOrCreateDeltaSyncRemote()
	end
end

if IsServer then
	task.defer(setupBatchFlushing)
end

--[[
	Send data to a specific player via a named remote
	
	This is the primary method for server-to-client communication. Data is
	automatically encoded, compressed, and batched according to the remote's config.
]]
--
function Server.Fire(remoteName: string, player: Player, ...: any)
	assert(validateString(remoteName), "[Wisp.Fire] remoteName must be a string")
	assert(validatePlayer(player), "[Wisp.Fire] player must be a Player instance")

	local config = getConfigForRemote(remoteName)
	local batchMode = if config then config.batching or "unreliable" else "unreliable"

	if not _batchEnabled or batchMode == "never" then
		local remote = getOrCreateRemote(remoteName)
		local encoded = remote:_encode({ ... }, player)
		if encoded then
			remote._remote:FireClient(player, encoded)
		end
		return
	end

	-- Get wrapper with correct config and pre-encode args
	local remote = getOrCreateRemote(remoteName)
	local encodedArgs = remote:_encode({ ... }, player)
	if not encodedArgs then
		return
	end

	local queue: { BatchPacket }
	local isUnreliable = batchMode == "unreliable"

	if isUnreliable then
		if not _unreliableBatchQueues[player] then
			_unreliableBatchQueues[player] = {}
		end
		queue = _unreliableBatchQueues[player]
	else
		if not _reliableBatchQueues[player] then
			_reliableBatchQueues[player] = {}
		end
		queue = _reliableBatchQueues[player]
	end

	table.insert(queue, {
		remoteName = remoteName,
		encodedArgs = encodedArgs,
		priority = if config then config.batchPriority or 999 else 999,
		reliable = not isUnreliable,
	})

	local maxSize = if config then config.maxBatchSize or 50 else 50
	if #queue >= maxSize then
		flushBatchForPlayer(player, isUnreliable)
	end
end

--[[
	Broadcast data to all connected players
	
	More efficient than calling Fire() for each player individually when
	sending the same data to everyone.
]]
--
function Server.FireAll(remoteName: string, ...: any)
	assert(validateString(remoteName), "[Wisp.FireAll] remoteName must be a string")

	local config = getConfigForRemote(remoteName)
	local batchMode = if config then config.batching or "unreliable" else "unreliable"

	if not _batchEnabled or batchMode == "never" then
		local remote = getOrCreateRemote(remoteName)
		local encoded = remote:_encode({ ... })
		if encoded then
			remote._remote:FireAllClients(encoded)
		end
		return
	end

	-- Get wrapper with correct config and pre-encode args
	local remote = getOrCreateRemote(remoteName)
	local encodedArgs = remote:_encode({ ... })
	if not encodedArgs then
		return
	end

	local isUnreliable = batchMode == "unreliable"
	local queue = if isUnreliable then _unreliableBatchAll else _reliableBatchAll

	table.insert(queue, {
		remoteName = remoteName,
		encodedArgs = encodedArgs,
		priority = if config then config.batchPriority or 999 else 999,
		reliable = not isUnreliable,
	})

	local maxSize = if config then config.maxBatchSize or 50 else 50
	if #queue >= maxSize then
		flushBatchForAll(isUnreliable)
	end
end

--[[
	Send data to a specific list of players
	
	Convenience method that calls Fire() for each player in the list.
	More efficient than manual iteration in user code.
]]
--
function Server.FireList(remoteName: string, players: { Player }, ...: any)
	assert(validateString(remoteName), "[Wisp.FireList] remoteName must be a string")
	assert(validatePlayerArray(players), "[Wisp.FireList] players must be an array of Player instances")

	for _, player in players do
		Server.Fire(remoteName, player, ...)
	end
end

--[[
	Send data to all players except those in the exclusion list
	
	Useful for broadcasting events to everyone except the player who triggered them,
	such as notifying other players when someone joins or achieves something.
]]
--
function Server.FireExcept(remoteName: string, except: Player | { Player }, ...: any)
	assert(validateString(remoteName), "[Wisp.FireExcept] remoteName must be a string")

	local excludeList: { Player } = if typeof(except) == "Instance" then { except } else except

	for _, player in Players:GetPlayers() do
		if not table.find(excludeList, player) then
			Server.Fire(remoteName, player, ...)
		end
	end
end

--[[
	Register a callback to handle data from clients
	
	When clients call Fire() on this remote, your callback will be invoked
	with the sending player and the decoded arguments.
]]
--
function Server.Connect(remoteName: string, callback: (player: Player, ...any) -> ())
	assert(validateString(remoteName), "[Wisp.Connect] remoteName must be a string")
	assert(validateCallback(callback), "[Wisp.Connect] callback must be a function")

	if not _listeners[remoteName] then
		_listeners[remoteName] = {}
		getOrCreateRemote(remoteName)
	end

	table.insert(_listeners[remoteName], callback)

	return function()
		local callbacks = _listeners[remoteName]
		if callbacks then
			local index = table.find(callbacks, callback)
			if index then
				table.remove(callbacks, index)
			end
		end
	end
end

--[[
	Register a callback that automatically disconnects after being called once
	
	Useful for waiting for a specific event from any client without manual cleanup.
]]
--
function Server.Once(remoteName: string, callback: (player: Player, ...any) -> ())
	assert(validateString(remoteName), "[Wisp.Once] remoteName must be a string")
	assert(validateCallback(callback), "[Wisp.Once] callback must be a function")

	local disconnect: (() -> ())?
	disconnect = Server.Connect(remoteName, function(player: Player, ...: any)
		if disconnect then
			disconnect()
		end
		callback(player, ...)
	end)
	return disconnect
end

--[[
	Register a callback for RemoteFunction invocations from clients
	
	When clients call Invoke() on this remote, your callback will be called
	and its return values sent back to the requesting client.
]]
--
function Server.OnInvoke(remoteName: string, callback: InvokeCallback)
	assert(validateString(remoteName), "[Wisp.OnInvoke] remoteName must be a string")
	assert(validateCallback(callback), "[Wisp.OnInvoke] callback must be a function")

	getOrCreateRemoteFunction(remoteName)
	_invokeCallbacks[remoteName] = callback
end

--[[
	Invoke a RemoteFunction on a client and wait for the response
	
	This sends data to a client and yields until they respond. Useful for
	requesting information or confirmation from players.
]]
--
function Server.Invoke(remoteName: string, player: Player, ...: any): ...any
	assert(validateString(remoteName), "[Wisp.Invoke] remoteName must be a string")
	assert(validatePlayer(player), "[Wisp.Invoke] player must be a Player instance")

	local remote, wrapper = getOrCreateRemoteFunction(remoteName)
	local encoded = wrapper:_encode({ ... }, player)
	if not encoded then
		return nil
	end

	local result = remote:InvokeClient(player, encoded)
	if not result then
		return nil
	end

	local decoded = wrapper:_decode(result, player)
	if decoded and type(decoded) == "table" then
		return table.unpack(decoded)
	end
	return nil
end

--[[
	Register data schemas for automatic validation and migration
	
	Schemas ensure data integrity and enable automatic upgrades when you
	change data structures between game updates.
]]
--
function Server.UseSchemas(schemas: { [string]: Types.Schema }, migrations: { [string]: MigrationMap }?)
	assert(t.table(schemas), "[Wisp.UseSchemas] schemas must be a table")

	for name, schema in schemas do
		_schemas[name] = schema
		if migrations and migrations[name] then
			_migrations[name] = migrations[name]
		end
	end

	for name, remote in _remotes do
		if _schemas[name] then
			remote._config.encode = remote._config.encode or {}
			remote._config.encode.mode = "schema"
			remote._config.encode.schema = _schemas[name]
			if _migrations[name] then
				remote._config.encode.migrations = _migrations[name]
			end
		end
	end
end

--[[
	Configure encoding, batching, and other options for remotes
	
	This is the primary way to customize how data is transmitted for specific
	remotes or as global defaults for all remotes.
]]
--
function Server.UseConfig(config: RemoteConfig, remoteName: string?)
	assert(t.table(config), "[Wisp.UseConfig] config must be a table")
	if remoteName then
		assert(validateString(remoteName), "[Wisp.UseConfig] remoteName must be a string")
	end

	if remoteName then
		_remoteConfigs[remoteName] = config
		if _remotes[remoteName] then
			_remotes[remoteName]._config = config
		end
	else
		_globalConfig = config
		for _, remote in _remotes do
			remote._config = config
		end
	end
end

--[[
	Enable data compression to reduce bandwidth usage
	
	Compression is especially effective for large data structures or when
	sending the same data to many players simultaneously.
]]
--
function Server.UseCompression(mode: Types.CompressionMode, remoteName: string?)
	assert(validateCompressionMode(mode), "[Wisp.UseCompression] mode must be a valid compression mode")
	if remoteName then
		assert(validateString(remoteName), "[Wisp.UseCompression] remoteName must be a string")
	end

	local config: RemoteConfig = {
		encode = { mode = "compressed", compression = mode },
	}
	Server.UseConfig(config, remoteName)
end

--[[
	Enable delta encoding to dramatically reduce bandwidth for large data updates
	
	Delta encoding only sends the changes since the last transmission, making it
	ideal for frequently updated data structures like game state or inventories.
]]
--
function Server.UseDelta(schema: Types.Schema?, remoteName: string?)
	if remoteName then
		assert(validateString(remoteName), "[Wisp.UseDelta] remoteName must be a string")
	end

	local config: RemoteConfig = {
		encode = { mode = "delta", schema = schema },
		syncDeltaCache = true,
	}
	Server.UseConfig(config, remoteName)
end

--[[
	Enable or disable the batching system globally
	
	Disabling batching increases network overhead but reduces latency by
	sending each Fire() call immediately.
]]
--
function Server.UseBatching(enabled: boolean)
	assert(validateBoolean(enabled), "[Wisp.UseBatching] enabled must be a boolean")
	_batchEnabled = enabled
end

--[[
	Configure a remote to use UnreliableRemoteEvent for lower latency
	
	Unreliable remotes sacrifice guaranteed delivery for reduced latency,
	making them ideal for high-frequency data like movement or animations.
]]
--
function Server.SetUnreliable(remoteName: string, unreliable: boolean)
	assert(validateString(remoteName), "[Wisp.SetUnreliable] remoteName must be a string")
	assert(validateBoolean(unreliable), "[Wisp.SetUnreliable] unreliable must be a boolean")

	_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
	_remoteConfigs[remoteName].unreliable = unreliable
	_remoteConfigs[remoteName].batching = if unreliable then "unreliable" else "reliable"
end

--[[
	Set the batching behavior for a specific remote
	
	Choose between immediate sending, unreliable batching, or reliable batching
	based on the importance and frequency of your data.
]]
--
function Server.SetBatchMode(remoteName: string, mode: Types.BatchMode)
	assert(validateString(remoteName), "[Wisp.SetBatchMode] remoteName must be a string")
	assert(validateBatchMode(mode), "[Wisp.SetBatchMode] mode must be 'never', 'unreliable', or 'reliable'")

	_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
	_remoteConfigs[remoteName].batching = mode
end

--[[
	Set the priority order for a remote within batches
	
	Lower numbers are processed first. Use this to ensure critical data
	is handled before less important updates.
]]
--
function Server.SetBatchPriority(remoteName: string, priority: number)
	assert(validateString(remoteName), "[Wisp.SetBatchPriority] remoteName must be a string")
	assert(validateNumber(priority), "[Wisp.SetBatchPriority] priority must be a number")

	_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
	_remoteConfigs[remoteName].batchPriority = priority
end

--[[
	Configure rate limiting to prevent spam from misbehaving clients
	
	Sets the minimum time interval between calls from the same player.
	Helps protect against exploits and accidental infinite loops.
]]
--
function Server.SetRateLimit(limit: number, remoteName: string?)
	assert(validateNumber(limit), "[Wisp.SetRateLimit] limit must be a number")
	if remoteName then
		assert(validateString(remoteName), "[Wisp.SetRateLimit] remoteName must be a string")
	end

	if remoteName then
		_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
		_remoteConfigs[remoteName].rateLimit = limit
		if _remotes[remoteName] then
			_remotes[remoteName]._config.rateLimit = limit
		end
	else
		_globalConfig = _globalConfig or {}
		_globalConfig.rateLimit = limit
	end
end

--[[
	Configure the maximum size of batches before forcing transmission
	
	Balance between efficiency (larger batches) and latency (smaller batches)
	based on your game's specific networking requirements.
]]
--
function Server.SetMaxBatchSize(size: number)
	assert(validateNumber(size), "[Wisp.SetMaxBatchSize] size must be a number")

	_globalConfig = _globalConfig or {}
	_globalConfig.maxBatchSize = size
end

--[[
	Enable delta cache synchronization for data integrity verification
	
	When enabled, clients and server exchange cache verification data to detect
	and automatically recover from delta desynchronization.
]]
--
function Server.EnableDeltaSync(remoteName: string?)
	if remoteName then
		assert(validateString(remoteName), "[Wisp.EnableDeltaSync] remoteName must be a string")
	end

	if remoteName then
		_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
		_remoteConfigs[remoteName].syncDeltaCache = true
	else
		_globalConfig = _globalConfig or {}
		_globalConfig.syncDeltaCache = true
		getOrCreateDeltaSyncRemote()
	end
end

--[[
	Immediately send all queued batch data to all players
	
	Use this when you need to ensure all pending data is transmitted immediately,
	such as before important game state changes or when players are leaving.
]]
--
function Server.FlushBatches()
	for player in pairs(_unreliableBatchQueues) do
		flushBatchForPlayer(player, true)
	end
	for player in pairs(_reliableBatchQueues) do
		flushBatchForPlayer(player, false)
	end
	flushBatchForAll(true)
	flushBatchForAll(false)
end

--[[
	Type creation utilities for schema validation
	
	These provide a convenient API for creating type validators used in schemas.
]]
--
Server.Types = Buffer.Types
Server.CreateType = Buffer.Types

return Server
