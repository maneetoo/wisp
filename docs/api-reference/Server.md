# Server

Server-side networking module for receiving client data and broadcasting events

## `Wisp.Fire`
```lua
Server.Fire(remoteName: string, player: Player, ...: any)
```
Send data to specific player.

### Parameters:
- `remoteName`: Remote identifier
- `player`: Target player
- `...`: Data to send (supports all Roblox types + tables)

### Example:
::: code-group
```lua [ExampleServer.lua]
local Wisp = require(ReplicatedStorage.Wisp).Server

Wisp.Fire("notification", player, "Welcome!", Color3.new(0, 1, 0))
```
:::

---

## `Wisp.FireAll`
```lua
Server.FireAll(remoteName: string, ...: any)
```
Broadcast data to all connected players.

### Parameters:
- `remoteName`: Remote identifier
- `...`: Data to send

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.FireAll("server_announcement", "Server restarting in 5 minutes")
```
:::

---

## `Wisp.FireList`
```lua
Server.FireList(remoteName: string, players: {Player}, ...: any)
```
Send data to list of players.

### Parameters:
- `remoteName`: Remote identifier
- `players`: Array of target players
- `...`: Data to send

### Example:
::: code-group
```lua [ExampleServer.lua]
local team = {player1, player2, player3}
Wisp.FireList("team_message", team, "Your team scored!")
```
:::

---

## `Wisp.FireExcept`
```lua
Server.FireExcept(remoteName: string, except: Player | {Player}, ...: any)
```
Broadcast to all except specified player(s).

### Parameters:
- `remoteName`: Remote identifier
- `except`: Player or array of players to exclude
- `...`: Data to send

### Example:
::: code-group
```lua [ExampleServer.lua]
-- Notify everyone except the killer
Wisp.FireExcept("player_death", killer, victim.Name, "was eliminated")
```
:::

---

## `Wisp.Connect`
```lua
Server.Connect(remoteName: string, callback: (player: Player, ...any) -> ()): () -> ()
```
Register callback for client events.

### Parameters:
- `remoteName`: Remote identifier
- `callback`: Function called when client fires event (receives player as first argument)

### Returns:
- `() -> ()`: Disconnect function

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.Connect("player_action", function(player, action, value)
    if action == "jump" then
        print(player.Name, "jumped with power", value)
    end
end)
```
:::

---

## `Wisp.Once`
```lua
Server.Once(remoteName: string, callback: (player: Player, ...any) -> ())
```
Register one-time callback.

### Parameters:
- `remoteName`: Remote identifier
- `callback`: Function called once when client fires event

### Returns:
- `() -> ()`: Disconnect function

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.Once("first_client_ready", function(player)
    print("First player ready:", player.Name)
end)
```
:::

---

## `Wisp.Invoke`
```lua
Server.Invoke(remoteName: string, player: Player, ...: any): ...any
```
Call client function and wait for response.

### Parameters:
- `remoteName`: Remote identifier
- `player`: Target player
- `...`: Arguments to send to client

### Returns:
- `...any`: Response values from client

### Example:
::: code-group
```lua [ExampleServer.lua]
local clientFPS = Wisp.Invoke("get_fps", player)
if clientFPS and clientFPS < 30 then
    -- Reduce graphics for this player
end
```
:::

---

## `Wisp.OnInvoke`
```lua
Server.OnInvoke(remoteName: string, callback: (player: Player, ...any) -> ...any)
```
Register handler for client invoke requests.

### Parameters:
- `remoteName`: Remote identifier
- `callback`: Function that returns response values (receives player as first argument)

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.OnInvoke("purchase_item", function(player, itemName, cost)
    local profile = getProfile(player)
    if profile.coins >= cost then
        profile.coins -= cost
        profile.inventory[itemName] = true
        return true, "Purchase successful"
    else
        return false, "Insufficient coins"
    end
end)
```
:::

---

## `Wisp.UseConfig`
```lua
Server.UseConfig(config: RemoteConfig, remoteName: string?)
```
Set encoding/batching configuration globally or per-remote.

