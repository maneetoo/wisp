# Compress

Low-level compression module supporting LZ4HC, Deflate, and Zstd algorithms

## Core Compression

### `Compress.Compress`
```lua
Compress.Compress(raw: buffer, hint: DataHint?): (buffer, boolean)
```
Compress buffer with automatic algorithm selection based on data type.

### Parameters:
- `raw`: Buffer to compress
- `hint` (optional): Data type hint for algorithm selection (`"text"` | `"numbers"` | `"spatial"` | `"binary"` | `"auto"`)

### Returns:
- `buffer`: Compressed buffer (or original if compression not beneficial)
- `boolean`: `true` if compressed, `false` if returned original

### Example:
::: code-group
```lua [ExampleCompress.lua]
local Compress = require(ReplicatedStorage.Wisp.modules.Compress)

-- Auto-detect best compression
local compressed, didCompress = Compress.Compress(data)
if didCompress then
    print("Saved", buffer.len(data) - buffer.len(compressed), "bytes")
end

-- With hint for better algorithm selection
local compressed = Compress.Compress(textData, "text")  -- Uses Deflate
local compressed = Compress.Compress(positions, "spatial")  -- Uses LZ4HC
```
:::

---

### `Compress.CompressMode`
```lua
Compress.CompressMode(mode: string, raw: buffer, hint: DataHint?): (buffer, boolean)
```
Compress buffer with explicit algorithm selection.

### Parameters:
- `mode`: Algorithm to use (`"lz4"` | `"deflate"` | `"zstd"` | `"auto"` | `"none"`)
- `raw`: Buffer to compress
- `hint` (optional): Data type hint

### Returns:
- `buffer`: Compressed buffer (or original if compression not beneficial)
- `boolean`: `true` if compressed, `false` if returned original

### Example:
::: code-group
```lua [ExampleCompress.lua]
-- Force specific algorithm
local compressed = Compress.CompressMode("lz4", data)
local compressed = Compress.CompressMode("deflate", textData)

-- Server-only: use Zstd for best ratio
if RunService:IsServer() then
    local compressed = Compress.CompressMode("zstd", largeData)
end

-- Skip compression
local uncompressed = Compress.CompressMode("none", data)
```
:::

---

### `Compress.CompressProgressive`
```lua
Compress.CompressProgressive(
    raw: buffer,
    mode: string,
    hint: DataHint?,
    onProgress: ProgressFn?
): buffer
```
Compress large buffer in 64KB chunks with progress callback.

### Parameters:
- `raw`: Buffer to compress
- `mode`: Algorithm to use
- `hint` (optional): Data type hint
- `onProgress` (optional): Callback `(done: number, total: number) -> ()`

### Returns:
- `buffer`: Progressive compressed buffer with chunk metadata

### Example:
::: code-group
```lua [ExampleCompress.lua]
local hugeBuffer = buffer.create(10_000_000)  -- 10MB

local compressed = Compress.CompressProgressive(
    hugeBuffer,
    "auto",
    nil,
    function(done, total)
        print(`Compressing: {math.floor(done/total*100)}%`)
    end
)
```
:::

---

## Decompression

### `Compress.decompress`
```lua
Compress.decompress(tag: number, src: buffer, offset: number): (buffer, number)
```
Decompress buffer starting at offset. Verifies Adler-32 checksum.

### Parameters:
- `tag`: Compression tag (`T_LZ4` | `T_DEFLATE` | `T_ZSTD`)
- `src`: Compressed buffer
- `offset`: Start offset (typically 1, after type tag)

### Returns:
- `buffer`: Decompressed buffer
- `number`: New offset after compressed data

### Example:
::: code-group
```lua [ExampleCompress.lua]
-- Usually called internally by Buffer.Decode
local tag = buffer.readu8(compressed, 0)

if tag == Compress.T_LZ4 or tag == Compress.T_DEFLATE then
    local decompressed, newOffset = Compress.decompress(tag, compressed, 1)
    print("Decompressed to", buffer.len(decompressed), "bytes")
end
```
:::

---

### `Compress.DecompressProgressive`
```lua
Compress.DecompressProgressive(b: buffer): buffer
```
Decompress progressive (chunked) buffer.

### Parameters:
- `b`: Progressive compressed buffer from `CompressProgressive`

### Returns:
- `buffer`: Fully decompressed buffer

### Example:
::: code-group
```lua [ExampleCompress.lua]
local decompressed = Compress.DecompressProgressive(progressiveBuffer)
print("Restored", buffer.len(decompressed), "bytes")
```
:::

---

## Dictionary

### `Compress.SetDict`
```lua
Compress.SetDict(dict: buffer?)
```
Set Deflate dictionary for domain-specific compression boost. Both encoder and decoder must use the same dictionary.

### Parameters:
- `dict`: Dictionary buffer (max 32KB), or `nil` to clear

### Example:
::: code-group
```lua [ExampleCompress.lua]
-- Create dictionary from common game terms
local commonWords = table.concat({
    "player", "health", "mana", "position",
    "inventory", "weapon", "armor", "damage"
}, " ")

local dict = buffer.fromstring(commonWords)
Compress.SetDict(dict)

-- Now Deflate compression will be more efficient for these words
local compressed = Compress.CompressMode("deflate", gameData)

-- Clear dictionary
Compress.SetDict(nil)
```
:::

---

### `Compress.GetDict`
```lua
Compress.GetDict(): buffer?
```
Get current Deflate dictionary.

