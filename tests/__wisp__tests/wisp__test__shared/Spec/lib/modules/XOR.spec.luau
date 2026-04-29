--!strict

local XOR = require("@game/ReplicatedStorage/Wisp/lib/modules/XOR")

return function()
	describe("XOR.apply", function()
		it("should transform buffer", function()
			local data = buffer.fromstring("Hello, World!")
			local result = XOR.apply(data)

			expect(result).to.be.ok()
			expect(buffer.len(result)).to.equal(buffer.len(data))
		end)

		it("should produce different output than input", function()
			local data = buffer.fromstring("Secret Data")
			local result = XOR.apply(data)

			local original = buffer.tostring(data)
			local encoded = buffer.tostring(result)

			expect(original).never.to.equal(encoded)
		end)

		it("should handle empty buffer", function()
			local data = buffer.create(0)
			local result = XOR.apply(data)

			expect(buffer.len(result)).to.equal(0)
		end)

		it("should handle single byte", function()
			local data = buffer.create(1)
			buffer.writeu8(data, 0, 65)
			local result = XOR.apply(data)

			expect(buffer.len(result)).to.equal(1)
			expect(buffer.readu8(result, 0)).never.to.equal(65)
		end)

		it("should handle large buffer", function()
			local data = buffer.fromstring(string.rep("A", 10000))
			local result = XOR.apply(data)

			expect(buffer.len(result)).to.equal(10000)
		end)

		it("should be symmetric (apply twice = original)", function()
			local original = "Hello, World!"
			local data = buffer.fromstring(original)
			local result = XOR.apply(XOR.apply(data))

			expect(buffer.tostring(result)).to.equal(original)
		end)

		it("should handle multiple apply cycles", function()
			local original = "Cycle Test"
			local data = buffer.fromstring(original)

			local result = data
			for _ = 1, 10 do
				result = XOR.apply(result)
				result = XOR.apply(result)
			end

			expect(buffer.tostring(result)).to.equal(original)
		end)
	end)

	describe("key rotation", function()
		it("should rotate key correctly (24-byte period)", function()
			local data = buffer.create(48)
			for i = 0, 47 do
				buffer.writeu8(data, i, 0x00)
			end

			local result = XOR.apply(data)

			-- Byte 0 and Byte 24 should be same (wraps after 24)
			expect(buffer.readu8(result, 0)).to.equal(buffer.readu8(result, 24))
			expect(buffer.readu8(result, 1)).to.equal(buffer.readu8(result, 25))
			expect(buffer.readu8(result, 23)).to.equal(buffer.readu8(result, 47))
		end)

		it("should handle data shorter than key", function()
			local data = buffer.create(3)
			buffer.writeu8(data, 0, 100)
			buffer.writeu8(data, 1, 100)
			buffer.writeu8(data, 2, 100)

			local result = XOR.apply(data)

			expect(buffer.len(result)).to.equal(3)
			-- Each byte XORed with different key byte
			expect(buffer.readu8(result, 0)).never.to.equal(0)
			expect(buffer.readu8(result, 1)).never.to.equal(0)
			expect(buffer.readu8(result, 2)).never.to.equal(0)
		end)
	end)

	describe("byte patterns", function()
		it("should transform all zero bytes", function()
			local data = buffer.create(10)
			for i = 0, 9 do
				buffer.writeu8(data, i, 0)
			end

			local result = XOR.apply(data)
			local hasNonZero = false

			for i = 0, 9 do
				if buffer.readu8(result, i) ~= 0 then
					hasNonZero = true
					break
				end
			end

			expect(hasNonZero).to.equal(true)
		end)

		it("should transform all 0xFF bytes", function()
			local data = buffer.create(10)
			for i = 0, 9 do
				buffer.writeu8(data, i, 0xFF)
			end

			local result = XOR.apply(data)
			local hasNonFF = false

			for i = 0, 9 do
				if buffer.readu8(result, i) ~= 0xFF then
					hasNonFF = true
					break
				end
			end

			expect(hasNonFF).to.equal(true)
		end)

		it("should create different patterns for repeated bytes", function()
			local data = buffer.fromstring(string.rep("A", 20))
			local result = XOR.apply(data)

			local uniqueValues = {}
			for i = 0, buffer.len(result) - 1 do
				uniqueValues[buffer.readu8(result, i)] = true
			end

			local count = 0
			for _ in uniqueValues do
				count += 1
			end

			-- At least 2 different values (not all same)
			expect(count > 1).to.equal(true)
		end)
	end)

	describe("integration", function()
		it("should work with binary data", function()
			local data = buffer.create(256)
			for i = 0, 255 do
				buffer.writeu8(data, i, i)
			end

			local result = XOR.apply(data)
			local restored = XOR.apply(result)

			for i = 0, 255 do
				expect(buffer.readu8(restored, i)).to.equal(i)
			end
		end)

		it("should preserve buffer size exactly", function()
			for size = 1, 100 do
				local data = buffer.create(size)
				local result = XOR.apply(data)

				expect(buffer.len(result)).to.equal(size)
			end
		end)

		it("should be deterministic", function()
			local data = buffer.fromstring("Deterministic Test")
			local result1 = XOR.apply(data)
			local result2 = XOR.apply(data)

			expect(buffer.tostring(result1)).to.equal(buffer.tostring(result2))
		end)

		it("should handle 24-byte boundary", function()
			-- Test exact key length boundary
			local data = buffer.create(24)
			for i = 0, 23 do
				buffer.writeu8(data, i, i)
			end

			local result = XOR.apply(data)
			local restored = XOR.apply(result)

			for i = 0, 23 do
				expect(buffer.readu8(restored, i)).to.equal(i)
			end
		end)

		it("should handle 48-byte data (2 key periods)", function()
			local data = buffer.create(48)
			for i = 0, 47 do
				buffer.writeu8(data, i, i % 256)
			end

			local result = XOR.apply(data)
			local restored = XOR.apply(result)

			for i = 0, 47 do
				expect(buffer.readu8(restored, i)).to.equal(i % 256)
			end
		end)
	end)
end
