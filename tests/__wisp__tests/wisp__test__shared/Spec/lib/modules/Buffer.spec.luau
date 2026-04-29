--!strict

local Buffer = require("@game/ReplicatedStorage/Wisp/lib/modules/Buffer")

return function()
	describe("Basic Encoding/Decoding", function()
		it("should encode and decode nil", function()
			local encoded, err = Buffer.Encode(false)
			expect(err).to.equal(nil)
			expect(encoded).to.be.ok()

			local decoded = Buffer.Decode(encoded :: buffer)
			expect(decoded).to.equal(false)
		end)

		it("should encode and decode booleans", function()
			local trueEncoded = Buffer.Encode(true)
			local falseEncoded = Buffer.Encode(false)

			expect(Buffer.Decode(trueEncoded :: buffer)).to.equal(true)
			expect(Buffer.Decode(falseEncoded :: buffer)).to.equal(false)
		end)

		it("should encode and decode numbers", function()
			local cases = { 0, 1, 42, 255, 256, 65535, -1, -128, 3.14, math.huge, -math.huge }

			for _, num in cases do
				local encoded = Buffer.Encode(num)
				expect(encoded).to.be.ok()
				local decoded = Buffer.Decode(encoded :: buffer)
				expect(decoded).to.equal(num)
			end
		end)

		it("should encode and decode strings", function()
			local cases = { "", "hello", "a", string.rep("x", 255), string.rep("y", 1000) }

			for _, str in cases do
				local encoded = Buffer.Encode(str)
				expect(encoded).to.be.ok()
				expect(Buffer.Decode(encoded :: buffer)).to.equal(str)
			end
		end)

		it("should reject nil as input", function()
			local _, err = Buffer.Encode(nil :: any)
			expect(err).to.be.ok()
			expect(err:find("nil")).to.be.ok()
		end)
	end)

	describe("Roblox Types", function()
		it("should encode Vector3", function()
			local v = Vector3.new(1, 2, 3)
			local encoded = Buffer.Encode(v)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.X).to.equal(v.X)
			expect(decoded.Y).to.equal(v.Y)
			expect(decoded.Z).to.equal(v.Z)
		end)

		it("should encode Vector2", function()
			local v = Vector2.new(5, 10)
			local encoded = Buffer.Encode(v)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.X).to.equal(v.X)
			expect(decoded.Y).to.equal(v.Y)
		end)

		it("should encode CFrame", function()
			local cf = CFrame.new(1, 2, 3) * CFrame.Angles(0.5, 1, 1.5)
			local encoded = Buffer.Encode(cf)
			local decoded = Buffer.Decode(encoded :: buffer)

			local delta = (decoded.Position - cf.Position).Magnitude
			expect(delta < 0.01).to.equal(true)
		end)

		it("should encode Color3", function()
			local c = Color3.fromRGB(255, 128, 64)
			local encoded = Buffer.Encode(c)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(math.abs(decoded.R - c.R) < 0.01).to.equal(true)
			expect(math.abs(decoded.G - c.G) < 0.01).to.equal(true)
			expect(math.abs(decoded.B - c.B) < 0.01).to.equal(true)
		end)

		it("should encode UDim2", function()
			local u = UDim2.new(0.5, 10, 0.75, 20)
			local encoded = Buffer.Encode(u)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.X.Scale).to.equal(u.X.Scale)
			expect(decoded.X.Offset).to.equal(u.X.Offset)
			expect(decoded.Y.Scale).to.equal(u.Y.Scale)
			expect(decoded.Y.Offset).to.equal(u.Y.Offset)
		end)

		it("should encode DateTime", function()
			local dt = DateTime.now()
			local encoded = Buffer.Encode(dt)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.UnixTimestampMillis).to.equal(dt.UnixTimestampMillis)
		end)

		it("should encode BrickColor", function()
			local bc = BrickColor.new("Bright red")
			local encoded = Buffer.Encode(bc)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.Number).to.equal(bc.Number)
		end)

		it("should encode EnumItem", function()
			local e = Enum.Material.Plastic
			local encoded = Buffer.Encode(e)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded).to.equal(e)
		end)
	end)

	describe("Tables", function()
		it("should encode simple array", function()
			local arr = { 1, 2, 3, 4, 5 }
			local encoded = Buffer.Encode(arr)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(#decoded).to.equal(5)
			for i = 1, 5 do
				expect(decoded[i]).to.equal(arr[i])
			end
		end)

		it("should encode dictionary", function()
			local dict = { name = "Test", value = 42, flag = true }
			local encoded = Buffer.Encode(dict)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.name).to.equal("Test")
			expect(decoded.value).to.equal(42)
			expect(decoded.flag).to.equal(true)
		end)

		it("should encode nested tables", function()
			local nested = {
				outer = {
					inner = {
						value = 123,
					},
				},
			}

			local encoded = Buffer.Encode(nested)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded.outer.inner.value).to.equal(123)
		end)

		it("should encode mixed tables", function()
			local mixed = { 1, 2, 3, name = "test", flag = true }
			local encoded = Buffer.Encode(mixed)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded["1"]).to.equal(1)
			expect(decoded["2"]).to.equal(2)
			expect(decoded["3"]).to.equal(3)
			expect(decoded.name).to.equal("test")
			expect(decoded.flag).to.equal(true)
		end)
	end)

	describe("Caching", function()
		it("should cache frequently used values", function()
			local value = "cached_string"

			local first = Buffer.Encode(value)
			local second = Buffer.Encode(value)

			expect(first).to.equal(second)
		end)

		it("should support priority caching", function()
			local value = Vector3.new(1, 2, 3)

			local hot = Buffer.EncodeWith(value, "hot")
			local warm = Buffer.EncodeWith(value, "warm")
			local cold = Buffer.EncodeWith(value, "cold")

			expect(hot).to.be.ok()
			expect(warm).to.be.ok()
			expect(cold).to.be.ok()
		end)

		it("should invalidate cache", function()
			local value = "invalidate_me"

			Buffer.Encode(value)
			Buffer.Invalidate(value)

			local encoded = Buffer.Encode(value)
			expect(encoded).to.be.ok()
		end)
	end)

	describe("Compression", function()
		it("should compress large data", function()
			local large = string.rep("test", 1000)
			local compressed, err = Buffer.EncodeCompressed(large, "auto")

			expect(err).to.equal(nil)
			expect(compressed).to.be.ok()

			local decoded = Buffer.Decode(compressed :: buffer)
			expect(decoded).to.equal(large)
		end)

		it("should support different compression modes", function()
			local data = string.rep("compress", 500)

			local modes = { "lz4", "deflate", "auto" }

			for _, mode in modes do
				local compressed, err = Buffer.EncodeCompressed(data, mode :: any)
				expect(err).to.equal(nil)

				if compressed then
					local decoded = Buffer.Decode(compressed)
					expect(decoded).to.equal(data)
				end
			end
		end)
	end)

	describe("Schema", function()
		it("should validate schema", function()
			local schema = {
				version = 1,
				fields = {
					{ name = "health", type = "number" },
					{ name = "name", type = "string" },
					{ name = "position", type = "Vector3", optional = true },
				},
			}

			local valid, err = Buffer.ValidateSchema(schema)
			expect(valid).to.equal(true)
			expect(err).to.equal(nil)
		end)

		it("should encode with schema", function()
			local schema = {
				version = 1,
				fields = {
					{ name = "id", type = "number" },
					{ name = "username", type = "string" },
				},
			}

			local data = { id = 123, username = "player1" }

			local encoded, err = Buffer.EncodeSchema(data, schema)
			expect(err).to.equal(nil)
			expect(encoded).to.be.ok()
		end)

		it("should decode with schema", function()
			local schema = {
				version = 1,
				fields = {
					{ name = "score", type = "number" },
					{ name = "active", type = "boolean" },
				},
			}

			local data = { score = 1000, active = true }

			local encoded = Buffer.EncodeSchema(data, schema)
			local decoded, err = Buffer.DecodeSchema(encoded :: buffer, schema)

			expect(err).to.equal(nil)
			expect(decoded).to.be.ok()
			expect(decoded.score).to.equal(1000)
			expect(decoded.active).to.equal(true)
		end)

		it("should handle optional fields", function()
			local schema = {
				version = 1,
				fields = {
					{ name = "required", type = "number" },
					{ name = "optional", type = "string", optional = true, default = "default" },
				},
			}

			local data = { required = 42 }

			local encoded = Buffer.EncodeSchema(data, schema)
			local decoded = Buffer.DecodeSchema(encoded :: buffer, schema)

			expect(decoded.required).to.equal(42)
			expect(decoded.optional).to.equal("default")
		end)
	end)

	describe("Delta Encoding", function()
		it("should encode delta", function()
			local old = { a = 1, b = 2, c = 3 }
			local new = { a = 1, b = 5, c = 3, d = 4 }

			local delta, err = Buffer.EncodeDelta(old, new)
			expect(err).to.equal(nil)
			expect(delta).to.be.ok()
		end)

		it("should apply delta", function()
			local old = { x = 10, y = 20 }
			local new = { x = 15, y = 20, z = 30 }

			local delta = Buffer.EncodeDelta(old, new)
			local result = Buffer.ApplyDelta(table.clone(old), delta :: buffer)

			expect(result.x).to.equal(15)
			expect(result.z).to.equal(30)
		end)

		it("should handle schema delta", function()
			local schema = {
				version = 1,
				fields = {
					{ name = "hp", type = "number" },
					{ name = "mp", type = "number" },
				},
			}

			local old = { hp = 100, mp = 50 }
			local new = { hp = 80, mp = 50 }

			local delta = Buffer.EncodeSchemaDelta(old, new, schema)
			expect(delta).to.be.ok()

			local result = Buffer.DecodeSchemaDelta(delta :: buffer, table.clone(old), schema)
			expect(result.hp).to.equal(80)
		end)
	end)

	describe("Instance Registry", function()
		it("should register instance", function()
			local part = Instance.new("Part")
			Buffer.RegisterInstance(part, 1)

			local encoded = Buffer.Encode(part)
			expect(encoded).to.be.ok()

			Buffer.UnregisterInstance(part)
			part:Destroy()
		end)

		it("should decode registered instance", function()
			local part = Instance.new("Part")
			Buffer.RegisterInstance(part, 2)

			local encoded = Buffer.Encode(part)
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded).to.equal(part)

			Buffer.UnregisterInstance(part)
			part:Destroy()
		end)
	end)

	describe("Stream API", function()
		it("should create stream", function()
			local stream = Buffer.CreateStream()
			expect(stream).to.be.ok()
		end)

		it("should write to stream", function()
			local stream = Buffer.CreateStream()

			local ok1 = stream:write(1)
			local ok2 = stream:write("test")
			local ok3 = stream:write(true)

			expect(ok1).to.equal(true)
			expect(ok2).to.equal(true)
			expect(ok3).to.equal(true)
		end)

		it("should finalize stream", function()
			local stream = Buffer.CreateStream()

			stream:write(42)
			stream:write("data")

			local result, err = stream:finalize()
			expect(err).to.equal(nil)
			expect(result).to.be.ok()
		end)

		it("should reject writes after finalize", function()
			local stream = Buffer.CreateStream()
			stream:finalize()

			local ok, err = stream:write(123)
			expect(ok).to.equal(false)
			expect(err).to.be.ok()
		end)
	end)

	describe("Error Handling", function()
		it("should handle corrupt buffer", function()
			local corrupt = buffer.create(10)
			buffer.writeu8(corrupt, 0, 255)

			local value, err = Buffer.SafeDecode(corrupt)
			expect(value).to.equal(nil)
			expect(err).to.be.ok()
		end)

		it("should reject cyclic tables", function()
			local cyclic = {}
			cyclic.self = cyclic

			local encoded, err = Buffer.EncodeSafe(cyclic)
			expect(encoded).to.equal(nil)
			expect(err).to.be.ok()
		end)

		it("should reject invalid schema", function()
			local invalid = {
				version = 1,
				fields = {
					{ name = "bad", type = "InvalidType" },
				},
			}

			local valid, err = Buffer.ValidateSchema(invalid)
			expect(valid).to.equal(false)
			expect(err).to.be.ok()
		end)
	end)

	describe("Utilities", function()
		it("should calculate encoded size", function()
			local value = { a = 1, b = 2, c = 3 }
			local size = Buffer.EncodedSize(value)

			expect(size).to.be.a("number")
			expect(size :: number > 0).to.equal(true)
		end)

		it("should visualize buffer", function()
			local encoded = Buffer.Encode(42)
			local viz = Buffer.Visualize(encoded :: buffer)

			expect(viz).to.be.a("string")
			expect(#viz > 0).to.equal(true)
		end)

		it("should detect data class", function()
			local str = Buffer.Encode("text")
			local num = Buffer.Encode(123)

			local strClass = Buffer.DetectDataClass(str :: buffer)
			local numClass = Buffer.DetectDataClass(num :: buffer)

			expect(strClass).to.be.a("string")
			expect(numClass).to.be.a("string")
		end)

		it("should convert to JSON", function()
			local data = { x = 10, y = 20, name = "test" }
			local encoded = Buffer.Encode(data)
			local json = Buffer.ToJSON(encoded :: buffer)

			expect(json).to.be.ok()
			expect((json :: string):find("test")).to.be.ok()
		end)

		it("should convert from JSON", function()
			local json = '{"value":42,"text":"hello"}'
			local encoded, err = Buffer.FromJSON(json)

			expect(err).to.equal(nil)
			expect(encoded).to.be.ok()

			local decoded = Buffer.Decode(encoded :: buffer)
			expect(decoded.value).to.equal(42)
		end)
	end)

	describe("Edge Cases", function()
		it("should handle empty table", function()
			local empty = {}
			local encoded = Buffer.Encode(empty)
			local decoded = Buffer.Decode(encoded :: buffer)

			local count = 0
			for _ in pairs(decoded) do
				count += 1
			end
			expect(count).to.equal(0)
		end)

		it("should handle large numbers", function()
			local cases = { 1e308, -1e308, 2 ^ 53, -(2 ^ 53) }

			for _, num in cases do
				local encoded = Buffer.Encode(num)
				local decoded = Buffer.Decode(encoded :: buffer)
				expect(decoded).to.equal(num)
			end
		end)

		it("should handle special floats", function()
			local nan = 0 / 0

			-- Попробуем безопасный вариант
			local encoded, err = Buffer.EncodeSafe(nan)

			if encoded then
				-- Если закодировалось успешно, то decoded должен быть NaN
				local decoded = Buffer.Decode(encoded)
				expect(decoded ~= decoded).to.equal(true)
			else
				-- Если не закодировалось, то должна быть ошибка
				expect(err).to.be.ok()
			end
		end)

		it("should handle empty string", function()
			local encoded = Buffer.Encode("")
			local decoded = Buffer.Decode(encoded :: buffer)

			expect(decoded).to.equal("")
		end)
	end)

	describe("Type Validators", function()
		it("should validate number range", function()
			local rangeType = Buffer.Types.numberRange(0, 100)

			local ok1 = rangeType.check(50)
			local ok2 = rangeType.check(150)

			expect(ok1).to.equal(true)
			expect(ok2).to.equal(false)
		end)

		it("should validate integer", function()
			local intType = Buffer.Types.integer()

			local ok1 = intType.check(42)
			local ok2 = intType.check(3.14)

			expect(ok1).to.equal(true)
			expect(ok2).to.equal(false)
		end)

		it("should validate array", function()
			local arrType = Buffer.Types.array(Buffer.Types.number(), 5)

			local ok1 = arrType.check({ 1, 2, 3 })
			local ok2 = arrType.check({ 1, 2, 3, 4, 5, 6 })

			expect(ok1).to.equal(true)
			expect(ok2).to.equal(false)
		end)

		it("should validate union", function()
			local unionType = Buffer.Types.union(Buffer.Types.number(), Buffer.Types.string())

			local ok1 = unionType.check(42)
			local ok2 = unionType.check("text")
			local ok3 = unionType.check(true)

			expect(ok1).to.equal(true)
			expect(ok2).to.equal(true)
			expect(ok3).to.equal(false)
		end)
	end)
end
