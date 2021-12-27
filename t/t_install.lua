-- Unit testing & Integration testing
-- Test install.lua
_G._TEST = true
package.loaded["dein/install"] = nil
local install = require 'dein/install'

print(vim.inspect(install.__convert_args('ping')))
assert(install._strwidthpart('fool', 3)=='foo')
assert(install._strwidthpart_reverse('fool', 3)=='ool')
assert(install._strwidthpart_reverse('你好世界', 0)=='')
assert(install._strwidthpart_reverse('你好世界', 3)=='界')  -- 从右往左截取<=3个显示单元的子串, 1个汉字占两个显示单元
assert(install._strwidthpart_reverse('你好世界', 2)=='界')
assert(install._strwidthpart_reverse('你好世界', 4)=='世界')
assert(install._strwidthpart_reverse('你好世界', 7)=='好世界')
assert(install._strwidthpart_reverse('你好世界', 20)=='你好世界')
assert(install._truncate_skipping('hello world', 6, 2, '...')=='h...ld')
print(install.__echo_mode('hello world\nneovim\n', 'error'))

-- Test install log
print(install._updates_log('hello log'))
print(install._updates_log('foo bar'))
print(vim.inspect(install._var_updates_log))
install._log('install log')
print(vim.inspect(install._var_log))

print(install._iconv('你好neovim', 'utf8', 'char'))
