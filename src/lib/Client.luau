local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IsClient: boolean = RunService:IsClient()

local Buffer = require("./modules/Buffer")
local Pool = require("./modules/Pool")
local Remote = require("./modules/Remote")
local Trove = require("../helpful_modules/Trove")
local Types = require("./Types")
local t = require("../helpful_modules/t")

type RemoteConfig = Types.RemoteConfig
type BatchPacket = Types.BatchPacket
type ClientInvokeCallback = Types.ClientInvokeCallback
type MigrationMap = Types.MigrationMap

local Client = {}

--[[
	Internal state management
	
	These variables track remote connections, batching queues, and configuration.
	The client maintains separate queues for unreliable (fast) and reliable (guaranteed) messages.
]]
--
local _trove = Trove.new()
local _remotes: { [string]: Remote.Remote } = {}
local _remoteInstances: { [string]: RemoteEvent | UnreliableRemoteEvent } = {}
local _remoteFunctions: { [string]: RemoteFunction } = {}
local _listeners: { [string]: { (...any) -> () } } = {}
local _invokeCallbacks: { [string]: ClientInvokeCallback } = {}
local _globalConfig: RemoteConfig? = nil
local _remoteConfigs: { [string]: RemoteConfig } = {}
local _container: Folder?
local _schemas: { [string]: Types.Schema } = {}
local _migrations: { [string]: MigrationMap } = {}

--[[
	Batch processing system
	
	The client batches multiple Fire() calls into single network packets for efficiency.
	Unreliable batches are faster but may be lost, reliable batches are guaranteed delivery.
]]
--
local _batchEnabled = true
local _unreliableBatchQueue: { BatchPacket } = {}
local _reliableBatchQueue: { BatchPacket } = {}
local _unreliableBatchRemote: UnreliableRemoteEvent?
local _reliableBatchRemote: RemoteEvent?

local _deltaSyncRemote: RemoteEvent?

--[[
	Type validation helpers
	
	These validators ensure proper types are passed to public API functions.
]]
--
local validateString = t.string
local validateCallback = t.callback
local validateNumber = t.number
local validateBoolean = t.boolean
local validateBatchMode = t.union(t.literal("never"), t.literal("unreliable"), t.literal("reliable"))
local validateCompressionMode =
	t.union(t.literal("auto"), t.literal("lz4"), t.literal("deflate"), t.literal("zstd"), t.literal("none"))

--[[
	Wait for the server to create the WispRemotes container in ReplicatedStorage
	
	The server creates this folder during initialization. The client waits for it
	before attempting to access any remote objects.
]]
--
local function waitForContainer(): Folder?
	if _container then
		return _container
	end

	_container = ReplicatedStorage:WaitForChild("WispRemotes", 10) :: Folder
	if _container then
		_trove:Add(_container)
	end
	return _container
end

--[[
	Get the unreliable batch remote for receiving server messages
	
	This remote handles high-frequency data that can tolerate packet loss,
	such as position updates or animation sync.
]]
--
local function getUnreliableBatchRemote(): UnreliableRemoteEvent?
	if _unreliableBatchRemote then
		return _unreliableBatchRemote
	end

	local container = waitForContainer()
	if not container then
		return nil
	end

	_unreliableBatchRemote = container:WaitForChild("__WispBatchUnreliable", 5) :: UnreliableRemoteEvent
	if _unreliableBatchRemote then
		_trove:Add(_unreliableBatchRemote)
	end
	return _unreliableBatchRemote
end

--[[
	Get the reliable batch remote for receiving server messages
	
	This remote handles important data that must be delivered, such as
	player stats, inventory changes, or purchase confirmations.
]]
--
local function getReliableBatchRemote(): RemoteEvent?
	if _reliableBatchRemote then
		return _reliableBatchRemote
	end

	local container = waitForContainer()
	if not container then
		return nil
	end

	_reliableBatchRemote = container:WaitForChild("__WispBatchReliable", 5) :: RemoteEvent
	if _reliableBatchRemote then
		_trove:Add(_reliableBatchRemote)
	end
	return _reliableBatchRemote
end

--[[
	Get the delta sync remote for cache verification
	
	This remote allows the client and server to verify that their delta caches
	are synchronized, preventing data corruption from packet loss.
]]
--
local function getDeltaSyncRemote(): RemoteEvent?
	if _deltaSyncRemote then
		return _deltaSyncRemote
	end

	local container = waitForContainer()
	if not container then
		return nil
	end

	_deltaSyncRemote = container:WaitForChild("__WispDeltaSync", 5) :: RemoteEvent
	if _deltaSyncRemote then
		_trove:Add(_deltaSyncRemote)
	end
	return _deltaSyncRemote
