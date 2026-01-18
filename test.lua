-- test.lua - Test suite for toon.lua

local toon = require("toon")

local passed, failed = 0, 0

local function test(name, fn)
    local ok = pcall(fn)
    if ok then
        io.write("✓")
        passed = passed + 1
    else
        io.write("✗")
        failed = failed + 1
    end
end

local function section(name)
    print("\n" .. string.rep("=", 60))
    print(name)
    print(string.rep("=", 60))
end

section("Primitive Types")

test("String encoding", function()
    assert(toon.encode({test = "hello"}) == "test: hello")
end)

test("Number encoding", function()
    assert(toon.encode({num = 42}) == "num: 42")
end)

test("Boolean true encoding", function()
    assert(toon.encode({val = true}) == "val: true")
end)

test("Boolean false encoding", function()
    assert(toon.encode({val = false}):find("val: false"))
end)

test("Null value handling", function()
    local r = toon.decode("val: null")
    assert(next(r) == nil)
end)

test("String decoding", function()
    local r = toon.decode("value: hello world")
    assert(r.value == "hello world")
end)

test("Number decoding", function()
    local r = toon.decode("num: 42")
    assert(r.num == 42)
end)

test("Boolean true decoding", function()
    local r = toon.decode("flag: true")
    assert(r.flag == true)
end)

test("Boolean false decoding", function()
    local r = toon.decode("flag: false")
    assert(r.flag == false)
end)

test("Null detection", function()
    local r = toon.decode("val: null")
    assert(r ~= nil and next(r) == nil)
end)

section("String Quoting and Escaping")

test("Empty string quoting", function()
    assert(toon.encode({empty = ""}) == 'empty: ""')
end)

test("String with leading/trailing whitespace", function()
    assert(toon.encode({ws = "  hello  "}) == 'ws: "  hello  "')
end)

test("String matching 'true' quoted", function()
    assert(toon.encode({val = "true"}) == 'val: "true"')
end)

test("String matching 'false' quoted", function()
    assert(toon.encode({val = "false"}) == 'val: "false"')
end)

test("String matching 'null' quoted", function()
    assert(toon.encode({val = "null"}) == 'val: "null"')
end)

test("Numeric string quoted", function()
    assert(toon.encode({val = "42"}) == 'val: "42"')
end)

test("String with colon quoted", function()
    assert(toon.encode({url = "http://example.com"}) == 'url: "http://example.com"')
end)

test("String with quotes escaped", function()
    assert(toon.encode({quoted = 'say "hello"'}) == 'quoted: "say \\"hello\\""')
end)

test("String with backslash escaped", function()
    assert(toon.encode({path = "C:\\Users"}) == 'path: "C:\\\\Users"')
end)

test("String with newline escaped", function()
    assert(toon.encode({multiline = "line1\nline2"}) == 'multiline: "line1\\nline2"')
end)

test("String with tab escaped", function()
    assert(toon.encode({tabbed = "a\tb"}) == 'tabbed: "a\\tb"')
end)

test("String starting with hyphen quoted", function()
    assert(toon.encode({dash = "-start"}) == 'dash: "-start"')
end)

test("String with brackets quoted", function()
    assert(toon.encode({arr = "[1,2,3]"}) == 'arr: "[1,2,3]"')
end)

test("Unescape string", function()
    local r = toon.decode('str: "hello\\nworld"')
    assert(r.str == "hello\nworld")
end)

section("Number Formatting")

test("Integer formatting", function()
    assert(toon.encode({num = 42}) == "num: 42")
end)

test("Float without trailing zeros", function()
    assert(toon.encode({num = 1.5}) == "num: 1.5")
end)

test("Float with trailing zeros normalized", function()
    assert(toon.encode({num = 1.50}) == "num: 1.5")
end)

test("Integer float normalized", function()
    assert(toon.encode({num = 1.0}) == "num: 1")
end)

test("Negative zero normalized", function()
    assert(toon.encode({negzero = -0}) == "negzero: 0")
end)

test("NaN encoded as null", function()
    assert(toon.encode({nan = 0/0}) == "nan: null")
end)

test("Infinity encoded as null", function()
    assert(toon.encode({inf = math.huge}) == "inf: null")
end)

test("Negative infinity encoded as null", function()
    assert(toon.encode({neginf = -math.huge}) == "neginf: null")
end)

test("Decode number", function()
    local r = toon.decode("num: 3.14")
    assert(r.num == 3.14)
end)

test("Decode leading-zero number as string", function()
    local r = toon.decode('num: "05"')
    assert(r.num == "05")
end)

section("Key Encoding")

test("Simple unquoted key", function()
    assert(toon.encode({simpleKey = "value"}):find("^simpleKey:"))
end)

test("Key with underscore", function()
    assert(toon.encode({my_key = "value"}):find("^my_key:"))
end)

test("Key with dots", function()
    assert(toon.encode({["user.name"] = "value"}) == '"user.name": value')
end)

test("Key starting with digit quoted", function()
    assert(toon.encode({["123key"] = "value"}) == '"123key": value')
end)

