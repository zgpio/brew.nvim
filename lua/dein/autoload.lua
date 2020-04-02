-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
require 'dein/util'
local a = vim.api
local M = {}

--@param ... the plugin name list or plugin dict list.
--If you omit it, it will source all plugins.
function _source(...)
  local plugins = {...}
  local _plugins = vim.g['dein#_plugins']
  if #plugins == 0 then plugins = vim.tbl_values(_plugins)
  else plugins = ... end
  if #plugins == 0 then
    return
  end

  if type(plugins[1]) ~= 'table' then
    plugins = vim.tbl_map(function(v) return (_plugins[v] or {}) end, plugins)
  end

  local rtps = _uniq(_split_rtp(vim.o.rtp))
  local index = vim.fn.index(rtps, _get_runtime_path())
  if index < 0 then
    return 1
  end

  local sourced = {}
  for _, plugin in ipairs(plugins) do
    if not vim.tbl_isempty(plugin) and plugin.sourced==0 and plugin.rtp ~= '' then
      source_plugin(_plugins, rtps, index, plugin, sourced)
    end
  end

  local filetype_before = vim.fn['dein#util#_redir']('autocmd FileType')
  vim.o.rtp = _join_rtp(rtps, vim.o.rtp, '')

  vim.fn['dein#call_hook']('source', sourced)

  -- Reload script files.
  for _, plugin in ipairs(sourced) do
    for _, directory in ipairs({'plugin', 'after/plugin'}) do
      if vim.fn.isdirectory(plugin.rtp..'/'..directory)==1 then
        for _, file in ipairs(vim.fn['dein#util#_globlist'](plugin.rtp..'/'..directory..'/**/*.vim')) do
          vim.api.nvim_command('source ' .. vim.fn.fnameescape(file))
        end
      end
    end

    if vim.fn.has('vim_starting')==0 then
      local augroup = (plugin.augroup or plugin.normalized_name)
      if vim.fn.exists('#'..augroup..'#VimEnter')==1 then
        local c = 'silent doautocmd '.. augroup.. ' VimEnter'
        vim.api.nvim_command(c)
      end
      if vim.fn.has('gui_running')==1 and vim.o.term == 'builtin_gui' and vim.fn.exists('#'..augroup..'#GUIEnter') then
        local c = 'silent doautocmd '.. augroup.. ' GUIEnter'
        vim.api.nvim_command(c)
      end
      if vim.fn.exists('#'..augroup..'#BufRead')==1 then
        local c = 'silent doautocmd '.. augroup.. ' BufRead'
        vim.api.nvim_command(c)
      end
    end
  end

  local filetype_after = vim.fn['dein#util#_redir']('autocmd FileType')

  local is_reset = is_reset_ftplugin(sourced)
  if is_reset==1 then
    reset_ftplugin()
  end

  if (is_reset==1 or filetype_before ~= filetype_after) and vim.o.ft ~= '' then
    -- Recall FileType autocmd
    vim.api.nvim_command('let &filetype = &filetype')
  end

  if vim.fn.has('vim_starting')==0 then
    vim.fn['dein#call_hook']('post_source', sourced)
  end
  vim.g['dein#_plugins'] = _plugins
end
function reset_ftplugin()
  local filetype_state = vim.fn.execute('filetype')

  if vim.fn.exists('b:did_indent')==1 or vim.fn.exists('b:did_ftplugin')==1 then
    vim.api.nvim_command('filetype plugin indent off')
  end

  if string.find(filetype_state, 'plugins:ON') then
    vim.api.nvim_command('silent! filetype plugin on')
  end

  if string.find(filetype_state, 'indent:ON') then
    vim.api.nvim_command('silent! filetype indent on')
  end
end

function is_reset_ftplugin(plugins)
  local ft = vim.bo.filetype
  if ft == '' then
    return 0
  end

  for i, plugin in ipairs(plugins) do
    local ftplugin = plugin.rtp .. '/ftplugin/' .. ft
    local after = plugin.rtp .. '/after/ftplugin/' .. ft
    -- TODO: use vim.tbl_filter instead
    local real = {}
    for i, t in ipairs({'ftplugin', 'indent', 'after/ftplugin', 'after/indent'}) do
      if vim.fn.filereadable(string.format('%s/%s/%s.vim', plugin.rtp, t, ft))==1 then
        table.insert(real, t)
      end
    end
    if #real > 0 or vim.fn.isdirectory(ftplugin)==1 or vim.fn.isdirectory(after)==1
        or vim.fn.glob(ftplugin.. '_*.vim') ~= '' or vim.fn.glob(after .. '_*.vim') ~= '' then
      return 1
    end
  end
  return 0
