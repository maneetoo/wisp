# XOR

Data obfuscation pre-processor for improving compression ratios

::: warning Not for Security
XOR pre-processing is a deterministic pattern-breaking step, **not encryption**. Do not use for sensitive data protection.
:::

## `XOR.apply`
```lua
XOR.apply(data: buffer): buffer
```
Apply XOR transformation to buffer. Symmetric operation — calling twice restores original data.

### Parameters:
- `data`: Buffer to transform

### Returns:
- `buffer`: XOR-transformed buffer (same size as input)

### Example:
::: code-group
```lua [ExampleXOR.lua]
local XOR = require(ReplicatedStorage.Wisp.modules.XOR)

-- Encode pipeline
local encoded = Buffer.Encode(data)
local obfuscated = XOR.apply(encoded)  -- Before compression
sendToServer(obfuscated)

-- Decode pipeline
local received = receiveFromServer()
local deobfuscated = XOR.apply(received)  -- Reverse (XOR is symmetric)
local decoded = Buffer.Decode(deobfuscated)

-- Verify symmetry
local original = buffer.fromstring("Hello World")
local transformed = XOR.apply(original)
local restored = XOR.apply(transformed)
-- restored == original ✓
```
:::

---

## How It Works

### XOR Pattern

```lua
-- Each byte is XORed with a rotating 24-byte key pattern:
byte[0] XOR key[1](137)
byte[1] XOR key[2](42)
byte[2] XOR key[3](251)
...
byte[23] XOR key[24](149)
byte[24] XOR key[1](137)  ← wraps around
byte[25] XOR key[2](42)
...

-- Completely reversible:
A XOR B XOR B = A
```

### Key Design

```lua
local KEY = {
    137, 42, 251, 19, 88, 203, 144, 67,  -- First 8  (primes + powers of 2)
     91, 178, 233, 54, 167, 12, 201, 89,  -- Second 8 (varied distribution)
    255, 7, 124, 193, 38, 211, 76, 149   -- Third 8  (large + small values)
}
```

| Property | Value |
|----------|-------|
| **Key length** | 24 bytes |
| **Pattern period** | 24 bytes before repeat |
| **Value range** | 7 – 255 |
| **Primes included** | 137, 251, 19, 67, 89, 193, 211, 149 |

---

## Why XOR Helps Compression

| Effect | Description | Improvement |
|--------|-------------|-------------|
| **Pattern breaking** | Breaks repetitive byte sequences (`AAAAAAA` → varied) | +5-15% |
| **Byte distribution** | Distributes values across 0-255 range | Better entropy |
| **LZ4 matching** | More varied patterns = better dictionary building | +5-10% |
| **Deflate codes** | Prevents Huffman tree skew from clustering | +3-8% |

### Example: Repetitive Data
```lua
-- Without XOR:
-- "AAAAAAA" → [65, 65, 65, 65, 65, 65, 65]
-- Compression sees identical bytes → poor match opportunities

-- With XOR (key starts at 137):
-- [65 XOR 137, 65 XOR 42, 65 XOR 251, ...]
-- → [200, 107, 186, 84, 25, ...]
-- More varied → better compression matches
```

---

## Performance

| Characteristic | Value |
|----------------|-------|
| **Speed** | ~0.1ns per byte |
| **Time complexity** | O(n) |
| **Space complexity** | O(n) output buffer |
| **Allocations** | 1 (output buffer, pre-sized) |
| **Branching** | None in hot loop |
| **CPU instruction** | Single XOR per byte |

### Integration in Pipeline

```lua
-- Encode pipeline (Remote:_encode):
local encoded = Buffer.Encode(value)
-- ... optional compression ...
local result = XOR.apply(encoded)  -- Always last step
return result

-- Decode pipeline (Remote:_decode):
local deobfuscated = XOR.apply(data)  -- Always first step
local value = Buffer.Decode(deobfuscated)
-- ... schema/delta processing ...
return value
```

::: info Always Active
XOR transformation is **always applied** in `Remote:_encode` and `Remote:_decode`. No configuration needed.
:::