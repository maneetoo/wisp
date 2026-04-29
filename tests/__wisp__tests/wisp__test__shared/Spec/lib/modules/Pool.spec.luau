--!strict

local Pool = require("@game/ReplicatedStorage/Wisp/lib/modules/Pool")

return function()
	describe("acquireBuffer", function()
		it("should return buffer of correct tier for small size", function()
			local buf = Pool.acquireBuffer(512)
			expect(buf).to.be.ok()
			expect(buffer.len(buf)).to.equal(1024)
			Pool.releaseBuffer(buf)
		end)

		it("should return buffer of correct tier for medium size", function()
			local buf = Pool.acquireBuffer(8192)
			expect(buf).to.be.ok()
			expect(buffer.len(buf)).to.equal(16384)
			Pool.releaseBuffer(buf)
		end)

		it("should return buffer of correct tier for large size", function()
			local buf = Pool.acquireBuffer(131072)
			expect(buf).to.be.ok()
			expect(buffer.len(buf)).to.equal(262144)
			Pool.releaseBuffer(buf)
		end)

		it("should reuse released buffers", function()
			local buf1 = Pool.acquireBuffer(100)
			local firstPtr = tostring(buf1)
			Pool.releaseBuffer(buf1)

			local buf2 = Pool.acquireBuffer(100)
			local secondPtr = tostring(buf2)

			expect(firstPtr).to.equal(secondPtr)
			Pool.releaseBuffer(buf2)
		end)

		it("should allocate new buffer when pool exhausted", function()
			local buffers = {}
			for i = 1, 15 do
				buffers[i] = Pool.acquireBuffer(100)
			end

			expect(#buffers).to.equal(15)

			for _, buf in buffers do
				Pool.releaseBuffer(buf)
			end
		end)

		it("should not return in-use buffers", function()
			local buf1 = Pool.acquireBuffer(100)
			local buf2 = Pool.acquireBuffer(100)
			local buf3 = Pool.acquireBuffer(100)

			expect(tostring(buf1)).never.to.equal(tostring(buf2))
			expect(tostring(buf2)).never.to.equal(tostring(buf3))
			expect(tostring(buf1)).never.to.equal(tostring(buf3))

			Pool.releaseBuffer(buf1)
			Pool.releaseBuffer(buf2)
			Pool.releaseBuffer(buf3)
		end)
	end)

	describe("releaseBuffer", function()
		it("should mark buffer as available", function()
			local buf = Pool.acquireBuffer(100)
			Pool.releaseBuffer(buf)

			local buf2 = Pool.acquireBuffer(100)
			expect(tostring(buf)).to.equal(tostring(buf2))
			Pool.releaseBuffer(buf2)
		end)

		it("should handle multiple releases safely", function()
			local buf = Pool.acquireBuffer(100)
			Pool.releaseBuffer(buf)
			Pool.releaseBuffer(buf)

			local buf2 = Pool.acquireBuffer(100)
			expect(buf2).to.be.ok()
			Pool.releaseBuffer(buf2)
		end)
	end)

	describe("estimateSize", function()
		it("should estimate number size", function()
			expect(Pool.estimateSize(42)).to.equal(10)
			expect(Pool.estimateSize(3.14)).to.equal(10)
			expect(Pool.estimateSize(-100)).to.equal(10)
		end)

		it("should estimate string size correctly", function()
			expect(Pool.estimateSize("hello")).to.equal(3 + 5)
			expect(Pool.estimateSize(string.rep("a", 300))).to.equal(5 + 300)
		end)

		it("should estimate boolean size", function()
			expect(Pool.estimateSize(true)).to.equal(2)
			expect(Pool.estimateSize(false)).to.equal(2)
		end)

		it("should estimate nil size", function()
			expect(Pool.estimateSize(nil)).to.equal(2)
		end)

		it("should estimate Vector3 size", function()
			expect(Pool.estimateSize(Vector3.new(1, 2, 3))).to.equal(14)
		end)

		it("should estimate Vector2 size", function()
			expect(Pool.estimateSize(Vector2.new(1, 2))).to.equal(10)
		end)

		it("should estimate CFrame size", function()
			expect(Pool.estimateSize(CFrame.new())).to.equal(50)
		end)

		it("should estimate Color3 size", function()
			expect(Pool.estimateSize(Color3.new(1, 0, 0))).to.equal(5)
		end)

		it("should estimate table size recursively", function()
			local size = Pool.estimateSize({
				a = 1,
				b = "test",
			})
			expect(size > 20).to.equal(true)
		end)

		it("should estimate nested table size", function()
			local size = Pool.estimateSize({
				nested = {
					value = 42,
				},
			})
			expect(size > 20).to.equal(true)
		end)

		it("should return default for unknown types", function()
			local size = Pool.estimateSize(workspace)
			expect(size).to.equal(32)
		end)
	end)

	describe("groupBatches", function()
		it("should group small packets into single group", function()
			local packets = {
				{ type = "move", pos = Vector3.new(1, 2, 3) },
				{ type = "jump", value = true },
				{ type = "health", hp = 100 },
			}

			local groups = Pool.groupBatches(packets)
			expect(#groups).to.equal(1)
			expect(#groups[1]).to.equal(3)
		end)

		it("should split large packets into multiple groups", function()
			local packets = {}
			for i = 1, 100 do
				packets[i] = { data = string.rep("x", 100) }
			end

			local groups = Pool.groupBatches(packets)
			expect(#groups > 1).to.equal(true)
		end)

		it("should respect 8KB threshold", function()
			local packets = {}
			for i = 1, 20 do
				packets[i] = { data = string.rep("x", 500) }
			end

			local groups = Pool.groupBatches(packets)

			for _, group in groups do
				local size = 0
				for _, packet in group do
					size += Pool.estimateSize(packet)
				end
				expect(size <= 10000).to.equal(true)
			end
		end)

		it("should handle empty packet list", function()
			local groups = Pool.groupBatches({})
			expect(#groups).to.equal(0)
		end)

		it("should handle single packet", function()
			local groups = Pool.groupBatches({ { value = 42 } })
			expect(#groups).to.equal(1)
			expect(#groups[1]).to.equal(1)
		end)
	end)

	describe("inlineEncode", function()
		it("should encode simple data", function()
			local packets = { { value = 42 } }
			local encoded = Pool.inlineEncode(packets, false)

			expect(encoded).to.be.ok()
			expect(buffer.len(encoded :: buffer) > 0).to.equal(true)
		end)

		it("should attempt compression for large data", function()
			local packets = {}
			for i = 1, 50 do
				packets[i] = { data = string.rep("a", 100) }
			end

			local result = Pool.inlineEncode(packets, true)
			expect(result).to.be.ok()
		end)

		it("should not compress small data", function()
			local packets = { { value = 1 } }
			local result = Pool.inlineEncode(packets, true)

			expect(result).to.be.ok()
			expect(buffer.len(result :: buffer) <= 300).to.equal(true)
		end)

		it("should return nil on encode failure", function()
			local packets = { { func = function() end } }
			local result = Pool.inlineEncode(packets, false)

			expect(result).never.to.be.ok()
		end)

		it("should handle empty packet list", function()
			local result = Pool.inlineEncode({}, false)
			expect(result).to.be.ok()
		end)
	end)

	describe("hashData", function()
		it("should produce consistent hash for same input", function()
			local data = { a = 1, b = 2, c = 3 }
			local hash1 = Pool.hashData(data)
			local hash2 = Pool.hashData(data)

			expect(hash1).to.equal(hash2)
		end)

		it("should produce different hash for different input", function()
			local hash1 = Pool.hashData({ a = 1 })
			local hash2 = Pool.hashData({ a = 2 })

			expect(hash1).never.to.equal(hash2)
		end)

		it("should return 8-character hex string", function()
			local hash = Pool.hashData("test")
			expect(#hash).to.equal(8)
			expect(hash:match("^%x+$")).to.be.ok()
		end)

		it("should handle nil", function()
			local hash = Pool.hashData(nil)
			expect(hash).to.be.ok()
			expect(#hash).to.equal(8)
		end)

		it("should handle numbers", function()
			local hash = Pool.hashData(42)
			expect(hash).to.be.ok()
			expect(#hash).to.equal(8)
		end)

		it("should handle strings", function()
			local hash = Pool.hashData("hello world")
			expect(hash).to.be.ok()
			expect(#hash).to.equal(8)
		end)

		it("should handle tables", function()
			local hash = Pool.hashData({ x = 1, y = 2, z = 3 })
			expect(hash).to.be.ok()
			expect(#hash).to.equal(8)
		end)

		it("should handle empty string", function()
			local hash = Pool.hashData("")
			expect(hash).to.be.ok()
			expect(#hash).to.equal(8)
		end)

		it("should produce different hashes for similar data", function()
			local hash1 = Pool.hashData("test1")
			local hash2 = Pool.hashData("test2")
			local hash3 = Pool.hashData("test3")

			expect(hash1).never.to.equal(hash2)
			expect(hash2).never.to.equal(hash3)
			expect(hash1).never.to.equal(hash3)
		end)
	end)

	describe("integration", function()
		it("should handle full acquire-encode-release cycle", function()
			local buf = Pool.acquireBuffer(1000)
			expect(buf).to.be.ok()

			local data = { value = 42, name = "test" }
			local encoded = Pool.inlineEncode({ data }, false)
			expect(encoded).to.be.ok()

			Pool.releaseBuffer(buf)

			local buf2 = Pool.acquireBuffer(1000)
			expect(tostring(buf)).to.equal(tostring(buf2))
			Pool.releaseBuffer(buf2)
		end)

		it("should handle multiple concurrent buffers", function()
			local bufs = {}
			for i = 1, 5 do
				bufs[i] = Pool.acquireBuffer(100 * i)
			end

			for _, buf in bufs do
				expect(buf).to.be.ok()
			end

			for _, buf in bufs do
				Pool.releaseBuffer(buf)
			end
		end)
	end)
end
