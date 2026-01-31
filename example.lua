local json = dofile("./json.lua/json.lua")
local toon = require("toon")

print("Version of json.lua: " .. json._version)
print("Version of toon.lua: " .. toon.version)

-- ============================================================================
-- UTILS
-- ============================================================================

--- Reads the entire content of a file.
-- @param filePath (string) The path to the file to read.
-- @return (string) The content of the file.
local function readFile(filePath)
    local file, err = io.open(filePath, "r")
    if not file or err then
        return ""
    end
    local content = file:read("*a")
    file:close()
    return content
end

--- Trim whitespace from both ends of a string.
-- @param s (string) The string to trim.
-- @return (string) The trimmed string.
local function trim(s)
    return s and s:match("^%s*(.-)%s*$") or ""
end

--- Convert json string to toon string
-- @param jsonStr (string) json string
-- @return (string) toon string
local function json2Toon(jsonStr)
    return toon.encode(json.decode(jsonStr))
end

--- Convert toon string to json string
-- @param toonStr (string) toon string
-- @return (string) json string
local function toon2Json(toonStr)
    return json.encode(toon.decode(toonStr))
end

-- Some paired json and toon files provided by `spec/examples/conversions`
local exampleFilsDir = "spec/examples/conversions/";
local files = {
    jsonFiles = {
        exampleFilsDir .. "api-response.json",
        exampleFilsDir .. "config.json",
        exampleFilsDir .. "users.json"
    },
    toonFiles = {
        exampleFilsDir .. "api-response.toon",
        exampleFilsDir .. "config.toon",
        exampleFilsDir .. "users.toon"
    }
}

-- ============================================================================
-- JSON TO TOON
-- ============================================================================

for _, path in pairs(files.jsonFiles) do
    local jsonIStr = trim(readFile(path))
    local toonOStr = trim(json2Toon(jsonIStr))
    print(string.rep("=", 60))
    print("Input json: \n" .. jsonIStr)
    print()
    print("Output toon: \n" .. toonOStr)
end

-- ============================================================================
-- TOON TO JSON
-- ============================================================================

for _, path in pairs(files.toonFiles) do
    local toonIStr = trim(readFile(path))
    local jsonOStr = trim(toon2Json(toonIStr))
    print(string.rep("=", 60))
    print("Input toon: \n" .. toonIStr)
    print()
    print("Output json: \n" .. jsonOStr)
end