### Returns:
- `buffer?`: Current dictionary buffer, or `nil` if not set

### Example:
::: code-group
```lua [ExampleCompress.lua]
local currentDict = Compress.GetDict()
if currentDict then
    print("Dictionary size:", buffer.len(currentDict))
end
```
:::

---

## Utilities

### `Compress.Adler32`
```lua
Compress.Adler32(b: buffer): number
```
Calculate Adler-32 checksum for integrity verification (non-cryptographic).

### Parameters:
- `b`: Buffer to checksum

### Returns:
- `number`: 32-bit checksum

### Example:
::: code-group
```lua [ExampleCompress.lua]
local checksum = Compress.Adler32(data)
print(string.format("Checksum: 0x%08X", checksum))

-- Verify integrity
local receivedChecksum = buffer.readu32(packet, 0)
local computedChecksum = Compress.Adler32(packet)
if receivedChecksum ~= computedChecksum then
    warn("Data corrupted!")
end
```
:::

---

### `Compress.VisualizeEntropy`
```lua
Compress.VisualizeEntropy(b: buffer): string
```
Render entropy distribution as ASCII visualization (64 segments).

### Parameters:
- `b`: Buffer to analyze

### Returns:
- `string`: Entropy visualization (`[::::----====++++####]`)

### Example:
::: code-group
```lua [ExampleCompress.lua]
print("Raw data:       ", Compress.VisualizeEntropy(rawData))
print("LZ4 compressed: ", Compress.VisualizeEntropy(lz4Data))
print("Deflate:        ", Compress.VisualizeEntropy(deflateData))

-- Low entropy (left side) = repetitive, compressible
-- High entropy (right side) = random, already compressed
```
:::

---

### `Compress.DetectClass`
```lua
Compress.DetectClass(b: buffer): DataHint
```
Detect data type from first tag byte (O(1) operation).

### Parameters:
- `b`: Buffer to analyze

### Returns:
- `DataHint`: `"text"` | `"numbers"` | `"spatial"` | `"binary"` | `"already_compressed"`

### Example:
::: code-group
```lua [ExampleCompress.lua]
local hint = Compress.DetectClass(encodedData)

if hint == "text" then
    print("Use Deflate for best compression")
elseif hint == "numbers" then
    print("Use LZ4HC for fast compression")
elseif hint == "already_compressed" then
    print("Skip compression")
end
```
:::

---

## Constants

### Compression Tags
```lua
Compress.T_LZ4       -- 47: LZ4HC algorithm
Compress.T_DEFLATE   -- 49: Deflate (fixed Huffman)
Compress.T_ZSTD      -- 50: Zstd (server-only)
```

### Header Size
```lua
Compress.HEADER_SIZE -- 13 bytes: tag(1) + origSize(4) + compSize(4) + adler32(4)
```

### Example:
::: code-group
```lua [ExampleCompress.lua]
local tag = buffer.readu8(compressed, 0)

if tag == Compress.T_LZ4 then
    print("LZ4 compressed")
elseif tag == Compress.T_DEFLATE then
    print("Deflate compressed")
elseif tag == Compress.T_ZSTD then
    print("Zstd compressed (server)")
end

-- Read header manually
local origSize = buffer.readu32(compressed, 1)
local compSize = buffer.readu32(compressed, 5)
print(`Original: {origSize}, Compressed: {compSize}, Ratio: {compSize/origSize}`)
```
:::

---

## Compressors Table

### `Compress.compressors`
```lua
Compress.compressors = {
    lz4: (buffer, DataHint?) -> (buffer, boolean),
    deflate: (buffer, DataHint?) -> (buffer, boolean),
    zstd: (buffer, DataHint?) -> (buffer, boolean),
    auto: (buffer, DataHint?) -> (buffer, boolean),
    none: (buffer, DataHint?) -> (buffer, boolean),
    text: (buffer, DataHint?) -> (buffer, boolean),
    numbers: (buffer, DataHint?) -> (buffer, boolean),
    spatial: (buffer, DataHint?) -> (buffer, boolean),
    binary: (buffer, DataHint?) -> (buffer, boolean)
}
```

Table of compressor functions for each mode.

### Example:
::: code-group
```lua [ExampleCompress.lua]
-- Direct access to compressor functions
local compressor = Compress.compressors["lz4"]
local compressed, didCompress = compressor(data, nil)

-- Custom compression logic
for _, mode in {"lz4", "deflate"} do
    local compressed, ok = Compress.compressors[mode](data)
    if ok then
        print(mode, ":", buffer.len(compressed), "bytes")
    end
end
```
:::

---

## Algorithm Comparison

| Algorithm | Speed | Ratio | Best For | Availability |
|-----------|-------|-------|----------|--------------|
| **LZ4HC** | Fast | Good | Numbers, spatial data, arrays | Client + Server |
| **Deflate** | Slow | Best | Text, JSON, repetitive strings | Client + Server |
| **Zstd** | Fast | Best | All data types | **Server only** |
| **None** | Instant | 0% | Already compressed data | Client + Server |

### Auto Selection Logic

```lua
-- size < 512 bytes → no compression
-- already_compressed → skip

-- Server available:
--   try Zstd first

-- Data class:
--   "text" → Deflate → fallback LZ4HC
--   "numbers" → LZ4HC
--   "spatial" → LZ4HC
--   "binary" → try both, pick best
```