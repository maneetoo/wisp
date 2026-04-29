--!nonstrict

local Buffer = require("@game/ReplicatedStorage/Wisp/lib/modules/Buffer")
local Remote = require("@game/ReplicatedStorage/Wisp/lib/modules/Remote")

local function createMockRemoteEvent()
	return {
		ClassName = "RemoteEvent",
		FireClient = function() end,
		FireAllClients = function() end,
		OnServerEvent = {
			Connect = function()
				return {
					Disconnect = function() end,
				}
			end,
		},
	} :: any
end

local function createMockPlayer(name: string)
	return {
		Name = name,
		UserId = math.random(1, 1000000),
	} :: any
end

return function()
	describe("Remote.new", function()
		it("should create Remote wrapper", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			expect(wrapper).to.be.ok()
			expect(wrapper._remote).to.equal(remote)
			expect(wrapper._isServer).to.equal(true)
		end)

		it("should use default config when none provided", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			expect(wrapper._config).to.be.ok()
			expect(wrapper._config.encode.mode).to.equal("basic")
			expect(wrapper._config.batching).to.equal("unreliable")
		end)

		it("should use provided config", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "compressed", compression = "lz4" },
				batching = "reliable",
			}
			local wrapper = Remote.new(remote, config :: any, true)

			expect(wrapper._config.encode.mode).to.equal("compressed")
			expect(wrapper._config.batching).to.equal("reliable")
		end)

		it("should initialize empty caches", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			expect(next(wrapper._deltaCache)).never.to.be.ok()
			expect(next(wrapper._deltaCacheHash)).never.to.be.ok()
			expect(next(wrapper._deltaCacheVersion)).never.to.be.ok()
		end)
	end)

	describe("_encode", function()
		it("should encode basic data", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local encoded = wrapper:_encode({ value = 42 })

			expect(encoded).to.be.ok()
			expect(buffer.len(encoded :: buffer) > 0).to.equal(true)
		end)

		it("should encode with priority", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "basic", priority = "hot" },
			}
			local wrapper = Remote.new(remote, config :: any, true)

			local encoded = wrapper:_encode({ value = 42 })

			expect(encoded).to.be.ok()
		end)

		it("should apply XOR preprocessing", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local original = { value = 42 }
			local encoded = wrapper:_encode(original)

			expect(encoded).to.be.ok()
		end)

		it("should auto-compress large payloads", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local largeData = { data = string.rep("test", 300) }
			local encoded = wrapper:_encode(largeData)

			expect(encoded).to.be.ok()
		end)

		it("should handle delta encoding first send", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			local data = { coins = 100, level = 1 }
			local encoded = wrapper:_encode(data, player)

			expect(encoded).to.be.ok()
			expect(wrapper._deltaCache[player]).to.be.ok()
			expect(wrapper._deltaCache[player].coins).to.equal(100)
		end)

		it("should handle delta encoding subsequent sends", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			local data1 = { coins = 100, level = 1 }
			wrapper:_encode(data1, player)

			local data2 = { coins = 150, level = 1 }
			local encoded = wrapper:_encode(data2, player)

			expect(encoded).to.be.ok()
			expect(wrapper._deltaCache[player].coins).to.equal(150)
		end)

		it("should handle delta cache desync", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
				syncDeltaCache = true,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			local data1 = { coins = 100 }
			wrapper:_encode(data1, player)

			wrapper._deltaCache[player].coins = 999

			local data2 = { coins = 150 }
			wrapper:_encode(data2, player)

			expect(wrapper._deltaCache[player].coins).to.equal(150)
		end)

		it("should return nil on encode failure", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local encoded = wrapper:_encode({ func = function() end })

			expect(encoded).never.to.be.ok()
		end)
	end)

	describe("_decode", function()
		it("should decode basic data", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local original = { value = 42 }
			local encoded = wrapper:_encode(original)
			local decoded = wrapper:_decode(encoded :: buffer)

			expect(decoded).to.be.ok()
			expect(decoded.value).to.equal(42)
		end)

		it("should reverse XOR preprocessing", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local original = { value = "test" }
			local encoded = wrapper:_encode(original)
			local decoded = wrapper:_decode(encoded :: buffer)

			expect(decoded.value).to.equal("test")
		end)

		it("should handle delta decoding", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			local data1 = { coins = 100, level = 1 }
			local encoded1 = wrapper:_encode(data1, player)
			wrapper:_decode(encoded1 :: buffer, player)

			local data2 = { coins = 150, level = 1 }
			local encoded2 = wrapper:_encode(data2, player)
			local decoded2 = wrapper:_decode(encoded2 :: buffer, player)

			expect(decoded2.coins).to.equal(150)
			expect(decoded2.level).to.equal(1)
		end)

		it("should handle missing delta cache", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			local data = { coins = 100 }
			local encoded = wrapper:_encode(data, player)
			local decoded = wrapper:_decode(encoded :: buffer, player)

			expect(decoded.coins).to.equal(100)
		end)
	end)

	describe("_checkRateLimit", function()
		it("should allow first send", function()
			local remote = createMockRemoteEvent()
			local config = {
				rateLimit = 0.1,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			expect(wrapper:_checkRateLimit(player)).to.equal(true)
		end)

		it("should block rapid sends", function()
			local remote = createMockRemoteEvent()
			local config = {
				rateLimit = 1.0,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_checkRateLimit(player)
			expect(wrapper:_checkRateLimit(player)).to.equal(false)
		end)

		it("should allow send after timeout", function()
			local remote = createMockRemoteEvent()
			local config = {
				rateLimit = 0.01,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_checkRateLimit(player)
			task.wait(0.02)
			expect(wrapper:_checkRateLimit(player)).to.equal(true)
		end)

		it("should allow unlimited when no rate limit set", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)
			local player = createMockPlayer("Test")

			expect(wrapper:_checkRateLimit(player)).to.equal(true)
			expect(wrapper:_checkRateLimit(player)).to.equal(true)
			expect(wrapper:_checkRateLimit(player)).to.equal(true)
		end)
	end)

	describe("EncodeBatch", function()
		it("should encode small batch", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local packets = {
				{ remoteName = "test1", args = { 1 } },
				{ remoteName = "test2", args = { 2 } },
			}

			local encoded = wrapper:EncodeBatch(packets :: any)

			expect(encoded).to.be.ok()
		end)

		it("should encode large batch with optimizer", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local packets = {}
			for i = 1, 15 do
				packets[i] = { remoteName = "test", args = { i } }
			end

			local encoded = wrapper:EncodeBatch(packets :: any)

			expect(encoded).to.be.ok()
		end)

		it("should increment sequence", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local packets = {
				{ remoteName = "test", args = { 1 } },
			}

			wrapper:EncodeBatch(packets :: any)
			local seq1 = wrapper._sequence

			wrapper:EncodeBatch(packets :: any)
			local seq2 = wrapper._sequence

			expect(seq2).to.equal(seq1 + 1)
		end)
	end)

	describe("DecodeBatch", function()
		it("should decode batch", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local packets = {
				{ remoteName = "test1", args = { 1 } },
				{ remoteName = "test2", args = { 2 } },
			}

			local encoded = wrapper:EncodeBatch(packets :: any)
			local decoded = wrapper:DecodeBatch(encoded :: buffer)

			expect(decoded).to.be.ok()
			expect(#decoded).to.equal(2)
		end)

		it("should return nil for invalid batch", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local invalidBuffer = buffer.create(10)

			local decoded = wrapper:DecodeBatch(invalidBuffer)

			expect(decoded).never.to.be.ok()
		end)
	end)

	describe("Delta Cache", function()
		it("should get delta cache hash", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
				syncDeltaCache = true,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_encode({ coins = 100 }, player)

			local hash = wrapper:GetDeltaCacheHash(player)
			expect(hash).to.be.ok()
		end)

		it("should get delta cache version", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
				syncDeltaCache = true,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_encode({ coins = 100 }, player)

			local version = wrapper:GetDeltaCacheVersion(player)
			expect(version).to.equal(1)
		end)

		it("should sync delta cache successfully", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
				syncDeltaCache = true,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_encode({ coins = 100 }, player)
			local hash = wrapper:GetDeltaCacheHash(player)

			local synced = wrapper:SyncDeltaCache(player, hash :: string, 1)
			expect(synced).to.equal(true)
		end)

		it("should detect delta cache desync", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
				syncDeltaCache = true,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_encode({ coins = 100 }, player)

			local synced = wrapper:SyncDeltaCache(player, "wronghash", 1)
			expect(synced).to.equal(false)
		end)
	end)

	describe("ClearPlayer", function()
		it("should clear all player data", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
				syncDeltaCache = true,
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			wrapper:_encode({ coins = 100 }, player)
			wrapper:_checkRateLimit(player)

			wrapper:ClearPlayer(player)

			expect(wrapper._deltaCache[player]).never.to.be.ok()
			expect(wrapper._deltaCacheHash[player]).never.to.be.ok()
			expect(wrapper._deltaCacheVersion[player]).never.to.be.ok()
			expect(wrapper._lastSend[player]).never.to.be.ok()
		end)
	end)

	describe("Integration", function()
		it("should handle full encode-decode cycle", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local original = {
				name = "Test",
				value = 42,
				nested = { a = 1, b = 2 },
			}

			local encoded = wrapper:_encode(original)
			local decoded = wrapper:_decode(encoded :: buffer)

			expect(decoded.name).to.equal("Test")
			expect(decoded.value).to.equal(42)
			expect(decoded.nested.a).to.equal(1)
		end)

		it("should handle delta cycle", function()
			local remote = createMockRemoteEvent()
			local config = {
				encode = { mode = "delta" },
			}
			local wrapper = Remote.new(remote, config :: any, true)
			local player = createMockPlayer("Test")

			local data1 = { coins = 100, level = 1, name = "Player" }
			local enc1 = wrapper:_encode(data1, player)
			wrapper:_decode(enc1 :: buffer, player)

			local data2 = { coins = 150, level = 1, name = "Player" }
			local enc2 = wrapper:_encode(data2, player)
			local dec2 = wrapper:_decode(enc2 :: buffer, player)

			expect(dec2.coins).to.equal(150)
			expect(dec2.level).to.equal(1)
			expect(dec2.name).to.equal("Player")
		end)

		it("should handle batch cycle", function()
			local remote = createMockRemoteEvent()
			local wrapper = Remote.new(remote, nil, true)

			local packets = {
				{ remoteName = "move", args = { Vector3.new(1, 2, 3) } },
				{ remoteName = "jump", args = { true } },
				{ remoteName = "health", args = { 100 } },
			}

			local encoded = wrapper:EncodeBatch(packets :: any)
			local decoded = wrapper:DecodeBatch(encoded :: buffer)

			expect(#decoded).to.equal(3)
			expect(decoded[1].remoteName).to.equal("move")
			expect(decoded[2].remoteName).to.equal("jump")
			expect(decoded[3].remoteName).to.equal("health")
		end)
	end)
end
