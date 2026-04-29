--!strict

local Cache = require("@game/ReplicatedStorage/Wisp/helpful_modules/Cache")

return function()
	describe("Basic Operations", function()
		it("should create cache", function()
			local cache = Cache.new(10)
			expect(cache).to.be.ok()
		end)

		it("should set and get value", function()
			local cache = Cache.new(10)
			cache:Set("key", "value")
			expect(cache:Get("key")).to.equal("value")
		end)

		it("should return nil for missing key", function()
			local cache = Cache.new(10)
			expect(cache:Get("missing")).to.equal(nil)
		end)

		it("should update existing value", function()
			local cache = Cache.new(10)
			cache:Set("key", "old")
			cache:Set("key", "new")
			expect(cache:Get("key")).to.equal("new")
		end)

		it("should remove with nil value", function()
			local cache = Cache.new(10)
			cache:Set("key", "value")
			cache:Set("key", nil)
			expect(cache:Get("key")).to.equal(nil)
		end)
	end)

	describe("LRU Eviction", function()
		it("should evict oldest when full", function()
			local cache = Cache.new(2)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")
			cache:Set("key3", "value3")

			expect(cache:Get("key1")).to.equal(nil)
			expect(cache:Get("key2")).to.equal("value2")
			expect(cache:Get("key3")).to.equal("value3")
		end)

		it("should move updated item to end", function()
			local cache = Cache.new(2)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")
			cache:Set("key1", "updated")
			cache:Set("key3", "value3")

			expect(cache:Get("key2")).to.equal(nil)
			expect(cache:Get("key1")).to.equal("updated")
		end)
	end)

	describe("Contains", function()
		it("should check existence", function()
			local cache = Cache.new(10)
			cache:Set("key", "value")

			expect(cache:Contains("key")).to.equal(true)
			expect(cache:Contains("missing")).to.equal(false)
		end)

		it("should not affect order", function()
			local cache = Cache.new(2)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")
			cache:Contains("key1")
			cache:Set("key3", "value3")

			expect(cache:Get("key1")).to.equal(nil)
		end)
	end)

	describe("Capacity", function()
		it("should track count", function()
			local cache = Cache.new(5)
			expect(cache:GetCount()).to.equal(0)

			cache:Set("key1", "value1")
			expect(cache:GetCount()).to.equal(1)

			cache:Set("key2", "value2")
			expect(cache:GetCount()).to.equal(2)
		end)

		it("should detect full", function()
			local cache = Cache.new(2)
			expect(cache:IsFull()).to.equal(false)

			cache:Set("key1", "value1")
			cache:Set("key2", "value2")
			expect(cache:IsFull()).to.equal(true)
		end)
	end)

	describe("Clear", function()
		it("should remove all entries", function()
			local cache = Cache.new(10)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")
			cache:Clear()

			expect(cache:GetCount()).to.equal(0)
			expect(cache:Get("key1")).to.equal(nil)
		end)
	end)

	describe("GetKeys", function()
		it("should return all keys", function()
			local cache = Cache.new(10)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")

			local keys = cache:GetKeys()
			expect(#keys).to.equal(2)
			expect(keys[1]).to.equal("key1")
			expect(keys[2]).to.equal("key2")
		end)
	end)

	describe("ForEach", function()
		it("should iterate entries", function()
			local cache = Cache.new(10)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")

			local count = 0
			cache:ForEach(function(_key, _value)
				count += 1
			end)

			expect(count).to.equal(2)
		end)
	end)

	describe("EvictOldest", function()
		it("should remove oldest", function()
			local cache = Cache.new(10)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")

			local key, value = cache:EvictOldest()
			expect(key).to.equal("key1")
			expect(value).to.equal("value1")
			expect(cache:GetCount()).to.equal(1)
		end)
	end)

	describe("Resize", function()
		it("should change capacity", function()
			local cache = Cache.new(5)
			cache:Resize(10)
			expect(cache:GetCapacity()).to.equal(10)
		end)

		it("should evict when shrinking", function()
			local cache = Cache.new(5)
			cache:Set("key1", "value1")
			cache:Set("key2", "value2")
			cache:Set("key3", "value3")

			cache:Resize(2)
			expect(cache:GetCount()).to.equal(2)
			expect(cache:Get("key1")).to.equal(nil)
		end)
	end)
end
