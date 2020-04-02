-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local a = vim.api
local M = {}
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
local is_mac = (not is_windows) and vim.fn.has('win32unix') == 0
  and (vim.fn.has('mac')==1 or vim.fn.has('macunix')==1 or vim.fn.has('gui_macvim')==1
    or (vim.fn.isdirectory('/proc')==0 and vim.fn.executable('sw_vers')==1))

function _is_windows()
  return is_windows
end
function _is_mac()
  return is_mac
end
function _get_runtime_path()
  local rtp = dein_runtime_path
  if rtp ~= '' then
    return rtp
  end
  rtp = _get_cache_path() .. '/.dein'
  dein_runtime_path = rtp
  if vim.fn.isdirectory(rtp)==0 then
    vim.fn.mkdir(rtp, 'p')
  end
  return rtp
end

function _save_cache(vimrcs, is_state, is_starting)
  if _get_cache_path() == '' or (is_starting==0) then
    -- Ignore
    return true
  end

  -- TODO: deepcopy
  local plugins = vim.fn['dein#get']()

  for _, plugin in ipairs(vim.tbl_values(plugins)) do
    if is_state == 0 then
      plugin.sourced = 0
    end
    if plugin['orig_opts'] ~= nil then
      plugin['orig_opts'] = nil
    end

    -- Hooks
    for _, hook in ipairs({'hook_add', 'hook_source',
      'hook_post_source', 'hook_post_update',}) do
      if plugin[hook] ~= nil and vim.fn.type(plugin[hook]) == 2 then
        plugin[hook] = nil
      end
    end
  end

  local base_path = dein_base_path
  if vim.fn.isdirectory(base_path) == 0 then
    vim.fn.mkdir(base_path, 'p')
  end

  local ftplugin = vim.g['dein#_ftplugin']
  vim.fn.writefile({vim.fn.string(vimrcs), vim.fn.json_encode(plugins), vim.fn.json_encode(ftplugin)},
    (vim.g['dein#cache_directory'] or base_path) ..'/cache_' .. dein_progname)
end

--@param ... {{{}, {}, ...}}
function _call_hook(hook_name, ...)
  local args = ...
  local hook = 'hook_' .. hook_name
  local t
  if #args > 0 then t = args[1] else t = {} end
  local plugins = vim.tbl_filter(
    function(x)
      return ((hook_name ~= 'source' and hook_name ~= 'post_source')
        or x.sourced==1) and x.hook ~= nil and vim.fn.isdirectory(x.path)==1
    end,
    vim.fn['dein#util#_get_plugins'](t)
  )

  for _, plugin in ipairs(
    vim.tbl_filter(function(x) return x.hook ~= nil end, vim.fn['dein#util#_tsort'](plugins))) do
    vim.fn['dein#util#_execute_hook'](plugin, plugin[hook])
  end
end
function _add_after(rtps, path)
  vim.validate{
    rtps={rtps, 't'},
    path={path, 's'},
  }
  local idx = vim.fn.index(rtps, vim.env.VIMRUNTIME)
  local i
  if idx <= 0 then i = -1 else i = idx + 1 end
  rtps = vim.fn.insert(rtps, path, i)
  return rtps
end
function _get_lazy_plugins()
  local plugins = vim.tbl_values(vim.g['dein#_plugins'])
  -- table.filter  https://gist.github.com/FGRibreau/3790217
  local rv = {}
  for i, t in ipairs(plugins) do
    if t.sourced == 0 and t.rtp ~= '' then
      table.insert(rv, t)
    end
  end
  return rv
end

function _check_lazy_plugins()
  local rv = {}
  for i, t in ipairs(_get_lazy_plugins()) do
    if vim.fn.isdirectory(t.rtp) == 1
      and not (t['local'] or false)
      and (t['hook_source'] or '') == ''
      and (t['hook_add'] or '') == ''
      and vim.fn.isdirectory(t.rtp..'/plugin') == 0
      and vim.fn.isdirectory(t.rtp..'/after/plugin') == 0 then
      table.insert(rv, t.name)
    end
  end
  return rv
end

function _get_cache_path()
  local cache_path = dein_cache_path
  if cache_path ~= '' then
    return cache_path
  end

  cache_path = (vim.g['dein#cache_directory'] or dein_base_path)
    ..'/.cache/'..vim.fn.fnamemodify(vim.fn['dein#util#_get_myvimrc'](), ':t')
  dein_cache_path = cache_path
  if vim.fn.isdirectory(cache_path) == 0 then
    vim.fn.mkdir(cache_path, 'p')
  end
  return cache_path
end

