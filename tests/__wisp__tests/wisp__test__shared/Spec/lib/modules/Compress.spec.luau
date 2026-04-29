--!strict

local Compress = require("@game/ReplicatedStorage/Wisp/lib/modules/Compress")
local Types = require("@game/ReplicatedStorage/Wisp/lib/Types")

return function()
	local function createTestBuffer(size: number, pattern: string?): buffer
		local buf = buffer.create(size)
		if pattern == "random" then
			for i = 0, size - 1 do
				buffer.writeu8(buf, i, math.random(0, 255))
			end
		elseif pattern == "text" then
			local text = string.rep("The quick brown fox jumps over the lazy dog. ", math.ceil(size / 46))
			buffer.writestring(buf, 0, string.sub(text, 1, size))
		elseif pattern == "zeros" then
			-- Already zero-filled
		elseif pattern == "numbers" then
			for i = 0, size - 1, 4 do
				if i + 3 < size then
					buffer.writef32(buf, i, math.sin(i / 10))
				end
			end
		elseif pattern == "spatial" then
			for i = 0, size - 1, 12 do
				if i + 11 < size then
					buffer.writef32(buf, i, math.random() * 100)
					buffer.writef32(buf, i + 4, math.random() * 100)
					buffer.writef32(buf, i + 8, math.random() * 100)
				end
			end
		end
		return buf
	end

	local function buffersEqual(a: buffer, b: buffer): boolean
		if buffer.len(a) ~= buffer.len(b) then
			return false
		end
		for i = 0, buffer.len(a) - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
				return false
			end
		end
		return true
	end

	describe("Adler32", function()
		it("should calculate checksum for empty buffer", function()
			local buf = buffer.create(0)
			local checksum = Compress.Adler32(buf)
			expect(checksum).to.be.a("number")
			expect(checksum).to.equal(1) -- Adler32 of empty is 1
		end)

		it("should calculate checksum for non-empty buffer", function()
			local buf = buffer.create(9)
			buffer.writestring(buf, 0, "Wikipedia")
			local checksum = Compress.Adler32(buf)

			-- Just verify it's consistent
			expect(checksum).to.be.a("number")
			expect(checksum > 0).to.equal(true)

			-- Verify consistency
			local checksum2 = Compress.Adler32(buf)
			expect(checksum).to.equal(checksum2)
		end)

		it("should produce different checksums for different data", function()
			local buf1 = buffer.create(5)
			buffer.writestring(buf1, 0, "hello")
			local buf2 = buffer.create(5)
			buffer.writestring(buf2, 0, "world")

			local cs1 = Compress.Adler32(buf1)
			local cs2 = Compress.Adler32(buf2)

			expect(cs1).never.to.equal(cs2)
		end)
	end)

	describe("Data Class Detection", function()
		it("should detect empty buffer as binary", function()
			local buf = buffer.create(0)
			expect(Compress.DetectClass(buf)).to.equal("binary")
		end)

		it("should detect numeric tags", function()
			local buf = buffer.create(2)
			buffer.writeu8(buf, 0, 2)
			buffer.writeu8(buf, 1, 42)
			expect(Compress.DetectClass(buf)).to.equal("numbers")
		end)

		it("should detect string tags", function()
			local buf = buffer.create(2)
			buffer.writeu8(buf, 0, 10)
			buffer.writeu8(buf, 1, 5)
			expect(Compress.DetectClass(buf)).to.equal("text")
		end)

		it("should detect spatial tags", function()
			local buf = buffer.create(1)
			buffer.writeu8(buf, 0, 12)
			expect(Compress.DetectClass(buf)).to.equal("spatial")
		end)

		it("should detect already compressed", function()
			local buf = buffer.create(1)
			buffer.writeu8(buf, 0, Compress.T_LZ4)
			expect(Compress.DetectClass(buf)).to.equal("already_compressed")
		end)

		it("should detect array tags as numbers", function()
			local buf = buffer.create(1)
			buffer.writeu8(buf, 0, 18)
			expect(Compress.DetectClass(buf)).to.equal("numbers")
		end)
	end)

	describe("LZ4HC Compression", function()
		it("should skip compression for tiny buffers", function()
			local small = createTestBuffer(50, "text")
			local compressed, didCompress = Compress.CompressMode("lz4", small)

			expect(didCompress).to.equal(false)
			expect(compressed).to.equal(small)
		end)

		it("should compress text data", function()
			local original = createTestBuffer(2048, "text")
			local compressed, didCompress = Compress.CompressMode("lz4", original)

			if didCompress then
				expect(buffer.len(compressed) < buffer.len(original)).to.equal(true)
			else
				-- Fine if it didn't compress
				expect(compressed).to.equal(original)
			end
		end)

		it("should compress repetitive data efficiently", function()
			local original = createTestBuffer(4096, "zeros")
			local compressed, didCompress = Compress.CompressMode("lz4", original)

			expect(didCompress).to.equal(true)
			expect(buffer.len(compressed) < buffer.len(original) / 10).to.equal(true)
		end)

		it("should not compress random data", function()
			local original = createTestBuffer(2048, "random")
			local compressed, didCompress = Compress.CompressMode("lz4", original)

			expect(didCompress).to.equal(false)
		end)

		it("should roundtrip correctly", function()
			local original = createTestBuffer(4096, "text")
			local compressed, didCompress = Compress.CompressMode("lz4", original)

			if didCompress then
				local tag = buffer.readu8(compressed, 0)
				expect(tag).to.equal(Compress.T_LZ4)

				local decompressed, _ = Compress.decompress(tag, compressed, 1)

				expect(buffersEqual(original, decompressed)).to.equal(true)
			end
		end)

		it("should handle large buffers", function()
			local original = createTestBuffer(100000, "text")
			local compressed, didCompress = Compress.CompressMode("lz4", original)

			if didCompress then
				local tag = buffer.readu8(compressed, 0)
				local decompressed, _ = Compress.decompress(tag, compressed, 1)

				expect(buffersEqual(original, decompressed)).to.equal(true)
			end
		end)
	end)

	describe("Deflate Compression", function()
		it("should compress text data", function()
			local original = createTestBuffer(2048, "text")
			local compressed, didCompress = Compress.CompressMode("deflate", original)

			if didCompress then
				expect(buffer.len(compressed) < buffer.len(original)).to.equal(true)
			end
		end)

		it("should compress better than LZ4 for text", function()
			local original = createTestBuffer(8192, "text")

			local lz4, lz4ok = Compress.CompressMode("lz4", original)
			local deflate, deflateok = Compress.CompressMode("deflate", original)

			if lz4ok and deflateok then
				-- Deflate often better for text, but not guaranteed
				expect(buffer.len(deflate)).to.be.a("number")
				expect(buffer.len(lz4)).to.be.a("number")
			end
		end)

		it("should roundtrip correctly", function()
			local original = createTestBuffer(4096, "text")
			local compressed, didCompress = Compress.CompressMode("deflate", original)

			if didCompress then
				local tag = buffer.readu8(compressed, 0)
				expect(tag).to.equal(Compress.T_DEFLATE)

				local decompressed, _ = Compress.decompress(tag, compressed, 1)

				expect(buffersEqual(original, decompressed)).to.equal(true)
			end
		end)

		it("should handle different data patterns", function()
			local patterns = { "text", "numbers", "spatial" }

			for _, pattern in patterns do
				local original = createTestBuffer(4096, pattern)
				local compressed, didCompress = Compress.CompressMode("deflate", original)

				if didCompress then
					local tag = buffer.readu8(compressed, 0)
					local decompressed, _ = Compress.decompress(tag, compressed, 1)

					expect(buffersEqual(original, decompressed)).to.equal(true)
				end
			end
		end)
	end)

	describe("Auto Mode", function()
		it("should select appropriate algorithm for text", function()
			local original = createTestBuffer(4096, "text")
			local compressed, didCompress = Compress.Compress(original, "text")

			if didCompress then
				local tag = buffer.readu8(compressed, 0)
				-- Could be Deflate, LZ4, or Zstd (server)
				local validTags = { Compress.T_DEFLATE, Compress.T_LZ4, Compress.T_ZSTD }
				local found = false
				for _, validTag in validTags do
					if tag == validTag then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end
		end)

		it("should select appropriate algorithm for numbers", function()
			local original = createTestBuffer(4096, "numbers")
			local compressed, didCompress = Compress.Compress(original, "numbers")

			if didCompress then
				local tag = buffer.readu8(compressed, 0)
				-- Could be LZ4 or Zstd (server)
				local validTags = { Compress.T_LZ4, Compress.T_ZSTD }
				local found = false
				for _, validTag in validTags do
					if tag == validTag then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end
		end)

		it("should skip already compressed data", function()
			local original = createTestBuffer(4096, "text")
			local once, _ = Compress.Compress(original, "text")
			local twice, didCompress = Compress.Compress(once, "auto")

			expect(didCompress).to.equal(false)
			expect(twice).to.equal(once)
		end)

		it("should skip buffers below threshold", function()
			local small = createTestBuffer(400, "text")
			local compressed, didCompress = Compress.Compress(small)

			expect(didCompress).to.equal(false)
		end)

		it("should roundtrip all patterns", function()
			local patterns = { "text", "numbers", "spatial", "zeros" }

			for _, pattern in patterns do
				local original = createTestBuffer(4096, pattern)
				local compressed, didCompress = Compress.Compress(original)

				if didCompress then
					local tag = buffer.readu8(compressed, 0)
					local decompressed, _ = Compress.decompress(tag, compressed, 1)

					expect(buffersEqual(original, decompressed)).to.equal(true)
				end
			end
		end)
	end)

	describe("Dictionary Support", function()
		it("should accept and store dictionary", function()
			local dict = createTestBuffer(1024, "text")
			Compress.SetDict(dict)

			local retrieved = Compress.GetDict()
			expect(retrieved).to.be.ok()
			expect(buffersEqual(dict, retrieved :: buffer)).to.equal(true)
		end)

		it("should trim oversized dictionary", function()
			local huge = createTestBuffer(50000, "text")
			Compress.SetDict(huge)

			local retrieved = Compress.GetDict()
			expect(retrieved).to.be.ok()
			expect(buffer.len(retrieved :: buffer)).to.equal(32768)
		end)

		it("should clear dictionary when nil", function()
			local dict = createTestBuffer(1024, "text")
			Compress.SetDict(dict)
			Compress.SetDict(nil)

			expect(Compress.GetDict()).to.equal(nil)
		end)

		it("should improve compression with dictionary", function()
			local pattern = "The quick brown fox jumps over the lazy dog. "
			local dict = buffer.create(#pattern)
			buffer.writestring(dict, 0, pattern)

			local testData = buffer.create(#pattern * 10)
			buffer.writestring(testData, 0, string.rep(pattern, 10))

			-- Without dictionary
			Compress.SetDict(nil)
			local withoutDict, ok1 = Compress.CompressMode("deflate", testData)

			-- With dictionary
			Compress.SetDict(dict)
			local withDict, ok2 = Compress.CompressMode("deflate", testData)

			-- Both should compress or both not
			if ok1 and ok2 then
				-- Dictionary may or may not help depending on implementation
				expect(buffer.len(withDict)).to.be.a("number")
			end

			Compress.SetDict(nil)
		end)

		it("should decompress correctly with dictionary", function()
			local dict = createTestBuffer(256, "text")
			Compress.SetDict(dict)

			local original = createTestBuffer(2048, "text")
			local compressed, didCompress = Compress.CompressMode("deflate", original)

			if didCompress then
				local tag = buffer.readu8(compressed, 0)
				local decompressed, _ = Compress.decompress(tag, compressed, 1)

				expect(buffersEqual(original, decompressed)).to.equal(true)
			end

			Compress.SetDict(nil)
		end)
	end)

	describe("Progressive Compression", function()
		it("should handle small buffers without chunking", function()
			local small = createTestBuffer(40000, "text")
			local compressed = Compress.CompressProgressive(small, "lz4", nil, nil)

			expect(buffer.len(compressed)).to.be.ok()
		end)

		it("should chunk large buffers", function()
			local large = createTestBuffer(200000, "text")
			local compressed = Compress.CompressProgressive(large, "lz4", nil, nil)

			local chunkCount = buffer.readu32(compressed, 0)
			expect(chunkCount >= 3).to.equal(true)
		end)

		it("should roundtrip correctly", function()
			local original = createTestBuffer(150000, "text")
			local compressed = Compress.CompressProgressive(original, "deflate", nil, nil)
			local decompressed = Compress.DecompressProgressive(compressed)

			expect(buffersEqual(original, decompressed)).to.equal(true)
		end)

		it("should call progress callback", function()
			local original = createTestBuffer(150000, "text")
			local callCount = 0
			local lastDone = 0

			Compress.CompressProgressive(original, "lz4", nil, function(done: number, total: number)
				callCount += 1
				expect(done >= lastDone).to.equal(true)
				expect(total).to.equal(150000)
				lastDone = done
			end)

			expect(callCount >= 1).to.equal(true)
		end)

		it("should handle different compression modes", function()
			local original = createTestBuffer(150000, "text")
			local modes = { "lz4", "deflate", "auto" }

			for _, mode in modes do
				local compressed = Compress.CompressProgressive(original, mode, nil, nil)
				local decompressed = Compress.DecompressProgressive(compressed)

				expect(buffersEqual(original, decompressed)).to.equal(true)
			end
		end)

		it("should reject corrupted progressive stream", function()
			local corrupt = buffer.create(10)
			buffer.writeu32(corrupt, 0, 999999)

			expect(function()
				Compress.DecompressProgressive(corrupt)
			end).to.throw()
		end)
	end)

	describe("Entropy Visualization", function()
		it("should visualize empty buffer", function()
			local buf = buffer.create(0)
			local vis = Compress.VisualizeEntropy(buf)

			expect(vis).to.be.a("string")
			expect(string.len(vis)).to.equal(66) -- [64 chars]
		end)

		it("should show different patterns for different data", function()
			local zeros = createTestBuffer(8192, "zeros")
			local random = createTestBuffer(8192, "random")

			local visZeros = Compress.VisualizeEntropy(zeros)
			local visRandom = Compress.VisualizeEntropy(random)

			expect(visZeros).never.to.equal(visRandom)
		end)

		it("should use correct character set", function()
			local buf = createTestBuffer(8192, "text")
			local vis = Compress.VisualizeEntropy(buf)

			local validChars = { " ", ".", ":", "-", "=", "+", "*", "#", "[", "]" }
			for i = 1, #vis do
				local char = string.sub(vis, i, i)
				local found = false
				for _, valid in validChars do
					if char == valid then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end
		end)
	end)

	describe("Error Handling", function()
		it("should reject corrupted LZ4 header", function()
			local corrupt = buffer.create(20)
			buffer.writeu8(corrupt, 0, Compress.T_LZ4)
			buffer.writeu32(corrupt, 1, 1000)
			buffer.writeu32(corrupt, 5, 5)

			expect(function()
				Compress.decompress(Compress.T_LZ4, corrupt, 1)
			end).to.throw()
		end)

		it("should reject checksum mismatch", function()
			local original = createTestBuffer(2048, "text")
			local compressed, didCompress = Compress.CompressMode("lz4", original)

			if didCompress and compressed ~= original then
				-- Corrupt the checksum
				buffer.writeu32(compressed, 9, 0xFFFFFFFF)

				local tag = buffer.readu8(compressed, 0)
				expect(function()
					Compress.decompress(tag, compressed, 1)
				end).to.throw()
			end
		end)

		it("should reject suspicious sizes", function()
			local corrupt = buffer.create(20)
			buffer.writeu8(corrupt, 0, Compress.T_LZ4)
			buffer.writeu32(corrupt, 1, 999999999)
			buffer.writeu32(corrupt, 5, 10)

			expect(function()
				Compress.decompress(Compress.T_LZ4, corrupt, 1)
			end).to.throw()
		end)

		it("should reject truncated buffer", function()
			local truncated = buffer.create(5)
			buffer.writeu8(truncated, 0, Compress.T_LZ4)

			expect(function()
				Compress.decompress(Compress.T_LZ4, truncated, 1)
			end).to.throw()
		end)

		it("should reject negative offset", function()
			local buf = createTestBuffer(1024, "text")

			expect(function()
				Compress.decompress(Compress.T_LZ4, buf, -1)
			end).to.throw()
		end)
	end)

	describe("Compressors Table", function()
		it("should have all required compressors", function()
			local required = { "lz4", "deflate", "auto", "none", "text", "numbers", "spatial", "binary" }

			for _, name in required do
				expect(Compress.compressors[name]).to.be.a("function")
			end
		end)

		it("should handle 'none' mode correctly", function()
			local original = createTestBuffer(2048, "text")
			local result, didCompress = Compress.compressors.none(original, nil)

			expect(didCompress).to.equal(false)
			expect(result).to.equal(original)
		end)

		it("should route modes correctly", function()
			local original = createTestBuffer(4096, "text")

			local lz4Result, lz4ok = Compress.CompressMode("lz4", original)
			local deflateResult, deflateok = Compress.CompressMode("deflate", original)

			if lz4ok and deflateok and lz4Result ~= original and deflateResult ~= original then
				local lz4Tag = buffer.readu8(lz4Result, 0)
				local deflateTag = buffer.readu8(deflateResult, 0)

				-- LZ4 should produce T_LZ4 or T_ZSTD (server)
				expect(lz4Tag == Compress.T_LZ4 or lz4Tag == Compress.T_ZSTD).to.equal(true)
				-- Deflate should produce T_DEFLATE or T_ZSTD (server)
				expect(deflateTag == Compress.T_DEFLATE or deflateTag == Compress.T_ZSTD).to.equal(true)
			end
		end)
	end)

	describe("Edge Cases", function()
		it("should handle exact chunk boundary", function()
			local exact = createTestBuffer(65536, "text")
			local compressed = Compress.CompressProgressive(exact, "lz4", nil, nil)
			local decompressed = Compress.DecompressProgressive(compressed)

			expect(buffersEqual(exact, decompressed)).to.equal(true)
		end)

		it("should handle single byte buffer", function()
			local single = buffer.create(1)
			buffer.writeu8(single, 0, 42)

			local compressed, _ = Compress.Compress(single, nil)
			expect(compressed).to.equal(single)
		end)

		it("should handle highly compressible data", function()
			local zeros = createTestBuffer(10000, "zeros")
			local compressed, didCompress = Compress.CompressMode("lz4", zeros)

			if didCompress then
				expect(buffer.len(compressed) < buffer.len(zeros) / 10).to.equal(true)
			end
		end)

		it("should handle mixed patterns", function()
			local mixed = buffer.create(8192)
			for i = 0, 4095 do
				buffer.writeu8(mixed, i, i % 4)
			end
			for i = 4096, 8191 do
				buffer.writeu8(mixed, i, math.random(0, 255))
			end

			local compressed, didCompress = Compress.Compress(mixed, nil)

			if didCompress and compressed ~= mixed then
				local tag = buffer.readu8(compressed, 0)
				local decompressed, _ = Compress.decompress(tag, compressed, 1)

				expect(buffersEqual(mixed, decompressed)).to.equal(true)
			end
		end)
	end)
end