end

--[[
	Resolve the effective configuration for a specific remote
	
	Configuration priority:
	1. Remote-specific config (set via UseConfig with remoteName)
	2. Global config (set via UseConfig without remoteName)
	3. Schema auto-application if registered
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
	Get or create a Remote wrapper for the given name
	
	This waits for the server to create the remote, then wraps it with encoding,
	decoding, and event handling capabilities. Each remote is cached for reuse.
]]
--
local function getOrCreateRemote(name: string): Remote.Remote?
	if _remotes[name] then
		return _remotes[name]
	end

	local container = waitForContainer()
	if not container then
		warn(`[Wisp] Failed to find WispRemotes container`)
		return nil
	end

	local remote = container:WaitForChild(name, 5) :: RemoteEvent?
	if not remote then
		warn(`[Wisp] Remote "{name}" not found (did server create it?)`)
		return nil
	end

	local config = getConfigForRemote(name)
	local wrapper = Remote.new(remote, config, false)

	_remotes[name] = wrapper
	_remoteInstances[name] = remote
	_trove:Add(function()
		wrapper:Destroy()
	end)

	_trove:Connect(remote.OnClientEvent, function(data: buffer)
		local decoded = wrapper:_decode(data)
		if not decoded or type(decoded) ~= "table" then
			return
		end

		local callbacks = _listeners[name]
		if callbacks then
			for _, callback in callbacks do
				task.spawn(callback, table.unpack(decoded))
			end
		end
	end)

	return wrapper
end

--[[
	Get or create a RemoteFunction wrapper for request/response communication
	
	Similar to getOrCreateRemote but handles the synchronous invoke pattern
	where the client sends a request and waits for a response.
]]
--
local function getOrCreateRemoteFunction(name: string): (RemoteFunction?, Remote.Remote?)
	if _remoteFunctions[name] then
		return _remoteFunctions[name], _remotes[name]
	end

	local container = waitForContainer()
	if not container then
		warn(`[Wisp] Failed to find WispRemotes container`)
		return nil, nil
	end

	local remote = container:WaitForChild(name, 5) :: RemoteFunction?
	if not remote then
		warn(`[Wisp] RemoteFunction "{name}" not found (did server create it?)`)
		return nil, nil
	end

	local config = getConfigForRemote(name)
	local wrapper = Remote.new(remote, config, false)

	_remoteFunctions[name] = remote
	_remotes[name] = wrapper
	_trove:Add(function()
		wrapper:Destroy()
	end)

	remote.OnClientInvoke = function(data: buffer)
		local decoded = wrapper:_decode(data)
		if not decoded or type(decoded) ~= "table" then
			return nil
		end

		local callback = _invokeCallbacks[name]
		if not callback then
			warn(`[Wisp] No invoke callback registered for "{name}"`)
			return nil
		end

		local results = { callback(table.unpack(decoded)) }
		local encoded = wrapper:_encode(results)

		return encoded
	end

	return remote, wrapper
end

