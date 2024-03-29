-- Unit testing & Integration testing
-- Test install.lua
_G._TEST = true
package.loaded["brew/install"] = nil
local install = require 'brew/install'

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
print(install.__echo_mode('"\'h中e"', 'error'))

-- Test install log
print(install._updates_log('hello log'))
print(install._updates_log('foo bar'))
print(vim.inspect(install._var_updates_log))
install._log('install log')
print(vim.inspect(install._var_log))

-- expr: str or list
-- from/to: encoding {from} to encoding {to}
-- function iconv(expr, from, to)
print(install._iconv('你好neovim', 'utf8', 'char'))
print(vim.inspect(install._iconv({'你好neovim', 'a不b错c'}, 'utf8', 'char')))
