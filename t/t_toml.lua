local info = debug.getinfo(1, "S")
local sfile = info.source:sub(2) -- remove @
local project_root = vim.fn.fnamemodify(sfile, ':p:h:h')

local filename = project_root .. '/t/t.toml'
local text = vim.fn.join(vim.fn.readfile(filename), "\n")
text = vim.fn.iconv(text, 'utf8', vim.o.encoding)
local toml = require "toml"
print(vim.inspect(toml.parse(text)))
print(vim.inspect(toml))

-- print(debug.traceback())
-- dein_log:write(vim.inspect(process), "\n")
-- dein_log:flush()