--[[
	Send all queued batch packets to the server immediately
	
	This function manually encodes batch data since the packets contain pre-encoded
	arguments as buffers, which can't be processed by the standard Buffer.Encode.
]]
--
local function flushBatch(unreliable: boolean)
	local queue = if unreliable then _unreliableBatchQueue else _reliableBatchQueue
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
		-- Manual encoding for batch with pre-encoded args
		local scratch = buffer.create(100000)
		local offset = 0

		-- Header: count + sequence
		buffer.writeu16(scratch, offset, #queue)
		offset += 2
		buffer.writeu32(scratch, offset, 0)
		offset += 4

		-- Packets
		for _, packet in queue do
			-- Remote name
			local nameLen = #packet.remoteName
			buffer.writeu8(scratch, offset, nameLen)
			offset += 1
			buffer.writestring(scratch, offset, packet.remoteName)
			offset += nameLen

			-- Size of encodedArgs
			local argsLen = buffer.len(packet.encodedArgs)
			buffer.writeu32(scratch, offset, argsLen)
			offset += 4

			-- encodedArgs
			buffer.copy(scratch, offset, packet.encodedArgs, 0, argsLen)
			offset += argsLen
		end

		encoded = buffer.create(offset)
		buffer.copy(encoded, 0, scratch, 0, offset)
	end

	if encoded then
		local batchRemote = if unreliable then getUnreliableBatchRemote() else getReliableBatchRemote()
		if batchRemote then
			batchRemote:FireServer(encoded)
		end
	end

	if unreliable then
		table.clear(_unreliableBatchQueue)
	else
		table.clear(_reliableBatchQueue)
	end
end

--[[
	Initialize the batch processing system
	
	Sets up automatic batch flushing every frame and handlers for incoming
	batches from the server. Also handles delta cache sync if enabled.
]]
--
local function setupBatchFlushing()
	_trove:Connect(RunService.Heartbeat, function()
		flushBatch(true)
		flushBatch(false)
	end)

	local unreliableBatch = getUnreliableBatchRemote()
	local reliableBatch = getReliableBatchRemote()

	--[[
		Handle incoming batch packets from the server
		
		Manually decodes the batch structure since it contains pre-encoded
		arguments that need to be decoded with each remote's specific config.
	]]
	--
	local function handleBatch(data: buffer, unreliable: boolean)
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

			local decodedArgs = remote:_decode(encodedArgs)
			if not decodedArgs or type(decodedArgs) ~= "table" then
				continue
			end

			local callbacks = _listeners[remoteName]
			if callbacks then
				for _, callback in callbacks do
					task.spawn(callback, table.unpack(decodedArgs))
				end
			end
		end
	end

	if unreliableBatch then
		_trove:Connect(unreliableBatch.OnClientEvent, function(data)
			handleBatch(data, true)
		end)
	end

	if reliableBatch then
		_trove:Connect(reliableBatch.OnClientEvent, function(data)
			handleBatch(data, false)
		end)
	end

	if _globalConfig and _globalConfig.syncDeltaCache then
		local deltaSyncRemote = getDeltaSyncRemote()
		if deltaSyncRemote then
			_trove:Connect(deltaSyncRemote.OnClientEvent, function(data: buffer)
				local decoded = Buffer.Decode(data)
				if type(decoded) ~= "table" then
					return
				end

				local remoteName = decoded.remoteName
				local status = decoded.status

				if status == "resync" then
					local remote = _remotes[remoteName]
					if remote then
						remote:ClearPlayer(game.Players.LocalPlayer)
					end
				end
			end)
		end
	end
end

if IsClient then
	task.defer(setupBatchFlushing)
end

--[[
	Wait for Wisp to be fully initialized and ready for use
	
	This should be called before using any other Wisp functions to ensure
	the server has created all necessary remotes and the client can connect.
]]
--
function Client.AwaitReady(timeout: number?): boolean
	if timeout then
		assert(validateNumber(timeout), "[Wisp.AwaitReady] timeout must be a number")
	end

	local maxWait = timeout or 30
	local startTime = os.clock()

	local container = waitForContainer()
	if not container then
		warn("[Wisp] Failed to find WispRemotes container within timeout")
		return false
	end

	if _batchEnabled then
		while os.clock() - startTime < maxWait do
			local unreliable = getUnreliableBatchRemote()
			local reliable = getReliableBatchRemote()

			if unreliable and reliable then
				return true
			end

			task.wait(0.1)
		end

		warn("[Wisp] Batch remotes not found within timeout")
		return false
	end

	return true
end

--[[
	Send data to the server via a named remote
	
	Depending on the remote's configuration, data may be batched with other
	sends for efficiency, or sent immediately. Delta encoding, compression,
	and schemas are automatically applied based on the remote's config.
]]
--
function Client.Fire(remoteName: string, ...: any)
	assert(validateString(remoteName), "[Wisp.Fire] remoteName must be a string")

	local config = getConfigForRemote(remoteName)
	local batchMode = if config then config.batching or "unreliable" else "unreliable"

	if not _batchEnabled or batchMode == "never" then
		local remote = getOrCreateRemote(remoteName)
		if not remote then
			return
		end

		if not remote:_checkRateLimit(game.Players.LocalPlayer) then
			warn(`[Wisp] Client rate limit exceeded for "{remoteName}"`)
			return
		end

		local encoded = remote:_encode({ ... })
		if encoded then
			remote._remote:FireServer(encoded)
		end
		return
	end

	-- Get wrapper with correct config and pre-encode args
	local remote = getOrCreateRemote(remoteName)
	if not remote then
		return
	end

	if not remote:_checkRateLimit(game.Players.LocalPlayer) then
		warn(`[Wisp] Client rate limit exceeded for "{remoteName}"`)
		return
	end

	local encodedArgs = remote:_encode({ ... })
	if not encodedArgs then
		return
	end

	local isUnreliable = batchMode == "unreliable"
	local queue = if isUnreliable then _unreliableBatchQueue else _reliableBatchQueue

	table.insert(queue, {
		remoteName = remoteName,
		encodedArgs = encodedArgs,
		priority = if config then config.batchPriority or 999 else 999,
		reliable = not isUnreliable,
	})

	local maxSize = if config then config.maxBatchSize or 50 else 50
	if #queue >= maxSize then
		flushBatch(isUnreliable)
	end
end

--[[
	Register a callback to be invoked when the server sends data via a remote
	
	Multiple callbacks can be registered for the same remote. Each callback
	is invoked with the decoded arguments from the server.
]]
--
function Client.Connect(remoteName: string, callback: (...any) -> ())
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
	
	Useful for waiting for a specific event without manual cleanup.
]]
--
function Client.Once(remoteName: string, callback: (...any) -> ())
	assert(validateString(remoteName), "[Wisp.Once] remoteName must be a string")
	assert(validateCallback(callback), "[Wisp.Once] callback must be a function")

	local disconnect: (() -> ())?
	disconnect = Client.Connect(remoteName, function(...: any)
		if disconnect then
			disconnect()
		end
		callback(...)
	end)
	return disconnect
