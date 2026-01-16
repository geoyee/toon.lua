local toon = {}

local DEFAULT_INDENT = 2
local DEFAULT_STRICT = true

local function escapeString(str)
    if str == nil then return "null" end
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

local function needsQuoting(value, delimiter, inArrayScope)
    if type(value) ~= "string" then return false end
    
    if value == "" then
        return true
    end
    
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed ~= value then
        return true
    end
    
    if value == "true" or value == "false" or value == "null" then
        return true
    end
    
    local num = tonumber(value)
    if num ~= nil then
        return true
    end
    
    if value:find("[\":\\]") then
        return true
    end
    
    if value:find("[%[%]{}]") then
        return true
    end
    
    if value:find("[\n\r\t]") then
        return true
    end
    
    if inArrayScope and value:find(delimiter, 1, true) then
        return true
    elseif not inArrayScope and value:find(",", 1, true) then
        return true
    end
    
    if value:sub(1, 1) == "-" then
        return true
    end
    
    return false
end

local function needsKeyQuoting(key)
    if type(key) ~= "string" then return true end
    if key == "" then return true end
    if key:find("%.") then return true end
    if key:find("%s") then return true end
    return not key:match("^[A-Za-z_][A-Za-z0-9_]*$")
end

local function formatKey(key)
    if needsKeyQuoting(key) then
        return '"' .. escapeString(key) .. '"'
    else
        return key
    end
end

local function formatNumber(num)
    if num ~= num then return "null" end
    if num == math.huge then return "null" end
    if num == -math.huge then return "null" end
    if num == 0 then return "0" end
    
    local str = tostring(num)
    
    if str:find("[eE]") then
        local sign = ""
        if str:find("^-") then
            sign = "-"
            str = str:sub(2)
        end
        
        local base, exp = str:match("^(%d+)%.?%d*[eE](.+)$")
        if not base then
            base, exp = str:match("^(%d+)[eE](.+)$")
        end
        
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
    
    str = str:gsub("^(%-?)0+(%d)", "%1%2")
    
    if str:find("%.") then
        str = str:gsub("0+$", "")
        str = str:gsub("%.$", "")
    end
    
    return str
end

local function isPrimitive(value)
    local vt = type(value)
    return vt == "string" or vt == "number" or vt == "boolean" or vt == "nil"
end

local function isTabularArray(arr)
    if #arr == 0 then return false, {} end
    
    local firstItem = arr[1]
    if type(firstItem) ~= "table" then return false, {} end
    
    local firstKeys = {}
    for k in pairs(firstItem) do
        table.insert(firstKeys, k)
    end
    table.sort(firstKeys)
    
    for i, item in ipairs(arr) do
        if type(item) ~= "table" then return false, {} end
        
        local itemKeys = {}
        for k in pairs(item) do
            table.insert(itemKeys, k)
        end
        table.sort(itemKeys)
        
        if #itemKeys ~= #firstKeys then return false, {} end
        for _, k in ipairs(firstKeys) do
            if item[k] == nil then return false, {} end
            if not isPrimitive(item[k]) then return false, {} end
        end
    end
    
    return true, firstKeys
end

local encodeValue
local encodeArray
local encodeObject

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
        if needsQuoting(value, activeDelimiter or ",", inArrayScope) then
            return '"' .. escapeString(value) .. '"'
        else
            return value
        end
    elseif type(value) == "table" then
        local mt = getmetatable(value)
        local isArr = #value > 0 or (mt and mt.n)
        
        if isArr then
            return encodeArray(value, indentLevel, options, activeDelimiter)
        else
            return encodeObject(value, indentLevel, options, activeDelimiter)
        end
    else
        return "null"
    end
end

function encodeObject(obj, indentLevel, options, activeDelimiter)
    if type(obj) ~= "table" then return "null" end
    
    local indentSize = options and options.indent or DEFAULT_INDENT
    local indent = string.rep(" ", indentLevel * indentSize)
    local nextIndent = string.rep(" ", (indentLevel + 1) * indentSize)
    
    local result = {}
    
    for key, value in pairs(obj) do
        local formattedKey = formatKey(key)
        
        if type(value) == "table" and next(value) ~= nil then
            local mt = getmetatable(value)
            local isArr = #value > 0 or (mt and mt.n)
            
            if not isArr then
                table.insert(result, indent .. formattedKey .. ":")
                table.insert(result, encodeObject(value, indentLevel + 1, options, activeDelimiter))
            else
                local encoded = encodeArray(value, indentLevel, options, activeDelimiter)
                local nl = encoded:find("\n")
                if nl then
                    local firstLine = encoded:sub(1, nl - 1)
                    local rest = encoded:sub(nl + 1)
                    table.insert(result, indent .. formattedKey .. firstLine)
                    table.insert(result, rest)
                else
                    table.insert(result, indent .. formattedKey .. encoded)
                end
            end
        elseif value == nil then
            table.insert(result, indent .. formattedKey .. ": null")
        else
            local encodedValue = encodeValue(value, 0, options, false, ",")
            table.insert(result, indent .. formattedKey .. ": " .. encodedValue)
        end
    end
    
    return table.concat(result, "\n")
