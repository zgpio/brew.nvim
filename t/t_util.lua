local reload = require 'dein/reload'
reload.reload('brew/util')
local util = require 'brew/util'

-- print(vim.inspect(util))
assert(util.chomp('foo/') == 'foo')
assert(util.chomp('foo') == 'foo')
assert(util.chomp('foo//') == 'foo/')

assert(vim.deep_equal(util.convert2list('1\n2\n3'), {'1', '2', '3'}))
assert(vim.deep_equal(util.convert2list('1\r\n2\n3'), {'1', '2', '3'}))
assert(vim.deep_equal(util.convert2list('123'), {'123'}))
assert(vim.deep_equal(util.convert2list(''), {}))
assert(vim.deep_equal(util.convert2list({1, 2, 3}), {1, 2, 3}))
assert(vim.deep_equal(util.convert2list(2), {2}))
assert(vim.deep_equal(util.convert2list({}), {}))
assert(vim.deep_equal(util.convert2list({a=2, b=4}), {a=2, b=4}))

print('test api check_install')
print(util.check_install('nvim-treesitter'))
print(util.check_install({'nvim-treesitter', 'bbb', 'ccc'}))
print(util.check_install({'nvim-treesitter', 'neomake', }))
print(util.check_install())

print(util._error('{"auto-pairs"}'))
print(util._error("{'nvim-treesitter'}"))

print('done')
