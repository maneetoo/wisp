# Pool

Buffer pooling and batch optimization utilities for efficient memory management

## Buffer Pool Management

### `Pool.acquireBuffer`
```lua
Pool.acquireBuffer(size: number): buffer
```
Acquire buffer from pool. Automatically selects appropriate tier (Small/Medium/Large) based on size.

### Parameters:
- `size`: Required buffer size in bytes

### Returns:
- `buffer`: Pooled or newly allocated buffer

### Example:
::: code-group
```lua [ExamplePool.lua]
local Pool = require(ReplicatedStorage.Wisp.modules.Pool)

-- Acquire buffer for small data
local buf = Pool.acquireBuffer(512)  -- Gets from Small pool (1KB)

-- Acquire buffer for player data
local buf = Pool.acquireBuffer(10000)  -- Gets from Medium pool (16KB)

-- Acquire buffer for large batch
local buf = Pool.acquireBuffer(100000)  -- Gets from Large pool (256KB)

-- Use buffer...

-- Always release when done
Pool.releaseBuffer(buf)
```
:::

---

### `Pool.releaseBuffer`
```lua
Pool.releaseBuffer(buf: buffer)
```
Release buffer back to pool for reuse. Buffer contents are **not** cleared.

### Parameters:
- `buf`: Buffer to release

### Example:
::: code-group
```lua [ExamplePool.lua]
local buf = Pool.acquireBuffer(1024)

-- Use buffer for encoding
local encoded = encodeData(buf)

-- Release back to pool
Pool.releaseBuffer(buf)
```
:::

---

## Size Estimation

### `Pool.estimateSize`
```lua
Pool.estimateSize(value: any): number
```
Estimate encoded size for value using fast heuristics. Conservative estimates to avoid buffer reallocation.

### Parameters:
- `value`: Value to estimate size for

### Returns:
- `number`: Estimated size in bytes

### Example:
::: code-group
```lua [ExamplePool.lua]
-- Estimate sizes before encoding
local numSize = Pool.estimateSize(100)  -- ~10 bytes
local strSize = Pool.estimateSize("Hello")  -- ~8 bytes (3 + 5)
local vecSize = Pool.estimateSize(Vector3.new(1, 2, 3))  -- ~14 bytes

local tableSize = Pool.estimateSize({
    hp = 100,
    name = "Player1",
    position = Vector3.new(10, 5, 0)
})
print("Table will encode to ~", tableSize, "bytes")

-- Acquire appropriately sized buffer
local buf = Pool.acquireBuffer(tableSize + 100)  -- Safety margin
```
:::

### Size Estimation Rules:

| Type | Estimated Size | Formula |
|------|---------------|---------|
| `number` | 10 bytes | tag(1) + f64(8) + safety(1) |
| `string` | 3-5 + length | tag(1) + len(1-2) + data |
| `boolean` / `nil` | 2 bytes | tag(1) + value(1) |
| `Vector3` | 14 bytes | tag(1) + 3×f32(12) + safety(1) |
| `Vector2` | 10 bytes | tag(1) + 2×f32(8) + safety(1) |
| `CFrame` | 50 bytes | tag(1) + 12×f32(48) + safety(1) |
| `Color3` | 5 bytes | tag(1) + 3×u8(3) + safety(1) |
| `table` | 3 + entries | tag(1) + count(2) + recursive |
| **Unknown** | 32 bytes | Conservative default |

---

## Batch Optimization

### `Pool.groupBatches`
```lua
Pool.groupBatches(packets: {any}): {{any}}
```
Group packets into optimal-sized batches for compression efficiency. Keeps groups ≤8KB for L1 cache efficiency.

### Parameters:
- `packets`: Array of packets to group

### Returns:
- `{{any}}`: Array of packet groups

### Example:
::: code-group
```lua [ExamplePool.lua]
local packets = {}
for i = 1, 100 do
    table.insert(packets, {
        id = i,
        data = someData
    })
end

-- Group into optimal batches
local groups = Pool.groupBatches(packets)
print("Split into", #groups, "groups")

for i, group in groups do
    local encoded = Pool.inlineEncode(group, true)
    sendToServer(encoded)
end
```
:::

