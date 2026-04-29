# Encoding Modes

Wisp supports multiple encoding strategies. Set them globally or per-remote:

## Basic Encoding

No extra processing. Data is serialized and sent as-is:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

-- Basic is the default, you don't need to set it explicitly
Wisp.Connect("player_move", function(player, data)
    print(data.position)
    print(data.health)
end)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

Wisp.Fire("player_move", {
    position = Vector3.new(10, 5, 2),
    health = 100
})
```

```bash [Output]
- 10, 5, 2
- 100
```
:::
Why is it `10, 5, 2` instead of [Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)? This happens because Output converts `Vector3.new(10, 5, 2)` to a `string`, so it outputs `10, 5, 2`

## Safe Encoding

Checks for circular references before encoding. Useful when sending complex nested data:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server
Wisp.UseConfig({encode = {mode = "safe"}}, "inventory")

Wisp.Connect("inventory", function(player, data)
	-- data is guaranteed to have no circular references
	print("Items count:", #data.items)
end)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

Wisp.UseConfig({encode = {mode = "safe"}}, "inventory")
Wisp.SetBatchMode("inventory", "never") -- Required for custom config for exactly remote

-- This will fail with a clear error instead of silently breaking
local self = {
	items = {
		Coins = 100,
		Diamonds = 0,
	}
}
self.parent = self  -- circular reference!

Wisp.Fire("inventory", self)
```

```bash [Output]
- [Wisp] Encode failed: [Buffer.EncodeSafe] cyclic reference at "root.1.parent"
```
:::

## Compressed Encoding

Automatically compresses data when it's large enough to benefit:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

-- Enable compression for specific data types
Wisp.UseCompression("lz4", "large_map_data") -- maps load fast
Wisp.UseCompression("deflate", "chat_history") -- text compresses well
Wisp.UseCompression("zstd", "world_state") -- best ratio for large data

-- Auto mode: Wisp picks the right algorithm
Wisp.UseCompression("auto")

Wisp.Connect("large_map_data", function(player, data)
    -- Data was compressed during transmission, decompressed automatically
    spawnMap(data.terrain, data.buildings)
end)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

-- Client also needs to enable compression
Wisp.UseCompression("lz4", "large_map_data")
Wisp.UseCompression("deflate", "chat_history")
Wisp.UseCompression("zstd", "world_state")
Wisp.UseCompression("auto")
```
:::

## Delta Encoding

Sends only what changed, not the entire state. Dramatically reduces bandwidth for frequently updated data:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

Wisp.UseDelta(nil, "player_stats")

Wisp.Connect("player_stats", function(player, stats)
    -- First call: receives all fields {hp=100, mp=50, xp=10}
    -- Later calls: receives only changed fields {hp=95},
	-- but you're already getting merged data
    print("Received stats update:", stats)
end)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

Wisp.UseDelta(nil, "player_stats")

-- First send: full data
Wisp.Fire("player_stats", {hp = 100, mp = 50, xp = 10})

-- Later sends: only what changed
Wisp.Fire("player_stats", {hp = 95, mp = 50, xp = 10})  -- only hp sent
Wisp.Fire("player_stats", {hp = 95, mp = 45, xp = 15})  -- mp and xp sent
```

```bash [Output]
- Received stats update:  ▼  {
                    ["hp"] = 100,
                    ["mp"] = 50,
                    ["xp"] = 10
                 }
- Received stats update:  ▼  {
                    ["hp"] = 95,
                    ["mp"] = 50,
                    ["xp"] = 10
                 }
- Received stats update:  ▼  {
                    ["hp"] = 95,
                    ["mp"] = 45,
                    ["xp"] = 15
                 }
```
:::

With a schema, delta encoding is even smarter — it uses a bitmask to track which fields changed:

::: code-group
```lua [Schemas.lua]
local Wisp = require(game.ReplicatedStorage.Wisp)
local Types = Wisp.Types

return {
	player_stats = {
		version = 1, -- optional, but recommended
		fields = {
			{name = "hp", type = Types.number()},
			{name = "mp", type = Types.number()},
			{name = "xp", type = Types.number()}
		}
	}
}
```
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server
local WispSchemas = require(game.ReplicatedStorage.WispSchemas)

Wisp.UseDelta(WispSchemas.player_stats, "player_stats")

Wisp.Connect("player_stats", function(player, stats)
	print(`Stats changed for {player.Name}:`, stats)
end)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
local WispSchemas = require(game.ReplicatedStorage.WispSchemas)
Wisp.AwaitReady()

Wisp.UseDelta(WispSchemas.player_stats, "player_stats")

Wisp.Fire("player_stats", {hp = 100, mp = 50, xp = 10})  -- first: all fields
Wisp.Fire("player_stats", {hp = 80, mp = 50, xp = 10}) -- delta: only hp
Wisp.Fire("player_stats", {hp = 80, mp = 30, xp = 20}) -- delta: mp and xp
```

```bash [Output]
- Stats changed for YourUsername:  ▼  {
                    ["hp"] = 100,
                    ["mp"] = 50,
                    ["xp"] = 10
                 }
- Stats changed for YourUsername:  ▼  {
                    ["hp"] = 80,
                    ["mp"] = 50,
                    ["xp"] = 10
                 }
