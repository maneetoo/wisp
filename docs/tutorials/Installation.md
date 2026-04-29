# Installation

## Package Managers
For first, add package to your package manager:
::: code-group
```toml [Wally.toml]
[dependencies]
Wisp = "maneetoo/wisp@0.1.0"
```

```toml [Pesde.toml]
[dependencies]
warp = { name = "maneetoo/wisp", version = "0.1.0" }
```

```bash [Pesde (CLI)]
pesde add maneetoo/wisp
```
:::

Now run this:
::: code-group
```bash [Wally]
wally install
```

```bash [Pesde]
pesde install
```
:::

## Manual
1. Get the `.rbxm` file from the [GitHub](https://github.com/maneetoo/wisp/releases)
2. Import the `.rbxm` file into Roblox Studio manually