### Why 8KB Groups?

| Benefit | Description |
|---------|-------------|
| **L1 Cache Fit** | 8KB fits in most CPU L1 caches (~32KB typical) |
| **Better Compression** | Similar data compresses better together |
| **Predictable Latency** | Smaller groups = consistent encode times |
| **Network Efficiency** | Balances overhead vs packet size |

---

### `Pool.inlineEncode`
```lua
Pool.inlineEncode(packets: {any}, compress: boolean?): buffer?
```
Encode packets directly to buffer with optional compression. Avoids intermediate copies.

### Parameters:
- `packets`: Array of packets to encode
- `compress` (optional): Enable compression if beneficial (default: `false`)

### Returns:
- `buffer?`: Encoded buffer, or `nil` on failure

### Example:
::: code-group
```lua [ExamplePool.lua]
local packets = {
    {type = "move", pos = Vector3.new(10, 5, 0)},
    {type = "action", id = 123}
}

-- Encode without compression
local encoded = Pool.inlineEncode(packets)

-- Encode with compression (auto-applies if >20% savings)
local encoded = Pool.inlineEncode(packets, true)

if encoded then
    print("Encoded", buffer.len(encoded), "bytes")
end
```
:::

### Compression Heuristic:

```lua
-- Compression is applied only if:
1. compress = true
2. Uncompressed size > 256 bytes
3. Compressed size < uncompressed * 0.8  (>20% savings)

-- Otherwise returns uncompressed
```

---

## Hashing

### `Pool.hashData`
```lua
Pool.hashData(data: any): string
```
Calculate DJB2-variant hash for delta cache verification. **Non-cryptographic** - for integrity checks only.

### Parameters:
- `data`: Data to hash (converted via `tostring()`)

### Returns:
- `string`: 8-character hex hash (e.g., `"a3f5b2c1"`)

### Example:
::: code-group
```lua [ExamplePool.lua]
local data = {hp = 100, mp = 50}
local hash1 = Pool.hashData(data)
print(hash1)  -- "a3f5b2c1"

-- Same data = same hash
local hash2 = Pool.hashData({hp = 100, mp = 50})
assert(hash1 == hash2)  -- Deterministic

-- Different data = different hash
local hash3 = Pool.hashData({hp = 80, mp = 50})
print(hash3)  -- Different from hash1

-- Use for delta cache verification
local serverHash = getServerHash()
local clientHash = Pool.hashData(clientCache)
if serverHash ~= clientHash then
    warn("Cache desync - requesting full data")
end
```
:::

### Hash Properties:

| Property | Value |
|----------|-------|
| **Algorithm** | DJB2 variant |
| **Speed** | ~10ns per byte |
| **Output** | 32-bit (8 hex chars) |
| **Collisions** | Low for small datasets |
| **Cryptographic** | ❌ No - use for checksums only |
| **Deterministic** | ✅ Yes - same input = same hash |

### DJB2 Algorithm:
```lua
hash = 5381
for each byte:
    hash = (hash * 33) + byte
    hash = hash & 0xFFFFFFFF  -- Keep 32-bit
return hex(hash)
```

---

## Pool Configuration

### Size Tiers

| Tier | Size | Use Case | Count |
|------|------|----------|-------|
| **Small** | 1 KB | Simple events, positions, health | 10 buffers |
| **Medium** | 16 KB | Player data, inventories, stats | 10 buffers |
| **Large** | 256 KB | Large batches, world state | 10 buffers |

### Pool Behavior

```lua
-- On acquireBuffer(size):
if size <= 1024 then
    → Small pool (1KB)
elseif size <= 16384 then
    → Medium pool (16KB)
else
    → Large pool (256KB)

-- If pool exhausted:
    → Allocate new buffer (rare)
    → Logs warning if frequent

-- On releaseBuffer(buf):
    → Mark as available
    → Contents NOT cleared
    → Reused immediately
```