end

--[[
	Wait for a remote event and return its arguments
	
	This yields the current thread until the event is received or the timeout
	expires. Useful for one-off event handling without setting up callbacks.
]]
--
function Client.Wait(remoteName: string, timeout: number?): ...any
	assert(validateString(remoteName), "[Wisp.Wait] remoteName must be a string")
	if timeout then
		assert(validateNumber(timeout), "[Wisp.Wait] timeout must be a number")
	end

	local thread = coroutine.running()
	local completed = false
	local results: { any } = {}

	local disconnect: (() -> ())?
	disconnect = Client.Connect(remoteName, function(...: any)
		if completed then
			return
		end
		completed = true
		results = { ... }
		if disconnect then
			disconnect()
		end
		task.spawn(thread)
	end)

	if timeout then
		task.delay(timeout, function()
			if not completed then
				completed = true
				if disconnect then
					disconnect()
				end
				task.spawn(thread)
			end
		end)
	end

	coroutine.yield()
	return table.unpack(results)
end

--[[
	Register a callback for RemoteFunction invocations from the server
	
	When the server calls Invoke() on this remote, your callback will be
	called and its return values sent back to the server.
]]
--
function Client.OnInvoke(remoteName: string, callback: ClientInvokeCallback)
	assert(validateString(remoteName), "[Wisp.OnInvoke] remoteName must be a string")
	assert(validateCallback(callback), "[Wisp.OnInvoke] callback must be a function")

	getOrCreateRemoteFunction(remoteName)
	_invokeCallbacks[remoteName] = callback
end

--[[
	Invoke a RemoteFunction on the server and wait for the response
	
	This sends data to the server and yields until a response is received.
	The response is decoded and returned as multiple values.
]]
--
function Client.Invoke(remoteName: string, ...: any): ...any
	assert(validateString(remoteName), "[Wisp.Invoke] remoteName must be a string")

	local remote, wrapper = getOrCreateRemoteFunction(remoteName)
	if not remote or not wrapper then
		return nil
	end

	local encoded = wrapper:_encode({ ... })
	if not encoded then
		return nil
	end

	local result = remote:InvokeServer(encoded)
	if not result then
		return nil
	end

	local decoded = wrapper:_decode(result)
	if decoded and type(decoded) == "table" then
		return table.unpack(decoded)
	end

	return nil
end

--[[
	Register data schemas for automatic validation and migration
	
	Schemas define the expected structure of data for specific remotes.
	Migrations allow upgrading data from older versions to newer ones.
]]
--
function Client.UseSchemas(schemas: { [string]: Types.Schema }, migrations: { [string]: MigrationMap }?)
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
	Configure encoding, compression, and other options for remotes
	
	If remoteName is provided, applies only to that remote.
	Otherwise, applies globally to all remotes as a default.
]]
--
function Client.UseConfig(config: RemoteConfig, remoteName: string?)
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
	Enable compression for remotes to reduce bandwidth usage
	
	Compression modes: auto, lz4, deflate, zstd, none
	Auto mode selects the best algorithm based on data characteristics.
]]
--
function Client.UseCompression(mode: Types.CompressionMode, remoteName: string?)
	assert(validateCompressionMode(mode), "[Wisp.UseCompression] mode must be a valid compression mode")
	if remoteName then
		assert(validateString(remoteName), "[Wisp.UseCompression] remoteName must be a string")
	end

	local config: RemoteConfig = {
		encode = { mode = "compressed", compression = mode },
	}
	Client.UseConfig(config, remoteName)
