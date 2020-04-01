-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
require 'dein/util'
local a = vim.api
local M = {}
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
function source_plugin(rtps, index, plugin, sourced)
  print("rtps >>> ", vim.inspect(rtps))
  print("-------------------------------------------------------------")
  print("index >>> ", vim.inspect(index))
  print("-------------------------------------------------------------")
  print("plugin >>> ", vim.inspect(plugin))
  print("-------------------------------------------------------------")
  print("sourced >>> ", vim.inspect(sourced))
  if plugin.sourced == 1 or vim.tbl_contains(sourced, plugin) then
    return
  end

  table.insert(sourced, plugin)

  -- Load dependencies
  for i, name in ipairs((plugin['depends'] or {})) do
    if vim.g['dein#_plugins'][name] == nil then
      vim.fn['dein#util#_error'](string.format('Plugin name "%s" is not found.', name))
    elseif not (plugin.lazy == 1) and (vim.g['dein#_plugins'][name].lazy == 1) then
      vim.fn['dein#util#_error'](
        string.format('Not lazy plugin "%s" depends lazy "%s" plugin.', plugin.name, name))
    else
      rtps, index, plugin, sourced = source_plugin(rtps, index, vim.g['dein#_plugins'][name], sourced)
    end
  end

  plugin.sourced = 1

  local sources = {}
  for i, t in ipairs(_get_lazy_plugins()) do
    local get = t['on_source'] or {}
    if vim.tbl_contains(get, plugin.name) then
      table.insert(sources, t)
    end
  end
  print(vim.inspect(sources))
  print("==========================================================================")
  for i, on_source in ipairs(sources) do
    rtps, index, plugin, sourced = source_plugin(rtps, index, on_source, sourced)
  end

  if plugin['dummy_commands'] ~= nil then
    for i, command in ipairs(plugin.dummy_commands) do
      vim.api.nvim_command('delcommand '..command[1])
    end
    plugin.dummy_commands = {}
  end

  if plugin['dummy_mappings'] ~= nil then
    for i, map in ipairs(plugin.dummy_mappings) do
      vim.api.nvim_command(map[1]..'unmap '..map[2])
    end
    plugin.dummy_mappings = {}
  end

  if not plugin.merged or (plugin['local'] or 0) then
    vim.fn.insert(rtps, plugin.rtp, index)
    if vim.fn.isdirectory(plugin.rtp..'/after') == 1 then
      rtps = _add_after(rtps, plugin.rtp..'/after')
    end
  end
  return rtps, index, plugin, sourced
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
