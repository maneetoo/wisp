# Wisp

High-performance networking library for Roblox with binary serialization, compression, delta encoding, and batching

::: warning Active Development
Wisp is still under active development. The module may contain errors in data transfer or even complete data loss in super-rare cases. Although it has passed all tests, some edge-cases can break the module.

**If you find a bug or error — [report it](https://github.com/maneetoo/wisp/issues)!**
:::

## Installation

::: code-group
```lua [Example.lua]
-- Place Wisp module in ReplicatedStorage
local Wisp = require(ReplicatedStorage.Wisp)

-- Access Client/Server APIs
local Client = Wisp.Client  -- LocalScript only
local Server = Wisp.Server  -- Script only
```
:::

---

## Quick Start

::: code-group
```lua [Server.lua]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Wisp = require(ReplicatedStorage.Wisp).Server

-- Listen for client events
Wisp.Connect("player_action", function(player, action, value)
    print(player.Name, "performed:", action, value)
end)

-- Send data to all players
Wisp.FireAll("game_started", {
    roundNumber = 1,
    mapName = "Desert"
})
```
```lua [Client.lua]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Wisp = require(ReplicatedStorage.Wisp).Client

-- Wait for server to be ready
Wisp.AwaitReady()

-- Listen for server events
Wisp.Connect("game_started", function(data)
    print("Round", data.roundNumber, "on", data.mapName)
end)

-- Send data to server
Wisp.Fire("player_action", "jump", 100)
```
:::

---

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `Client` | `ClientModule` | Client-side networking API (LocalScript only) |
| `Server` | `ServerModule` | Server-side networking API (Script only) |
| `Types` | `TypeConstructors` | Schema type validators |
| `CreateType` | `TypeConstructors` | Alias for `Types` |

---