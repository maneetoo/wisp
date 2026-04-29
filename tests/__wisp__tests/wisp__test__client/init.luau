--@maneetoo

--!strict

local Container = script.Parent
local SpecTestModules = Container.wisp__test__client.Spec
local TestEZ = require(Container.TestEZ)

local RunTest: boolean = true

-- Checks basic functions for operability
if RunTest then
	TestEZ.TestBootstrap:run({
		SpecTestModules,
	})
end
