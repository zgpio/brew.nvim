filename = '/Users/zgp/vtest/.config/nvim/rc/dein.toml'
local text = vim.fn.join(vim.fn.readfile(filename), "\n")
text = vim.fn.iconv(text, 'utf8', vim.o.encoding)
TOML = require "toml"
print(vim.inspect(TOML.parse(text)))
print(vim.inspect(TOML))

-- print(debug.traceback())
-- dein_log:write(vim.inspect(process), "\n")
-- dein_log:flush()
