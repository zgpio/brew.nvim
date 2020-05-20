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
  local rtp = dein._runtime_path
  if rtp ~= '' then
    return rtp
  end
  rtp = _get_cache_path() .. '/.dein'
  dein._runtime_path = rtp
  if vim.fn.isdirectory(rtp)==0 then
    vim.fn.mkdir(rtp, 'p')
  end
  return rtp
end

function _get_myvimrc()
  local vimrc = vim.env['MYVIMRC']
  if vimrc == '' then
    vimrc = vim.fn.matchstr(vim.fn.split(vim.fn.execute('scriptnames'), '\n')[0], [[^\s*\d\+:\s\zs.*]])
  end
  return _substitute_path(vimrc)
end

function _clear_state()
  local base = vim.g['dein#cache_directory'] or dein._base_path
  local caches = _globlist(base..'/state_*.vim')
  vim.list_extend(caches, _globlist(base..'/cache_*'))
  caches = vim.tbl_filter(function(v) return v~='' end, caches)
  for _, cache in ipairs(caches) do
    vim.fn.delete(cache)
  end
end

function _check_vimrcs()
  local time = vim.fn.getftime(_get_runtime_path())
  local ret = vim.tbl_isempty(vim.tbl_filter(
    function(v)
      return time < v
    end,
    vim.tbl_map(
      function(v)
        return vim.fn.getftime(vim.fn.expand(v))
      end,
      vim.deepcopy(dein._vimrcs)
    )))
  if ret then
    return 0
  end

  _clear_state()

  if (vim.g['dein#auto_recache'] or 0)==1 then
    a.nvim_command('silent source '.. _get_myvimrc())

    if _get_merged_plugins() ~= _load_merged_plugins() then
      _notify('auto recached')
      vim.fn['dein#recache_runtimepath']()
    end
  end

  return 1
end
function _save_cache(vimrcs, is_state, is_starting)
  if _get_cache_path() == '' or (is_starting==0) then
    -- Ignore
    return true
  end

  -- TODO: deepcopy
  local plugins = dein.get()

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

  local base_path = dein._base_path
  if vim.fn.isdirectory(base_path) == 0 then
    vim.fn.mkdir(base_path, 'p')
  end

  local ftplugin = dein._ftplugin
  vim.fn.writefile({vim.fn.string(vimrcs), vim.fn.json_encode(plugins), vim.fn.json_encode(ftplugin)},
    (vim.g['dein#cache_directory'] or base_path) ..'/cache_' .. dein._progname)
end

--@param ... {{{}, {}, ...}}
function _call_hook(hook_name, ...)
  local args = ...
  local hook = 'hook_' .. hook_name
  local t
  if args and #args > 0 then t = args[1] else t = {} end
  local plugins = vim.tbl_filter(
    function(x)
      return ((hook_name ~= 'source' and hook_name ~= 'post_source')
        or x.sourced==1) and x[hook] ~= nil and vim.fn.isdirectory(x.path)==1
    end,
    _get_plugins(t)
  )

  for _, plugin in ipairs(
    vim.tbl_filter(function(x) return x[hook] ~= nil end, _tsort(plugins))) do
    vim.fn['dein#util#_execute_hook'](plugin, plugin[hook])
  end
end
function _globlist(path)
  return vim.split(vim.fn.glob(path), '\n')
end
function _add_after(rtps, path)
  vim.validate{
    rtps={rtps, 't'},
    path={path, 's'},
  }
  local idx = vim.fn.index(rtps, vim.env.VIMRUNTIME)
  local i
  if idx <= 0 then i = #rtps+1 else i = idx + 2 end
  table.insert(rtps, i, path)
  return rtps
end
--@returns [{}, {}]
function _get_lazy_plugins()
  local plugins = vim.tbl_values(dein._plugins)
  -- table.filter  https://gist.github.com/FGRibreau/3790217
  local rv = {}
  for _, t in ipairs(plugins) do
    if t.sourced == 0 and t.rtp ~= '' then
      table.insert(rv, t)
    end
  end
  return rv
end

