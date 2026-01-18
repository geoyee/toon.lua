-- toon.lua - TOON (Typed Object Notation) parser for Lua
-- https://toonformat.dev/

local toon = {}

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function trim(s) return s:match("^%s*(.-)%s*$") end

local function escapeString(s)
    if s == nil then return "null" end
    return (s:gsub("[\\\"%c]", {
        ["\\"] = "\\\\",
        ["\""] = "\\\"",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t"
    }))
end

local function unescapeString(s)
    if s == nil then return nil end
    return (s:gsub("\\(%d%d%d)", function(n)
        n = tonumber(n)
        if n <= 127 then return string.char(n) else return "\\" .. n end
    end):gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\"))
end

local function getDelimiter(o)
    if o and o.delimiter == "tab" then return "\t" end
    if o and o.delimiter == "pipe" then return "|" end
    return ","
end

local function getDelimiterMark(delim)
    if delim == "\t" then return "\t" end
    if delim == "|" then return "|" end
    return ""
end

local function formatNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    if n == 0 then return "0" end
    local s = tostring(n)
    s = s:gsub("^(%-?)0+(%d)", "%1%2"):gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return s
end

local function isArray(t)
    if type(t) ~= "table" then return false end
    return #t > 0 or (getmetatable(t) and getmetatable(t).n)
end

local function needsQuoting(v, delim)
    if type(v) ~= "string" then return false end
    return v == "" or v:match("^%s") or v:match("%s$") or
        v == "true" or v == "false" or v == "null" or tonumber(v) or
        v:find("[%\"%:%[%]%{%}%%\\]") or v:find("[\n\r\t]") or
        (delim and v:find(delim, 1, true)) or v:sub(1,1) == "-"
end

-- ============================================================================
-- ENCODER
-- ============================================================================

local encodeObject, encodeArray

local function encodeValue(v, opts, delim)
    if v == nil then return "null" end
    local tp = type(v)
    if tp == "boolean" then return v and "true" or "false" end
    if tp == "number" then return formatNumber(v) end
    if tp == "string" then
        return needsQuoting(v, delim) and '"' .. escapeString(v) .. '"' or v
    end
    if tp == "table" then
        if isArray(v) then return encodeArray(v, 0, opts, delim) end
        return encodeObject(v, 0, opts, delim)
    end
    return "null"
end

encodeArray = function(a, lvl, opts, delim)
    if type(a) ~= "table" then return "null" end
    local ind = string.rep(" ", (opts.indent or 2) * lvl)
    local nxt = string.rep(" ", (opts.indent or 2) * (lvl + 1))
    if delim == nil then delim = getDelimiter(opts) end
    local c = #a
    if c == 0 then return ind .. "[" .. c .. getDelimiterMark(delim) .. "]:" end

    local first = a[1]
    if type(first) == "table" then
        local ks, same = {}, true
        for k in pairs(first) do table.insert(ks, k) end
        table.sort(ks)
        for _, it in ipairs(a) do
            if type(it) ~= "table" then same = false break end
            local iks = {}
            for k in pairs(it) do table.insert(iks, k) end
            table.sort(iks)
            if #iks ~= #ks then same = false break end
            for _, k in ipairs(ks) do
                local vt = type(it[k])
                if not it[k] or (vt ~= "string" and vt ~= "number" and vt ~= "boolean") then
                    same = false break
                end
            end
            if not same then break end
        end
        if same then
            local fl = table.concat(ks, delim)
            local lines = {ind .. "[" .. c .. getDelimiterMark(delim) .. "]{" .. fl .. "}:"}
            for _, it in ipairs(a) do
                local row = {}
                for _, k in ipairs(ks) do row[#row+1] = encodeValue(it[k], opts, delim) end
                lines[#lines+1] = nxt .. table.concat(row, delim)
            end
            return table.concat(lines, "\n")
        end
    end

    local allPrim = true
    for i = 1, c do if type(a[i]) == "table" then allPrim = false break end end
    if allPrim then
        local vals = {}
        for i = 1, c do vals[#vals+1] = encodeValue(a[i], opts, delim) end
        return ind .. "[" .. c .. getDelimiterMark(delim) .. "]: " .. table.concat(vals, delim)
    end

    local lines = {ind .. "[" .. c .. getDelimiterMark(delim) .. "]:"}
    for i = 1, c do
        local it = a[i]
        if type(it) == "table" then
            if isArray(it) then
                local ne = encodeArray(it, lvl + 2, opts, delim)
                lines[#lines+1] = nxt .. "- " .. (ne:match("^[^\n]+") or "")
            else
                local ne = encodeObject(it, lvl + 2, opts, delim)
                lines[#lines+1] = nxt .. "- " .. ne:gsub("^%s+", "")
            end
        else
            lines[#lines+1] = nxt .. "- " .. encodeValue(it, opts, delim)
        end
    end
    return table.concat(lines, "\n")
end

encodeObject = function(o, lvl, opts, delim)
    if type(o) ~= "table" then return "null" end
    local ind = string.rep(" ", (opts.indent or 2) * lvl)
    local nxt = string.rep(" ", (opts.indent or 2) * (lvl + 1))
    delim = delim or getDelimiter(opts)
    local lines = {}

    for k, v in pairs(o) do
        local fk = k
        if type(k) ~= "string" or k == "" or k:find("[%.%s]") or not k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            fk = '"' .. escapeString(k) .. '"'
        end

        local tp = type(v)
        if tp == "table" then
            if next(v) == nil then
                if isArray(v) then
                    lines[#lines+1] = fk .. "[0]:"
                else
                    lines[#lines+1] = fk .. ":"
                end
            elseif isArray(v) then
                local en = encodeArray(v, lvl, opts, delim)
                local nl = en:find("\n")
                if nl then
                    lines[#lines+1] = ind .. fk .. en:sub(1, nl - 1)
                    lines[#lines+1] = en:sub(nl + 1)
                else
                    lines[#lines+1] = ind .. fk .. en
                end
            else
                lines[#lines+1] = ind .. fk .. ":"
                lines[#lines+1] = encodeObject(v, lvl + 1, opts, delim)
            end
        elseif v == nil then
            lines[#lines+1] = ind .. fk .. ": null"
        else
            lines[#lines+1] = ind .. fk .. ": " .. encodeValue(v, opts, delim)
        end
    end
    return table.concat(lines, "\n")
end

function toon.encode(d, o)
    if type(d) ~= "table" then return nil, "data must be a table" end
    o = o or {}
    local lines = {}
    local delim = getDelimiter(o)
    for k, v in pairs(d) do
        local fk = k
        if type(k) ~= "string" or k == "" or k:find("[%.%s]") or not k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            fk = '"' .. escapeString(k) .. '"'
        end
        local tp = type(v)
        if tp == "table" then
            if next(v) == nil then
                if isArray(v) then
                    lines[#lines+1] = fk .. "[0]:"
                else
                    lines[#lines+1] = fk .. ":"
                end
            elseif isArray(v) then
                local en = encodeArray(v, 0, o, delim)
                local nl = en:find("\n")
                if nl then
                    lines[#lines+1] = fk .. en:sub(1, nl - 1)
                    lines[#lines+1] = en:sub(nl + 1)
                else
                    lines[#lines+1] = fk .. en
                end
            else
                lines[#lines+1] = fk .. ":"
                lines[#lines+1] = encodeObject(v, 1, o, delim)
            end
        elseif v == nil then
            lines[#lines+1] = fk .. ": null"
        else
            lines[#lines+1] = fk .. ": " .. encodeValue(v, o, delim)
        end
    end
    return table.concat(lines, "\n")
end

-- ============================================================================
-- DECODER
-- ============================================================================

local function parseValue(tok)
    if not tok or tok == "" then return "" end
    if tok == "null" then return nil end
    if tok == "true" then return true end
    if tok == "false" then return false end
    if tok:sub(1,1) == '"' and tok:sub(-1) == '"' then
        return unescapeString(tok:sub(2, -2))
    end
    local n = tonumber(tok)
    if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
    return tok
end

local function parseKeyValue(line)
    local cp = line:find(":")
    if not cp then return nil end
    local kp = trim(line:sub(1, cp - 1))
    local vp = trim(line:sub(cp + 1))
    if kp == "" then return nil end
    local key = (kp:sub(1,1) == '"' and kp:sub(-1) == '"') and unescapeString(kp:sub(2, -2)) or kp
    if vp == "" then return key, nil end
    return key, parseValue(vp)
end

local function splitDelim(s, d)
    local r, cur, inq = {}, "", false
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == '"' then inq = not inq
        elseif not inq and c == d then r[#r+1] = trim(cur); cur = ""
        else cur = cur .. c end
    end
    r[#r+1] = trim(cur)
    return r
end

local function parseArrayHeader(line)
    local bs = line:find("%[")
    if not bs then return nil end
    local be = line:find("]", bs)
    if not be then return nil end
    
    local inside = line:sub(bs + 1, be - 1)
    
    local cnt, d
    
    local pipe_pos = inside:find("|")
    if pipe_pos then
        local count_part = inside:sub(1, pipe_pos - 1)
        local delim_part = inside:sub(pipe_pos + 1)
        cnt = tonumber(count_part)
        if delim_part == "" then
            d = "|"
        else
            d = delim_part
        end
    else
        local tab_pos = inside:find("\t")
        if tab_pos then
            local count_part = inside:sub(1, tab_pos - 1)
            local delim_part = inside:sub(tab_pos + 1)
            cnt = tonumber(count_part)
            if delim_part == "" then
                d = "\t"
            else
                d = delim_part
            end
        else
            cnt = tonumber(inside)
            d = ","
        end
    end
    
    if not cnt then return nil end
    
    local fl = nil
    local rest = line:sub(be + 1)
    if rest:sub(1, 1) == "{" then
        local eb = rest:find("}")
        if eb then
            fl = {}
            for f in rest:sub(2, eb - 1):gmatch("[^,]+") do
                f = trim(f)
                if f:sub(1,1) == '"' and f:sub(-1) == '"' then f = unescapeString(f:sub(2, -2)) end
                fl[#fl+1] = f
            end
            rest = rest:sub(eb + 1)
        end
    end
    if rest:sub(1, 1) ~= ":" then return nil end
    local iv = trim(rest:sub(2))
    return {count = cnt, delimiter = d, fields = fl, inlineValue = iv ~= "" and iv or nil}
end

local function parseTabularRow(l, fs, d)
    local vs = splitDelim(l, d)
    local o = {}
    for i, f in ipairs(fs) do o[f] = parseValue(vs[i] or "") end
    return o
end

local function parseListItem(l)
    if not l:find("^%s*- ") then return nil end
    local c = trim(l:match("^%s*-(.*)$") or "")
    if c == "" then return {} end
    local h = parseArrayHeader(c)
    if h then
        if h.inlineValue then
            local vs = splitDelim(h.inlineValue, h.delimiter)
            local r = {}
            for _, v in ipairs(vs) do r[#r+1] = parseValue(v) end
            return r
        end
        return {}
    end
    local k, v = parseKeyValue(c)
    if k then return {[k] = v} end
    return parseValue(c)
end

local function countSpaces(l) return (l:match("^ *") or ""):len() end

local function decodeObject(ls, sd)
    local r, i = {}, 1
    while i <= #ls do
        local ln = ls[i]
        if ln == "" then i = i + 1 end

        local d = countSpaces(ln)
        local ct = ln:sub(d + 1)

        if d < sd then return r end

        if ct:find("^%s*- ") then
            if d < sd then return r end
            r[#r+1] = parseListItem(ct)
            i = i + 1
        end

        local h = parseArrayHeader(ct)
        if h then
            local kp = trim(ct:sub(1, ct:find("%[") - 1))
            local key = (kp:sub(1,1) == '"' and kp:sub(-1) == '"') and unescapeString(kp:sub(2, -2)) or kp
            local a = {}

            if h.fields then
                local j = i + 1
                while j <= #ls and ls[j] ~= "" and countSpaces(ls[j]) > d do
                    a[#a+1] = parseTabularRow(ls[j], h.fields, h.delimiter)
                    j = j + 1
                end
                r[key] = a
                i = j
            elseif h.inlineValue then
                for v in h.inlineValue:gmatch("[^" .. h.delimiter .. "]+") do
                    a[#a+1] = parseValue(trim(v))
                end
                r[key] = a
                i = i + 1
            else
                local j = i + 1
                while j <= #ls and ls[j] ~= "" and countSpaces(ls[j]) > d do
                    if ls[j]:find("^%s*- ") then a[#a+1] = parseListItem(ls[j]) end
                    j = j + 1
                end
                r[key] = a
                i = j
            end
        else
            local k, v = parseKeyValue(ct)
            if k then
                if v == nil then
                    local j = i + 1
                    local ns, hc = {}, false
                    while j <= #ls and ls[j] ~= "" do
                        if countSpaces(ls[j]) <= d then break end
                        hc = true
                        ns[#ns+1] = ls[j]
                        j = j + 1
                    end
                    if hc then
                        r[k] = decodeObject(ns, d)
                    end
                    i = j
                else
                    r[k] = v
                    i = i + 1
                end
            else
                i = i + 1
            end
        end
    end
    return r
end

local function parseLines(t)
    local l = {}
    for line in (t .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" or #l > 0 then l[#l+1] = line end
    end
    return l
end

function toon.decode(t)
    t = t or ""
    local ls = parseLines(t)
    if #ls == 0 then return {} end

    local ne = {}
    for _, l in ipairs(ls) do if l ~= "" then ne[#ne+1] = l end end
    if #ne == 0 then return {} end

    local fl = ne[1]
    local fh = parseArrayHeader(fl)
    if fh and not fl:find("^[A-Za-z_]") and not fl:find('^"') then
        local a = {}
        if fh.inlineValue then
            for v in fh.inlineValue:gmatch("[^" .. fh.delimiter .. "]+") do a[#a+1] = parseValue(trim(v)) end
        elseif fh.fields then
            for i = 2, #ne do if ne[i] == "" then break end a[#a+1] = parseTabularRow(ne[i], fh.fields, fh.delimiter) end
        end
        return a
    end

    if #ne == 1 then
        local line = ne[1]
        if not line:find(":") then
            local v = parseValue(line)
            if v ~= nil then return v end
        end
    end

    return decodeObject(ls, 0)
end

return toon
