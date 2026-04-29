# Basic Usage

For first, visit the [Installation page](/tutorials/) to install the Wisp library in your game/project

## Before Start
For first, require the imported library:
::: code-group
```lua [Example.lua]
local Wisp = require(game.ReplicatedStorage.Wisp) -- or everywhere
```
:::

Due to problems with LSP Roblox ([Luau](https://luau.org/)), you will have to get the execution side (`Client`, `Server`) yourself. Here's how it works:
::: code-group
```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
-- Now you can freely use Wisp
```

```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server
-- Now you can freely use Wisp
```
:::

## AwaitReady
If there are a lot of [RemoteEvents](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)/[RemoteFunctions](https://create.roblox.com/docs/reference/engine/classes/RemoteFunction) or if the hardware is poor, the client may not be able to initialize correctly. Therefore, it is recommended to use the `Wisp.AwaitReady()` method before using it in [LocalScript](https://create.roblox.com/docs/reference/engine/classes/LocalScript), as follows:
::: code-group
```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()
```
```lua [ClientWithTimeout.lua]
-- You can also pass the AwaitReady timeout 
-- and check whether the Wisp is initialized or not
local Wisp = require(game.ReplicatedStorage.Wisp).Client
local IsWispReady: boolean = Wisp.AwaitReady(10) -- after the time has elapsed, it will display warn in the Output
if not IsWispReady then
    error("Can't start, Wisp is not ready") -- optional
end
```
:::


## Fire & Connect
`Wisp.Fire` and `Wisp.Connect` are similar to the usual [behavior of RemoteEvents](https://create.roblox.com/docs/scripting/events/remote). Let's take a closer look at `Wisp.Fire` and `Wisp.Connect`:
::: code-group
```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

Wisp.Fire("player_joined", "I'm new here:)") -- will send RemoteEvent with name "player_joined"
-- there can be as many arguments as you like, and almost any type
```

```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

Wisp.Connect("player_joined", function(player: Player, message: string) -- the player is always passed as the first argument
    print(`{player.Name} Joined. Welcome! Player Message: {message}`)
end)

-- or:
Wisp.Once("player_joined", function(player: Player, message: string) -- listen once, auto-disconnects
    print(`{player.Name} Joined. Welcome! Player Message: {message}`)
end)
```

```bash [Output]
- PlayerName Joined. Welcome! Player Message: I'm new here:)
```
:::

The Server-Side also has additional sending functions:
::: code-group
```lua [ServerAdditionals.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

-- Send to all players
Wisp.FireAll(remoteName: string, ...: any)

-- Send to a list of players
Wisp.FireList(remoteName: string, players: {Player}, ...: any)

-- Send to everyone except
Wisp.FireExcept(remoteName: string, except: Player | {Player}, ...: any)
```
:::

The client also has an additional method, namely `Wisp.Wait()`:
::: code-group
```lua [ClientWait.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

local message: string? = Wisp.Wait("private_message") -- Infinity waiting
print("Got message:", message)

local message: boolean? = Wisp.Wait("match_start", 30) -- 30s waiting
if message then
    print("Match starting!")
else
    print("Timeout - no match found")
end
```
:::

## Invoke & OnInvoke
`Wisp.Invoke` and `Wisp.OnInvoke` are similar to the normal behavior of [RemoteFunction.Invoke](https://create.roblox.com/docs/reference/engine/classes/RemoteFunction#methods) and [RemoteFunction.OnInvoke](https://create.roblox.com/docs/reference/engine/classes/RemoteFunction#callbacks), respectively:
::: code-group
```lua [Client.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Client
Wisp.AwaitReady()

local ServerTime: number = Wisp.Invoke("get_time")
print("Server Time:", ServerTime)
```

```lua [Server.lua]
local Wisp = require(game.ReplicatedStorage.Wisp).Server

Wisp.OnInvoke("get_time", function(_player: Player)
    return os.time()
end)
```

```bash [Output]
- Server Time: 1777266546
```
:::

`Wisp.Invoke` and `Wisp.OnInvoke` also accept an infinite number of arguments of almost all types, as do `Wisp.Fire` and `Wisp.Connect`.