- Stats changed for YourUsername:  ▼  {
                    ["hp"] = 80,
                    ["mp"] = 30,
                    ["xp"] = 20
                 }
```
:::

## Compression Modes

Three algorithms for different use cases:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

-- LZ4HC: blazing fast, great for Vector3s, numbers, positions
Wisp.UseCompression("lz4", "player_position")

-- Deflate: better for text, chat logs, JSON-like data
Wisp.UseCompression("deflate", "chat_history")

-- Zstd: maximum compression, requires server EncodingService
Wisp.UseCompression("zstd", "map_data")

-- Auto: Wisp checks the data type and picks the best algorithm
Wisp.UseCompression("auto", "misc_events")

-- None: disable compression entirely
Wisp.UseCompression("none")
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

-- Client also needs to enable compression
Wisp.UseCompression("lz4", "player_position")
Wisp.UseCompression("deflate", "chat_history")
Wisp.UseCompression("zstd", "map_data")
Wisp.UseCompression("auto", "misc_events")
Wisp.UseCompression("none")
```
:::

## Rate Limiting

Prevent spam without writing your own cooldown system:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

-- Shooting: max once per 100ms (10 shots per second)
Wisp.SetRateLimit(0.1, "shoot")
Wisp.SetBatchMode("shoot", "never") -- To be sent immediately, not in the next frame

-- When a player hits the limit, the event is dropped:
Wisp.Connect("shoot", function(player, origin, direction)
	print(`Created bullet for {player.Name}, origin: {origin}, direction: {direction}`)
end)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

-- Shooting: max once per 100ms (10 shots per second)
Wisp.SetRateLimit(0.1, "shoot") 
Wisp.SetBatchMode("shoot", "never") -- To be sent immediately, not in the next frame

local mouse = game.Players.LocalPlayer:GetMouse()
local camera = workspace.CurrentCamera

-- Simulating a mouse click
for i = 1, 10 do
	Wisp.Fire("shoot", mouse.Hit.Position, camera.CFrame.LookVector)
	task.wait(0.05)
end
```

```bash [Output]
- Created bullet for YourUsername, origin: 48.027610778808594, 2.045400381088257, 32.26676940917969, direction: -0, -0.258819043636322, -0.9659258127212524
- [Wisp] Client rate limit exceeded for "shoot"
- Created bullet for YourUsername, origin: 48.027610778808594, 2.0454013347625732, 32.26676559448242, direction: -0, -0.2588190734386444, -0.965925931930542
- [Wisp] Client rate limit exceeded for "shoot"
- Created bullet for YourUsername, origin: 48.027610778808594, 2.045400381088257, 32.26676940917969, direction: -0, -0.258819043636322, -0.9659258127212524
- [Wisp] Client rate limit exceeded for "shoot"
- Created bullet for YourUsername, origin: 48.027610778808594, 2.0454013347625732, 32.26676559448242, direction: -0, -0.2588190734386444, -0.965925931930542
- [Wisp] Client rate limit exceeded for "shoot"
- Created bullet for YourUsername, origin: 48.027610778808594, 2.045400381088257, 32.26676940917969, direction: -0, -0.258819043636322, -0.9659258127212524
- [Wisp] Client rate limit exceeded for "shoot"
```
:::

## Delivery Modes

Choose how events travel — fast and lossy, or guaranteed:

::: code-group
```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

-- Position updates: fast, loss is acceptable
Wisp.SetUnreliable("player_move", true)
Wisp.SetBatchMode("player_move", "unreliable")
Wisp.SetBatchPriority("player_move", 100)

-- Purchases: must never be lost
Wisp.SetUnreliable("buy_item", false)
Wisp.SetBatchMode("buy_item", "reliable")

-- Important instant messages: no batching
Wisp.SetBatchMode("kick_player", "never")

-- Chat: batched reliable, high priority
Wisp.SetUnreliable("chat", false)
Wisp.SetBatchMode("chat", "reliable")
Wisp.SetBatchPriority("chat", 10)

-- Analytics: batched unreliable, low priority
Wisp.SetUnreliable("analytics", true)
Wisp.SetBatchMode("analytics", "unreliable")
Wisp.SetBatchPriority("analytics", 999)
```

```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

-- Client also needs to enable modes
Wisp.SetUnreliable("player_move", true)
Wisp.SetBatchMode("player_move", "unreliable")
Wisp.SetBatchPriority("player_move", 100)
Wisp.SetUnreliable("buy_item", false)
Wisp.SetBatchMode("buy_item", "reliable")
Wisp.SetBatchMode("kick_player", "never")
Wisp.SetUnreliable("chat", false)
Wisp.SetBatchMode("chat", "reliable")
Wisp.SetBatchPriority("chat", 10)
Wisp.SetUnreliable("analytics", true)
Wisp.SetBatchMode("analytics", "unreliable")
Wisp.SetBatchPriority("analytics", 999)
```
:::

Force flush when you need immediate delivery:

::: code-group
```lua [Server.lua]
-- End of match: send everything now
Wisp.Fire("match_result", player, "victory")
Wisp.Fire("rewards", player, {coins = 500, items = {"sword"}})
Wisp.FlushBatches()  -- all queued events sent immediately (not in the next frame)
```
:::