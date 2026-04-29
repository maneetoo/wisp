# Wisp Supported Types

## Primitives

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **NIL** | 0 | 1 byte | `nil` | Null value |
| **BOOL** | 1 | 2 bytes | `boolean` | `true`, `false` |
| **U8** | 2 | 2 bytes | `number` | `0` – `255` |
| **U16** | 3 | 3 bytes | `number` | `0` – `65,535` |
| **U32** | 4 | 5 bytes | `number` | `0` – `4,294,967,295` |
| **I8** | 5 | 2 bytes | `number` | `-128` – `127` |
| **I16** | 6 | 3 bytes | `number` | `-32,768` – `32,767` |
| **I32** | 7 | 5 bytes | `number` | `-2,147,483,648` – `2,147,483,647` |
| **F32** | 8 | 5 bytes | `number` | 32-bit float (round-trip check) |
| **F64** | 9 | 9 bytes | `number` | 64-bit float (NaN, ±Infinity) |

## Strings

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **STR8** | 10 | 3 + len | `string` | Max 255 bytes: `"hello"` |
| **STR16** | 11 | 4 + len | `string` | Max 65,535 bytes: long text |

## Vectors & Spatial

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **VEC3** | 12 | 13 bytes | `Vector3` | `Vector3.new(1, 2, 3)` — 3×f32 |
| **VEC2** | 20 | 9 bytes | `Vector2` | `Vector2.new(10, 20)` — 2×f32 |
| **VEC3INT16** | 33 | 7 bytes | `Vector3int16` | `Vector3int16.new(1, 2, 3)` — 3×i16 |
| **VEC2INT16** | 34 | 5 bytes | `Vector2int16` | `Vector2int16.new(5, 10)` — 2×i16 |
| **CF_LOSSY** | 13 | 29 bytes | `CFrame` | Axis-angle (pos + axis + angle) — 7×f32<br>±0.001mm precision |
| **CF_FULL** | 14 | 49 bytes | `CFrame` | Full matrix — 12×f32<br>For sheared/non-standard CFrames |
| **RAY** | 22 | 25 bytes | `Ray` | `Ray.new(origin, direction)` — 6×f32 |
| **REGION3** | 39 | 25 bytes | `Region3` | CFrame center + half-size — 6×f32 |
| **REGION3INT16** | 40 | 13 bytes | `Region3int16` | Min/Max — 6×i16 |

## Colors & UI

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **COLOR3** | 15 | 4 bytes | `Color3` | `Color3.fromRGB(255, 128, 0)` — 3×u8 (0–255) |
| **BRICKCLR** | 24 | 3 bytes | `BrickColor` | `BrickColor.new("Bright red")` — u16 palette ID |
| **UDIM** | 27 | 9 bytes | `UDim` | `UDim.new(0.5, 10)` — f32 + i32 |
| **UDIM2** | 21 | 17 bytes | `UDim2` | `UDim2.new(0, 100, 0, 50)` — 2×(f32+i32) |
| **RECT** | 28 | 17 bytes | `Rect` | `Rect.new(0, 0, 100, 100)` — 4×f32 |

## Sequences

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **COLORSEQ** | 29 | 2 + N×7 | `ColorSequence` | Max 255 keypoints<br>Each: f32 time + 3×u8 RGB |
| **COLORSEQKP** | 45 | 8 bytes | `ColorSequenceKeypoint` | Single keypoint |
| **NUMSEQ** | 30 | 2 + N×12 | `NumberSequence` | Max 255 keypoints<br>Each: 3×f32 (time, value, envelope) |
| **NUMBERSEQKP** | 46 | 13 bytes | `NumberSequenceKeypoint` | Single keypoint |
| **NRANGE** | 23 | 6 or 10 | `NumberRange` | `NumberRange.new(0, 100)` |

## Tables & Arrays

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **TABLE** | 17 | 3 + data | `table` | Dictionary `{hp=100, name="Bob"}`<br>Max 65,535 fields |
| **ARRAY** | 18 | 3 + data | `table` | Sequence `{1, 2, 3, 4}`<br>Max 65,535 elements |
| **ARRAY_RLE** | 19 | 3 + runs | `table` | Run-length encoded array<br>Auto for runs ≥3 in 64+ elements |
| **DELTA** | 26 | 3 + patch | `table` | Patch format for delta encoding |

## Special Types

| Type | Tag | Wire Size | Roblox Type | Example / Notes |
|------|-----|-----------|-------------|-----------------|
| **ENUM** | 25 | 4 + len | `EnumItem` | `Enum.Material.Plastic`<br>Wire: enum name (str8) + u16 value |
| **INSTANCE** | 48 | 5 bytes | `Instance` | Registered via `Buffer.RegisterInstance(inst, id)`<br>Wire: u32 ID |
| **FONT** | 31 | varies | `Font` | Family (str8) + Weight (u16) + Style (u8) |
| **CONTENT** | 32 | varies | `Content` | URI as str8 or str16 (if ≥255 bytes) |
| **DATETIME** | 38 | 9 bytes | `DateTime` | `DateTime.now()` — f64 UnixMillis |
| **PHYSPROP** | 35 | 21 bytes | `PhysicalProperties` | Custom: 5×f32 (density, friction, elasticity, weights) |
| **PHYSPROP_DEFAULT** | 36 | 1 byte | `PhysicalProperties` | Default (Plastic) — tag only |
| **AXES** | 42 | 2 bytes | `Axes` | Bitmask: X=1, Y=2, Z=4 |
| **FACES** | 43 | 2 bytes | `Faces` | Bitmask: Top/Bottom/Left/Right/Front/Back |
| **TWEENINFO** | 44 | 16 bytes | `TweenInfo` | f32 time + 2×u8 style/dir + i32 repeats + u8 reverses + f32 delay |

## Compression Wrappers

| Type | Tag | Wire Size | Format | Notes |
|------|-----|-----------|--------|-------|
| **LZ4** | 47 | 13 + compressed | Compressed | Header: tag(1) + origSize(4) + compSize(4) + adler32(4) + payload |
| **DEFLATE** | 49 | 13 + compressed | Compressed | Fixed Huffman — best for text |
| **ZSTD** | 50 | 13 + compressed | Compressed | Server-only via EncodingService |

## Custom Types

| Type | Tag | Wire Size | API | Notes |
|------|-----|-----------|-----|-------|
| **CUSTOM** | 41 | 2 + data | `Buffer.RegisterType(id, customType)` | User-defined encoders/decoders<br>Max 255 custom type IDs (0–254) |

---

## Notes

### Automatic Type Selection
- **Numbers**: `numTag()` auto-selects smallest tag (U8 → F64)
- **CFrame**: Prefers CF_LOSSY (29 bytes) when precision ≤1mm, else CF_FULL (49 bytes)
- **Arrays**: Auto-applies RLE when beneficial (≥64 elements, ≥3-element runs)

### Size Limits
- **String**: Max 65,535 bytes (STR16)
- **Table/Array**: Max 65,535 fields/elements
- **Schema**: Max 32 fields for delta encoding (bitmask limit)
- **ColorSequence/NumberSequence**: Max 255 keypoints

### Wire Format Pattern
```
[TAG:u8] [SIZE_IF_NEEDED] [DATA]
```
- Tag always 1 byte
- Variable-length data uses u8/u16 length prefix
- Fixed-size types omit length (e.g., Vector3 is always 12 bytes)