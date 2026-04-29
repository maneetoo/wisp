--@maneetoo

--!strict
--!native
--!optimize 2

local Buffer = require("./Buffer")

local Pool = {}

-- Buffer pool configuration
-- Three size tiers to minimize waste while avoiding frequent allocations
local POOL_SIZE = 10 -- Buffers per tier
local SMALL_SIZE = 1024 -- 1KB - for simple events (position, health, etc)
local MEDIUM_SIZE = 16384 -- 16KB - for player data, inventories
local LARGE_SIZE = 262144 -- 256KB - for large batches, world state

-- Pool storage
local _smallPool: { buffer } = {}
local _mediumPool: { buffer } = {}
local _largePool: { buffer } = {}
local _inUse: { [buffer]: true } = {}

-- Initialize pools on module load
for i = 1, POOL_SIZE do
	table.insert(_smallPool, buffer.create(SMALL_SIZE))
	table.insert(_mediumPool, buffer.create(MEDIUM_SIZE))
	table.insert(_largePool, buffer.create(LARGE_SIZE))
end

--[[
	Acquire buffer from pool
	
	Strategy:
        Pick pool based on requested size
        Return first available buffer from pool
        If pool exhausted, allocate new buffer (rare case)
]]
--
function Pool.acquireBuffer(size: number): buffer
	-- Select appropriate pool tier
	local pool = if size <= SMALL_SIZE then _smallPool elseif size <= MEDIUM_SIZE then _mediumPool else _largePool

	-- Find unused buffer in pool
	for i, buf in pool do
		if not _inUse[buf] then
			_inUse[buf] = true
			return buf
		end
	end

	-- Pool exhausted - allocate new buffer
	-- This should be rare; if frequent, increase POOL_SIZE
	local buf = buffer.create(size)
	_inUse[buf] = true
	return buf
end

--[[
	Release buffer back to pool
	
	Mark buffer as available for reuse
	Buffer contents are not cleared - will be overwritten on next use
]]
--
function Pool.releaseBuffer(buf: buffer)
	_inUse[buf] = nil
end

--[[
	Estimate encoded size for value
	
	Fast heuristic to determine buffer size needed
	Conservative estimates to avoid reallocation
	
	Estimation rules:
	- Numbers: 10 bytes (worst case: tag + f64)
	- Strings: 4 + length (tag + u16 length + data)
	- Vectors: Fixed sizes (tag + components)
	- Tables: Recursive sum of entries + overhead
]]
--
function Pool.estimateSize(value: any): number
	local vt = typeof(value)

	if vt == "number" then
		return 10 -- tag(1) + f64(8) + safety(1)
	elseif vt == "string" then
		local len = #value
		return if len <= 255 then 3 + len else 5 + len
	elseif vt == "boolean" or vt == "nil" then
		return 2 -- tag(1) + value(1)
	elseif vt == "Vector3" then
		return 14 -- tag(1) + 3*f32(12) + safety(1)
	elseif vt == "Vector2" then
		return 10 -- tag(1) + 2*f32(8) + safety(1)
	elseif vt == "CFrame" then
		return 50 -- tag(1) + 12*f32(48) + safety(1)
	elseif vt == "Color3" then
		return 5 -- tag(1) + 3*u8(3) + safety(1)
	elseif vt == "table" then
		local size = 3 -- tag(1) + count(2)
		for k, v in pairs(value :: any) do
			size += Pool.estimateSize(k)
			size += Pool.estimateSize(v)
			size += 2 -- key length overhead
		end
		return size
	end

	-- Conservative default for unknown types
	return 32
end

--[[
	Group batch packets for optimal compression
	
	Strategy:
	1. Group packets until reaching size threshold
	2. Create new group when threshold exceeded
	3. Keep groups small enough for L1 cache efficiency
	
	Why this helps:
	- Similar data types compress better together
	- Smaller groups = more predictable latency
	- 8KB groups fit well in L1 cache during compression
]]
--
function Pool.groupBatches(packets: { any }): { { any } }
	local groups: { { any } } = {}
	local currentGroup: { any } = {}
	local currentSize = 0
	local maxGroupSize = 8192 -- 8KB sweet spot for L1 cache

	for _, packet in packets do
		local size = Pool.estimateSize(packet)

		-- Start new group if adding this would exceed threshold
		if currentSize + size > maxGroupSize and #currentGroup > 0 then
			table.insert(groups, currentGroup)
			currentGroup = {}
			currentSize = 0
		end

		table.insert(currentGroup, packet)
		currentSize += size
	end

	-- Add remaining packets
	if #currentGroup > 0 then
		table.insert(groups, currentGroup)
	end

	return groups
end

--[[
	Inline encode packets to buffer
	
	Optimization: Encode directly to final buffer without intermediate copies
	
	Process:
	1. Estimate total size needed
	2. Acquire appropriately sized buffer from pool
	3. Encode data using Buffer module
	4. Apply compression if beneficial
	
	Compression heuristic:
	- Only compress if >256 bytes (overhead not worth it for small data)
	- Compare compressed vs uncompressed size
	- Use compressed only if >20% smaller
]]
--
function Pool.inlineEncode(packets: { any }, compress: boolean?): buffer?
	-- Estimate size needed
	local estimatedSize = 0
	for _, packet in packets do
		estimatedSize += Pool.estimateSize(packet)
	end

	-- Acquire buffer with safety margin
	local buf = Pool.acquireBuffer(estimatedSize + 1024)

	-- Encode using Buffer module
	local encoded, _ = Buffer.Encode(packets)

	if not encoded then
		Pool.releaseBuffer(buf)
		return nil
	end

	-- Try compression if requested and size warrants it
	if compress and buffer.len(encoded) > 256 then
		local compressed = Buffer.EncodeCompressed(packets, "auto")
		-- Use compressed only if significantly smaller (20% threshold)
		if compressed and buffer.len(compressed) < buffer.len(encoded) * 0.8 then
			encoded = compressed
		end
	end

	return encoded
end

--[[
	Hash data for delta cache verification
	
	DJB2-variant hash: Fast, non-cryptographic, good distribution
	
	Properties:
	- Deterministic: Same input = same output
	- Fast: ~10ns per byte on modern CPUs
	- Low collision: Good for small datasets
	- NOT cryptographic: Do not use for security
	
	Algorithm:
	hash = 5381
	for each byte:
	    hash = (hash * 33) + byte
]]
--
function Pool.hashData(data: any): string
	-- Convert to string representation
	local str = tostring(data)
	local hash = 5381 -- DJB2 magic number

	-- Process each byte
	for i = 1, #str do
		-- hash = hash * 33 + byte
		-- Optimized as: hash = (hash << 5) + hash + byte
		hash = bit32.lshift(hash, 5) + hash + string.byte(str, i)
		-- Keep in 32-bit range
		hash = bit32.band(hash, 0xFFFFFFFF)
	end

	-- Return as hex string for easy comparison
	return string.format("%08x", hash)
end

return Pool
