# Client

Client-side networking module for sending data to server and receiving events

## `Wisp.AwaitReady`
```lua
Client.AwaitReady(timeout: number?): boolean
```
Wait for Wisp to initialize and server remotes to be available.

### Parameters:
- `timeout` (optional): Max wait time in seconds (default: 30)

### Returns:
- `boolean`: `true` if ready, `false` if timeout

### Example:
::: code-group
```lua [ExampleClient.lua]
local Wisp = require(ReplicatedStorage.Wisp).Client

if not Wisp.AwaitReady(10) then
    warn("Failed to connect to server")
    return
end

print("Wisp ready!")
```
:::

---

## `Wisp.Fire`
```lua
Client.Fire(remoteName: string, ...: any)
```
Send data to server via named remote. Automatically batches by default.

### Parameters:
- `remoteName`: Remote identifier
- `...`: Data to send (supports all Roblox types + tables)

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Send player action
Wisp.Fire("player_action", "jump", 100)

-- Send complex data
Wisp.Fire("player_stats", {
    hp = 80,
    mp = 50,
    position = Vector3.new(10, 5, 0)
})
```
:::

---

## `Wisp.Connect`
```lua
Client.Connect(remoteName: string, callback: (...any) -> ()): () -> ()
```

Register callback for server events. Returns disconnect function.

### Parameters:
- `remoteName`: Remote identifier
- `callback`: Function called when server fires event

### Returns:
- `() -> ()`: Disconnect function

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Listen for server updates
local disconnect = Wisp.Connect("server_update", function(message, data)
    print("Server says:", message, data)
end)

-- Later: stop listening
disconnect()
```
:::

---

## `Wisp.Once`
```lua
Client.Once(remoteName: string, callback: (...any) -> ()): () -> ()
```
Register one-time callback (auto-disconnects after first call).

### Parameters:
- `remoteName`: Remote identifier
- `callback`: Function called when server fires event

### Returns:
- `() -> ()`: Disconnect function

### Example:
::: code-group
```lua [ExampleClient.lua]
Wisp.Once("round_start", function(roundNumber)
    print("Round", roundNumber, "started!")
    -- Automatically disconnects after this
end)
```
:::

---

## `Wisp.Wait`
```lua
Client.Wait(remoteName: string, timeout: number?): ...any
```

Yield until event is received or timeout expires.

### Parameters:
- `remoteName`: Remote identifier
- `timeout` (optional): Max wait time in seconds

### Returns:
- `...any`: Event arguments (unpacked)

### Example:
::: code-group
```lua [ExampleClient.lua]
local winner, score = Wisp.Wait("round_end", 60)
if winner then
    print(winner, "won with", score, "points!")
else
    print("Round end timeout")
end
```
:::

---

## `Wisp.Invoke`
```lua
Client.Invoke(remoteName: string, ...: any): ...any
```

Call server function and wait for response.

### Parameters:
- `remoteName`: Remote identifier
- `...`: Arguments to send to server

### Returns:
- `...any`: Response values from server

### Example:
::: code-group
```lua [ExampleClient.lua]
local success, message = Wisp.Invoke("purchase_item", "Sword", 100)
if success then
    print("Purchased:", message)
else
    print("Failed:", message)
end
```
:::

---

## `Wisp.OnInvoke`
```lua
Client.OnInvoke(remoteName: string, callback: (...any) -> ...any)
```

Register handler for server invoke requests.

### Parameters:
- `remoteName`: Remote identifier
- `callback`: Function that returns response values

### Example:
::: code-group
```lua [ExampleClient.lua]
Wisp.OnInvoke("get_client_data", function()
    return {
        renderDistance = workspace.CurrentCamera.ViewportSize.Magnitude,
        fps = 60
    }
end)
```
:::

---

## `Wisp.UseConfig`
```lua
Client.UseConfig(config: RemoteConfig, remoteName: string?)
```

Set encoding/batching configuration globally or per-remote.