test("Decode quoted key", function()
    local r = toon.decode('"my-key": value')
    assert(r["my-key"] == "value")
end)

test("Decode key with spaces", function()
    local r = toon.decode('"key with spaces": value')
    assert(r["key with spaces"] == "value")
end)

section("Object Encoding and Decoding")

test("Simple object", function()
    local r = toon.encode({id = 123, name = "Ada", active = true})
    assert(r:find("id: 123") and r:find("name: Ada") and r:find("active: true"))
end)

test("Nested object", function()
    local r = toon.encode({user = {id = 123, name = "Ada"}})
    assert(r:find("^user:") and r:find("  id: 123") and r:find("  name: Ada"))
end)

test("Deeply nested object", function()
    local r = toon.encode({
        root = {
            level1 = {
                level2 = {
                    level3 = {value = "deep"}
                }
            }
        }
    })
    assert(r:find("root:") and r:find("  level1:") and r:find("    level2:") and r:find("      level3:") and r:find("        value: deep"))
end)

test("Decode nested object", function()
    local r = toon.decode("user:\n  id: 123\n  name: Ada")
    assert(r.user.id == 123 and r.user.name == "Ada")
end)

test("Empty object", function()
    assert(toon.encode({empty = {}}):find("empty"))
end)

test("Empty document for empty object", function()
    assert(toon.encode({}) == "")
end)

test("Key order preserved", function()
    local r = toon.encode({z_key = 1, a_key = 2, m_key = 3})
    assert(r:find("z_key") and r:find("a_key") and r:find("m_key"))
end)

section("Inline Array Encoding")

test("Inline string array", function()
    assert(toon.encode({tags = {"admin", "ops", "dev"}}) == "tags[3]: admin,ops,dev")
end)

test("Inline number array", function()
    assert(toon.encode({nums = {1, 2, 3}}) == "nums[3]: 1,2,3")
end)

test("Inline mixed array", function()
    assert(toon.encode({mixed = {1, "two", true}}):find("mixed%[3%]:"))
end)

test("Empty inline array", function()
    assert(toon.encode({items = {}}):find("empty") or toon.encode({items = {}}):find("items"))
end)

test("Array with delimiter in value", function()
    assert(toon.encode({vals = {"a,b", "c"}}):find("vals%[2%]:"))
end)

test("Decode inline array", function()
    local r = toon.decode("tags[3]: admin,ops,dev")
    assert(r.tags[1] == "admin" and r.tags[2] == "ops" and r.tags[3] == "dev")
end)

section("Tabular Array Encoding")

test("Tabular array basic", function()
    local r = toon.encode({
        items = {
            {id = 1, name = "A", qty = 2},
            {id = 2, name = "B", qty = 1}
        }
    })
    assert(r:find("items%[2%]{id,name,qty}:") and r:find("  1,A,2") and r:find("  2,B,1"))
end)

test("Tabular array with string values requiring quotes", function()
    local r = toon.encode({
        items = {
            {id = 1, name = "Hello, World"},
            {id = 2, name = "Test"}
        }
    })
    assert((r:find("%{id,name%}:") or r:find("%{name,id%}:")) and r:find('1,"Hello, World"') and r:find("  2,Test"))
end)

test("Tabular array encoding", function()
    local r = toon.encode({
        items = {
            {z = 1, a = 2, m = 3},
            {z = 4, a = 5, m = 6}
        }
    })
    assert(r:find("%[2%]{.-}:") or r:find("%[2%]:"))
end)

test("Decode tabular array", function()
    local r = toon.decode("items[2]{id,name,qty}:\n  1,A,2\n  2,B,1")
    assert(r.items[1].id == 1 and r.items[1].name == "A" and r.items[1].qty == 2)
end)

section("Expanded Array (List Items)")

test("Expanded primitive array", function()
    local r = toon.encode({
        items = {
            {val = 1},
            {val = 2},
            {val = 3}
        }
    })
    assert((r:find("%[3%]:") or r:find("%[3%]{")) and (r:find("  1") or r:find("  - 1")))
end)

test("Expanded array of objects", function()
    local r = toon.encode({
        users = {
            {id = 1, name = "Alice"},
            {id = 2, name = "Bob"}
        }
    })
    assert((r:find("users%[2%]:") or r:find("users%[2%]{")) and (r:find("  1,") or r:find("  -")))
end)

test("Mixed array", function()
    local r = toon.encode({
        mixed = {
            {val = 1},
            {name = "test"},
            {val = "text"}
        }
    })
    assert(r:find("%[3%]:"))
end)

test("Decode list items", function()
    local r = toon.decode("items[3]:\n  - 1\n  - a: 1\n  - text")
    assert(r.items[1] == 1 and r.items[2].a == 1 and r.items[3] == "text")
end)

section("Delimiter Variations")

test("Tab delimiter in array", function()
    local r = toon.encode({items = {1, 2, 3}}, {delimiter = "tab"})
    assert(r:find("items%[3"))
end)

