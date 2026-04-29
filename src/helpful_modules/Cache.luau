--@maneetoo & @crusherfire

--!strict

type CacheEntry<K, V> = {
	Key: K,
	Value: V,
}

type CacheFields<K, V> = {
	_size: number,
	_cache: { CacheEntry<K, V> },
	_lookup: { [K]: number },
	_hits: number,
	_misses: number,
}

local CacheClass = {}
local MT = {}

MT.__index = MT
MT.__newindex = function()
	error("[Cache] Unable to set a new value directly in CacheType object!")
end
MT.__tostring = function(self)
	return string.format("Cache(size=%d/%d, hits=%d, misses=%d)", #self._cache, self._size, self._hits, self._misses)
end

export type CacheType<K = any, V = any> = typeof(setmetatable({} :: CacheFields<K, V>, MT))

--[[
	Updates the lookup mapping for all cache entries starting at startIndex.
	Called after removing an entry to maintain correct index references
]]
local function updateLookupFrom<K, V>(self: CacheType<K, V>, startIndex: number)
	local cache = self._cache
	local lookup = self._lookup
	for i = startIndex, #cache do
		local entry = cache[i]
		lookup[entry.Key] = i
	end
end

--[[
	Creates a new LRU cache with the specified maximum size
]]
function CacheClass.new<K, V>(size: number?): CacheType<K, V>
	local actualSize = size or 100
	assert(actualSize > 0, "[Cache] size must be positive")

	local self: CacheFields<K, V> = {
		_size = actualSize,
		_cache = table.create(actualSize),
		_lookup = {},
		_hits = 0,
		_misses = 0,
	}

	return setmetatable(self, MT) :: any
end

--[[
	Retrieves a value from the cache by key
]]
function MT.Get<K, V>(self: CacheType<K, V>, key: K): (V?, number?)
	assert(key ~= nil, "[Cache] Key must be non-nil")

	local index = self._lookup[key]
	if index then
		self._hits += 1
		return self._cache[index].Value, index
	end

	self._misses += 1
	return nil, nil
end

--[[
	Sets or updates a value in the cache.
	
	• If the key exists, updates the value and moves it to the end (most recent)
	• If the key is new and cache is at capacity, evicts the oldest entry
	• Passing nil as value removes the entry from the cache
	
]]
function MT.Set<K, V>(self: CacheType<K, V>, key: K, value: V?)
	assert(key ~= nil, "[Cache] Key must be non-nil")

	local isNilValue = (value == nil)
	local existingIndex = self._lookup[key]

	if existingIndex then
		-- Key exists: remove from current position
		local entry = table.remove(self._cache, existingIndex)
		self._lookup[key] = nil
		updateLookupFrom(self, existingIndex)

		-- Re-add at end if value is not nil (updates position to most recent)
		if not isNilValue and entry then
			entry.Value = value :: V
			table.insert(self._cache, entry)
			self._lookup[key] = #self._cache
		end
	elseif not isNilValue then
		-- New key with value: add to cache
		local entry: CacheEntry<K, V> = {
			Key = key,
			Value = value :: V,
		}

		-- Evict oldest if at capacity
		if #self._cache >= self._size then
			local removed = table.remove(self._cache, 1)
			if removed then
				self._lookup[removed.Key] = nil
				updateLookupFrom(self, 1)
			end
		end

		table.insert(self._cache, entry)
		self._lookup[key] = #self._cache
	end
	-- If isNilValue and key doesn't exist, do nothing
end

--[[
	Checks if a key exists in the cache.
	Does NOT update the entry's position (no LRU side effect)
]]
function MT.Contains<K, V>(self: CacheType<K, V>, key: K): boolean
	assert(key ~= nil, "[Cache] Key must be non-nil")
	return self._lookup[key] ~= nil
end

--[[
	Returns the current number of entries in the cache
]]
function MT.GetCount<K, V>(self: CacheType<K, V>): number
	return #self._cache
end

--[[
	Returns the maximum capacity of the cache
]]
function MT.GetCapacity<K, V>(self: CacheType<K, V>): number
	return self._size
end

--[[
	Checks if the cache is at maximum capacity
]]
function MT.IsFull<K, V>(self: CacheType<K, V>): boolean
	return #self._cache >= self._size
end

--[[
	Clears all entries from the cache.
	Resets hit/miss statistics
]]
function MT.Clear<K, V>(self: CacheType<K, V>)
	table.clear(self._cache)
	table.clear(self._lookup)
	self._hits = 0
	self._misses = 0
end

--[[
	Returns all keys currently in the cache.
	Keys are returned in order from oldest to newest
]]
function MT.GetKeys<K, V>(self: CacheType<K, V>): { K }
	local keys = table.create(#self._cache)
	for i, entry in ipairs(self._cache) do
		keys[i] = entry.Key
	end
	return keys
end

--[[
	Iterates over all entries in the cache.
	Entries are visited from oldest to newest
]]
function MT.ForEach<K, V>(self: CacheType<K, V>, callback: (key: K, value: V) -> ())
	for _, entry in ipairs(self._cache) do
		callback(entry.Key, entry.Value)
	end
end

--[[
	Removes and returns the oldest entry from the cache.
	Useful for manual eviction
]]
function MT.EvictOldest<K, V>(self: CacheType<K, V>): (K?, V?)
	if #self._cache == 0 then
		return nil, nil
	end

	local entry = table.remove(self._cache, 1)
	if entry then
		self._lookup[entry.Key] = nil
		updateLookupFrom(self, 1)
		return entry.Key, entry.Value
	end

	return nil, nil
end

--[[
	Resizes the cache to a new maximum capacity.
	If the new size is smaller, evicts oldest entries until within capacity
]]
function MT.Resize<K, V>(self: CacheType<K, V>, newSize: number)
	assert(newSize > 0, "[Cache] newSize must be positive")

	-- Evict entries if shrinking
	while #self._cache > newSize do
		self:EvictOldest()
	end

	self._size = newSize
end

return CacheClass
