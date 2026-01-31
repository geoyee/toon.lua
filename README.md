# toon.lua

A lightweight [TOON](https://toonformat.dev/) parser for Lua.

## Install

```bash
cp toon.lua /path/to/your/project/
```

## Usage

```lua
local toon = require("toon")
```

### Encode (Lua -> TOON)

```lua
local data = {
    name = "Alice",
    age = 30,
    tags = {"lua", "programming"},
    metadata = {version = "1.0"}
}

local str = toon.encode(data)
print(str)
```

Output:

```toon
name: Alice
age: 30
tags[2]: lua,programming
metadata:
  version: 1.0
```

### Decode (TOON -> Lua)

```lua
local input = [[
name: Bob
age: 25
scores[3]: 95,87,92
contact:
  email: bob@example.com
]]

local data = toon.decode(input)
print(data.name)        -- Bob
print(data.scores[1])   -- 95
print(data.contact.email) -- bob@example.com
```

## API

### toon.encode(value[, options])

Encode a Lua value to TOON string.

Options:

- `indent` (number): spaces per indent level (default: 2)
- `delimiter` (string): array delimiter - `","`, `"|"`, `"\t"` (default: ",")
- `keyFolding` (string): fold nested keys into dotted notation - `"safe"` (default: nil)

### toon.decode(text[, options])

Decode a TOON string to Lua table.

Options:

- `strict` (boolean): strict parsing mode (default: false)
- `pathExpansion` (boolean): expand dotted keys into nested tables (default: false)

## Array Formats

**Inline arrays:**

```lua
toon.encode({tags = {"a", "b"}})  -- tags[2]: a,b
```

**Tabular arrays:**

```lua
toon.encode({users = {{id = 1, name = "A"}, {id = 2, name = "B"}}})
-- users[2]{id,name}:
--   1,A
--   2,B
```

## Test

> Test case generation and final validation modifications both utilize AI-assisted technology (MiniMax M2.1), which may result in certain edge cases not being fully covered.

These tests were generated based on the [TOON specification](https://github.com/toon-format/spec.git).

```bash
lua test.lua
```

## Example

This example demonstrates mutual conversion between TOON and JSON using [json.lua](https://github.com/rxi/json.lua.git), following the conversion examples in the [TOON examples](https://github.com/toon-format/spec/tree/main/examples/conversions).

```bash
lua example.lua
```

## Other

Code review was performed using AI-assisted tools (gemini-code-assist), with modifications made based on its suggestions.
