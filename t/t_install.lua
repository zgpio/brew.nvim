-- Unit testing & Integration testing
-- Test install.lua
_G._TEST = true
package.loaded["dein/install"] = nil
local install = require 'dein/install'

print(vim.inspect(install.__convert_args('ping')))
assert(install._strwidthpart('fool', 3)=='foo')
assert(install._strwidthpart_reverse('fool', 3)=='ool')
print(install._strwidthpart_reverse('你好世界', 3))
print(install._strwidthpart_reverse('你好世界', 2))
assert(install._truncate_skipping('hello world', 6, 2, '...')=='h...ld')
print(install.__echo_mode('hello world\nneovim\n', 'error'))

-- Test install log
print(install._updates_log('hello log'))
print(install._updates_log('foo bar'))
print(vim.inspect(install._var_updates_log))
install._log('install log')
print(vim.inspect(install._var_log))

print(install._iconv('你好neovim', 'utf8', 'char'))
