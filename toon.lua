-- toon.lua - TOON (Typed Object Notation) parser for Lua
-- https://toonformat.dev/

local toon = {}

-- Configuration constants
local DEFAULT_INDENT = 2  -- spaces per indent level

-- ============================================================================
-- STRING ESCAPING / UNESCAPING
-- ============================================================================

local ESCAPE_MAP = {
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\""] = "\\\"",
    ["\\"] = "\\\\"
}

local UNESCAPE_MAP = {
    ["\\n"] = "\n",
    ["\\r"] = "\r",
    ["\\t"] = "\t",
    ["\\\""] = "\"",
    ["\\\\"] = "\\"
}

local function escapeString(str)
    -- Handle nil by returning "null" marker (caller decides how to use)
    if str == nil then return "null" end

    for char, escape in pairs(ESCAPE_MAP) do
        str = string.gsub(str, escape, char)  -- Note: escaped first, then reversed
    end

    -- The above does the reverse, let me fix it:
    str = string.gsub(str, "\\", "\\\\")
    str = string.gsub(str, "\"", "\\\"")
    str = string.gsub(str, "\n", "\\n")
    str = string.gsub(str, "\r", "\\r")
    str = string.gsub(str, "\t", "\\t")

    return str
end

local function unescapeString(str)
    if str == nil then return nil end

    str = string.gsub(str, "\\n", "\n")
    str = string.gsub(str, "\\r", "\r")
    str = string.gsub(str, "\\t", "\t")
    str = string.gsub(str, "\\\"", "\"")
    str = string.gsub(str, "\\\\", "\\")

    return str
end

-- ============================================================================
-- KEY HANDLING
-- ============================================================================

local function needsKeyQuoting(key)
    -- Keys must be non-empty strings
    if type(key) ~= "string" or key == "" then return true end

    -- Keys with dots or spaces must be quoted
    if key:find("%.") or key:find("%s") then return true end

    -- Valid keys: start with letter/underscore, contain only alphanumerics/underscore
    return not key:match("^[A-Za-z_][A-Za-z0-9_]*$")
end

local function formatKey(key)
    if needsKeyQuoting(key) then
        return '"' .. escapeString(key) .. '"'
    end
    return key
end

-- ============================================================================
-- VALUE TYPE CHECKING
-- ============================================================================

local function isPrimitive(value)
    local t = type(value)
    return t == "string" or t == "number" or t == "boolean" or t == "nil"
end

local function isArray(value)
    if type(value) ~= "table" then return false end
    local mt = getmetatable(value)
    return #value > 0 or (mt and mt.n)
end

local function isTabularArray(arr)
    -- Check if array can be encoded in tabular format:
    -- - non-empty
    -- - all items are tables with same primitive keys
    if #arr == 0 then return false, {} end

    local first = arr[1]
    if type(first) ~= "table" then return false, {} end

    local keys = {}
    for k in pairs(first) do table.insert(keys, k) end
    table.sort(keys)

    for _, item in ipairs(arr) do
        if type(item) ~= "table" then return false, {} end

        local itemKeys = {}
        for k in pairs(item) do table.insert(itemKeys, k) end
        table.sort(itemKeys)

        if #itemKeys ~= #keys then return false, {} end

        for _, k in ipairs(keys) do
            if item[k] == nil or not isPrimitive(item[k]) then
                return false, {}
            end
        end
    end

    return true, keys
end

-- ============================================================================
-- STRING QUOTING FOR VALUES
-- ============================================================================

local RESERVED_VALUES = {["true"] = true, ["false"] = true, ["null"] = true}

local function needsQuoting(value, delimiter)
    if type(value) ~= "string" then return false end

    -- Empty string needs quoting
    if value == "" then return true end

    -- Leading/trailing whitespace needs quoting
    if value:match("^%s") or value:match("%s$") then return true end

    -- Reserved values need quoting
    if RESERVED_VALUES[value] then return true end

    -- Numeric strings need quoting
    if tonumber(value) then return true end

    -- Characters that require quoting
    if value:find("[\":\\]") then return true end
    if value:find("[%[%]{}]") then return true end
    if value:find("[\n\r\t]") then return true end

    -- Delimiter in array scope needs quoting
    if delimiter and value:find(delimiter, 1, true) then return true end

    -- Keys starting with hyphen need quoting
    if value:sub(1, 1) == "-" then return true end

    return false
