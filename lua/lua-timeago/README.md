# lua-timeago
Simple Lua library library for displaying dates as relative time ago language 

## Installation
You can just copy the source files into your project or use the [rock](https://luarocks.org/modules/f-person/lua-timeago) with [luarocks](https://luarocks.org/).

## Basic Usage
```lua
local timeago = require('lua-timeago')

local now = os.time()
timeago.format(now - (60 * 5)) -- Returns '5 minutes ago'
```

### Language
The library uses English by default. You can set the language with `set_language`
function. It accepts a string with the language file name from the `languages`
directory or a dictionary with language rules (take a look at `languages/en.lua` for an example).

```lua
local timeago = require('lua-timeago')

local now = os.time()
timeago.format(now - (60 * 5)) -- Returns '5 minutes ago'

timeago.set_language('hy')
timeago.format(now - (60 * 5)) -- Returns '5 րոպե առաջ'
```

---
Thanks to [wscherphof/lua-timeago](https://github.com/wscherphof/lua-timeago)