-- function! dein#util#_substitute_path(path) abort
--   return ((s:is_windows || has('win32unix')) && a:path =~# '\\') ?
--         \ tr(a:path, '\', '/') : a:path
-- endfunction

function _save_state(is_starting)
  if dein_block_level ~= 0 then
    _error('Invalid dein#save_state() usage.')
    return 1
  end

  if _get_cache_path() == '' or is_starting == 0 then
    -- Ignore
    return 1
  end

  dein_vimrcs = _uniq(dein_vimrcs)
  vim.o.rtp = _join_rtp(_uniq(_split_rtp(vim.o.rtp)), vim.o.rtp, '')

  _save_cache(dein_vimrcs, 1, is_starting)

  -- Version check

  local lines = {
    'lua require "dein/autoload"',
    'if g:dein#_cache_version !=# ' .. vim.g['dein#_cache_version'] .. ' || ' ..
    'g:dein#_init_runtimepath !=# ' .. vim.fn.string(vim.g['dein#_init_runtimepath']) ..
         ' | throw "Cache loading error" | endif',
    'let [plugins, ftplugin] = dein#load_cache_raw('..
         vim.fn.string(dein_vimrcs) ..')',
    "if empty(plugins) | throw 'Cache loading error' | endif",
    'let g:dein#_plugins = plugins',
    'let g:dein#_ftplugin = ftplugin',
    'lua dein_base_path = ' .. vim.fn.string(dein_base_path),
    'lua dein_runtime_path = ' .. vim.fn.string(dein_runtime_path),
    'lua dein_cache_path = ' .. vim.fn.string(dein_cache_path),
    'let &runtimepath = ' .. vim.fn.string(vim.o.rtp),
  }

  if dein_off1 ~= '' then
    table.insert(lines, dein_off1)
  end
  if dein_off2 ~= '' then
    table.insert(lines, dein_off2)
  end

  -- Add dummy mappings/commands
  for _, plugin in ipairs(vim.fn['dein#util#_get_lazy_plugins']()) do
    for _, command in ipairs(plugin['dummy_commands'] or {}) do
      table.insert(lines, 'silent! ' .. command[2])
    end
    for _, mapping in ipairs(plugin['dummy_mappings'] or {}) do
      table.insert(lines, 'silent! ' .. mapping[3])
    end
  end

  -- Add hooks
  if vim.fn.empty(dein_hook_add)==0 then
    vim.list_extend(lines, skipempty(dein_hook_add))
  end
  for _, plugin in ipairs(vim.fn['dein#util#_tsort'](vim.fn.values(vim.fn['dein#get']()))) do
    if plugin.hook_add~=nil and type(plugin.hook_add) == 'string' then
      vim.list_extend(lines, skipempty(plugin.hook_add))
    end
  end

  -- Add events
  for event, plugins in pairs(vim.g['dein#_event_plugins']) do
    if vim.fn.exists('##' .. event)==1 then
      local e
      if vim.fn.exists('##' .. event)==1 then
        e = event .. ' *'
      else
        e = 'User ' .. event
      end
      vim.list_extend(lines, {vim.fn.printf('autocmd dein-events %s call dein#autoload#_on_event("%s", %s)',
            e, event, vim.fn.string(plugins))})
    end
  end

  vim.fn.writefile(lines,
    (vim.g['dein#cache_directory'] or dein_base_path) ..'/state_' .. dein_progname .. '.vim')
end
function _writefile(path, list)
  if vim.g['dein#_is_sudo'] == 1 or (vim.fn.filewritable(_get_cache_path())==0) then
    return 1
  end

  path = _get_cache_path() .. '/' .. path
  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  return vim.fn.writefile(list, path)
end

function skipempty(string)
  return vim.tbl_filter(function(x) return x~='' end, vim.split(string, '\n'))
end
-- TODO
function _get_plugins(plugins)
  local rv = {}
  if #plugins == 0 then
    rv = vim.tbl_values(vim.fn['dein#get']())
  else
    if not vim.tbl_islist(plugins) then
      plugins = {plugins}
    end
    for i, t in ipairs(plugins) do

    end
  end
  return rv
end

-- function _set_default(var, val, ...)
--   if vim.fn.exists(var)==0 or type({var}) != type(val) then
--     let alternate_var = get(a:000, 0, '')
--     let {var} = exists(alternate_var) ? {alternate_var} : val
--   end
-- end

function execute(expr)
  return vim.fn.execute(vim.split(expr, '\n'))
end
function M._error(msg)
  for i, mes in ipairs(msg2list(msg)) do
    local c = string.format('echomsg "[dein] %s"', mes)
    vim.api.nvim_command('echohl WarningMsg')
    vim.api.nvim_command(c)
    vim.api.nvim_command('echohl None')
  end
end
function _split_rtp(rtp)
  if vim.fn.stridx(rtp, [[\,]]) < 0 then
    return vim.fn.split(rtp, ',')
  end

  local split = vim.fn.split(rtp, [[\\\@<!\%(\\\\\)*\zs,]])
  return vim.fn.map(split, [[substitute(v:val, '\\\([\\,]\)', '\1', 'g')]])
end
function _join_rtp(list, runtimepath, rtp)
  if vim.fn.stridx(runtimepath, [[\,]]) < 0 and vim.fn.stridx(rtp, ',') < 0 then
    return vim.fn.join(list, ',')
  else
    return vim.fn.join(vim.tbl_map(escape, list), ',')
  end
end
function escape(path)
  -- Escape a path for runtimepath.
  return vim.fn.substitute(path, [[,\|\\,\@=]], [[\\\0]], 'g')
end
function _check_install(plugins)
  if not vim.tbl_isempty(plugins) then
    local invalids = vim.tbl_filter(function(x) return vim.tbl_isempty(vim.fn['dein#get'](x)) end,
      vim.fn['dein#util#_convert2list'](plugins))
    if not vim.tbl_isempty(invalids) then
      M._error('Invalid plugins: ' .. vim.fn.string(vim.fn.map(invalids, 'v:val')))
      return -1
    end
  end
  if vim.tbl_isempty(plugins) then
    plugins = vim.tbl_values(vim.fn['dein#get']())
  else
    plugins = vim.fn.map(vim.fn['dein#util#_convert2list'](plugins), 'dein#get(v:val)')
  end
  plugins = vim.tbl_filter(function(x) return vim.fn.isdirectory(x.path)==0 end, plugins)
  if vim.tbl_isempty(plugins) then return 0 end
  _notify('Not installed plugins: ' .. vim.fn.string(vim.fn.map(plugins, 'v:val.name')))
  return 1
end

function _notify(msg)
  vim.fn['dein#util#_set_default']('g:dein#enable_notification', 0)
  vim.fn['dein#util#_set_default']('g:dein#notification_icon', '')
  vim.fn['dein#util#_set_default']('g:dein#notification_time', 2)

  if vim.g['dein#enable_notification']==0 or msg == '' or vim.fn.has('vim_starting')==1 then
    M._error(msg)
    return
  end

  local icon = vim.fn['dein#util#_expand'](vim.g['dein#notification_icon'])

  local title = '[dein]'
  local cmd = ''
  if vim.fn.executable('notify-send')==1 then
    cmd = vim.fn.printf('notify-send --expire-time=%d', vim.g['dein#notification_time'] * 1000)
    if icon ~= '' then
      cmd = cmd.. ' --icon=' .. vim.fn.string(icon)
    end
    cmd = cmd.. ' ' .. vim.fn.string(title) .. ' ' .. vim.fn.string(msg)
  elseif _is_windows() and vim.fn.executable('Snarl_CMD')==1 then
    cmd = vim.fn.printf('Snarl_CMD snShowMessage %d "%s" "%s"',
           vim.g['dein#notification_time'], title, msg)
    if icon ~= '' then
      cmd = cmd.. ' "' .. icon .. '"'
    end
  elseif _is_mac() then
    cmd = ''
    if vim.fn.executable('terminal-notifier')==1 then
      cmd = cmd .. 'terminal-notifier -title ' ..
        vim.fn.string(title) .. ' -message ' .. vim.fn.string(msg)
      if icon ~= '' then
        cmd = cmd.. ' -appIcon ' .. vim.fn.string(icon)
      end
    else
      cmd = cmd .. vim.fn.printf("osascript -e 'display notification "
                    .."\"%s\" with title \"%s\"'", msg, title)
    end
  end

  if cmd ~= '' then
    vim.fn['dein#install#_system'](cmd)
  end
end
function msg2list(expr)
  if type(expr) == 'table' then
    return expr
  else
    return vim.split(expr, '\n')
  end
end

function _begin(path, vimrcs)
  if vim.fn.exists('#dein')==0 then
    vim.fn['dein#_init']()
  end

  -- Reset variables
  vim.api.nvim_exec([[
    let g:dein#_plugins = {}
    let g:dein#_event_plugins = {}
    let g:dein#_ftplugin = {}
    lua dein_hook_add = ''
  ]], true)

  if path == '' or dein_block_level ~= 0 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  dein_block_level = dein_block_level + 1
  dein_base_path = vim.fn['dein#util#_expand'](path)
  if dein_base_path:sub(-1) == '/' then
    dein_base_path = dein_base_path:sub(1, -2)
  end
  _get_runtime_path()
  _get_cache_path()
  dein_vimrcs = vim.fn['dein#util#_get_vimrcs'](vimrcs)
  dein_hook_add = ''

  -- Filetype off
  if vim.fn.exists('g:did_load_filetypes')==1 or vim.fn.has('nvim')==1 then
    dein_off1 = 'filetype off'
    vim.api.nvim_command(dein_off1)
  end
  if vim.fn.exists('b:did_indent')==1 or vim.fn.exists('b:did_ftplugin')==1 then
    dein_off2 = 'filetype plugin indent off'
    vim.api.nvim_command(dein_off2)
  end

  if vim.fn.has('vim_starting')==0 then
    vim.api.nvim_command('set rtp-='..vim.fn.fnameescape(dein_runtime_path))
    vim.api.nvim_command('set rtp-='..vim.fn.fnameescape(dein_runtime_path..'/after'))
  end

  -- Insert dein runtimepath to the head in 'runtimepath'.
  local rtps = _split_rtp(vim.o.rtp)
  local idx = vim.fn.index(rtps, vim.env['VIMRUNTIME'])
  if idx < 0 then
    M._error('Invalid runtimepath.')
    return 1
  end
  if vim.fn.fnamemodify(path, ':t') == 'plugin' and vim.fn.index(rtps, vim.fn.fnamemodify(path, ':h')) >= 0 then
    M._error('You must not set the installation directory under "&runtimepath/plugin"')
    return 1
  end
  rtps = vim.fn.insert(rtps, dein_runtime_path, idx)
  rtps = _add_after(rtps, dein_runtime_path..'/after')
  vim.o.runtimepath = _join_rtp(rtps, vim.o.rtp, dein_runtime_path)
end

function _chomp(str)
  if str ~= '' and str:sub(-1) == '/' then
    return str:sub(1, -2)
  else
    return str
  end
end
function _end()
  if dein_block_level ~= 1 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  dein_block_level = dein_block_level - 1

  if vim.fn.has('vim_starting')==0 then
    -- TODO
    -- vim.fn['dein#source'](vim.fn.filter(vim.fn.values(vim.g['dein#_plugins']), "!v:val.lazy && !v:val.sourced && v:val.rtp !=# ''"))
    a.nvim_command([[call dein#source(filter(values(g:dein#_plugins), "!v:val.lazy && !v:val.sourced && v:val.rtp !=# ''"))]])
  end

  -- Add runtimepath
  rtps = _split_rtp(vim.o.rtp)
  local index = vim.fn.index(rtps, dein_runtime_path)
  if index < 0 then
    M._error('Invalid runtimepath.')
    return 1
  end

  local depends = {}
  local sourced = vim.fn.has('vim_starting')==1 and (vim.fn.exists('&loadplugins')==0 or vim.o.loadplugins)
  local _plugins = vim.g['dein#_plugins']
  for _, plugin in ipairs(
    vim.tbl_filter(function (x) return x.lazy==0 and x.sourced==0 and x.rtp~='' end,
      vim.tbl_values(_plugins))) do
    -- Load dependencies
    if plugin['depends'] ~= nil then
      depends = depends + plugin.depends
    end

    if plugin.merged==0 then
      rtps = vim.fn.insert(rtps, plugin.rtp, index)
      if vim.fn.isdirectory(plugin.rtp..'/after')==1 then
        rtps = _add_after(rtps, plugin.rtp..'/after')
      end
    end

    plugin.sourced = sourced
  end
  vim.g['dein#_plugins'] = _plugins
  vim.o.rtp = _join_rtp(rtps, vim.o.rtp, '')

  if vim.fn.empty(depends)==0 then
    vim.fn['dein#source'](depends)
  end

  if dein_hook_add ~= '' then
    vim.fn['dein#util#_execute_hook']({}, dein_hook_add)
  end

  local _event_plugins = vim.g['dein#_event_plugins']
  -- TODO
  _event_plugins[true] = nil
  for event, plugins in pairs(_event_plugins) do
    if vim.fn.exists('##'..event) then
      local t = event .. ' *'
      vim.api.nvim_command(
        vim.fn.printf('autocmd dein-events %s call dein#autoload#_on_event("%s", %s)',
        t, event, vim.fn.string(plugins))
      )
    end
  end

  if vim.fn.has('vim_starting')==0 then
    vim.fn['dein#call_hook']('add')
    vim.fn['dein#call_hook']('source')
    vim.fn['dein#call_hook']('post_source')
  end
end

--@param list basic type list
function _uniq(list)
  list = vim.deepcopy(list)
  local l = {}
  local i = 1
  local seen = {}
  for _, x in ipairs(list) do
    if seen[x] == nil then
      seen[x] = 1
      l[i] = x
      i = i + 1
    end
  end
  return l
end

return M
