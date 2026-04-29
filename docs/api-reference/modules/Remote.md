# Remote

Internal wrapper class for RemoteEvent/UnreliableRemoteEvent/RemoteFunction with encoding, compression, delta processing, and rate limiting

::: warning Internal Module
This module is used internally by Client and Server APIs. You typically don't need to use it directly.
:::

## Constructor

### `Remote.new`
```lua
Remote.new(
    remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction,
    config: RemoteConfig?,
    isServer: boolean
): Remote
```
Create a new Remote wrapper around a Roblox remote object.

### Parameters:
- `remote`: Roblox remote instance to wrap
- `config` (optional): Remote configuration (encoding, batching, rate limiting)
- `isServer`: `true` if running on server, `false` for client

### Returns:
- `Remote`: Remote wrapper instance

### Example:
::: code-group
```lua [ExampleRemote.lua]
local Remote = require(ReplicatedStorage.Wisp.modules.Remote)

-- Create wrapper for server
local remoteEvent = Instance.new("RemoteEvent")
remoteEvent.Name = "PlayerAction"
remoteEvent.Parent = ReplicatedStorage

local wrapper = Remote.new(remoteEvent, {
    encode = {mode = "schema", schema = mySchema},
    rateLimit = 0.1,
    batching = "unreliable"
}, true)  -- isServer = true
```
:::

---

## Batch Processing

### `Remote:EncodeBatch`
```lua
Remote:EncodeBatch(packets: {BatchPacket}): buffer?
```
Encode multiple packets into a single batch buffer with metadata (sequence numbers, priority).

### Parameters:
- `packets`: Array of batch packets with pre-encoded arguments

### Returns:
- `buffer?`: Encoded batch buffer, or `nil` on failure

### Example:
::: code-group
```lua [ExampleRemote.lua]
local packets = {
    {
        remoteName = "player_move",
        encodedArgs = encodedMoveData,
        priority = 1,
        reliable = false
    },
    {
        remoteName = "player_action",
        encodedArgs = encodedActionData,
        priority = 5,
        reliable = true
    }
}

local batchBuffer = wrapper:EncodeBatch(packets)
if batchBuffer then
    remoteEvent:FireServer(batchBuffer)
end
```
:::

---

### `Remote:DecodeBatch`
```lua
Remote:DecodeBatch(data: buffer, player: Player?): {BatchPacket}?
```
Decode batch buffer back into individual packets. Returned packets still contain encoded arguments.

### Parameters:
- `data`: Batch buffer to decode
- `player` (optional): Player who sent the batch (server-side)

### Returns:
- `{BatchPacket}?`: Array of batch packets, or `nil` on failure

### Example:
::: code-group
```lua [ExampleRemote.lua]
-- Server-side batch handler
remoteEvent.OnServerEvent:Connect(function(player, batchBuffer)
    local packets = wrapper:DecodeBatch(batchBuffer, player)
    
    if packets then
        for _, packet in packets do
            -- Decode each packet's arguments with its specific config
            local args = decodePacketArgs(packet.encodedArgs)
            handleRemote(packet.remoteName, player, args)
        end
    end
end)
```
:::

---

## Delta Cache Management

### `Remote:GetDeltaCacheHash`
```lua
Remote:GetDeltaCacheHash(player: Player): string?
```
Get the DJB2 hash of the delta cache for a specific player.

### Parameters:
- `player`: Player to get cache hash for

### Returns:
- `string?`: 8-character hex hash, or `nil` if no cache exists

### Example:
::: code-group
```lua [ExampleRemote.lua]
-- Server: send cache hash to client for verification
local hash = wrapper:GetDeltaCacheHash(player)
if hash then
    sendCacheHash:FireClient(player, hash)
end
```
:::

---

### `Remote:GetDeltaCacheVersion`
```lua
Remote:GetDeltaCacheVersion(player: Player): number?
```
Get the version number of the delta cache for a specific player. Increments with each successful delta operation.

### Parameters:
- `player`: Player to get cache version for

### Returns:
- `number?`: Cache version number, or `nil` if no cache exists