end

-- TODO: review
-- NOTE: 不访问全局变量
function source_plugin(plugins, rtps, index, plugin, sourced)
  if plugin.sourced == 1 or vim.tbl_contains(sourced, plugin) then
    return
  end

  table.insert(sourced, plugin)

  -- Load dependencies
  for _, name in ipairs((plugin['depends'] or {})) do
    if plugins[name] == nil then
      require 'dein/util'._error(string.format('Plugin name "%s" is not found.', name))
    elseif plugin.lazy==0 and (plugins[name].lazy == 1) then
      require 'dein/util'._error(
        string.format('Not lazy plugin "%s" depends lazy "%s" plugin.', plugin.name, name))
    else
      source_plugin(plugins, rtps, index, plugins[name], sourced)
    end
  end

  plugin.sourced = 1

  local lazy_plugins = vim.tbl_filter(
    function(v) return v.sourced == 0 and v.rtp ~= '' end,
    vim.tbl_values(plugins)
  )
  local sources = vim.tbl_filter(
    function(v)
      return vim.tbl_contains((v['on_source'] or {}), plugin.name)
    end,
    lazy_plugins
  )

  for _, on_source in ipairs(sources) do
    source_plugin(plugins, rtps, index, on_source, sourced)
  end

  if plugin['dummy_commands'] ~= nil then
    for _, command in ipairs(plugin.dummy_commands) do
      vim.api.nvim_command('silent! delcommand '..command[1])
    end
    plugin.dummy_commands = {}
  end

  if plugin['dummy_mappings'] ~= nil then
    for _, map in ipairs(plugin.dummy_mappings) do
      vim.api.nvim_command('silent! '..map[1]..'unmap '..map[2])
    end
    plugin.dummy_mappings = {}
  end

  if plugin.merged==0 or (plugin['local']==1 or false) then
    table.insert(rtps, index+1, plugin.rtp)
    if vim.fn.isdirectory(plugin.rtp..'/after') == 1 then
      rtps = _add_after(rtps, plugin.rtp..'/after')
    end
  end
end

function get_input()
  local input = ''
  local termstr = '<M-_>'

  vim.fn.feedkeys(termstr, 'n')

  while true do
    local char = vim.fn.getchar()
    if type(char) == 'number' then
      input = input .. vim.fn.nr2char(char)
    else
      input = input .. char
    end

    local idx = vim.fn.stridx(input, termstr)
    if idx >= 1 then
      input = input:sub(1, idx)
      break
    elseif idx == 0 then
      input = ''
      break
    end
  end

  return input
end

function _on_map(mapping, name, mode)
  local cnt = vim.v.count
  if cnt <= 0 then cnt = '' end

  local input = get_input()

  vim.fn['dein#source'](name)

  if mode == 'v' or mode == 'x' then
    vim.fn.feedkeys('gv', 'n')
  elseif mode == 'o' and vim.v.operator ~= 'c' then
    -- TODO: omap
    -- v:prevcount?
    -- Cancel waiting operator mode.
    vim.fn.feedkeys(vim.v.operator, 'm')
  end

  vim.fn.feedkeys(cnt, 'n')

  if mode == 'o' and vim.v.operator == 'c' then
    -- Note: This is the dirty hack.
    vim.api.nvim_command(mapargrec(mapping .. input, mode):match(':<C%-U>(.*)<CR>'))
  else
    while mapping:find('<[%a%d_-]+>') do
      -- ('<LeaDer>'):gsub('<[lL][eE][aA][dD][eE][rR]>', vim.g.mapleader)
      mapping = vim.fn.substitute(mapping, [[\c<Leader>]], (vim.g.mapleader or [[\]]), 'g')
      mapping = vim.fn.substitute(mapping, [[\c<LocalLeader>]], (vim.g.maplocalleader or [[\]]), 'g')
      local ctrl = vim.fn.matchstr(mapping, [=[<\zs[[:alnum:]_-]\+\ze>]=])
      local s = ("<%s>"):format(ctrl)
      mapping = vim.fn.substitute(mapping, s, vim.api.nvim_replace_termcodes(s, true, true, true), '')
    end
    vim.fn.feedkeys(mapping .. input, 'm')
  end

  return ''
end
function mapargrec(map, mode)
  local arg = vim.fn.maparg(map, mode)
  while vim.fn.maparg(arg, mode) ~= '' do
    arg = vim.fn.maparg(arg, mode)
  end
  return arg
end

return M