function _check_lazy_plugins()
  local rv = {}
  for _, t in ipairs(_get_lazy_plugins()) do
    if vim.fn.isdirectory(t.rtp) == 1
      and (t['local'] or 0) == 0
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
  local cache_path = dein._cache_path
  if cache_path ~= '' then
    return cache_path
  end

  cache_path = (vim.g['dein#cache_directory'] or dein._base_path)
    ..'/.cache/'..vim.fn.fnamemodify(_get_myvimrc(), ':t')
  dein._cache_path = cache_path
  if vim.fn.isdirectory(cache_path) == 0 then
    vim.fn.mkdir(cache_path, 'p')
  end
  return cache_path
end

function _substitute_path(path)
  if (is_windows or vim.fn.has('win32unix')==1) and path:find([[\]]) then
    return vim.fn.tr(path, [[\]], '/')
  else
    return path
  end
end

function _save_state(is_starting)
  if dein._block_level ~= 0 then
    _error('Invalid dein#save_state() usage.')
    return 1
  end

  if _get_cache_path() == '' or is_starting == 0 then
    -- Ignore
    return 1
  end

  dein._vimrcs = _uniq(dein._vimrcs)
  vim.o.rtp = _join_rtp(_uniq(_split_rtp(vim.o.rtp)), vim.o.rtp, '')

  _save_cache(dein._vimrcs, 1, is_starting)

  -- Version check

  local lines = {
    'lua require "dein/autoload"',
    'if luaeval("dein._cache_version") !=# ' .. dein._cache_version .. ' || ' ..
    'luaeval("dein._init_runtimepath") !=# ' .. vim.fn.string(dein._init_runtimepath) ..
         ' | throw "Cache loading error" | endif',
    'let [plugins, ftplugin] = v:lua.load_cache_raw('..
         vim.fn.string(dein._vimrcs) ..')',
    "if empty(plugins) | throw 'Cache loading error' | endif",
    'call luaeval("set_dein_plugins(_A)", plugins)',
    'call luaeval("set_dein_ftplugin(_A)", ftplugin)',
    'lua dein._base_path = ' .. vim.fn.string(dein._base_path),
    'lua dein._runtime_path = ' .. vim.fn.string(dein._runtime_path),
    'lua dein._cache_path = ' .. vim.fn.string(dein._cache_path),
    'let &runtimepath = ' .. vim.fn.string(vim.o.rtp),
  }

  if dein._off1 ~= '' then
    table.insert(lines, dein._off1)
  end
  if dein._off2 ~= '' then
    table.insert(lines, dein._off2)
  end

  -- Add dummy mappings/commands
  for _, plugin in ipairs(_get_lazy_plugins()) do
    for _, command in ipairs(plugin['dummy_commands'] or {}) do
      table.insert(lines, 'silent! ' .. command[2])
    end
    for _, mapping in ipairs(plugin['dummy_mappings'] or {}) do
      table.insert(lines, 'silent! ' .. mapping[3])
    end
  end

  -- Add hooks
  if vim.fn.empty(dein._hook_add)==0 then
    vim.list_extend(lines, skipempty(dein._hook_add))
  end
  for _, plugin in ipairs(_tsort(vim.tbl_values(dein.get()))) do
    if plugin.hook_add~=nil and type(plugin.hook_add) == 'string' then
      vim.list_extend(lines, skipempty(plugin.hook_add))
    end
  end

  -- Add events
  for event, plugins in pairs(dein._event_plugins) do
    if vim.fn.exists('##' .. event)==1 then
      local e
      if vim.fn.exists('##' .. event)==1 then
        e = event .. ' *'
      else
        e = 'User ' .. event
      end
      vim.list_extend(lines, {vim.fn.printf('autocmd dein-events %s lua _on_event("%s", %s)',
            e, event, vim.inspect(plugins))})
    end
  end

  vim.fn.writefile(lines,
    (vim.g['dein#cache_directory'] or dein._base_path) ..'/state_' .. dein._progname .. '.vim')
end
function _writefile(path, list)
  if dein._is_sudo == 1 or (vim.fn.filewritable(_get_cache_path())==0) then
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
  return vim.tbl_filter(function(v) return v~='' end, vim.split(string, '\n'))
end

