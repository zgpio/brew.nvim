-- test_spec.lua
_G._TEST = true
package.loaded["dein/types/git"] = nil
local git = require "dein/types/git"

print(git_get_revision([[C:\Users\zgp\vtest\.cache\dein\repos\gitee.com\zgpio\auto-pairs]]))
print(vim.inspect(git))
assert(git._join_paths('aaa', 'bbbbbbb')=='aaa/bbbbbbb')
print(git._join_paths('aaa', '/bbbbbbb'))
print(git._join_paths('/aaa', '/bbbbbbb'))
print(git._is_absolute('/home/fool'))
print(git._is_absolute('home/fool'))
print(git._is_git_dir('/home/fool'))
print(git._is_git_dir('/Users/zgp/Note/.git'))

plugin = {
    repo = "https://gitee.com/zgpio/onedark.vim",
    path = "/Users/zgp/vtest/.cache/dein/repos/gitee.com/zgpio/onedark.vim"
}
print(git:get_sync_command(plugin))
print(git:get_uri(plugin.repo, plugin))
print(vim.inspect(git:get_revision_number_command(plugin)))
print(vim.inspect(git:get_revision_lock_command(plugin)))
print(vim.inspect(git:get_rollback_command(plugin, 'revision')))
print(vim.inspect(git:get_revision_remote_command(plugin)))
print(vim.inspect(git:get_fetch_remote_command(plugin)))
print(vim.inspect(git:get_log_command(plugin, 'new_rev', 'old_rev')))
print(vim.inspect(git:init(plugin.repo, {})))
-- TODO 获取git.vim的测试样例