end

function encodeArray(arr, indentLevel, options, activeDelimiter)
    if type(arr) ~= "table" then return "null" end
    
    local indentSize = options and options.indent or DEFAULT_INDENT
    local indent = string.rep(" ", indentLevel * indentSize)
    local nextIndent = string.rep(" ", (indentLevel + 1) * indentSize)
    
    local delim = ","
    if options and options.delimiter == "tab" then
        delim = "\t"
    elseif options and options.delimiter == "pipe" then
        delim = "|"
    end
    
    local count = #arr
    if count == 0 then
        return indent .. "[" .. count .. "]:"
    end
    
    local canBeTabular, fields = isTabularArray(arr)
    
    if canBeTabular then
        local delimChar = ""
        if delim == "\t" then
            delimChar = "\t"
        elseif delim == "|" then
            delimChar = "|"
        end
        local fieldList = table.concat(fields, delim)
        local lines = {}
        
        table.insert(lines, indent .. "[" .. count .. delimChar .. "]{" .. fieldList .. "}:")
        
        for _, item in ipairs(arr) do
            local values = {}
            for _, field in ipairs(fields) do
                local val = item[field]
                local encoded = encodeValue(val, 0, options, true, delim)
                table.insert(values, encoded)
            end
            table.insert(lines, nextIndent .. table.concat(values, delim))
        end
        
        return table.concat(lines, "\n")
    end
    
    local allPrimitive = true
    for i, item in ipairs(arr) do
        if type(item) == "table" then
            allPrimitive = false
            break
        end
    end
    
    if allPrimitive then
        local values = {}
        for i, item in ipairs(arr) do
            local encoded = encodeValue(item, 0, options, true, delim)
            table.insert(values, encoded)
        end
        local delimMark = delim == "\t" and "\t" or (delim == "|" and "|" or "")
        return indent .. "[" .. count .. delimMark .. "]: " .. table.concat(values, delim)
    end
    
    local lines = {}
    table.insert(lines, indent .. "[" .. count .. "]:")
    
    local itemIndent = nextIndent
    
    for i, item in ipairs(arr) do
        if type(item) == "table" then
            local mt = getmetatable(item)
            local isArr = #item > 0 or (mt and mt.n)
            
            if not isArr then
                local nested = encodeObject(item, indentLevel + 2, options, delim)
                local nestedContent = nested
                local nl = nestedContent:find("\n")
                if nl then
                    local prefixLen = (indentLevel + 1) * indentSize
                    nestedContent = nestedContent:sub(prefixLen + 1)
                end
                table.insert(lines, itemIndent .. "- " .. nestedContent)
            else
                local nested = encodeArray(item, indentLevel + 2, options, delim)
                local firstLine = nested:match("^[^\n]+")
                if firstLine then
                    table.insert(lines, itemIndent .. "- " .. firstLine)
                end
            end
        else
            local encoded = encodeValue(item, 0, options, true, delim)
            table.insert(lines, itemIndent .. "- " .. encoded)
        end
    end
    
    return table.concat(lines, "\n")
end

function toon.encode(data, options)
    options = options or {}
    
    if type(data) ~= "table" then
        return nil, "data must be a table"
    end
    
    local result = {}
    
    for key, value in pairs(data) do
        local formattedKey = formatKey(key)
        
        if type(value) == "table" and next(value) ~= nil then
            local mt = getmetatable(value)
            local isArr = #value > 0 or (mt and mt.n)
            
            if isArr then
                local encoded = encodeArray(value, 0, options, nil)
                local nl = encoded:find("\n")
                if nl then
                    local firstLine = encoded:sub(1, nl - 1)
                    local rest = encoded:sub(nl + 1)
                    table.insert(result, formattedKey .. firstLine)
                    table.insert(result, rest)
                else
                    table.insert(result, formattedKey .. encoded)
                end
            else
                table.insert(result, formattedKey .. ":")
                table.insert(result, encodeObject(value, 1, options, nil))
            end
        elseif value == nil then
            table.insert(result, formattedKey .. ": null")
        else
            local encodedValue = encodeValue(value, 0, options, false, ",")
            table.insert(result, formattedKey .. ": " .. encodedValue)
        end
    end
    
    return table.concat(result, "\n")