function _get_plugins(plugins)
  local rv = {}
  if vim.tbl_isempty(plugins) then
    return vim.tbl_values(dein.get())
  else
    plugins = vim.tbl_map(
      function(v)
        if type(v)=='table' and not vim.tbl_islist(v) then
          return v
        else
          return dein.get(v)
        end
      end,
      _convert2list(plugins)
    )
    local rv = {}
    for k, v in pairs(plugins) do
      if not vim.tbl_isempty(v) then
        rv[k] = v
      end
    end
    return rv
  end
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
local function tsort_impl(target, mark, sorted)
  if vim.tbl_isempty(target) or mark[target.name]~=nil then
    return
  end

  mark[target.name] = 1
  if target.depends~=nil then
    for _, depend in ipairs(target.depends) do
      tsort_impl(dein.get(depend), mark, sorted)
    end
  end

  table.insert(sorted, target)
end
--@param plugins plugin list
function _tsort(plugins)
  local sorted = {}
  local mark = {}
  for _, target in ipairs(plugins) do
    tsort_impl(target, mark, sorted)
  end

  return sorted
end
function _convert2list(expr)
  if type(expr) == 'table' then
    return vim.deepcopy(expr)
  elseif type(expr) == 'string' then
    if expr == '' then
      return {}
    else
      return vim.split(expr, '\r?\n')
    end
  else
    return {expr}
  end
end
function escape(path)
  -- Escape a path for runtimepath.
  return vim.fn.substitute(path, [[,\|\\,\@=]], [[\\\0]], 'g')
end
function _check_install(plugins)
  if not vim.tbl_isempty(plugins) then
    local invalids = vim.tbl_filter(function(x) return vim.tbl_isempty(dein.get(x)) end,
      _convert2list(plugins))
    if not vim.tbl_isempty(invalids) then
      M._error('Invalid plugins: ' .. vim.fn.string(vim.fn.map(invalids, 'v:val')))
      return -1
    end
  end
  if vim.tbl_isempty(plugins) then
    plugins = vim.tbl_values(dein.get())
  else
    plugins = vim.tbl_map(function(v) return dein.get(v) end, _convert2list(plugins))
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
function _get_vimrcs(vimrcs)
  if vim.fn.empty(vimrcs)==1 then
    return {_get_myvimrc()}
  else
    return vim.tbl_map(
      function(v)
        return vim.fn.expand(v)
      end,
      _convert2list(vimrcs)
    )
  end
end

function _begin(path, vimrcs)
  if vim.fn.exists('#dein')==0 then
    dein._init()
  end

  -- Reset variables
  vim.api.nvim_exec([[
    lua dein._plugins = {}
    lua dein._event_plugins = {}
    lua dein._ftplugin = {}
    lua dein._hook_add = ''
  ]], true)

  if path == '' or dein._block_level ~= 0 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  dein._block_level = dein._block_level + 1
  dein._base_path = vim.fn['dein#util#_expand'](path)
  if dein._base_path:sub(-1) == '/' then
    dein._base_path = dein._base_path:sub(1, -2)
  end
  _get_runtime_path()
  _get_cache_path()
  dein._vimrcs = _get_vimrcs(vimrcs)
  dein._hook_add = ''

  -- Filetype off
  if vim.fn.exists('g:did_load_filetypes')==1 or vim.fn.has('nvim')==1 then
    dein._off1 = 'filetype off'
    vim.api.nvim_command(dein._off1)
  end
  if vim.fn.exists('b:did_indent')==1 or vim.fn.exists('b:did_ftplugin')==1 then
    dein._off2 = 'filetype plugin indent off'
    vim.api.nvim_command(dein._off2)
  end

  if vim.fn.has('vim_starting')==0 then
    vim.api.nvim_command('set rtp-='..vim.fn.fnameescape(dein._runtime_path))
    vim.api.nvim_command('set rtp-='..vim.fn.fnameescape(dein._runtime_path..'/after'))
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
  rtps = vim.fn.insert(rtps, dein._runtime_path, idx)
  rtps = _add_after(rtps, dein._runtime_path..'/after')
  vim.o.runtimepath = _join_rtp(rtps, vim.o.rtp, dein._runtime_path)
end

-- TODO: duplicate
function slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end
  return sliced
end
function _save_merged_plugins()
  local merged = _get_merged_plugins()
  local h = slice(merged, 1, dein._merged_length - 1)
  local t = slice(merged, dein._merged_length)
  vim.list_extend(h, {vim.fn.string(t)})
  vim.fn.writefile(h, _get_cache_path() .. '/merged')