### Parameters:
- `config`: Configuration table (see [RemoteConfig](#remoteconfig))
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Global config
Wisp.UseConfig({
    encode = {mode = "compressed", compression = "auto"},
    batching = "unreliable",
    maxBatchSize = 50
})

-- Per-remote config
Wisp.UseConfig({
    encode = {mode = "delta", schema = playerStatsSchema},
    rateLimit = 0.1
}, "player_stats")
```
:::

---

## `Wisp.UseSchemas`
```lua
Client.UseSchemas(schemas: {[string]: Schema}, migrations: {[string]: MigrationMap}?)
```

Register schemas for automatic validation and migration.

### Parameters:
- `schemas`: Table mapping remote names to schema definitions
- `migrations` (optional): Table mapping remote names to migration maps

### Example:
::: code-group
```lua [ExampleClient.lua]
local schemas = {
    player_data = {
        version = 2,
        fields = {
            {name = "id", type = Types.number()},
            {name = "username", type = Types.string(20)},
            {name = "level", type = Types.integer()}
        }
    }
}

local migrations = {
    player_data = {
        [1] = function(data)
            data.level = data.level or 1
            return data
        end
    }
}

Wisp.UseSchemas(schemas, migrations)
```
:::

---

## `Wisp.UseCompression`
```lua
Client.UseCompression(mode: CompressionMode, remoteName: string?)
```

Enable compression for bandwidth savings.

### Parameters:
- `mode`: `"auto"` | `"lz4"` | `"deflate"` | `"zstd"` | `"none"`
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Global compression
Wisp.UseCompression("auto")

-- Compress only large data remotes
Wisp.UseCompression("deflate", "map_data")
```
:::

---

## `Wisp.UseDelta`
```lua
Client.UseDelta(schema: Schema?, remoteName: string?)
```

Enable delta encoding (send only changed fields).

### Parameters:
- `schema` (optional): Schema for delta validation
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleClient.lua]
local statsSchema = {
    fields = {
        {name = "hp", type = Types.number()},
        {name = "mp", type = Types.number()},
        {name = "xp", type = Types.number()}
    }
}

Wisp.UseDelta(statsSchema, "player_stats")

-- First send: all fields
Wisp.Fire("player_stats", {hp = 100, mp = 50, xp = 0})

-- Next sends: only changed fields
Wisp.Fire("player_stats", {hp = 80, mp = 50, xp = 0})  -- Only hp sent
```
:::

---

## `Wisp.UseBatching`
```lua
Client.UseBatching(enabled: boolean)
```

Enable/disable automatic batching globally.

### Parameters:
- `enabled`: `true` to enable batching, `false` to disable

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Disable batching for low-latency mode
Wisp.UseBatching(false)
```
:::

---

## `Wisp.SetUnreliable`
```lua
Client.SetUnreliable(remoteName: string, unreliable: boolean)
```

Configure remote to use UnreliableRemoteEvent (lower latency, packet loss possible).

### Parameters:
- `remoteName`: Remote identifier
- `unreliable`: `true` for UnreliableRemoteEvent, `false` for RemoteEvent

### Example:
::: code-group
```lua [ExampleClient.lua]
-- High-frequency position updates
Wisp.SetUnreliable("player_position", true)
```
:::

---

## `Wisp.SetBatchMode`
```lua
Client.SetBatchMode(remoteName: string, mode: BatchMode)
```

Set batching behavior for remote.

### Parameters:
- `remoteName`: Remote identifier
- `mode`: `"never"` | `"unreliable"` | `"reliable"`

### Example:
::: code-group
```lua [ExampleClient.lua]
Wisp.SetBatchMode("critical_event", "never")  -- Send immediately
Wisp.SetBatchMode("player_position", "unreliable")  -- Batch, fast
Wisp.SetBatchMode("player_stats", "reliable")  -- Batch, guaranteed
```
:::

---

## `Wisp.SetBatchPriority`
```lua
Client.SetBatchPriority(remoteName: string, priority: number)
```

Set send priority within batches (lower = sent first).

### Parameters:
- `remoteName`: Remote identifier
- `priority`: Priority number (0-999, lower = higher priority)

### Example:
::: code-group
```lua [ExampleClient.lua]
Wisp.SetBatchPriority("player_health", 1)  -- High priority
Wisp.SetBatchPriority("player_cosmetic", 100)  -- Low priority
```
:::

---

## `Wisp.SetMaxBatchSize`
```lua
Client.SetMaxBatchSize(size: number)
```

Set max packets per batch before force flush.

### Parameters:
- `size`: Maximum number of packets in a batch

### Example:
::: code-group
```lua [ExampleClient.lua]
Wisp.SetMaxBatchSize(100)  -- Larger batches = more efficient, higher latency
```
:::

---

## `Wisp.SetRateLimit`
```lua
Client.SetRateLimit(limit: number, remoteName: string?)
```

Set minimum interval between sends (seconds).

### Parameters:
- `limit`: Minimum seconds between sends
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Global: max 10 sends/sec
Wisp.SetRateLimit(0.1)

-- Per-remote: max 20 position updates/sec
Wisp.SetRateLimit(0.05, "player_position")
```
:::

---

## `Wisp.EnableDeltaSync`
```lua
Client.EnableDeltaSync(remoteName: string?)
```

Enable delta cache hash verification.

### Parameters:
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleClient.lua]
Wisp.EnableDeltaSync("player_stats")
```
:::

---

## `Wisp.FlushBatch`
```lua
Client.FlushBatch()
```

Immediately send all queued batches.

### Example:
::: code-group
```lua [ExampleClient.lua]
-- Before critical operation
Wisp.Fire("action1", data1)
Wisp.Fire("action2", data2)
Wisp.FlushBatch()  -- Send now, don't wait for next frame
```
:::