end

--[[
	Enable delta encoding to send only changed data
	
	Delta encoding dramatically reduces bandwidth for updates to large data
	structures by sending only the differences since the last transmission.
]]
--
function Client.UseDelta(schema: Types.Schema?, remoteName: string?)
	if remoteName then
		assert(validateString(remoteName), "[Wisp.UseDelta] remoteName must be a string")
	end

	local config: RemoteConfig = {
		encode = { mode = "delta", schema = schema },
		syncDeltaCache = true,
	}
	Client.UseConfig(config, remoteName)
end

--[[
	Enable or disable the batching system globally
	
	When disabled, all Fire() calls send immediately instead of being batched.
	This increases network overhead but reduces latency.
]]
--
function Client.UseBatching(enabled: boolean)
	assert(validateBoolean(enabled), "[Wisp.UseBatching] enabled must be a boolean")
	_batchEnabled = enabled
end

--[[
	Configure a remote to use UnreliableRemoteEvent for faster transmission
	
	Unreliable remotes have lower latency but may lose packets. Best for
	high-frequency data like position updates or animation sync.
]]
--
function Client.SetUnreliable(remoteName: string, unreliable: boolean)
	assert(validateString(remoteName), "[Wisp.SetUnreliable] remoteName must be a string")
	assert(validateBoolean(unreliable), "[Wisp.SetUnreliable] unreliable must be a boolean")

	_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
	_remoteConfigs[remoteName].unreliable = unreliable
	_remoteConfigs[remoteName].batching = if unreliable then "unreliable" else "reliable"
end

--[[
	Configure rate limiting to prevent excessive client-side sends
	
	Sets the minimum time interval between Fire() calls for a remote.
	Helps prevent accidental spam from client-side loops or rapid events.
]]
--
function Client.SetRateLimit(limit: number, remoteName: string?)
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
	Set the batching behavior for a specific remote
	
	Options: "never" (send immediately), "unreliable" (fast batching),
	"reliable" (guaranteed delivery batching)
]]
--
function Client.SetBatchMode(remoteName: string, mode: Types.BatchMode)
	assert(validateString(remoteName), "[Wisp.SetBatchMode] remoteName must be a string")
	assert(validateBatchMode(mode), "[Wisp.SetBatchMode] mode must be 'never', 'unreliable', or 'reliable'")

	_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
	_remoteConfigs[remoteName].batching = mode
end

--[[
	Set the priority for a remote within batches
	
	Lower priority values are sent first within a batch. Useful for ensuring
	important data is processed before less critical updates.
]]
--
function Client.SetBatchPriority(remoteName: string, priority: number)
	assert(validateString(remoteName), "[Wisp.SetBatchPriority] remoteName must be a string")
	assert(validateNumber(priority), "[Wisp.SetBatchPriority] priority must be a number")

	_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
	_remoteConfigs[remoteName].batchPriority = priority
end

--[[
	Configure the maximum batch size before forcing transmission
	
	Larger batches are more efficient but increase latency. Smaller batches
	reduce latency but increase network overhead.
]]
--
function Client.SetMaxBatchSize(size: number)
	assert(validateNumber(size), "[Wisp.SetMaxBatchSize] size must be a number")

	_globalConfig = _globalConfig or {}
	_globalConfig.maxBatchSize = size
end

--[[
	Enable delta cache synchronization for data integrity
	
	When enabled, the client and server exchange cache hashes to detect
	desynchronization and automatically request full data resends when needed.
]]
--
function Client.EnableDeltaSync(remoteName: string?)
	if remoteName then
		assert(validateString(remoteName), "[Wisp.EnableDeltaSync] remoteName must be a string")
	end

	if remoteName then
		_remoteConfigs[remoteName] = _remoteConfigs[remoteName] or {}
		_remoteConfigs[remoteName].syncDeltaCache = true
	else
		_globalConfig = _globalConfig or {}
		_globalConfig.syncDeltaCache = true
		getDeltaSyncRemote()
	end
end

--[[
	Immediately send all queued batch data
	
	Useful when you need to ensure data is transmitted before a critical
	operation, such as a round ending or player leaving.
]]
--
function Client.FlushBatch()
	flushBatch(true)
	flushBatch(false)
end

--[[
	Type creation utilities for schema validation
	
	These provide a convenient API for creating type validators used in schemas.
]]
--
Client.Types = Buffer.Types
Client.CreateType = Buffer.Types

return Client
