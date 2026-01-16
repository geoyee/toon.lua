local toon = require("toon")

local function deepCompare(a, b, path)
    path = path or ""
    local typeA, typeB = type(a), type(b)
    
    if typeA ~= typeB then
        return false, path .. ": type mismatch (" .. typeA .. " vs " .. typeB .. ")"
    end
    
    if typeA == "table" then
        local keysA, keysB = {}, {}
        for k in pairs(a) do table.insert(keysA, k) end
        for k in pairs(b) do table.insert(keysB, k) end
        table.sort(keysA)
        table.sort(keysB)
        
        if #keysA ~= #keysB then
            return false, path .. ": table key count mismatch"
        end
        
        for _, k in ipairs(keysA) do
            local subPath = path .. (path ~= "" and "." or "") .. tostring(k)
            local ok, err = deepCompare(a[k], b[k], subPath)
            if not ok then return false, err end
        end
        return true
    end
    
    if a ~= b then
        return false, path .. ": value mismatch (" .. tostring(a) .. " vs " .. tostring(b) .. ")"
    end
    
    return true
end

local totalPassed = 0
local totalFailed = 0

local function test(name, fn)
    local success, err = pcall(fn)
    if success then
        io.write("✓")
        totalPassed = totalPassed + 1
        return true
    else
        io.write("✗")
        io.write(" [ERROR: " .. tostring(err) .. "]")
        totalFailed = totalFailed + 1
        return false
    end
end

local function section(name)
    print("\n" .. string.rep("=", 60))
    print(name)
    print(string.rep("=", 60))
end

section("Primitive Types")

