--[[
    MIT License

    Copyright (c) 2026 manee_too

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]
--

--[[
    ⚠️⚠️⚠️⚠️⚠️⚠️⚠️
    ------------------
    WISP IS STILL UNDER ACTIVE DEVELOPMENT, 
    THE MODULE MAY CONTAIN ERRORS IN DATA TRANSFER OR EVEN COMPLETE DATA LOSS IN SUPER-RARE CASES!
    ALTHOUGH IT HAS PASSED ALL TESTS, BUT SOME EDGE-CASES CAN BREAK THE MODULE.
    IF YOU FIND A BUG OR ERROR - REPORT IT TO US! https://github.com/maneetoo/wisp/issues
    ------------------
    ⚠️⚠️⚠️⚠️⚠️⚠️⚠️
]]
--

assert(game, "[Wisp] Must be required in Roblox Studio")

local Types = require("@self/lib/Types")

-- Roblox Luau is still bad at this, so we're exporting them again to use them correctly in Roblox Studio
export type Schema = Types.Schema
export type SchemaType = Types.SchemaType
export type MigrationMap = Types.MigrationMap
export type CompressionMode = Types.CompressionMode
export type Priority = Types.Priority
export type EncodeConfig = Types.EncodeConfig
export type BatchMode = Types.BatchMode
export type RemoteConfig = Types.RemoteConfig
export type BatchPacket = Types.BatchPacket
export type DeltaSyncPacket = Types.DeltaSyncPacket
export type InvokeCallback = Types.InvokeCallback
export type ClientInvokeCallback = Types.ClientInvokeCallback

return require("@self/lib")