### Parameters:
- `config`: Configuration table (see [RemoteConfig](#remoteconfig))
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleServer.lua]
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
Server.UseSchemas(schemas: {[string]: Schema}, migrations: {[string]: MigrationMap}?)
```
Register schemas for automatic validation and migration.

### Parameters:
- `schemas`: Table mapping remote names to schema definitions
- `migrations` (optional): Table mapping remote names to migration maps

### Example:
::: code-group
```lua [ExampleServer.lua]
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
Server.UseCompression(mode: CompressionMode, remoteName: string?)
```
Enable compression for bandwidth savings.

### Parameters:
- `mode`: `"auto"` | `"lz4"` | `"deflate"` | `"zstd"` | `"none"`
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleServer.lua]
-- Global compression
Wisp.UseCompression("auto")

-- Compress only large data remotes
Wisp.UseCompression("deflate", "map_data")

-- Server-only: use Zstd for best compression
Wisp.UseCompression("zstd", "world_state")
```
:::

---

## `Wisp.UseDelta`
```lua
Server.UseDelta(schema: Schema?, remoteName: string?)
```
Enable delta encoding (send only changed fields).

### Parameters:
- `schema` (optional): Schema for delta validation
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleServer.lua]
local statsSchema = {
    fields = {
        {name = "hp", type = Types.number()},
        {name = "mp", type = Types.number()},
        {name = "xp", type = Types.number()}
    }
}

Wisp.UseDelta(statsSchema, "player_stats")

-- First send: all fields
Wisp.Fire("player_stats", player, {hp = 100, mp = 50, xp = 0})

-- Next sends: only changed fields
Wisp.Fire("player_stats", player, {hp = 80, mp = 50, xp = 0})  -- Only hp sent
```
:::

---

## `Wisp.UseBatching`
```lua
Server.UseBatching(enabled: boolean)
```
Enable/disable automatic batching globally.

### Parameters:
- `enabled`: `true` to enable batching, `false` to disable

### Example:
::: code-group
```lua [ExampleServer.lua]
-- Disable batching for low-latency mode
Wisp.UseBatching(false)
```
:::

---

## `Wisp.SetUnreliable`
```lua
Server.SetUnreliable(remoteName: string, unreliable: boolean)
```
Configure remote to use UnreliableRemoteEvent (lower latency, packet loss possible).

### Parameters:
- `remoteName`: Remote identifier
- `unreliable`: `true` for UnreliableRemoteEvent, `false` for RemoteEvent

### Example:
::: code-group
```lua [ExampleServer.lua]
-- High-frequency position updates
Wisp.SetUnreliable("player_position", true)
```
:::

---

## `Wisp.SetBatchMode`
```lua
Server.SetBatchMode(remoteName: string, mode: BatchMode)
```
Set batching behavior for remote.

### Parameters:
- `remoteName`: Remote identifier
- `mode`: `"never"` | `"unreliable"` | `"reliable"`

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.SetBatchMode("critical_event", "never")  -- Send immediately
Wisp.SetBatchMode("player_position", "unreliable")  -- Batch, fast
Wisp.SetBatchMode("player_stats", "reliable")  -- Batch, guaranteed
```
:::

---

## `Wisp.SetBatchPriority`
```lua
Server.SetBatchPriority(remoteName: string, priority: number)
```
Set send priority within batches (lower = sent first).

### Parameters:
- `remoteName`: Remote identifier
- `priority`: Priority number (0-999, lower = higher priority)

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.SetBatchPriority("player_health", 1)  -- High priority
Wisp.SetBatchPriority("player_cosmetic", 100)  -- Low priority
```
:::

---

## `Wisp.SetMaxBatchSize`
```lua
Server.SetMaxBatchSize(size: number)
```
Set max packets per batch before force flush.

### Parameters:
- `size`: Maximum number of packets in a batch

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.SetMaxBatchSize(100)  -- Larger batches = more efficient, higher latency
```
:::

---

## `Wisp.SetRateLimit`
```lua
Server.SetRateLimit(limit: number, remoteName: string?)
```
Set minimum interval between client sends (anti-spam protection).

### Parameters:
- `limit`: Minimum seconds between sends per player
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleServer.lua]
-- Global: max 10 requests/sec per player
Wisp.SetRateLimit(0.1)

-- Critical endpoint: 1 request/sec max
Wisp.SetRateLimit(1.0, "admin_command")

-- High-frequency data: 20 updates/sec max
Wisp.SetRateLimit(0.05, "player_position")
```
:::

---

## `Wisp.EnableDeltaSync`
```lua
Server.EnableDeltaSync(remoteName: string?)
```
Enable delta cache hash verification.

### Parameters:
- `remoteName` (optional): Apply only to this remote

### Example:
::: code-group
```lua [ExampleServer.lua]
Wisp.EnableDeltaSync("player_stats")
```
:::

---

## `Wisp.FlushBatches`
```lua
Server.FlushBatches()
```
Immediately send all queued batches to all players.

### Example:
::: code-group
```lua [ExampleServer.lua]
-- Critical state update
Wisp.FireAll("game_state", newState)
Wisp.FlushBatches()  -- Send immediately
```
:::