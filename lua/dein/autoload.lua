-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
require 'dein/util'
local a = vim.api
local M = {}

dein_log = io.open(vim.fn.expand('~/pmlog.txt'), 'a+')
function _dummy_complete(arglead, cmdline, cursorpos)
  local command = vim.fn.matchstr(cmdline, [[\h\w*]])
  local exists = vim.fn.exists(':'..command)
  if exists == 2 then
    -- Remove the dummy command.
    a.nvim_command('silent! delcommand ' ..command)
  end

  -- Load plugins
  _on_pre_cmd(command:lower())

  if exists == 2 then
    -- Print the candidates
    vim.fn.feedkeys(a.nvim_replace_termcodes('<c-d>', true, true, true), 'n')
  end

  return {arglead}
end
function _on_pre_cmd(name)
  local t = vim.tbl_filter(
    function(v)
      local s = string.gsub(v.normalized_name:lower(), '[_-]', '')
      return vim.tbl_contains(
        vim.tbl_map(function(v) return v:lower() end, vim.deepcopy(v.on_cmd or {})), name)
        or vim.fn.stridx(name:lower(), s) == 0
    end,
    _get_lazy_plugins()
  )
  _source(t)
end
function _on_default_event(event)
  local lazy_plugins = _get_lazy_plugins()
  local plugins = {}

  local path = vim.fn.expand('<afile>')
  -- For ":edit ~".
  if vim.fn.fnamemodify(path, ':t') == '~' then
    path = '~'
  end
  path = _expand(path)

  for _, ft in ipairs(vim.split(vim.bo.filetype, '.', true)) do
    local t = vim.tbl_filter(
      function(v)
        return vim.tbl_contains(v.on_ft or {}, ft)
      end,
      lazy_plugins
    )
    vim.list_extend(plugins, t)
  end

  local t = vim.tbl_filter(
    function(v)
      local t = vim.tbl_filter(
        function(val)
          return path == val
        end,
        vim.deepcopy(v.on_path or {})
      )
      return not vim.tbl_isempty(t)
    end,
    lazy_plugins
  )
  vim.list_extend(plugins, t)
  local t = vim.tbl_filter(
    function(v)
      return v.on_event==nil and v.on_if~=nil and a.nvim_eval(tostring(v.on_if))==1
    end,
    lazy_plugins
  )
  vim.list_extend(plugins, t)

  source_events(event, plugins)
end
--@param ... the plugin name list or plugin dict list.
--If you omit it, it will source all plugins.
function _source(...)
  local plugins = {...}
  local _plugins = dein._plugins
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

  local filetype_before = vim.fn.execute('autocmd FileType')
  vim.o.rtp = _join_rtp(rtps, vim.o.rtp, '')

  _call_hook('source', {sourced})

  -- Reload script files.
  for _, plugin in ipairs(sourced) do
    for _, directory in ipairs({'plugin', 'after/plugin'}) do
      if vim.fn.isdirectory(plugin.rtp..'/'..directory)==1 then
        for _, file in ipairs(_globlist(plugin.rtp..'/'..directory..'/**/*.vim')) do
          a.nvim_command('source ' .. vim.fn.fnameescape(file))
        end
      end
    end

    if vim.fn.has('vim_starting')==0 then
      local augroup = (plugin.augroup or plugin.normalized_name)
      if vim.fn.exists('#'..augroup..'#VimEnter')==1 then
        local c = 'silent doautocmd '.. augroup.. ' VimEnter'
        a.nvim_command(c)
      end
      if vim.fn.has('gui_running')==1 and vim.o.term == 'builtin_gui' and vim.fn.exists('#'..augroup..'#GUIEnter') then
        local c = 'silent doautocmd '.. augroup.. ' GUIEnter'
        a.nvim_command(c)
      end
      if vim.fn.exists('#'..augroup..'#BufRead')==1 then
        local c = 'silent doautocmd '.. augroup.. ' BufRead'
        a.nvim_command(c)
      end
    end
  end

  local filetype_after = vim.fn.execute('autocmd FileType')

  local is_reset = is_reset_ftplugin(sourced)
  if is_reset==1 then
    reset_ftplugin()
  end

  if (is_reset==1 or filetype_before ~= filetype_after) and vim.o.ft ~= '' then
    -- Recall FileType autocmd
    a.nvim_command('let &filetype = &filetype')
  end

  if vim.fn.has('vim_starting')==0 then
    _call_hook('post_source', {sourced})
  end