end
function _load_merged_plugins()
  local path = _get_cache_path() .. '/merged'
  if vim.fn.filereadable(path)==0 then
    return {}
  end
  local merged = vim.fn.readfile(path)
  if #merged ~= dein._merged_length then
    return {}
  end
  -- TODO sandbox
  local h = slice(merged, 1, dein._merged_length - 1)
  local t = a.nvim_eval(merged[#merged])
  vim.list_extend(h, t)
  return h
end
function _get_merged_plugins()
  local ftplugin_len = 0
  local _ftplugin = dein._ftplugin
  for _, ftplugin in ipairs(vim.tbl_values(_ftplugin)) do
    ftplugin_len = ftplugin_len + #ftplugin
  end
  local _plugins = dein._plugins
  local r1 = {dein._merged_format, vim.fn.string(ftplugin_len)}
  local r2 = vim.fn.sort(vim.fn.map(vim.tbl_values(_plugins), dein._merged_format))
  vim.list_extend(r1, r2)
  return r1
end

function _chomp(str)
  if str ~= '' and str:sub(-1) == '/' then
    return str:sub(1, -2)
  else
    return str
  end
end
function _end()
  if dein._block_level ~= 1 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  dein._block_level = dein._block_level - 1

  if vim.fn.has('vim_starting')==0 then
    require 'dein/autoload'
    local plugins = vim.tbl_filter(
      function(v)
        return v.lazy==0 and v.sourced==0 and v.rtp ~= ''
      end,
      vim.tbl_values(dein._plugins)
    )
    _source(plugins)
  end

  -- Add runtimepath
  rtps = _split_rtp(vim.o.rtp)
  local index = vim.fn.index(rtps, dein._runtime_path)
  if index < 0 then
    M._error('Invalid runtimepath.')
    return 1
  end

  local depends = {}
  local sourced = vim.fn.has('vim_starting')==1 and (vim.fn.exists('&loadplugins')==0 or vim.o.loadplugins)
  local _plugins = dein._plugins
  for _, plugin in ipairs(
    vim.tbl_filter(function (x) return x.lazy==0 and x.sourced==0 and x.rtp~='' end,
      vim.tbl_values(_plugins))) do
    -- Load dependencies
    if plugin['depends'] ~= nil then
      depends = depends + plugin.depends
    end

    if plugin.merged==0 then
      table.insert(rtps, index+1, plugin.rtp)
      if vim.fn.isdirectory(plugin.rtp..'/after')==1 then
        rtps = _add_after(rtps, plugin.rtp..'/after')
      end
    end

    plugin.sourced = sourced
  end
  dein._plugins = _plugins
  vim.o.rtp = _join_rtp(rtps, vim.o.rtp, '')

  if vim.fn.empty(depends)==0 then
    vim.fn['dein#source'](depends)
  end

  if dein._hook_add ~= '' then
    vim.fn['dein#util#_execute_hook']({}, dein._hook_add)
  end

  local _event_plugins = dein._event_plugins
  -- TODO
  _event_plugins[true] = nil
  for event, plugins in pairs(_event_plugins) do
    if vim.fn.exists('##'..event) then
      local t = event .. ' *'
      vim.api.nvim_command(
        vim.fn.printf('autocmd dein-events %s lua _on_event("%s", %s)',
        t, event, vim.inspect(plugins))
      )
    end
  end

  if vim.fn.has('vim_starting')==0 then
    _call_hook('add')
    _call_hook('source')
    _call_hook('post_source')
  end
end

function _download(uri, outpath)
  if vim.fn.exists('g:dein#download_command')==0 then
    local c
    if vim.fn.executable('curl')==1 then
      c = 'curl --silent --location --output'
    elseif vim.fn.executable('wget')==1 then
      c = 'wget -q -O'
    else
      c = ''
    end
    vim.g['dein#download_command'] = c
  end
  if c ~= '' then
    return vim.fn.printf('%s "%s" "%s"', c, outpath, uri)
  elseif _is_windows() then
    -- Use powershell
    -- TODO: Proxy support
    local pscmd = vim.fn.printf("(New-Object Net.WebClient).DownloadFile('%s', '%s')", uri, outpath)
    return vim.fn.printf('powershell -Command "%s"', pscmd)
  else
    return 'E: curl or wget command is not available!'
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