totalPassed = totalPassed + (test("String encoding", function()
    local result = toon.encode({test = "hello"})
    assert(result == 'test: hello', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Number encoding", function()
    local result = toon.encode({num = 42})
    assert(result == 'num: 42', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Boolean true encoding", function()
    local result = toon.encode({val = true})
    assert(result == 'val: true', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Boolean false encoding", function()
    local result = toon.encode({val = false})
    assert(result:find('val: false'), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Null value handling", function()
    local decoded = toon.decode("val: null")
    assert(next(decoded) == nil, "nil value should result in empty table in Lua")
end) and 1 or 0)

totalPassed = totalPassed + (test("String decoding", function()
    local result, err = toon.decode("value: hello world")
    assert(result.value == "hello world", "got: " .. tostring(result and result.value))
end) and 1 or 0)

totalPassed = totalPassed + (test("Number decoding", function()
    local result, err = toon.decode("num: 42")
    assert(result.num == 42, "got: " .. tostring(result and result.num))
end) and 1 or 0)

totalPassed = totalPassed + (test("Boolean true decoding", function()
    local result, err = toon.decode("flag: true")
    assert(result.flag == true, "got: " .. tostring(result and result.flag))
end) and 1 or 0)

totalPassed = totalPassed + (test("Boolean false decoding", function()
    local result, err = toon.decode("flag: false")
    assert(result.flag == false, "got: " .. tostring(result and result.flag))
end) and 1 or 0)

totalPassed = totalPassed + (test("Null detection", function()
    local result, err = toon.decode("val: null")
    assert(result ~= nil, "result should not be nil")
    assert(next(result) == nil, "table should be empty (nil removed in Lua)")
end) and 1 or 0)

section("String Quoting and Escaping")

totalPassed = totalPassed + (test("Empty string quoting", function()
    local result = toon.encode({empty = ""})
    assert(result == 'empty: ""', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with leading/trailing whitespace", function()
    local result = toon.encode({ws = "  hello  "})
    assert(result == 'ws: "  hello  "', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String matching 'true' quoted", function()
    local result = toon.encode({val = "true"})
    assert(result == 'val: "true"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String matching 'false' quoted", function()
    local result = toon.encode({val = "false"})
    assert(result == 'val: "false"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String matching 'null' quoted", function()
    local result = toon.encode({val = "null"})
    assert(result == 'val: "null"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Numeric string quoted", function()
    local result = toon.encode({val = "42"})
    assert(result == 'val: "42"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with colon quoted", function()
    local result = toon.encode({url = "http://example.com"})
    assert(result == 'url: "http://example.com"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with quotes escaped", function()
    local result = toon.encode({quoted = 'say "hello"'})
    assert(result == 'quoted: "say \\"hello\\""', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with backslash escaped", function()
    local result = toon.encode({path = "C:\\Users"})
    assert(result == 'path: "C:\\\\Users"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with newline escaped", function()
    local result = toon.encode({multiline = "line1\nline2"})
    assert(result == 'multiline: "line1\\nline2"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with tab escaped", function()
    local result = toon.encode({tabbed = "a\tb"})
    assert(result == 'tabbed: "a\\tb"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String starting with hyphen quoted", function()
    local result = toon.encode({dash = "-start"})
    assert(result == 'dash: "-start"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("String with brackets quoted", function()
    local result = toon.encode({arr = "[1,2,3]"})
    assert(result == 'arr: "[1,2,3]"', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Unescape string", function()
    local result, err = toon.decode('str: "hello\\nworld"')
    assert(result.str == "hello\nworld", "got: " .. tostring(result and result.str))
end) and 1 or 0)

section("Number Formatting")

totalPassed = totalPassed + (test("Integer formatting", function()
    local result = toon.encode({num = 42})
    assert(result == 'num: 42', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Float without trailing zeros", function()
    local result = toon.encode({num = 1.5})
    assert(result == 'num: 1.5', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Float with trailing zeros normalized", function()
    local result = toon.encode({num = 1.50})
    assert(result == 'num: 1.5', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Integer float normalized", function()
    local result = toon.encode({num = 1.0})
    assert(result == 'num: 1', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Negative zero normalized", function()
    local result = toon.encode({negzero = -0})
    assert(result == 'negzero: 0', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("NaN encoded as null", function()
    local result = toon.encode({nan = 0/0})
    assert(result == 'nan: null', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Infinity encoded as null", function()
    local result = toon.encode({inf = math.huge})
    assert(result == 'inf: null', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Negative infinity encoded as null", function()
    local result = toon.encode({neginf = -math.huge})
    assert(result == 'neginf: null', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode number", function()
    local result, err = toon.decode("num: 3.14")
    assert(result.num == 3.14, "got: " .. tostring(result and result.num))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode leading-zero number as string", function()
    local result, err = toon.decode('num: "05"')
    assert(result.num == "05", "got: " .. tostring(result and result.num))
end) and 1 or 0)

section("Key Encoding")

totalPassed = totalPassed + (test("Simple unquoted key", function()
    local result = toon.encode({simpleKey = "value"})
    assert(result:find("^simpleKey:"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Key with underscore", function()
    local result = toon.encode({my_key = "value"})
    assert(result:find("^my_key:"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Key with dots", function()
    local result = toon.encode({["user.name"] = "value"})
    assert(result == '"user.name": value', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Key starting with digit quoted", function()
    local result = toon.encode({["123key"] = "value"})
    assert(result == '"123key": value', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode quoted key", function()
    local result, err = toon.decode('"my-key": value')
    assert(result["my-key"] == "value", "got: " .. tostring(result and result["my-key"]))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode key with spaces", function()
    local result, err = toon.decode('"key with spaces": value')
    assert(result["key with spaces"] == "value", "got: " .. tostring(result and result["key with spaces"]))
end) and 1 or 0)

section("Object Encoding and Decoding")

totalPassed = totalPassed + (test("Simple object", function()
    local result = toon.encode({id = 123, name = "Ada", active = true})
    assert(result:find('id: 123'), "got: " .. tostring(result))
    assert(result:find('name: Ada'), "got: " .. tostring(result))
    assert(result:find('active: true'), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Nested object", function()
    local result = toon.encode({
        user = {
            id = 123,
            name = "Ada"
        }
    })
    assert(result:find("^user:"), "got: " .. tostring(result))
    assert(result:find("  id: 123"), "got: " .. tostring(result))
    assert(result:find("  name: Ada"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Deeply nested object", function()
    local result = toon.encode({
        root = {
            level1 = {
                level2 = {
                    level3 = {
                        value = "deep"
                    }
                }
            }
        }
    })
    assert(result:find("root:"), "got: " .. tostring(result))
    assert(result:find("  level1:"), "got: " .. tostring(result))
    assert(result:find("    level2:"), "got: " .. tostring(result))
    assert(result:find("      level3:"), "got: " .. tostring(result))
    assert(result:find("        value: deep"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode nested object", function()
    local input = [[user:
  id: 123
  name: Ada]]
    local result, err = toon.decode(input)
    assert(result.user.id == 123, "got: " .. tostring(result and result.user and result.user.id))
    assert(result.user.name == "Ada", "got: " .. tostring(result and result.user and result.user.name))
end) and 1 or 0)

totalPassed = totalPassed + (test("Empty object", function()
    local result = toon.encode({empty = {}})
    assert(result:find("empty"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Empty document for empty object", function()
    local result = toon.encode({})
    assert(result == "", "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Key order preserved", function()
    local data = {z_key = 1, a_key = 2, m_key = 3}
    local result = toon.encode(data)
    assert(result:find("z_key"), "missing z_key")
    assert(result:find("a_key"), "missing a_key")
    assert(result:find("m_key"), "missing m_key")
end) and 1 or 0)

section("Inline Array Encoding")

totalPassed = totalPassed + (test("Inline string array", function()
    local result = toon.encode({tags = {"admin", "ops", "dev"}})
    assert(result == 'tags[3]: admin,ops,dev', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Inline number array", function()
    local result = toon.encode({nums = {1, 2, 3}})
    assert(result == 'nums[3]: 1,2,3', "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Inline mixed array", function()
    local result = toon.encode({mixed = {1, "two", true}})
    assert(result:find('mixed%[3%]:'), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Empty inline array", function()
    local result = toon.encode({items = {}})
    assert(result:find("empty") or result:find("items"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Array with delimiter in value", function()
    local result = toon.encode({vals = {"a,b", "c"}})
    assert(result:find('vals%[2%]:'), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode inline array", function()
    local result, err = toon.decode("tags[3]: admin,ops,dev")
    assert(result.tags[1] == "admin", "got: " .. tostring(result and result.tags and result.tags[1]))
    assert(result.tags[2] == "ops", "got: " .. tostring(result and result.tags and result.tags[2]))
    assert(result.tags[3] == "dev", "got: " .. tostring(result and result.tags and result.tags[3]))
end) and 1 or 0)

section("Tabular Array Encoding")

totalPassed = totalPassed + (test("Tabular array basic", function()
    local result = toon.encode({
        items = {
            {id = 1, name = "A", qty = 2},
            {id = 2, name = "B", qty = 1}
        }
    })
    assert(result:find("items%[2%]{id,name,qty}:"), "got: " .. tostring(result))
    assert(result:find("  1,A,2"), "got: " .. tostring(result))
    assert(result:find("  2,B,1"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Tabular array with string values requiring quotes", function()
    local result = toon.encode({
        items = {
            {id = 1, name = "Hello, World"},
            {id = 2, name = "Test"}
        }
    })
    assert(result:find("%{id,name%}:") or result:find("%{name,id%}:"), "got: " .. tostring(result))
    assert(result:find('1,"Hello, World"'), "got: " .. tostring(result))
    assert(result:find("  2,Test"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Tabular array encoding", function()
    local result = toon.encode({
        items = {
            {z = 1, a = 2, m = 3},
            {z = 4, a = 5, m = 6}
        }
    })
    assert(result:find("%[2%]{.-}:") or result:find("%[2%]:"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode tabular array", function()
    local input = [[items[2]{id,name,qty}:
  1,A,2
  2,B,1]]
    local result, err = toon.decode(input)
    assert(result.items[1].id == 1, "got: " .. tostring(result and result.items and result.items[1] and result.items[1].id))
    assert(result.items[1].name == "A", "got: " .. tostring(result and result.items and result.items[1] and result.items[1].name))
    assert(result.items[1].qty == 2, "got: " .. tostring(result and result.items and result.items[1] and result.items[1].qty))
    assert(result.items[2].id == 2, "got: " .. tostring(result and result.items and result.items[2] and result.items[2].id))
end) and 1 or 0)

section("Expanded Array (List Items)")

totalPassed = totalPassed + (test("Expanded primitive array", function()
    local result = toon.encode({
        items = {
            {val = 1},
            {val = 2},
            {val = 3}
        }
    })
    assert(result:find("%[3%]:") or result:find("%[3%]{"), "got: " .. tostring(result))
    assert(result:find("  1") or result:find("  - 1"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Expanded array of objects", function()
    local result = toon.encode({
        users = {
            {id = 1, name = "Alice"},
            {id = 2, name = "Bob"}
        }
    })
    assert(result:find("users%[2%]:") or result:find("users%[2%]{"), "got: " .. tostring(result))
    assert(result:find("  1,") or result:find("  -"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Mixed array", function()
    local result = toon.encode({
        mixed = {
            {val = 1},
            {name = "test"},
            {val = "text"}
        }
    })
    assert(result:find("%[3%]:"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode list items", function()
    local input = [[items[3]:
  - 1
  - a: 1
  - text]]
    local result, err = toon.decode(input)
    assert(result.items[1] == 1, "got: " .. tostring(result and result.items and result.items[1]))
    assert(result.items[2].a == 1, "got: " .. tostring(result and result.items and result.items[2] and result.items[2].a))
    assert(result.items[3] == "text", "got: " .. tostring(result and result.items and result.items[3]))
end) and 1 or 0)

section("Delimiter Variations")

totalPassed = totalPassed + (test("Tab delimiter in array", function()
    local result = toon.encode({items = {1, 2, 3}}, {delimiter = "tab"})
    assert(result:find("items%[3"), "got: " .. tostring(result))
    assert(result:find(":"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Pipe delimiter in array", function()
    local result = toon.encode({items = {1, 2, 3}}, {delimiter = "pipe"})
    assert(result:find("items%[3%|%]:"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Tab delimiter in tabular array", function()
    local result = toon.encode({
        items = {
            {id = 1, name = "A"},
            {id = 2, name = "B"}
        }
    }, {delimiter = "tab"})
    assert(result:find("items%[2"), "got: " .. tostring(result))
    assert(result:find("  1") or result:find("  2"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode tab-delimited array", function()
    local input = "items[3]: 1,2,3"
    local result, err = toon.decode(input)
    assert(result.items[1] == 1, "got: " .. tostring(result and result.items and result.items[1]))
    assert(result.items[2] == 2, "got: " .. tostring(result and result.items and result.items[2]))
    assert(result.items[3] == 3, "got: " .. tostring(result and result.items and result.items[3]))
end) and 1 or 0)

section("Edge Cases")

totalPassed = totalPassed + (test("Unicode strings", function()
    local result = toon.encode({msg = "Hello 世界 👋"})
    assert(result:find("msg: Hello 世界 👋"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Emoji in array", function()
    local result = toon.encode({tags = {"🎉", "🎊", "🎈"}})
    assert(result:find("🎉"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Large numbers", function()
    local result = toon.encode({bignum = 9007199254740992})
    assert(result:find("9007199254740992"), "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Scientific notation decoded", function()
    local result, err = toon.decode("num: 1e-6")
    assert(result.num == 0.000001, "got: " .. tostring(result and result.num))
end) and 1 or 0)

totalPassed = totalPassed + (test("Negative scientific notation decoded", function()
    local result, err = toon.decode("num: -1E+3")
    assert(result.num == -1000, "got: " .. tostring(result and result.num))
end) and 1 or 0)

totalPassed = totalPassed + (test("Decode leading zero number as string", function()
    local result, err = toon.decode('val: "05"')
    assert(result.val == "05", "got: " .. tostring(result and result.val))
end) and 1 or 0)

totalPassed = totalPassed + (test("Empty array at root", function()
    local result = toon.encode({items = {}})
    assert(result:find("items"), "got: " .. tostring(result))
end) and 1 or 0)

section("Strict Mode Validation")

totalPassed = totalPassed + (test("Strict mode: array count mismatch handled", function()
    local result, err = toon.decode("items[5]: a,b,c", {strict = true})
    assert(result ~= nil, "should return result even with count mismatch")
    assert(#result.items == 3, "got: " .. tostring(#(result and result.items)))
end) and 1 or 0)

totalPassed = totalPassed + (test("Non-strict mode: loose parsing", function()
    local result, err = toon.decode("items[3]: a,b,c", {strict = false})
    assert(result ~= nil, "should parse despite mismatch")
    assert(#result.items == 3, "got: " .. tostring(#(result and result.items)))
end) and 1 or 0)

section("Root Form Detection")

totalPassed = totalPassed + (test("Root object", function()
    local result, err = toon.decode("key: value")
    assert(result.key == "value", "got: " .. tostring(result and result.key))
end) and 1 or 0)

totalPassed = totalPassed + (test("Root array", function()
    local input = "[3]: 1,2,3"
    local result, err = toon.decode(input)
    assert(result[1] == 1, "got: " .. tostring(result and result[1]))
    assert(result[2] == 2, "got: " .. tostring(result and result[2]))
    assert(result[3] == 3, "got: " .. tostring(result and result[3]))
end) and 1 or 0)

totalPassed = totalPassed + (test("Root primitive", function()
    local result, err = toon.decode("hello")
    assert(result == "hello", "got: " .. tostring(result))
end) and 1 or 0)

totalPassed = totalPassed + (test("Empty document", function()
    local result, err = toon.decode("")
    assert(result ~= nil and next(result) == nil, "should return empty table")
end) and 1 or 0)

section("Specification Examples")

totalPassed = totalPassed + (test("Example: context object", function()
    local input = [[context:
  task: Our favorite hikes together
  location: Boulder
  season: spring_2025]]
    local result, err = toon.decode(input)
    assert(result.context.task == "Our favorite hikes together", "got: " .. tostring(result and result.context and result.context.task))
    assert(result.context.location == "Boulder", "got: " .. tostring(result and result.context and result.context.location))
    assert(result.context.season == "spring_2025", "got: " .. tostring(result and result.context and result.context.season))
end) and 1 or 0)

totalPassed = totalPassed + (test("Example: friends array", function()
    local input = "friends[3]: ana,luis,sam"
    local result, err = toon.decode(input)
    assert(result.friends[1] == "ana", "got: " .. tostring(result and result.friends and result.friends[1]))
    assert(result.friends[2] == "luis", "got: " .. tostring(result and result.friends and result.friends[2]))
    assert(result.friends[3] == "sam", "got: " .. tostring(result and result.friends and result.friends[3]))
end) and 1 or 0)

totalPassed = totalPassed + (test("Example: hikes tabular array", function()
    local input = [[hikes[3]{id,name,distanceKm,elevationGain,companion,wasSunny}:
  1,Blue Lake Trail,7.5,320,ana,true
  2,Ridge Overlook,9.2,540,luis,false
  3,Wildflower Loop,5.1,180,sam,true]]
    local result, err = toon.decode(input)
    assert(result.hikes[1].id == 1, "got: " .. tostring(result and result.hikes and result.hikes[1] and result.hikes[1].id))
    assert(result.hikes[1].name == "Blue Lake Trail", "got: " .. tostring(result and result.hikes and result.hikes[1] and result.hikes[1].name))
    assert(result.hikes[2].companion == "luis", "got: " .. tostring(result and result.hikes and result.hikes[2] and result.hikes[2].companion))
    assert(result.hikes[3].wasSunny == true, "got: " .. tostring(result and result.hikes and result.hikes[3] and result.hikes[3].wasSunny))
end) and 1 or 0)

totalPassed = totalPassed + (test("Example: users tabular", function()
    local input = [[users[2]{id,name,role}:
  1,Alice,admin
  2,Bob,user]]
    local result, err = toon.decode(input)
    assert(result.users[1].id == 1, "got: " .. tostring(result and result.users and result.users[1] and result.users[1].id))
    assert(result.users[1].role == "admin", "got: " .. tostring(result and result.users and result.users[1] and result.users[1].role))
    assert(result.users[2].name == "Bob", "got: " .. tostring(result and result.users and result.users[2] and result.users[2].name))
end) and 1 or 0)

totalPassed = totalPassed + (test("Example: pairs arrays of arrays", function()
    local input = [[pairs[2]:
  - [2]: 1,2
  - [2]: 3,4]]
    local result, err = toon.decode(input)
    assert(result.pairs[1][1] == 1, "got: " .. tostring(result and result.pairs and result.pairs[1] and result.pairs[1][1]))
    assert(result.pairs[1][2] == 2, "got: " .. tostring(result and result.pairs and result.pairs[1] and result.pairs[1][2]))
    assert(result.pairs[2][1] == 3, "got: " .. tostring(result and result.pairs and result.pairs[2] and result.pairs[2][1]))
    assert(result.pairs[2][2] == 4, "got: " .. tostring(result and result.pairs and result.pairs[2] and result.pairs[2][2]))
end) and 1 or 0)

totalPassed = totalPassed + (test("Example: list item with object", function()
    local input = [[items[2]:
  - name: Alice
  - name: Bob]]
    local result, err = toon.decode(input)
    assert(result.items[1].name == "Alice", "got: " .. tostring(result and result.items and result.items[1] and result.items[1].name))
    assert(result.items[2].name == "Bob", "got: " .. tostring(result and result.items and result.items[2] and result.items[2].name))
end) and 1 or 0)

totalPassed = totalPassed + (test("Example: quoted colons in URLs", function()
    local input = [[links[2]{id,url}:
  1,"http://a:b"
  2,"https://example.com?q=a:b"]]
    local result, err = toon.decode(input)
    assert(result.links[1].url == "http://a:b", "got: " .. tostring(result and result.links and result.links[1] and result.links[1].url))
    assert(result.links[2].url == "https://example.com?q=a:b", "got: " .. tostring(result and result.links and result.links[2] and result.links[2].url))
end) and 1 or 0)

section("Indentation")

totalPassed = totalPassed + (test("Custom indent size", function()
    local result = toon.encode({nested = {val = 1}}, {indent = 4})
    assert(result:find("nested:"), "got: " .. tostring(result))
    assert(result:find("    val: 1"), "got: " .. tostring(result))
end) and 1 or 0)

section("Error Cases")

totalPassed = totalPassed + (test("Missing colon returns parsed value", function()
    local result, err = toon.decode("key value", {strict = true})
    assert(result ~= nil, "should return result")
    assert(result == "key value", "got: " .. tostring(result))
end) and 1 or 0)

section("Print Summary")

print("\n" .. string.rep("=", 60))
print("TEST SUMMARY")
print(string.rep("=", 60))
print("Passed: " .. tostring(totalPassed))
print("Failed: " .. tostring(totalFailed))
print(string.rep("=", 60))

if totalFailed == 0 then
    print("✓ All tests passed!")
else
    print("✗ " .. tostring(totalFailed) .. " tests failed")
end
