# Introduction

Wisp solves a simple problem: Roblox RemoteEvents send data as-is, which means your Vector3 positions, CFrame rotations, and table-based state all travel across the network in whatever form you write them. Wisp compresses and packs that data into the smallest possible binary buffer before transmission, then unpacks it on the other side.

```lua
-- Without Wisp: data travels as Lua values
remote:FireServer("player_move", 10.5, 20.3, 5.0)  -- three floats, ~24 bytes

-- With Wisp: data is packed into a binary buffer
Wisp.Fire("player_move", {x = 10.5, y = 20.3, z = 5.0})  -- ~13 bytes
```

The framework handles serialization, compression, batching, and delivery strategy so you don't have to build that infrastructure yourself

## Example Code

::: code-group
```lua [Server.lua]
-- Basic Usage

local Wisp = require(game.ReplicatedStorage.Wisp).Server

Wisp.Connect("player_spawn", function(player: Player, message: string)
	print(`Received message from {player.Name}: {message}`)
end)
```

```lua [Client.lua]
-- Basic Usage

local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady() --> Yields until Wisp is ready to be used, optional, but recommended

Wisp.Fire("Hello_from_client", "I'm Here!")
```

```bash [Output]
- Received message from YourUsername: I'm Here!
```
:::

That's it. Wisp creates the RemoteEvent, serializes the string, sends it, deserializes on the other side, and dispatches to your callback. No visible RemoteEvents, no manual type conversion, no boilerplate.