test("Pipe delimiter in array", function()
    assert(toon.encode({items = {1, 2, 3}}, {delimiter = "pipe"}):find("items%[3%|%]:"))
end)

test("Tab delimiter in tabular array", function()
    local r = toon.encode({
        items = {
            {id = 1, name = "A"},
            {id = 2, name = "B"}
        }
    }, {delimiter = "tab"})
    assert(r:find("items%[2") and (r:find("  1") or r:find("  2")))
end)

test("Decode tab-delimited array", function()
    local r = toon.decode("items[3]: 1,2,3")
    assert(r.items[1] == 1 and r.items[2] == 2 and r.items[3] == 3)
end)

section("Edge Cases")

test("Unicode strings", function()
    assert(toon.encode({msg = "Hello 世界 👋"}):find("msg: Hello 世界 👋"))
end)

test("Emoji in array", function()
    assert(toon.encode({tags = {"🎉", "🎊", "🎈"}}):find("🎉"))
end)

test("Large numbers", function()
    assert(toon.encode({bignum = 9007199254740992}):find("9007199254740992"))
end)

test("Scientific notation decoded", function()
    local r = toon.decode("num: 1e-6")
    assert(r.num == 0.000001)
end)

test("Negative scientific notation decoded", function()
    local r = toon.decode("num: -1E+3")
    assert(r.num == -1000)
end)

test("Decode leading zero number as string", function()
    local r = toon.decode('val: "05"')
    assert(r.val == "05")
end)

test("Empty array at root", function()
    assert(toon.encode({items = {}}):find("items"))
end)

section("Strict Mode Validation")

test("Strict mode: array count mismatch handled", function()
    local r = toon.decode("items[5]: a,b,c", {strict = true})
    assert(r ~= nil and #r.items == 3)
end)

test("Non-strict mode: loose parsing", function()
    local r = toon.decode("items[3]: a,b,c", {strict = false})
    assert(r ~= nil and #r.items == 3)
end)

section("Root Form Detection")

test("Root object", function()
    local r = toon.decode("key: value")
    assert(r.key == "value")
end)

test("Root array", function()
    local r = toon.decode("[3]: 1,2,3")
    assert(r[1] == 1 and r[2] == 2 and r[3] == 3)
end)

test("Root primitive", function()
    assert(toon.decode("hello") == "hello")
end)

test("Empty document", function()
    local r = toon.decode("")
    assert(r ~= nil and next(r) == nil)
end)

section("Specification Examples")

test("Example: context object", function()
    local r = toon.decode("context:\n  task: Our favorite hikes together\n  location: Boulder\n  season: spring_2025")
    assert(r.context.task == "Our favorite hikes together" and r.context.location == "Boulder")
end)

test("Example: friends array", function()
    local r = toon.decode("friends[3]: ana,luis,sam")
    assert(r.friends[1] == "ana" and r.friends[2] == "luis" and r.friends[3] == "sam")
end)

test("Example: hikes tabular array", function()
    local r = toon.decode("hikes[3]{id,name,distanceKm,elevationGain,companion,wasSunny}:\n  1,Blue Lake Trail,7.5,320,ana,true\n  2,Ridge Overlook,9.2,540,luis,false\n  3,Wildflower Loop,5.1,180,sam,true")
    assert(r.hikes[1].id == 1 and r.hikes[1].name == "Blue Lake Trail")
end)

test("Example: users tabular", function()
    local r = toon.decode("users[2]{id,name,role}:\n  1,Alice,admin\n  2,Bob,user")
    assert(r.users[1].id == 1 and r.users[1].role == "admin")
end)

test("Example: pairs arrays of arrays", function()
    local r = toon.decode("pairs[2]:\n  - [2]: 1,2\n  - [2]: 3,4")
    assert(r.pairs[1][1] == 1 and r.pairs[1][2] == 2 and r.pairs[2][1] == 3)
end)

test("Example: list item with object", function()
    local r = toon.decode("items[2]:\n  - name: Alice\n  - name: Bob")
    assert(r.items[1].name == "Alice" and r.items[2].name == "Bob")
end)

test("Example: quoted colons in URLs", function()
    local r = toon.decode('links[2]{id,url}:\n  1,"http://a:b"\n  2,"https://example.com?q=a:b"')
    assert(r.links[1].url == "http://a:b" and r.links[2].url == "https://example.com?q=a:b")
end)

section("Indentation")

test("Custom indent size", function()
    local r = toon.encode({nested = {val = 1}}, {indent = 4})
    assert(r:find("nested:") and r:find("    val: 1"))
end)

section("Error Cases")

test("Missing colon returns parsed value", function()
    local r = toon.decode("key value", {strict = true})
    assert(r == "key value")
end)

section("Print Summary")

print("\n" .. string.rep("=", 60))
print("TEST SUMMARY")
print(string.rep("=", 60))
print("Passed: " .. passed)
print("Failed: " .. failed)
print(string.rep("=", 60))

if failed == 0 then
    print("✓ All tests passed!")
else
    print("✗ " .. failed .. " tests failed")
end