end

local function parseLines(text)
    local lines = {}
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        if line ~= "" or #lines > 0 then
            table.insert(lines, line)
        end
    end
    return lines
end

local function countLeadingSpaces(line)
    local count = 0
    for i = 1, #line do
        if line:sub(i, i) == " " then
            count = count + 1
        elseif line:sub(i, i) == "\t" then
            return -1
        else
            break
        end
    end
    return count
end

local function parseNumber(str)
    if not str or str == "" then return nil end
    
    if str:find("^%-?0%d") then
        return nil
    end
    
    local num = tonumber(str)
    if num and num == num and num ~= math.huge and num ~= -math.huge then
        return num
    end
    
    return nil
end

local function parseValue(token)
    if not token or token == "" then
        return ""
    end
    
    if token == "null" then
        return nil
    elseif token == "true" then
        return true
    elseif token == "false" then
        return false
    end
    
    if token:sub(1, 1) == '"' and token:sub(#token, #token) == '"' then
        return unescapeString(token:sub(2, #token - 1))
    end
    
    local num = parseNumber(token)
    if num ~= nil then
        return num
    end
    
    return token
end

local function parseKeyValue(line)
    local colonPos = line:find(":")
    if not colonPos then
        return nil
    end
    
    local keyPart = line:sub(1, colonPos - 1)
    local valuePart = line:sub(colonPos + 1)
    
    if keyPart == "" then
        return nil
    end
    
    local key
    if keyPart:sub(1, 1) == '"' and keyPart:sub(#keyPart, #keyPart) == '"' then
        key = unescapeString(keyPart:sub(2, #keyPart - 1))
    else
        key = keyPart
    end
    
    valuePart = valuePart:match("^%s*(.-)%s*$")
    if valuePart == "" then
        return key, nil
    end
    
    local value = parseValue(valuePart)
    return key, value
end

local function parseArrayHeader(line)
    local bracketStart = line:find("%[")
    if not bracketStart then return nil end
    
    local bracketEnd = line:find("]", bracketStart)
    if not bracketEnd then return nil end
    
    local countStr = line:sub(bracketStart + 1, bracketEnd - 1)
    local count = tonumber(countStr)
    if not count then return nil end
    
    local delim = ","
    local charAfter = line:sub(bracketEnd + 1, bracketEnd + 1)
    if charAfter == "\t" then
        delim = "\t"
    elseif charAfter == "|" then
        delim = "|"
    end
    
    local afterBracket = line:sub(bracketEnd + 1)
    local fields = nil
    
    if afterBracket:sub(1, 1) == "{" then
        local braceEnd = afterBracket:find("}")
        if braceEnd then
            local fieldStr = afterBracket:sub(2, braceEnd - 1)
            fields = {}
            for field in string.gmatch(fieldStr, "([^" .. delim .. "]+)") do
                field = field:match("^%s*(.-)%s*$")
                if field:sub(1, 1) == '"' and field:sub(#field, #field) == '"' then
                    field = unescapeString(field:sub(2, #field - 1))
                end
                table.insert(fields, field)
            end
            afterBracket = afterBracket:sub(braceEnd + 1)
        end
    end
    
    if afterBracket:sub(1, 1) ~= ":" then
        return nil
    end
    
    local inlineValue = afterBracket:sub(2):match("^%s*(.-)%s*$")
    
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
        local char = str:sub(i, i)
        
        if char == '"' then
            inQuotes = not inQuotes
            current = current .. char
        elseif not inQuotes and char == delim then
            table.insert(result, current:match("^%s*(.-)%s*$") or "")
            current = ""
        else
            current = current .. char
        end
    end
    
    table.insert(result, current:match("^%s*(.-)%s*$") or "")
    
    return result
end

local function parseTabularRow(line, fields, activeDelimiter)
    local values = splitByDelimiter(line, activeDelimiter)
    
    local obj = {}
    for i, field in ipairs(fields) do
        obj[field] = parseValue(values[i] or "")
    end
    
    return obj
end

local function parseListItem(line)
    if not line:find("^%s*- ") then return nil end
    
    local content = line:match("^%s*- (.*)$")
    if not content or content == "" then
        return {}
    end
    
    local header = parseArrayHeader(content)
    if header then
        local values = {}
        if header.inlineValue then
            values = splitByDelimiter(header.inlineValue, header.delimiter)
        end
        
        local parsed = {}
        for _, val in ipairs(values) do
            table.insert(parsed, parseValue(val))
        end
        
        return parsed
    end
    
    local key, value = parseKeyValue(content)
    if key then
        local obj = {}
        obj[key] = value
        return obj
    end
    
    local val = parseValue(content)
    return val
end

local decodeObject

local function decodeRootArray(lines)
    local firstLine = lines[1]
    local header = parseArrayHeader(firstLine)
    
    if not header then
        return nil, "invalid array header"
    end
    
    local arr = {}
    
    if header.inlineValue and header.inlineValue ~= "" then
        local values = splitByDelimiter(header.inlineValue, header.delimiter)
        for _, val in ipairs(values) do
            table.insert(arr, parseValue(val))
        end
    elseif header.fields then
        for i = 2, #lines do
            local line = lines[i]
            if line == "" then break end
            
            local obj = parseTabularRow(line, header.fields, header.delimiter)
            table.insert(arr, obj)
        end
    else
        for i = 2, #lines do
            local line = lines[i]
            if line == "" then break end
            
            if line:find("^%s*- ") then
                local item = parseListItem(line)
                table.insert(arr, item)
            end
        end
    end
    
    return arr
end

function decodeObject(lines, startDepth)
    local indentSize = DEFAULT_INDENT
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
        
        if content:find("^%s*- ") then
            if depth < startDepth then
                return result
            end
            
            local item = parseListItem(content)
            table.insert(result, item)
            i = i + 1
            goto continue
        end
        
        if depth < startDepth then
            return result
        end
        
        local header = parseArrayHeader(content)
        if header then
            local keyPrefixEnd = content:find("%[") - 1
            local keyPrefix = content:sub(1, keyPrefixEnd):match("^%s*(.-)%s*$")
            if keyPrefix == "" then
                i = i + 1
                goto continue
            end
            
            local key
            if keyPrefix:sub(1, 1) == '"' and keyPrefix:sub(#keyPrefix, #keyPrefix) == '"' then
                key = unescapeString(keyPrefix:sub(2, #keyPrefix - 1))
            else
                key = keyPrefix
            end
            
            local arr = {}
            
            if header.fields then
                local j = i + 1
                while j <= #lines do
                    local rowLine = lines[j]
                    if rowLine == "" then break end
                    
                    local rowDepth = countLeadingSpaces(rowLine)
                    if rowDepth <= depth then break end
                    
                    local obj = parseTabularRow(rowLine, header.fields, header.delimiter)
                    table.insert(arr, obj)
                    j = j + 1
                end
                
                result[key] = arr
                i = j
                goto continue
            elseif header.inlineValue then
                local values = splitByDelimiter(header.inlineValue, header.delimiter)
                for _, val in ipairs(values) do
                    table.insert(arr, parseValue(val))
                end
                
                result[key] = arr
                i = i + 1
                goto continue
            else
                local j = i + 1
                while j <= #lines do
                    local nextLine = lines[j]
                    if nextLine == "" then break end
                    
                    local nextDepth = countLeadingSpaces(nextLine)
                    if nextDepth <= depth then break end
                    
                    if nextLine:find("^%s*- ") then
                        local item = parseListItem(nextLine)
                        table.insert(arr, item)
                    end
                    j = j + 1
                end
                
                result[key] = arr
                i = j
                goto continue
            end
        end
        
        local key, value = parseKeyValue(content)
        if not key then
            i = i + 1
            goto continue
        end
        
        if value == nil then
            local j = i + 1
            local nestedLines = {}
            local hasMoreLines = false
            while j <= #lines do
                local nextLine = lines[j]
                if nextLine == "" then break end
                
                local nextDepth = countLeadingSpaces(nextLine)
                if nextDepth <= depth then break end
                
                hasMoreLines = true
                table.insert(nestedLines, nextLine)
                j = j + 1
            end
            
            if hasMoreLines then
                local nested = decodeObject(nestedLines, depth)
                result[key] = nested
                i = j
            else
                result[key] = nil
                i = i + 1
            end
        else
            result[key] = value
            i = i + 1
        end
        
        ::continue::
    end
    
    return result
end

function toon.decode(text)
    text = text or ""
    
    local lines = parseLines(text)
    
    if #lines == 0 then
        return {}
    end
    
    local nonEmptyLines = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            table.insert(nonEmptyLines, line)
        end
    end
    
    if #nonEmptyLines == 0 then
        return {}
    end
    
    local firstLine = nonEmptyLines[1]
    local firstHeader = parseArrayHeader(firstLine)
    
    if firstHeader and not firstLine:find("^[A-Za-z_]") and not firstLine:find('^"') then
        return decodeRootArray(lines)
    end
    
    if #nonEmptyLines == 1 then
        local line = nonEmptyLines[1]
        if not parseArrayHeader(line) and not line:find(":") then
            local value = parseValue(line)
            if value ~= nil then
                return value
            end
        end
    end
    
    return decodeObject(lines, 0)
end

return toon
