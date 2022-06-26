-- test _dict in parse.lua
-- Q: 为什么要备份为orig_opts
_TEST = true
local parse = require'brew/parse'
local plug = {
  depends = "ultisnips",
  hook_post_update = "call coc#util#install()\n",
  hook_source = "source $root/rc/plugins/coc.vim",
  lazy = 1,
  on_ft = { "vim", "c", "cpp", "python", "go", "lua" },
  orig_opts = {
    depends = "ultisnips",
    hook_post_update = "call coc#util#install()\n",
    hook_source = "source $root/rc/plugins/coc.vim",
    lazy = 1,
    on_ft = { "vim", "c", "cpp", "python", "go", "lua" },
    repo = "https://gitee.com/zgpio/coc.nvim",
    rev = "release",
    type = "git"
  },
  path = "/Users/zgp/vtest/.cache/dein/repos/gitee.com/zgpio/coc.nvim",
  repo = "https://gitee.com/zgpio/coc.nvim",
  rev = "release",
  type = "git"
}
print(vim.inspect(parse._dict(plug)))

local plugin1 = {
    on_map = {nx = {'<Plug>'}},
    normalized_name='caw.vim'
}
parse.generate_dummy_mappings(plugin1)
print(vim.inspect(plugin1))


local plugin2 = {
    on_map = "<Plug>(wildfire-",
    normalized_name='wildfire.vim'
}
if type(plugin2.on_map) ~= "table" then
    plugin2.on_map = {plugin2.on_map}
end

-- on_map: List or Dict, parse_lazy 将其转换为table
parse.generate_dummy_mappings(plugin2)
print(vim.inspect(plugin2))

local cases = {
{ "https://gitee.com/zgpio/LeaderF", {
    hook_add = "LeaderF-hook_add",
    hook_post_update = "LeaderF-hook_post_update",
    lazy = 0,
    repo = "https://gitee.com/zgpio/LeaderF"
  } },
{ "nvim-lua/plenary.nvim", {
    lazy = 0,
    repo = "nvim-lua/plenary.nvim"
  } },
{ "~/.cache/dein/repos/local/YouCompleteMe", {
    lazy = 0,
    repo = "~/.cache/dein/repos/local/YouCompleteMe"
  } },
{ "https://gitee.com/zgpio/dein.vim", {
    lazy = 0,
    repo = "https://gitee.com/zgpio/dein.vim"
  } }
}
for i, case in ipairs(cases) do
    local repo, opts = unpack(case)
    local plugin = parse._init(repo, opts)
    print(vim.inspect(plugin))
end