end
--@param plugins plugin name list
function _on_event(event, plugins)
  local lazy_plugins = vim.tbl_filter(function(v) return v.sourced==0 end, _get_plugins(plugins))
  if vim.tbl_isempty(lazy_plugins) then
    a.nvim_command('autocmd! dein-events ' ..event)
    return
  end

  local plugins = vim.tbl_filter(
    function(v)
      return v.on_if==nil or vim.fn.eval(v.on_if)==1
    end,
    lazy_plugins
  )

  source_events(event, plugins)
end
function _on_cmd(command, name, args, bang, line1, line2)
  _source({name})

  if vim.fn.exists(':' .. command) ~= 2 then
    _error(string.format('command %s is not found.', command))
    return
  end

  local range
  if line1 == line2 then
    range = ''
  elseif line1 == vim.fn.line("'<") and line2 == vim.fn.line("'>") then
    range = "'<,'>"
  else
    range = line1..','..line2
  end

  try {
    function()
      local cmd = string.format('execute ' .. vim.fn.string(range .. command .. bang ..' '.. args))
      vim.api.nvim_command(cmd)
    end,
    catch {
      function(e)
        -- TODO catch /^Vim\%((\a\+)\)\=:E481/
        -- E481: No range allowed
        -- execute command bang args
        print('caught error: ' .. e)
      end
    }
  }
end

function M._on_func(name)
  local function_prefix = vim.fn.substitute(name, '[^#]*$', '', '')
  if function_prefix:find('^dein#') or function_prefix:find('^vital#') or vim.fn.has('vim_starting')==1 then
    return
  end

  local x = vim.tbl_filter(
    function(v)
      return vim.fn.stridx(function_prefix, v.normalized_name..'#') == 0
        or vim.tbl_contains(v.on_func or {}, name)
    end,
    _get_lazy_plugins()
  )
  _source(x)
end
function source_events(event, plugins)
  if vim.tbl_isempty(plugins) then
    return
  end

  local prev_autocmd = vim.fn.execute('autocmd ' .. event)
  _source(plugins)
  local new_autocmd = vim.fn.execute('autocmd ' .. event)

  if event == 'InsertCharPre' then
    -- Queue this key again
    vim.fn.feedkeys(vim.v.char)
    vim.v.char = ''
  else
    if vim.fn.exists('#BufReadCmd')==1 and event == 'BufNew' then
      -- For BufReadCmd plugins
      a.nvim_command('silent doautocmd <nomodeline> BufReadCmd')
    end
    if vim.fn.exists('#' .. event)==1 and prev_autocmd ~= new_autocmd then
      a.nvim_command('doautocmd <nomodeline> ' .. event)
    elseif vim.fn.exists('#User#' .. event)==1 then
      a.nvim_command('doautocmd <nomodeline> User ' ..event)
    end
  end
end
function reset_ftplugin()
  local filetype_state = vim.fn.execute('filetype')

  if vim.fn.exists('b:did_indent')==1 or vim.fn.exists('b:did_ftplugin')==1 then
    a.nvim_command('filetype plugin indent off')
  end

  if string.find(filetype_state, 'plugins:ON') then
    a.nvim_command('silent! filetype plugin on')
  end

  if string.find(filetype_state, 'indent:ON') then
    a.nvim_command('silent! filetype indent on')
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
      a.nvim_command('silent! delcommand '..command[1])
    end
    plugin.dummy_commands = {}
  end

  if plugin['dummy_mappings'] ~= nil then
    for _, map in ipairs(plugin.dummy_mappings) do
      a.nvim_command('silent! '..map[1]..'unmap '..map[2])
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

  _source({name})

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
    a.nvim_command(mapargrec(mapping .. input, mode):match(':<C%-U>(.*)<CR>'))
  else
    while mapping:find('<[%a%d_-]+>') do
      -- ('<LeaDer>'):gsub('<[lL][eE][aA][dD][eE][rR]>', vim.g.mapleader)
      mapping = vim.fn.substitute(mapping, [[\c<Leader>]], (vim.g.mapleader or [[\]]), 'g')
      mapping = vim.fn.substitute(mapping, [[\c<LocalLeader>]], (vim.g.maplocalleader or [[\]]), 'g')
      local ctrl = vim.fn.matchstr(mapping, [=[<\zs[[:alnum:]_-]\+\ze>]=])
      local s = ("<%s>"):format(ctrl)
      mapping = vim.fn.substitute(mapping, s, a.nvim_replace_termcodes(s, true, true, true), '')
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
function set_dein_ftplugin(ftplugin)
  dein._ftplugin = ftplugin
end
function set_dein_plugins(plugins)
  dein._plugins = plugins
end

return M