end

-- ============================================================================
-- NUMBER FORMATTING
-- ============================================================================

local function formatNumber(num)
    -- Handle special cases
    if num ~= num then return "null" end  -- NaN
    if num == math.huge then return "null" end
    if num == -math.huge then return "null" end
    if num == 0 then return "0" end

    local str = tostring(num)

    -- Normalize scientific notation to decimal
    if str:find("[eE]") then
        local sign = ""
        if str:find("^-") then
            sign = "-"
            str = str:sub(2)
        end

        local base, exp = str:match("^(%d+)%.?%d*[eE](.+)$")
        if not base then base, exp = str:match("^(%d+)[eE](.+)$") end

        if base and exp then
            exp = tonumber(exp)
            if exp and exp > 0 then
                str = sign .. tostring(tonumber(base) * (10 ^ exp))
            elseif exp and exp < 0 then
                local absExp = -exp
                str = sign .. string.format("%." .. absExp .. "f", tonumber(base) / (10 ^ absExp))
                str = str:gsub("0+$", "")
                str = str:gsub("%.$", "")
            end
        end
    end

    -- Remove leading zeros (but keep single 0)
    str = str:gsub("^(%-?)0+(%d)", "%1%2")

    -- Remove trailing zeros after decimal point
    if str:find("%.") then
        str = str:gsub("0+$", "")
        str = str:gsub("%.$", "")
    end

    return str
end

-- ============================================================================
-- DELIMITER UTILITIES
-- ============================================================================

local function getDelimiter(options)
    if options and options.delimiter == "tab" then return "\t" end
    if options and options.delimiter == "pipe" then return "|" end
    return ","
end

local function getDelimiterMark(delim)
    if delim == "\t" then return "\t" end
    if delim == "|" then return "|" end
    return ""
end

-- ============================================================================
-- ENCODER - VALUE
-- ============================================================================

local encodeValue, encodeArray, encodeObject  -- forward declarations

function encodeValue(value, indentLevel, options, inArrayScope, activeDelimiter)
    local indentSize = options and options.indent or DEFAULT_INDENT
    local indent = string.rep(" ", (indentLevel or 0) * indentSize)

    if value == nil then
        return "null"
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    elseif type(value) == "number" then
        return formatNumber(value)
    elseif type(value) == "string" then
        local delim = activeDelimiter or ","
        if needsQuoting(value, inArrayScope and delim or nil) then
            return '"' .. escapeString(value) .. '"'
        end
        return value
    elseif type(value) == "table" then
        if isArray(value) then
            return encodeArray(value, indentLevel, options, activeDelimiter)
        end
        return encodeObject(value, indentLevel, options, activeDelimiter)
    end

    return "null"
end

-- ============================================================================
-- ENCODER - OBJECT
-- ============================================================================

