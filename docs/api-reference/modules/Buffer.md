# Buffer

Low-level serialization module for encoding/decoding Roblox data types to binary buffers

## Core Encoding

### `Buffer.Encode`
```lua
Buffer.Encode(value: any): (buffer?, string?)
```
Serialize any supported Roblox value to buffer.

### Parameters:
- `value`: Any encodable value (primitives, Roblox types, tables)

### Returns:
- `buffer?`: Encoded buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local Buffer = require(ReplicatedStorage.Wisp.modules.Buffer)

local buf, err = Buffer.Encode({
    position = Vector3.new(10, 5, 0),
    health = 100,
    name = "Player1"
})

if buf then
    print("Encoded size:", buffer.len(buf))
end
```
:::

---

### `Buffer.Decode`
```lua
Buffer.Decode(b: buffer): any
```
Deserialize buffer to original value. **Throws on error.**

### Parameters:
- `b`: Buffer to decode

### Returns:
- `any`: Decoded value

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local value = Buffer.Decode(buf)
print(value.position)  -- Vector3(10, 5, 0)
```
:::

---

### `Buffer.SafeDecode`
```lua
Buffer.SafeDecode(b: buffer): (any, string?)
```
Safe decode with error handling (doesn't throw).

### Parameters:
- `b`: Buffer to decode

### Returns:
- `any`: Decoded value on success, `nil` on failure
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local value, err = Buffer.SafeDecode(buf)
if err then
    warn("Decode failed:", err)
else
    print("Decoded:", value)
end
```
:::

---

## Advanced Encoding

### `Buffer.EncodeWith`
```lua
Buffer.EncodeWith(value: any, priority: Priority): (buffer?, string?)
```
Encode with LRU cache tier for frequently encoded values.

### Parameters:
- `value`: Value to encode
- `priority`: `"hot"` (100-slot) | `"warm"` (500-slot) | `"cold"` (2000-slot)

### Returns:
- `buffer?`: Encoded buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
-- Frequently changing data
local buf = Buffer.EncodeWith(playerPosition, "hot")

-- Static config
local buf = Buffer.EncodeWith(gameConfig, "cold")
```
:::

---

### `Buffer.EncodeCompressed`
```lua
Buffer.EncodeCompressed(value: any, mode: CompressionMode?, hint: DataHint?): (buffer?, string?)
```
Encode with compression.

### Parameters:
- `value`: Value to encode
- `mode` (optional): `"auto"` | `"lz4"` | `"deflate"` | `"zstd"` | `"none"` (default: `"auto"`)
- `hint` (optional): `"text"` | `"numbers"` | `"spatial"` | `"binary"` | `"auto"` (default: `"auto"`)

### Returns:
- `buffer?`: Compressed buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
-- Large text data
local buf = Buffer.EncodeCompressed(longText, "deflate", "text")

-- Numeric arrays
local buf = Buffer.EncodeCompressed(heights, "lz4", "numbers")

-- Auto-detect best compression
local buf = Buffer.EncodeCompressed(data, "auto")
```
:::

---

### `Buffer.EncodeSafe`
```lua
Buffer.EncodeSafe(value: any): (buffer?, string?)
```
Encode with cyclic reference detection.

### Parameters:
- `value`: Value to encode

### Returns:
- `buffer?`: Encoded buffer on success
- `string?`: Error message (including cyclic reference details)

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local tbl = {a = 1}
tbl.self = tbl  -- Cyclic reference

local buf, err = Buffer.EncodeSafe(tbl)
-- err: "cyclic reference at root.self"
```
:::

---

## Schema Encoding

### `Buffer.ValidateSchema`
```lua
Buffer.ValidateSchema(schema: Schema): (boolean, string?)
```
Validate schema structure before use.

### Parameters:
- `schema`: Schema definition to validate

### Returns:
- `boolean`: `true` if valid, `false` if invalid
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local ok, err = Buffer.ValidateSchema(mySchema)
if not ok then
    error("Invalid schema: " .. err)
end
```
:::

---

### `Buffer.EncodeSchema`
```lua
Buffer.EncodeSchema(value: {[string]: any}, schema: Schema): (buffer?, string?)
```
Encode using schema (field names omitted from wire for efficiency).

### Parameters:
- `value`: Table with fields matching schema
- `schema`: Schema definition

### Returns:
- `buffer?`: Encoded buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local schema = {
    fields = {
        {name = "hp", type = "number"},
        {name = "mp", type = "number"}
    }
}

local buf = Buffer.EncodeSchema({hp = 100, mp = 50}, schema)
-- Wire: [version:1] [100] [50]  (no field names!)
```
:::

---

### `Buffer.DecodeSchema`
```lua
Buffer.DecodeSchema(b: buffer, schema: Schema): ({[string]: any}?, string?)
```
Decode schema-encoded buffer.

### Parameters:
- `b`: Schema-encoded buffer
- `schema`: Schema definition (must match encoding schema)

### Returns:
- `{[string]: any}?`: Decoded table on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local data, err = Buffer.DecodeSchema(buf, schema)
if data then
    print(data.hp, data.mp)  -- 100, 50
end
```
:::

---

## Delta Encoding

### `Buffer.EncodeDelta`
```lua
Buffer.EncodeDelta(old: {[string]: any}, new: {[string]: any}): (buffer?, string?)
```
Encode only changed fields (table diff).

### Parameters:
- `old`: Previous table state
- `new`: New table state

### Returns:
- `buffer?`: Delta patch buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local old = {hp = 100, mp = 50, xp = 0}
local new = {hp = 80, mp = 50, xp = 10}

local delta = Buffer.EncodeDelta(old, new)
-- Wire: only {hp = 80, xp = 10}
```
:::

---

### `Buffer.ApplyDelta`
```lua
Buffer.ApplyDelta(target: {[string]: any}, delta: buffer): {[string]: any}
```
Apply delta patch to table.

### Parameters:
- `target`: Current table to patch
- `delta`: Delta buffer from `EncodeDelta`

### Returns:
- `{[string]: any}`: Patched table

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local current = {hp = 100, mp = 50, xp = 0}
current = Buffer.ApplyDelta(current, delta)
print(current.hp, current.xp)  -- 80, 10
```
:::

---

### `Buffer.EncodeSchemaDelta`
```lua
Buffer.EncodeSchemaDelta(old: {[string]: any}, new: {[string]: any}, schema: Schema): (buffer?, string?)
```
Schema-aware delta encoding using bitmask (max 32 fields).

### Parameters:
- `old`: Previous table state
- `new`: New table state
- `schema`: Schema definition

### Returns:
- `buffer?`: Delta buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local statsSchema = {
    fields = {
        {name = "hp", type = "number"},
        {name = "mp", type = "number"},
        {name = "xp", type = "number"}
    }
}

local delta = Buffer.EncodeSchemaDelta(oldStats, newStats, statsSchema)
-- Wire: [version:1] [bitmask:u32] [changed_values...]
```
:::

---

### `Buffer.DecodeSchemaDelta`
```lua
Buffer.DecodeSchemaDelta(b: buffer, current: {[string]: any}, schema: Schema): ({[string]: any}?, string?)
```
Decode schema delta and merge with current state.

### Parameters:
- `b`: Delta buffer
- `current`: Current table state to merge into
- `schema`: Schema definition

### Returns:
- `{[string]: any}?`: Merged table on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local current = {hp = 100, mp = 50, xp = 0}
local updated, err = Buffer.DecodeSchemaDelta(deltaBuffer, current, statsSchema)
if updated then
    print(updated.hp)  -- Updated value
end
```
:::

---

## Migration

### `Buffer.MigrateSchema`
```lua
Buffer.MigrateSchema(
    data: {[string]: any},
    fromVersion: number,
    toVersion: number,
    migrations: MigrationMap
): ({[string]: any}?, string?)
```
Upgrade data through version chain.

### Parameters:
- `data`: Data at old version
- `fromVersion`: Current data version
- `toVersion`: Target version
- `migrations`: Map of version upgrade functions

### Returns:
- `{[string]: any}?`: Upgraded data on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local migrations = {
    [1] = function(data)  -- v1 → v2
        data.newField = data.oldField * 2
        data.oldField = nil
        return data
    end,
    [2] = function(data)  -- v2 → v3
        data.anotherField = true
        return data
    end
}

local upgraded = Buffer.MigrateSchema(
    oldData,   -- version 1
    1,         -- from
    3,         -- to
    migrations
)
```
:::

---

## Instance Encoding

### `Buffer.RegisterInstance`
```lua
Buffer.RegisterInstance(instance: Instance, id: number)
```
Register instance for encoding. Must be called before encoding instances.

### Parameters:
- `instance`: Instance to register
- `id`: Unique ID (u32, 0-4,294,967,295)

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local workspace = game.Workspace
Buffer.RegisterInstance(workspace, 1)

local buf = Buffer.Encode(workspace)
-- Wire: [T_INSTANCE:1] [id:4] → total 5 bytes
```
:::

---

### `Buffer.UnregisterInstance`
```lua
Buffer.UnregisterInstance(instance: Instance)
```
Remove instance from registry.

### Parameters:
- `instance`: Instance to unregister

### Example:
::: code-group
```lua [ExampleBuffer.lua]
Buffer.UnregisterInstance(workspace)
```
:::

---

## Custom Types

### `Buffer.RegisterType`
```lua
Buffer.RegisterType(id: number, ct: CustomType)
```
Register custom encoder/decoder for user-defined types.

### Parameters:
- `id`: Type ID (0-254)
- `ct`: CustomType with `check`, `encode`, `decode` functions

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local MyType = {}
MyType.__index = MyType

function MyType.new(x, y)
    return setmetatable({x = x, y = y}, MyType)
end

Buffer.RegisterType(1, {
    check = function(v)
        return getmetatable(v) == MyType
    end,
    encode = function(value, offset)
        buffer.writef32(BB, offset, value.x)
        buffer.writef32(BB, offset + 4, value.y)
        return offset + 8, nil
    end,
    decode = function(b, offset)
        local x = buffer.readf32(b, offset)
        local y = buffer.readf32(b, offset + 4)
        return MyType.new(x, y), offset + 8
    end
})

-- Now you can encode/decode MyType instances
local obj = MyType.new(10, 20)
local buf = Buffer.Encode(obj)
```
:::

---

## Utilities

### `Buffer.EncodedSize`
```lua
Buffer.EncodedSize(value: any): (number?, string?)
```
Calculate encoded size without allocating buffer.

### Parameters:
- `value`: Value to measure

### Returns:
- `number?`: Size in bytes on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local size = Buffer.EncodedSize(largeTable)
print("Will encode to", size, "bytes")
```
:::

---

### `Buffer.Invalidate`
```lua
Buffer.Invalidate(value: any)
```
Remove value from all LRU caches (hot/warm/cold).

### Parameters:
- `value`: Value to invalidate

### Example:
::: code-group
```lua [ExampleBuffer.lua]
-- Config changed, invalidate cache
Buffer.Invalidate(gameConfig)
```
:::

---

### `Buffer.SetCompressionDict`
```lua
Buffer.SetCompressionDict(dict: buffer)
```
Set Deflate dictionary for domain-specific compression boost.

### Parameters:
- `dict`: Dictionary buffer (max 32KB)

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local dict = buffer.fromstring("common game words player health mana...")
Buffer.SetCompressionDict(dict)
```
:::

---

### `Buffer.Visualize`
```lua
Buffer.Visualize(b: buffer): string
```
Render buffer contents as human-readable tag list.

### Parameters:
- `b`: Buffer to visualize

### Returns:
- `string`: Tag listing with offsets

### Example:
::: code-group
```lua [ExampleBuffer.lua]
print(Buffer.Visualize(buf))
-- [0000] 11 TABLE
-- [0001] 03 U8
-- [0002] 64 (value: 100)
```
:::

---

### `Buffer.VisualizeEntropy`
```lua
Buffer.VisualizeEntropy(b: buffer): string
```
Render entropy distribution for compression analysis.

### Parameters:
- `b`: Buffer to analyze

### Returns:
- `string`: ASCII entropy visualization

### Example:
::: code-group
```lua [ExampleBuffer.lua]
print(Buffer.VisualizeEntropy(buf))
-- [::::----====++++####]
-- Low entropy (left) = compressible
-- High entropy (right) = already compressed/random
```
:::

---

### `Buffer.DetectDataClass`
```lua
Buffer.DetectDataClass(b: buffer): DataHint
```
Detect data type from first tag byte.

### Parameters:
- `b`: Buffer to analyze

### Returns:
- `DataHint`: `"numbers"` | `"text"` | `"spatial"` | `"binary"` | `"already_compressed"`

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local hint = Buffer.DetectDataClass(buf)
if hint == "text" then
    print("Use Deflate compression")
elseif hint == "numbers" then
    print("Use LZ4 compression")
end
```
:::

---

### `Buffer.ToJSON`
```lua
Buffer.ToJSON(b: buffer): (string?, string?)
```
Convert buffer to JSON string.

### Parameters:
- `b`: Buffer to convert

### Returns:
- `string?`: JSON string on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local json, err = Buffer.ToJSON(buf)
if json then
    print(json)  -- {"hp":100,"mp":50}
end
```
:::

---

### `Buffer.FromJSON`
```lua
Buffer.FromJSON(json: string): (buffer?, string?)
```
Parse JSON and encode to buffer.

### Parameters:
- `json`: JSON string to parse

### Returns:
- `buffer?`: Encoded buffer on success
- `string?`: Error message on failure

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local buf, err = Buffer.FromJSON('{"hp":100,"mp":50}')
if buf then
    local data = Buffer.Decode(buf)
    print(data.hp)  -- 100
end
```
:::

---

## Async Operations

### `Buffer.EncodeAsync`
```lua
Buffer.EncodeAsync(value: any): AsyncHandle
```
Encode large tables without blocking (yields every 256 fields).

### Parameters:
- `value`: Value to encode (typically large table)

### Returns:
- `AsyncHandle`: Handle with `:Await()` and `:Cancel()` methods

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local handle = Buffer.EncodeAsync(hugeTable)

-- Wait for completion
local buf, err = handle:Await()

-- Or cancel if needed
handle:Cancel()
```
:::

---

### `Buffer.DecodeAsync`
```lua
Buffer.DecodeAsync(b: buffer): AsyncHandle
```
Async decode for large buffers.

### Parameters:
- `b`: Buffer to decode

### Returns:
- `AsyncHandle`: Handle with `:Await()` and `:Cancel()` methods

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local handle = Buffer.DecodeAsync(largeBuffer)
local value, err = handle:Await()
```
:::

---

### `Buffer.CreateStream`
```lua
Buffer.CreateStream(): Stream
```
Create write-only stream for incremental encoding.

### Returns:
- `Stream`: Stream with `:write()` and `:finalize()` methods

### Example:
::: code-group
```lua [ExampleBuffer.lua]
local stream = Buffer.CreateStream()
stream:write(value1)
stream:write(value2)
stream:write(value3)

local buf = stream:finalize()
print("Encoded", buffer.len(buf), "bytes")
```
:::

---

## Type Constructors

Schema validation helpers accessed via `Buffer.Types`.

### `Types.any()`
```lua
Types.any(): SchemaType
```
Accept any value (no validation).

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "data", type = Types.any()}
```
:::

---

### `Types.exact()`
```lua
Types.exact(typeofStr: string): SchemaType
```
Exact typeof() match.

### Parameters:
- `typeofStr`: Expected typeof() string

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "part", type = Types.exact("Instance")}
```
:::

---

### `Types.number()`
```lua
Types.number(): SchemaType
```
Any number (including NaN, Infinity).

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "score", type = Types.number()}
```
:::

