--@maneetoo

--!strict

--[[
    Makes a table strict by preventing access to undefined keys.
    Any attempt to read or write to a key that doesn't exist will throw an error.
    Useful for catching typos and enforcing structure in configuration tables
]]
--
local Strict = function<T>(tbl: T, name: string?): T
	local tableName: string = name or tostring(tbl)

	return setmetatable(tbl, {
		__index = function<T>(_self: any, key: T): never
			error(`{key} ({typeof(key)} is not valid member of {tableName}`)
		end,

		__newindex = function<T, V>(_self: any, key: T, _value: V): never
			error(`{key} ({typeof(key)} is not valid member of {tableName}`)
		end,
	}) :: T
end

return Strict
