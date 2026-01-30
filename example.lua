local json = dofile("./json.lua/json.lua")
local toon = require("toon")

print("Version of json.lua: " .. json._version)
print("Version of toon.lua: " .. toon.version)
print("\n")

-- ============================================================================
-- JSON TO TOON
-- ============================================================================

local jsonStrInput = [[
{
  "name": "张三",
  "age": 30,
  "address": {
    "city": "北京",
    "district": "朝阳区"
  },
  "hobbies": ["阅读", "游泳", "编程"]
}
]]
local toonStrOutput = toon.encode(json.decode(jsonStrInput))
print("Input json: \n" .. jsonStrInput)
print("Output toon: \n" .. toonStrOutput)
print("\n")

-- ============================================================================
-- TOON TO JSON
-- ============================================================================

local toonStrInput = [[
employees[3]{id, name, department, salary}:
  1, 张三, 技术部, 8000
  2, 李四, 市场部, 7500
  3, 王五, 人事部, 6800
]]
local jsonStrOutput = json.encode(toon.decode(toonStrInput))
print("Input toon: \n" .. toonStrInput)
print("Output json: \n" .. jsonStrOutput)

