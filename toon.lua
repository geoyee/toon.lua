-- toon.lua - TOON (Typed Object Notation) parser for Lua
-- https://toonformat.dev/

local toon = {version = "0.1.0"}

-- ============================================================================
-- UTILITY FUNCTIONS
-- General purpose utilities used throughout the module.
-- ============================================================================

--- Trim whitespace from both ends of a string.
-- @param s (string) The string to trim.
-- @return (string) The trimmed string.
local function trim(s)
    return s and s:match("^%s*(.-)%s*$") or ""
end

--- Check if a value represents an array (non-empty sequential table).
-- @param t (any) Value to check.
-- @return (boolean) True if t is an array, false otherwise.
local function isArray(t)
    if type(t) ~= "table" then return false end
    if #t > 0 then return true end
    local mt = getmetatable(t)
    return mt and mt.n ~= nil
end

--- Count leading spaces in a string.
-- @param l (string) The line to check.
-- @return (number) Number of leading spaces.
local function countSpaces(l)
    local match = l:match("^ *")
    return match and #match or 0
end

--- Split a string by a delimiter, respecting quoted sections.
-- Optimized to use table storage for better long-string performance.
-- @param s (string) The string to split.
-- @param d (string) The delimiter character.
-- @return (table) Array of split segments.
local function splitDelim(s, d)
    if not s or s == "" then return {} end
    
    local result = {}
    local current = ""
    local inQuote = false
    local len = #s
    
    for i = 1, len do
        local c = s:sub(i, i)
        if c == '"' then
            inQuote = not inQuote
            current = current .. c
        elseif not inQuote and c == d then
            result[#result + 1] = trim(current)
            current = ""
        else
            current = current .. c
        end
    end
    
    result[#result + 1] = trim(current)
    return result
end

--- Parse a line into key-value pairs.
-- @param line (string) The line to parse.
-- @return (mixed) Key (string) or nil if no colon found.
-- @return (mixed) Value or nil.
local function parseKeyValue(line)
    local colonPos = line:find(":")
    if not colonPos then return nil end
    
    local keyPart = trim(line:sub(1, colonPos - 1))
    local valuePart = trim(line:sub(colonPos + 1))
    
    if keyPart == "" then return nil end
    
    local key
    if keyPart:sub(1, 1) == '"' and keyPart:sub(-1) == '"' then
        key = keyPart:sub(2, -2)
    else
        key = keyPart
    end
    
    if valuePart == "" then return key, nil end
    return key, valuePart
end

--- Split a dotted path into components.
-- Pre-computes path splitting for use in path expansion.
-- @param path (string) Dotted path like "a.b.c".
-- @return (table) Array of path components.
local function splitPath(path)
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

-- ============================================================================
-- STRING ESCAPING AND UNESCAPING
-- Handle special character escaping for strings.
-- ============================================================================

--- Escape special characters in a string for TOON output.
-- Uses optimized single-pass replacement.
-- @param s (string) The string to escape.
-- @return (string) The escaped string.
local function escapeString(s)
    if s == nil then return "null" end
    
    local result = {}
    local len = #s
    local pos = 1
    
    while pos <= len do
        local c = s:sub(pos, pos)
        local escape = nil
        
        if c == "\\" then escape = "\\\\"
        elseif c == '"' then escape = '\\"'
        elseif c == "\n" then escape = "\\n"
        elseif c == "\r" then escape = "\\r"
        elseif c == "\t" then escape = "\\t"
        elseif string.byte(c) <= 31 then
            escape = string.format("\\%03d", string.byte(c))
        end
        
        if escape then
            result[#result + 1] = escape
        else
            result[#result + 1] = c
        end
        
        pos = pos + 1
    end
    
    return table.concat(result)
end

--- Unescape a TOON string to get the original value.
-- @param s (string) The escaped string.
-- @return (string) The unescaped string.
local function unescapeString(s)
    if s == nil then return nil end
    
    return (s:gsub("\\(%d%d%d)", function(n)
        local val = tonumber(n)
        if val and val <= 127 then
            return string.char(val)
        end
        return "\\" .. n
    end)
    :gsub("\\n", "\n")
    :gsub("\\r", "\r")
    :gsub("\\t", "\t")
    :gsub('\\"', '"')
    :gsub("\\\\", "\\"))
end

-- ============================================================================
-- KEY ENCODING AND DECODING
-- Functions for handling key formatting (quoting, escaping).
-- ============================================================================

--- Decode a key from TOON input.
-- Handles quoted and unquoted keys.
-- @param kp (string) The key part from parsing.
-- @return (string) The decoded key.
local function decodeKey(kp)
    if kp:sub(1, 1) == '"' and kp:sub(-1) == '"' then
        return unescapeString(kp:sub(2, -2))
    end
    return kp
end

--- Encode a key for TOON output.
-- Quotes keys that contain special characters or are reserved words.
-- @param k (any) The key to encode.
-- @return (string) The encoded key.
local function encodeKey(k)
    if type(k) ~= "string" or k == "" then
        return '"' .. tostring(k) .. '"'
    end
    
    if k:find("[%.%s]") or not k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
        return '"' .. k .. '"'
    end
    
    return k
end

-- ============================================================================
-- NUMBER FORMATTING
-- Handle number to string conversion for TOON output.
-- Optimized to minimize gsub calls.
-- ============================================================================

--- Format a number for TOON output.
-- Handles special cases and optimizes formatting.
-- @param n (number) The number to format.
-- @return (string) The formatted number string.
local function formatNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then
        return "null"
    end
    
    if n == 0 then return "0" end
    
    local s = tostring(n)
    
    if s:find("^%-?0%.") then
        s = s:gsub("^(%-?)0+(%d)", "%1%2")
    end
    
    if s:find("%.") then
        s = s:gsub("(%..-)0+$", "%1")
        s = s:gsub("%.$", "")
    end
    
    return s
end

-- ============================================================================
-- VALUE PARSING AND ENCODING
-- Parse and encode individual values.
-- ============================================================================

--- Parse a token value into its Lua equivalent.
-- @param tok (string) The token to parse.
-- @return (mixed) The parsed Lua value.
local function parseValue(tok)
    if not tok or tok == "" then return "" end
    
    if tok == "null" then return nil end
    if tok == "true" then return true end
    if tok == "false" then return false end
    
    if tok:sub(1, 1) == '"' and tok:sub(-1) == '"' then
        return unescapeString(tok:sub(2, -2))
    end
    
    local n = tonumber(tok)
    if n and n == n and n ~= math.huge and n ~= -math.huge then
        return n
    end
    
    return tok
end

--- Check if a string value needs quoting in TOON output.
-- @param v (string) The value to check.
-- @param delim (string) The array delimiter.
-- @return (boolean) True if quoting is needed.
local function needsQuoting(v, delim)
    if type(v) ~= "string" then return false end
    if v == "" then return true end
    if v:match("^%s") or v:match("%s$") then return true end
    if v == "true" or v == "false" or v == "null" then return true end
    if tonumber(v) then return true end
    if v:find("[%\"%:%[%]%{%}%%\\]") then return true end
    if v:find("[\n\r\t]") then return true end
    if delim and v:find(delim, 1, true) then return true end
    if v:sub(1, 1) == "-" then return true end
    return false
end

-- ============================================================================
-- DELIMITER HANDLING
-- Manage array delimiters for encoding and decoding.
-- ============================================================================

--- Get the delimiter character from options.
-- @param opts (table) Options table.
-- @return (string) The delimiter character.
local function getDelimiter(opts)
    if opts and opts.delimiter == "tab" then return "\t" end
    if opts and opts.delimiter == "pipe" then return "|" end
    return ","
end

--- Get the delimiter mark for array header.
-- @param delim (string) The delimiter character.
-- @return (string) The delimiter mark to use in header.
local function getDelimiterMark(delim)
    if delim == "\t" then return "\t" end
    if delim == "|" then return "|" end
    return ""
end

-- ============================================================================
-- PATH EXPANSION
-- Handle dotted path expansion during decoding.
-- ============================================================================

--- Set a nested value in a table using a dotted path.
-- Optimized with pre-split paths.
-- @param t (table) The table to modify.
-- @param path (string) Dotted path or pre-split parts table.
-- @param value (any) The value to set.
-- @param pathParts (table) Optional pre-split path components.
local function setNestedValue(t, path, value, pathParts)
    local parts = pathParts or (type(path) == "table" and path or splitPath(path))
    local current = t
    local len = #parts
    
    for i = 1, len do
        local part = parts[i]
        if i == len then
            current[part] = value
        else
            if current[part] == nil or type(current[part]) ~= "table" then
                current[part] = {}
            end
            current = current[part]
        end
    end
end

-- ============================================================================
-- KEY FOLDING
-- Handle key folding during encoding (nested keys to dotted notation).
-- Implemented iteratively to avoid stack overflow on deep nesting.
-- ============================================================================

--- Check if a value can be folded (all single-key nested tables).
-- Returns the folded path and leaf value if foldable.
-- Iterative implementation to prevent stack overflow.
-- @param v (table) The value to check.
-- @return (boolean) Whether the value can be folded.
-- @return (string/nil) The folded path (nil if not foldable).
-- @return (any) The leaf value.
local function canFoldKey(v)
    if type(v) ~= "table" then
        return false, nil, v
    end
    
    if next(v) == nil then
        return false, nil, nil
    end
    
    if isArray(v) then
        return false, nil, nil
    end
    
    local path = ""
    local current = v
    
    while true do
        local keys = {}
        for k in pairs(current) do
            keys[#keys + 1] = k
        end
        
        if #keys ~= 1 then
            return false, path == "" and nil or path, current
        end
        
        local key = keys[1]
        if type(key) ~= "string" then
            return false, path == "" and nil or path, current
        end
        
        if key == "" or key:find("[%.%s]") or not key:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            return false, path == "" and nil or path, current
        end
        
        path = path == "" and key or path .. "." .. key
        local child = current[key]
        
        if type(child) ~= "table" or next(child) == nil or isArray(child) then
            return true, path, child
        end
        
        current = child
    end
end

--- Get a nested value using a dotted path.
-- Iterative implementation for better performance.
-- @param v (table) The table to search.
-- @param path (string) Dotted path or pre-split parts.
-- @param pathParts (table) Optional pre-split path components.
-- @return (any) The nested value or nil.
local function getNestedValue(v, path, pathParts)
    local parts = pathParts or (type(path) == "table" and path or splitPath(path))
    local current = v
    local len = #parts
    
    for i = 1, len do
        if current == nil then return nil end
        current = current[parts[i]]
    end
    
    return current
end

-- ============================================================================
-- ENCODER - HELPER FUNCTIONS
-- Forward declarations and helper functions for encoding.
-- ============================================================================

-- Forward declarations for mutually recursive functions
local encodeArray
local encodeObject

--- Encode a single value to TOON string.
-- @param v (any) The value to encode.
-- @param opts (table) Encoding options.
-- @param delim (string) The array delimiter.
-- @return (string) The encoded value.
local function encodeValue(v, opts, delim)
    if v == nil then return "null" end
    
    local tp = type(v)
    
    if tp == "boolean" then
        return v and "true" or "false"
    end
    
    if tp == "number" then
        return formatNumber(v)
    end
    
    if tp == "string" then
        if needsQuoting(v, delim) then
            return '"' .. escapeString(v) .. '"'
        end
        return v
    end
    
    if tp == "table" then
        if isArray(v) then
            return encodeArray(v, 0, opts, delim)
        end
        return encodeObject(v, 0, opts, delim)
    end
    
    return "null"
end

--- Fold and encode a value with key folding.
-- @param prefix (string) The current prefix path.
-- @param v (any) The value to encode.
-- @param opts (table) Encoding options.
-- @param delim (string) The delimiter.
-- @param lines (table) Output lines accumulator.
local function foldValue(prefix, v, opts, delim, lines)
    local tp = type(v)
    
    if tp ~= "table" or isArray(v) then
        lines[#lines + 1] = prefix .. ": " .. encodeValue(v, opts, delim)
        return
    end
    
    if next(v) == nil then
        lines[#lines + 1] = prefix .. ":"
        return
    end
    
    local foldable, foldedPath, leafValue = canFoldKey(v)
    
    if foldable then
        lines[#lines + 1] = prefix .. "." .. foldedPath .. ": " .. encodeValue(leafValue, opts, delim)
    elseif foldedPath then
        local leaf = getNestedValue(v, foldedPath)
        if leaf ~= nil then
            lines[#lines + 1] = prefix .. "." .. foldedPath .. ": " .. encodeValue(leaf, opts, delim)
        else
            lines[#lines + 1] = prefix .. "." .. foldedPath .. ":"
        end
    else
        for k, val in pairs(v) do
            local fk = encodeKey(k)
            foldValue(prefix .. "." .. fk, val, opts, delim, lines)
        end
    end
end

--- Encode an array to TOON format.
-- Optimized to check array characteristics in a single pass.
-- @param a (table) The array to encode.
-- @param lvl (number) Indentation level.
-- @param opts (table) Encoding options.
-- @param delim (string) The delimiter.
-- @return (string) The encoded array.
function encodeArray(a, lvl, opts, delim)
    if type(a) ~= "table" then return "null" end
    
    local indent = string.rep(" ", (opts.indent or 2) * lvl)
    local nextIndent = string.rep(" ", (opts.indent or 2) * (lvl + 1))
    delim = delim or getDelimiter(opts)
    local count = #a
    
    if count == 0 then
        return indent .. "[" .. count .. getDelimiterMark(delim) .. "]:"
    end
    
    local firstElement = a[1]
    
    if type(firstElement) == "table" then
        local keys = {}
        local allSame = true
        local hasNonPrimitive = false
        
        for _, item in ipairs(a) do
            if type(item) ~= "table" then
                allSame = false
                break
            end
            
            local itemKeys = {}
            for k in pairs(item) do
                itemKeys[#itemKeys + 1] = k
            end
            table.sort(itemKeys)
            
            if #keys == 0 then
                keys = itemKeys
            else
                if #itemKeys ~= #keys then
                    allSame = false
                    break
                end
                for i, k in ipairs(keys) do
                    if itemKeys[i] ~= k then
                        allSame = false
                        break
                    end
                end
                if not allSame then break end
            end
            
            for _, k in ipairs(keys) do
                local vt = type(item[k])
                if vt == "table" or vt == "function" or vt == "userdata" then
                    hasNonPrimitive = true
                    break
                end
            end
            if hasNonPrimitive then break end
        end
        
        if allSame and #keys > 0 and not hasNonPrimitive then
            local fieldList = table.concat(keys, delim)
            local result = {indent .. "[" .. count .. getDelimiterMark(delim) .. "]{" .. fieldList .. "}:"}
            
            for _, item in ipairs(a) do
                local row = {}
                for _, k in ipairs(keys) do
                    row[#row + 1] = encodeValue(item[k], opts, delim)
                end
                result[#result + 1] = nextIndent .. table.concat(row, delim)
            end
            
            return table.concat(result, "\n")
        end
    end
    
    local hasTable = false
    for i = 1, count do
        if type(a[i]) == "table" then
            hasTable = true
            break
        end
    end
    
    if not hasTable then
        local values = {}
        for i = 1, count do
            values[#values + 1] = encodeValue(a[i], opts, delim)
        end
        return indent .. "[" .. count .. getDelimiterMark(delim) .. "]: " .. table.concat(values, delim)
    end
    
    local lines = {indent .. "[" .. count .. getDelimiterMark(delim) .. "]:"}
    
    for i = 1, count do
        local item = a[i]
        if type(item) == "table" then
            if isArray(item) then
                local encoded = encodeArray(item, lvl + 2, opts, delim)
                local firstLine = encoded:match("^[^\n]+") or ""
                lines[#lines + 1] = nextIndent .. "- " .. firstLine
            else
                local encoded = encodeObject(item, lvl + 2, opts, delim)
                lines[#lines + 1] = nextIndent .. "- " .. (encoded:gsub("^%s+", ""))
            end
        else
            lines[#lines + 1] = nextIndent .. "- " .. encodeValue(item, opts, delim)
        end
    end
    
    return table.concat(lines, "\n")
end

--- Encode an object (non-array table) to TOON format.
-- @param o (table) The object to encode.
-- @param lvl (number) Indentation level.
-- @param opts (table) Encoding options.
-- @param delim (string) The delimiter.
-- @return (string) The encoded object.
function encodeObject(o, lvl, opts, delim)
    if type(o) ~= "table" then return "null" end
    
    local indent = string.rep(" ", (opts.indent or 2) * lvl)
    delim = delim or getDelimiter(opts)
    local lines = {}
    
    for k, v in pairs(o) do
        local fk = encodeKey(k)
        local tp = type(v)
        
        if tp == "table" then
            if next(v) == nil then
                if isArray(v) then
                    lines[#lines + 1] = fk .. "[0]:"
                else
                    lines[#lines + 1] = fk .. ":"
                end
            elseif isArray(v) then
                local encoded = encodeArray(v, lvl, opts, delim)
                local nl = encoded:find("\n")
                if nl then
                    lines[#lines + 1] = indent .. fk .. encoded:sub(1, nl - 1)
                    lines[#lines + 1] = encoded:sub(nl + 1)
                else
                    lines[#lines + 1] = indent .. fk .. encoded
                end
            else
                lines[#lines + 1] = indent .. fk .. ":"
                lines[#lines + 1] = encodeObject(v, lvl + 1, opts, delim)
            end
        elseif v == nil then
            lines[#lines + 1] = indent .. fk .. ": null"
        else
            lines[#lines + 1] = indent .. fk .. ": " .. encodeValue(v, opts, delim)
        end
    end
    
    return table.concat(lines, "\n")
end

-- ============================================================================
-- MAIN ENCODER FUNCTION
-- Public API for encoding.
-- ============================================================================

--- Encode a Lua value to TOON string.
-- @param data (table) The data to encode.
-- @param opts (table) Encoding options.
-- @return (string/nil) The encoded TOON string, or nil on error.
function toon.encode(data, opts)
    if type(data) ~= "table" then
        return nil, "data must be a table"
    end
    
    opts = opts or {}
    local delim = getDelimiter(opts)
    local lines = {}
    local useFolding = opts.keyFolding
    
    for k, v in pairs(data) do
        local fk = encodeKey(k)
        local tp = type(v)
        
        if tp == "table" then
            if next(v) == nil then
                if isArray(v) then
                    lines[#lines + 1] = fk .. "[0]:"
                else
                    lines[#lines + 1] = fk .. ":"
                end
            elseif isArray(v) then
                local encoded = encodeArray(v, 0, opts, delim)
                local nl = encoded:find("\n")
                if nl then
                    lines[#lines + 1] = fk .. encoded:sub(1, nl - 1)
                    lines[#lines + 1] = encoded:sub(nl + 1)
                else
                    lines[#lines + 1] = fk .. encoded
                end
            elseif useFolding then
                local foldable, foldedKey = canFoldKey(v)
                if foldable or foldedKey then
                    foldValue(fk, v, opts, delim, lines)
                else
                    lines[#lines + 1] = fk .. ":"
                    lines[#lines + 1] = encodeObject(v, 1, opts, delim)
                end
            else
                lines[#lines + 1] = fk .. ":"
                lines[#lines + 1] = encodeObject(v, 1, opts, delim)
            end
        elseif v == nil then
            lines[#lines + 1] = fk .. ": null"
        else
            lines[#lines + 1] = fk .. ": " .. encodeValue(v, opts, delim)
        end
    end
    
    return table.concat(lines, "\n")
end

-- ============================================================================
-- DECODER - PARSING FUNCTIONS
-- Parsing functions for TOON input.
-- ============================================================================

--- Parse array header to extract count, delimiter, and fields.
-- Simplified structure with clearer logic flow.
-- @param line (string) The line to parse.
-- @return (table/nil) Header info or nil if not an array header.
local function parseArrayHeader(line)
    local openBracket = line:find("%[")
    if not openBracket then return nil end
    
    local closeBracket = line:find("]", openBracket)
    if not closeBracket then return nil end
    
    local inside = line:sub(openBracket + 1, closeBracket - 1)
    local count, delimiter
    
    local pipePos = inside:find("|")
    if pipePos then
        count = tonumber(inside:sub(1, pipePos - 1))
        local delimPart = inside:sub(pipePos + 1)
        delimiter = delimPart == "" and "|" or delimPart
    else
        local tabPos = inside:find("\t")
        if tabPos then
            count = tonumber(inside:sub(1, tabPos - 1))
            local delimPart = inside:sub(tabPos + 1)
            delimiter = delimPart == "" and "\t" or delimPart
        else
            count = tonumber(inside)
            delimiter = ","
        end
    end
    
    if not count then return nil end
    
    local fields = nil
    local rest = line:sub(closeBracket + 1)
    
    if rest:sub(1, 1) == "{" then
        local closeBrace = rest:find("}")
        if closeBrace then
            fields = {}
            local fieldContent = rest:sub(2, closeBrace - 1)
            for field in fieldContent:gmatch("[^,]+") do
                local f = trim(field)
                if f:sub(1, 1) == '"' and f:sub(-1) == '"' then
                    f = unescapeString(f:sub(2, -2))
                end
                fields[#fields + 1] = f
            end
            rest = rest:sub(closeBrace + 1)
        end
    end
    
    if rest:sub(1, 1) ~= ":" then return nil end
    
    local inlineValue = trim(rest:sub(2))
    if inlineValue == "" then inlineValue = nil end
    
    return {
        count = count,
        delimiter = delimiter,
        fields = fields,
        inlineValue = inlineValue
    }
end

--- Parse a list item (array element starting with "-").
-- @param line (string) The line to parse.
-- @return (mixed) The parsed list item.
local function parseListItem(line)
    if not line:find("^%s*- ") then return nil end
    
    local content = trim(line:match("^%s*-(.*)$") or "")
    
    if content == "" then return {} end
    
    local header = parseArrayHeader(content)
    if header then
        if header.inlineValue then
            local values = splitDelim(header.inlineValue, header.delimiter)
            local result = {}
            for _, v in ipairs(values) do
                result[#result + 1] = parseValue(v)
            end
            return result
        end
        return {}
    end
    
    local k, v = parseKeyValue(content)
    if k then return {[k] = parseValue(v)} end
    
    return parseValue(content)
end

--- Parse a tabular row into an object.
-- @param line (string) The line to parse.
-- @param fields (table) Field names.
-- @param delimiter (string) The delimiter character.
-- @return (table) The parsed row object.
local function parseTabularRow(line, fields, delimiter)
    local values = splitDelim(line, delimiter)
    local result = {}
    
    for i, field in ipairs(fields) do
        result[field] = parseValue(values[i] or "")
    end
    
    return result
end

-- ============================================================================
-- DECODER - OBJECT DECODING
-- Main decoding logic for objects.
-- ============================================================================

--- Decode a block of lines into an object.
-- Modularized for better maintainability.
-- @param lines (table) Array of lines.
-- @param startDepth (number) Starting indentation depth.
-- @param opts (table) Decoding options.
-- @return (table) The decoded object.
local function decodeObject(lines, startDepth, opts)
    opts = opts or {}
    local result = {}
    local i = 1
    local len = #lines
    
    while i <= len do
        local line = lines[i]
        
        if line == "" then
            i = i + 1
            goto continue
        end
        
        local depth = countSpaces(line)
        local content = line:sub(depth + 1)
        
        if depth < startDepth then
            return result
        end
        
        if content:find("^%s*- ") then
            if depth < startDepth then return result end
            result[#result + 1] = parseListItem(content)
            i = i + 1
            goto continue
        end
        
        local header = parseArrayHeader(content)
        if header then
            local keyPart = content:sub(1, content:find("%[") - 1)
            local key = decodeKey(trim(keyPart))
            local pathParts = key:find("%.") and splitPath(key) or nil
            
            if header.fields then
                local j = i + 1
                local rows = {}
                while j <= len and lines[j] ~= "" and countSpaces(lines[j]) > depth do
                    rows[#rows + 1] = parseTabularRow(lines[j], header.fields, header.delimiter)
                    j = j + 1
                end
                
                if opts.pathExpansion and pathParts then
                    setNestedValue(result, key, rows, pathParts)
                else
                    result[key] = rows
                end
                
                i = j
            elseif header.inlineValue then
                local values = {}
                for v in header.inlineValue:gmatch("[^" .. header.delimiter .. "]+") do
                    values[#values + 1] = parseValue(trim(v))
                end
                
                if opts.pathExpansion and pathParts then
                    setNestedValue(result, key, values, pathParts)
                else
                    result[key] = values
                end
                
                i = i + 1
            else
                local j = i + 1
                local items = {}
                while j <= len and lines[j] ~= "" and countSpaces(lines[j]) > depth do
                    if lines[j]:find("^%s*- ") then
                        items[#items + 1] = parseListItem(lines[j])
                    end
                    j = j + 1
                end
                
                if opts.pathExpansion and pathParts then
                    setNestedValue(result, key, items, pathParts)
                else
                    result[key] = items
                end
                
                i = j
            end
        else
            local k, v = parseKeyValue(content)
            if k then
                if v == nil then
                    local j = i + 1
                    local nestedLines = {}
                    local hasContent = false
                    
                    while j <= len and lines[j] ~= "" do
                        if countSpaces(lines[j]) <= depth then break end
                        hasContent = true
                        nestedLines[#nestedLines + 1] = lines[j]
                        j = j + 1
                    end
                    
                    if hasContent then
                        local nested = decodeObject(nestedLines, depth, opts)
                        local pathParts = k:find("%.") and splitPath(k) or nil

                        if opts.pathExpansion and pathParts then
                            setNestedValue(result, k, nested, pathParts)
                        else
                            result[k] = nested
                        end
                    else
                        local pathParts = k:find("%.") and splitPath(k) or nil
                        if opts.pathExpansion and pathParts then
                            setNestedValue(result, k, {}, pathParts)
                        else
                            result[k] = {}
                        end
                    end
                    
                    i = j
                else
                    local pathParts = k:find("%.") and splitPath(k) or nil
                    
                    if opts.pathExpansion and pathParts then
                        setNestedValue(result, k, parseValue(v), pathParts)
                    else
                        result[k] = parseValue(v)
                    end
                    
                    i = i + 1
                end
            else
                i = i + 1
            end
        end
        
        ::continue::
    end
    
    return result
end

--- Parse text into lines, handling trailing newline.
-- @param text (string) The text to parse.
-- @return (table) Array of lines.
local function parseLines(text)
    text = text or ""
    local lines = {}
    
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" or #lines > 0 then
            lines[#lines + 1] = line
        end
    end
    
    return lines
end

-- ============================================================================
-- MAIN DECODER FUNCTION
-- Public API for decoding.
-- ============================================================================

--- Decode a TOON string to Lua table.
-- @param text (string) The TOON text to decode.
-- @param opts (table) Decoding options.
-- @return (table) The decoded Lua table.
function toon.decode(text, opts)
    text = text or ""
    opts = opts or {}
    
    local lines = parseLines(text)
    if #lines == 0 then return {} end
    
    local nonEmptyLines = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            nonEmptyLines[#nonEmptyLines + 1] = line
        end
    end
    
    if #nonEmptyLines == 0 then return {} end
    
    local firstLine = nonEmptyLines[1]
    local header = parseArrayHeader(firstLine)
    
    if header and not firstLine:find("^[A-Za-z_]") and not firstLine:find('^"') then
        local result = {}
        
        if header.inlineValue then
            for v in header.inlineValue:gmatch("[^" .. header.delimiter .. "]+") do
                result[#result + 1] = parseValue(trim(v))
            end
        elseif header.fields then
            for i = 2, #nonEmptyLines do
                if nonEmptyLines[i] == "" then break end
                result[#result + 1] = parseTabularRow(nonEmptyLines[i], header.fields, header.delimiter)
            end
        end
        
        return result
    end
    
    if #nonEmptyLines == 1 then
        local line = nonEmptyLines[1]
        if not line:find(":") then
            local value = parseValue(line)
            if value ~= nil then return value end
        end
    end
    
    return decodeObject(lines, 0, opts)
end

return toon