function encodeObject(obj, indentLevel, options)
    if type(obj) ~= "table" then return "null" end

    local indentSize = options and options.indent or DEFAULT_INDENT
    local indent = string.rep(" ", indentLevel * indentSize)
    local nextIndent = string.rep(" ", (indentLevel + 1) * indentSize)
    local delim = getDelimiter(options)

    local lines = {}

    for key, value in pairs(obj) do
        local fkey = formatKey(key)
        local t = type(value)

        if t == "table" and next(value) ~= nil then
            if isArray(value) then
                local encoded = encodeArray(value, indentLevel, options, delim)
                local nl = encoded:find("\n")
                if nl then
                    lines[#lines + 1] = indent .. fkey .. encoded:sub(1, nl - 1)
                    lines[#lines + 1] = encoded:sub(nl + 1)
                else
                    lines[#lines + 1] = indent .. fkey .. encoded
                end
            else
                lines[#lines + 1] = indent .. fkey .. ":"
                lines[#lines + 1] = encodeObject(value, indentLevel + 1, options)
            end
        elseif value == nil then
            lines[#lines + 1] = indent .. fkey .. ": null"
        else
            local encoded = encodeValue(value, 0, options, false, delim)
            lines[#lines + 1] = indent .. fkey .. ": " .. encoded
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- ENCODER - ARRAY
-- ============================================================================

function encodeArray(arr, indentLevel, options)
    if type(arr) ~= "table" then return "null" end

    local indentSize = options and options.indent or DEFAULT_INDENT
    local indent = string.rep(" ", indentLevel * indentSize)
    local nextIndent = string.rep(" ", (indentLevel + 1) * indentSize)
    local delim = getDelimiter(options)
    local count = #arr

    -- Empty array
    if count == 0 then
        return indent .. "[" .. count .. getDelimiterMark(delim) .. "]:"
    end

    -- Check for tabular format
    local canBeTabular, fields = isTabularArray(arr)

    if canBeTabular then
        local fieldList = table.concat(fields, delim)
        local lines = {
            indent .. "[" .. count .. getDelimiterMark(delim) .. "]{" .. fieldList .. "}:"
        }

        for _, item in ipairs(arr) do
            local values = {}
            for _, field in ipairs(fields) do
                values[#values + 1] = encodeValue(item[field], 0, options, true, delim)
            end
            lines[#lines + 1] = nextIndent .. table.concat(values, delim)
        end

        return table.concat(lines, "\n")
    end

    -- Check if all items are primitives
    local allPrimitive = true
    for i = 1, count do
        if type(arr[i]) == "table" then
            allPrimitive = false
            break
        end
    end

    if allPrimitive then
        local values = {}
        for i = 1, count do
            values[#values + 1] = encodeValue(arr[i], 0, options, true, delim)
        end
        return indent .. "[" .. count .. getDelimiterMark(delim) .. "]: " .. table.concat(values, delim)
    end

    -- Expanded format with list items
    local lines = {indent .. "[" .. count .. "]: "}
    local itemIndent = nextIndent

    for i = 1, count do
        local item = arr[i]
        if type(item) == "table" then
            if isArray(item) then
                local nested = encodeArray(item, indentLevel + 2, options, delim)
                local firstLine = nested:match("^[^\n]+")
                if firstLine then
                    lines[#lines + 1] = itemIndent .. "- " .. firstLine
                end
            else
                local nested = encodeObject(item, indentLevel + 2, options)
                local nl = nested:find("\n")
                local content = nl and nested:sub((indentLevel + 1) * indentSize + 1) or nested
                lines[#lines + 1] = itemIndent .. "- " .. content
            end
        else
            lines[#lines + 1] = itemIndent .. "- " .. encodeValue(item, 0, options, true, delim)
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- PUBLIC API - ENCODE
-- ============================================================================

function toon.encode(data, options)
    options = options or {}

    if type(data) ~= "table" then
        return nil, "data must be a table"
    end

    local lines = {}

    for key, value in pairs(data) do
        local fkey = formatKey(key)
        local t = type(value)

        if t == "table" and next(value) ~= nil then
            if isArray(value) then
                local encoded = encodeArray(value, 0, options)
                local nl = encoded:find("\n")
                if nl then
                    lines[#lines + 1] = fkey .. encoded:sub(1, nl - 1)
                    lines[#lines + 1] = encoded:sub(nl + 1)
                else
                    lines[#lines + 1] = fkey .. encoded
                end
            else
                lines[#lines + 1] = fkey .. ":"
                lines[#lines + 1] = encodeObject(value, 1, options)
            end
        elseif value == nil then
            lines[#lines + 1] = fkey .. ": null"
        else
            local encoded = encodeValue(value, 0, options, false, getDelimiter(options))
            lines[#lines + 1] = fkey .. ": " .. encoded
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- DECODER - UTILITIES
-- ============================================================================

local function parseLines(text)
    local lines = {}
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        if line ~= "" or #lines > 0 then
            lines[#lines + 1] = line
        end
    end
    return lines
end

local function countLeadingSpaces(line)
    local count = 0
    for i = 1, #line do
        local c = line:sub(i, i)
        if c == " " then
            count = count + 1
        elseif c == "\t" then
            return -1  -- tabs not allowed
        else
            break
        end
    end
    return count
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function parseNumber(str)
    if not str or str == "" then return nil end
    if str:find("^%-?0%d") then return nil end  -- leading zeros not allowed

    local num = tonumber(str)
    if num and num == num and num ~= math.huge and num ~= -math.huge then
        return num
    end
    return nil
end

local function parseValue(token)
    if not token or token == "" then return "" end

    if token == "null" then return nil end
    if token == "true" then return true end
    if token == "false" then return false end

    -- Quoted string
    if token:sub(1, 1) == '"' and token:sub(#token) == '"' then
        return unescapeString(token:sub(2, #token - 1))
    end

    -- Number
    local num = parseNumber(token)
    if num then return num end

    return token
end

local function parseKeyValue(line)
    local colonPos = line:find(":")
    if not colonPos then return nil end

    local keyPart = line:sub(1, colonPos - 1)
    local valuePart = line:sub(colonPos + 1)

    if keyPart == "" then return nil end

    -- Parse key (may be quoted)
    local key
    if keyPart:sub(1, 1) == '"' and keyPart:sub(#keyPart) == '"' then
        key = unescapeString(keyPart:sub(2, #keyPart - 1))
    else
        key = keyPart
    end

    valuePart = trim(valuePart)
    if valuePart == "" then return key, nil end

    return key, parseValue(valuePart)
end

-- ============================================================================
-- DECODER - ARRAY PARSING
-- ============================================================================

local function parseArrayHeader(line)
    -- Format: key[N] or key[N]| or key[N]{field1,field2}:
    local bs = line:find("%[")
    if not bs then return nil end

    local be = line:find("]", bs)
    if not be then return nil end

    local countStr = line:sub(bs + 1, be - 1)
    local count = tonumber(countStr)
    if not count then return nil end

    -- Detect delimiter
    local delim = ","
    local after = line:sub(be + 1, be + 1)
    if after == "\t" then delim = "\t"
    elseif after == "|" then delim = "|" end

    -- Parse field list if present
    local fields = nil
    after = line:sub(be + 1)

    if after:sub(1, 1) == "{" then
        local braceEnd = after:find("}")
        if braceEnd then
            local fieldStr = after:sub(2, braceEnd - 1)
            fields = {}
            for field in string.gmatch(fieldStr, "([^" .. delim .. "]+)") do
                field = trim(field)
                if field:sub(1, 1) == '"' and field:sub(#field) == '"' then
                    field = unescapeString(field:sub(2, #field - 1))
                end
                fields[#fields + 1] = field
            end
            after = after:sub(braceEnd + 1)
        end
    end

    -- Must end with colon
    if after:sub(1, 1) ~= ":" then return nil end

    local inlineValue = trim(after:sub(2))

    return {
        count = count,
        delimiter = delim,
        fields = fields,
        inlineValue = inlineValue ~= "" and inlineValue or nil
    }
end

local function splitByDelimiter(str, delim)
    local result = {}
    local inQuotes = false
    local current = ""

    for i = 1, #str do
        local c = str:sub(i, i)
        if c == '"' then
            inQuotes = not inQuotes
            current = current .. c
        elseif not inQuotes and c == delim then
            result[#result + 1] = trim(current)
            current = ""
        else
            current = current .. c
        end
    end

    result[#result + 1] = trim(current)
    return result
end

local function parseTabularRow(line, fields, delim)
    local values = splitByDelimiter(line, delim)
    local obj = {}

    for i, field in ipairs(fields) do
        obj[field] = parseValue(values[i] or "")
    end

    return obj
end

local function parseListItem(line)
    if not line:find("^%s*- ") then return nil end

    local content = trim(line:match("^%s*- (.*)$") or "")
    if content == "" then return {} end

    -- Check for array header
    local header = parseArrayHeader(content)
    if header then
        local values = {}
        if header.inlineValue then
            values = splitByDelimiter(header.inlineValue, header.delimiter)
        end
        local parsed = {}
        for _, v in ipairs(values) do
            parsed[#parsed + 1] = parseValue(v)
        end
        return parsed
    end

    -- Check for key-value
    local key, value = parseKeyValue(content)
    if key then
        return {[key] = value}
    end

    -- Plain value
    return parseValue(content)
end

-- ============================================================================
-- DECODER - OBJECT PARSING
-- ============================================================================

local decodeObject

local function decodeRootArray(lines)
    local header = parseArrayHeader(lines[1])
    if not header then return nil, "invalid array header" end

    local arr = {}

    if header.inlineValue then
        local values = splitByDelimiter(header.inlineValue, header.delimiter)
        for _, v in ipairs(values) do
            arr[#arr + 1] = parseValue(v)
        end
    elseif header.fields then
        for i = 2, #lines do
            if lines[i] == "" then break end
            arr[#arr + 1] = parseTabularRow(lines[i], header.fields, header.delimiter)
        end
    else
        for i = 2, #lines do
            if lines[i] == "" then break end
            if lines[i]:find("^%s*- ") then
                arr[#arr + 1] = parseListItem(lines[i])
            end
        end
    end

    return arr
end

function decodeObject(lines, startDepth)
    local result = {}
    local i = 1

    while i <= #lines do
        local line = lines[i]

        if line == "" then
            i = i + 1
            goto continue
        end

        local depth = countLeadingSpaces(line)
        local content = line:sub(depth + 1)

        -- List item
        if content:find("^%s*- ") then
            if depth < startDepth then return result end
            result[#result + 1] = parseListItem(content)
            i = i + 1
            goto continue
        end

        -- Check depth
        if depth < startDepth then return result end

        -- Array header
        local header = parseArrayHeader(content)
        if header then
            local keyPrefixEnd = content:find("%[") - 1
            local keyPrefix = trim(content:sub(1, keyPrefixEnd))

            local key
            if keyPrefix:sub(1, 1) == '"' and keyPrefix:sub(#keyPrefix) == '"' then
                key = unescapeString(keyPrefix:sub(2, #keyPrefix - 1))
            else
                key = keyPrefix
            end

            local arr = {}

            if header.fields then
                local j = i + 1
                while j <= #lines do
                    if lines[j] == "" then break end
                    local rowDepth = countLeadingSpaces(lines[j])
                    if rowDepth <= depth then break end
                    arr[#arr + 1] = parseTabularRow(lines[j], header.fields, header.delimiter)
                    j = j + 1
                end
                result[key] = arr
                i = j
            elseif header.inlineValue then
                local values = splitByDelimiter(header.inlineValue, header.delimiter)
                for _, v in ipairs(values) do
                    arr[#arr + 1] = parseValue(v)
                end
                result[key] = arr
                i = i + 1
            else
                local j = i + 1
                while j <= #lines do
                    if lines[j] == "" then break end
                    local nextDepth = countLeadingSpaces(lines[j])
                    if nextDepth <= depth then break end
                    if lines[j]:find("^%s*- ") then
                        arr[#arr + 1] = parseListItem(lines[j])
                    end
                    j = j + 1
                end
                result[key] = arr
                i = j
            end

            goto continue
        end

        -- Regular key-value
        local key, value = parseKeyValue(content)
        if not key then
            i = i + 1
            goto continue
        end

        if value == nil then
            -- Check for nested object
            local j = i + 1
            local nestedLines = {}
            local hasContent = false

            while j <= #lines do
                if lines[j] == "" then break end
                local nextDepth = countLeadingSpaces(lines[j])
                if nextDepth <= depth then break end
                hasContent = true
                nestedLines[#nestedLines + 1] = lines[j]
                j = j + 1
            end

            if hasContent then
                result[key] = decodeObject(nestedLines, depth)
            end
            i = j
        else
            result[key] = value
            i = i + 1
        end

        ::continue::
    end

    return result
end

-- ============================================================================
-- PUBLIC API - DECODE
-- ============================================================================

function toon.decode(text)
    text = text or ""
    local lines = parseLines(text)

    if #lines == 0 then return {} end

    -- Remove empty lines
    local nonEmpty = {}
    for _, l in ipairs(lines) do
        if l ~= "" then nonEmpty[#nonEmpty + 1] = l end
    end
    if #nonEmpty == 0 then return {} end

    -- Check for root array
    local firstLine = nonEmpty[1]
    local firstHeader = parseArrayHeader(firstLine)

    if firstHeader and not firstLine:find("^[A-Za-z_]") and not firstLine:find('^"') then
        return decodeRootArray(lines)
    end

    -- Single line primitive
    if #nonEmpty == 1 then
        local line = nonEmpty[1]
        if not parseArrayHeader(line) and not line:find(":") then
            local v = parseValue(line)
            if v ~= nil then return v end
        end
    end

    return decodeObject(lines, 0)
end

return toon