### Example:
::: code-group
```lua [ExampleRemote.lua]
local version = wrapper:GetDeltaCacheVersion(player)
print("Player cache version:", version)
```
:::

---

### `Remote:SyncDeltaCache`
```lua
Remote:SyncDeltaCache(player: Player, hash: string, version: number): boolean
```
Verify that client and server delta caches are synchronized. Clears cache if hash mismatch detected.

### Parameters:
- `player`: Player to verify cache for
- `hash`: Client's cache hash
- `version`: Client's cache version

### Returns:
- `boolean`: `true` if synchronized, `false` if mismatch (cache cleared)

### Example:
::: code-group
```lua [ExampleRemote.lua]
-- Server: handle cache sync request from client
syncRemote.OnServerEvent:Connect(function(player, clientHash, clientVersion)
    local isSync = wrapper:SyncDeltaCache(player, clientHash, clientVersion)
    
    if not isSync then
        warn("Cache desync for", player.Name, "- sending full data")
        sendFullData:FireClient(player, fullDataSet)
    else
        print("Cache in sync for", player.Name)
    end
end)
```
:::

---

## Cleanup

### `Remote:ClearPlayer`
```lua
Remote:ClearPlayer(player: Player)
```
Clear all cached data for a specific player (delta cache, rate limits, etc.). Called automatically on PlayerRemoving.

### Parameters:
- `player`: Player to clear data for

### Example:
::: code-group
```lua [ExampleRemote.lua]
-- Manually clear player cache
wrapper:ClearPlayer(player)

-- Or handle custom cleanup
Players.PlayerRemoving:Connect(function(player)
    wrapper:ClearPlayer(player)
    -- Additional cleanup...
end)
```
:::

---

### `Remote:Destroy`
```lua
Remote:Destroy()
```
Clean up all resources and disconnect listeners via Trove.

### Example:
::: code-group
```lua [ExampleRemote.lua]
-- Clean up when no longer needed
wrapper:Destroy()

-- Or let Trove handle it
local trove = Trove.new()
trove:Add(wrapper)
-- wrapper:Destroy() called automatically on trove:Clean()
```
:::

---

## Internal Methods

::: details Private Methods (Not for Direct Use)

These methods are used internally by Client/Server APIs and should not be called directly:

### `Remote:_encode(value: any, player: Player?): buffer?`
Encode data using configured mode (basic/schema/delta/compressed/safe).

### `Remote:_decode(data: buffer, player: Player?): any`
Decode buffer back to original data, handling delta patching and migrations.

### `Remote:_checkRateLimit(player: Player): boolean`
Check if player has exceeded rate limit for this remote.

### `Remote:_migrateSchema(data: any, fromVersion: number, toVersion: number): any?`
Apply schema migrations to upgrade data between versions.

:::

---

## Type Definition

```lua
export type Remote = {
    _trove: any,
    _remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction,
    _config: RemoteConfig,
    _lastSend: {[Player]: number},
    _deltaCache: {[any]: any},
    _deltaCacheHash: {[any]: string},
    _deltaCacheVersion: {[any]: number},
    _isServer: boolean,
    _sequence: number,
    
    -- Public methods
    EncodeBatch: (self: Remote, packets: {BatchPacket}) -> buffer?,
    DecodeBatch: (self: Remote, data: buffer, player: Player?) -> {BatchPacket}?,
    GetDeltaCacheHash: (self: Remote, player: Player) -> string?,
    GetDeltaCacheVersion: (self: Remote, player: Player) -> number?,
    SyncDeltaCache: (self: Remote, player: Player, hash: string, version: number) -> boolean,
    ClearPlayer: (self: Remote, player: Player) -> (),
    Destroy: (self: Remote) -> ()
}
```

---

## Encoding Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `basic` | Standard encoding | General data |
| `schema` | Field names omitted | Structured data with validation |
| `delta` | Only changed fields | Frequent updates |
| `compressed` | Force compression | Large payloads |
| `safe` | Cyclic detection | Untrusted data |