---

### `Types.numberRange()`
```lua
Types.numberRange(min: number, max: number): SchemaType
```
Number within range [min, max].

### Parameters:
- `min`: Minimum value (inclusive)
- `max`: Maximum value (inclusive)

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "health", type = Types.numberRange(0, 100)}
{name = "temperature", type = Types.numberRange(-273.15, 1000)}
```
:::

---

### `Types.integer()`
```lua
Types.integer(): SchemaType
```
Integer (no decimals).

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "level", type = Types.integer()}
```
:::

---

### `Types.string()`
```lua
Types.string(maxLen: number?): SchemaType
```
String with optional max length.

### Parameters:
- `maxLen` (optional): Maximum string length

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "username", type = Types.string(20)}
{name = "description", type = Types.string()}  -- No limit
```
:::

---

### `Types.boolean()`
```lua
Types.boolean(): SchemaType
```
Boolean value.

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{name = "isActive", type = Types.boolean()}
```
:::

---

### `Types.array()`
```lua
Types.array(elementType: SchemaType, maxLen: number?): SchemaType
```
Array (sequence table) with typed elements.

### Parameters:
- `elementType`: Type validator for array elements
- `maxLen` (optional): Maximum array length

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{
    name = "scores",
    type = Types.array(Types.integer(), 100)
}

{
    name = "players",
    type = Types.array(Types.string(20))
}
```
:::

---

### `Types.union()`
```lua
Types.union(...: SchemaType): SchemaType
```
Value must match one of the types.

### Parameters:
- `...`: Variable number of SchemaType validators

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{
    name = "value",
    type = Types.union(
        Types.number(),
        Types.string()
    )
}
```
:::

---

### `Types.optional()`
```lua
Types.optional(inner: SchemaType): SchemaType
```
Allow nil or inner type.

### Parameters:
- `inner`: Type validator for non-nil values

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{
    name = "nickname",
    type = Types.optional(Types.string(30))
}
```
:::

---

### `Types.literal()`
```lua
Types.literal(...: any): SchemaType
```
Value must be one of the literals.

### Parameters:
- `...`: Variable number of literal values

### Returns:
- `SchemaType`: Type validator

### Example:
::: code-group
```lua [ExampleBuffer.lua]
{
    name = "team",
    type = Types.literal("Red", "Blue", "Green")
}

{
    name = "status",
    type = Types.literal("pending", "active", "completed")
}
```
:::