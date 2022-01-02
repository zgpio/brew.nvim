-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local a = vim.api
local M = {}
local brew = dein
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
local is_mac = (not is_windows) and vim.fn.has('win32unix') == 0
  and (vim.fn.has('mac')==1 or vim.fn.has('macunix')==1 or vim.fn.has('gui_macvim')==1
    or (vim.fn.isdirectory('/proc')==0 and vim.fn.executable('sw_vers')==1))

local _merged_length = 3

function M.is_windows()
  return is_windows
end
function M.is_mac()
  return is_mac
end
function M.get_runtime_path()
  local rtp = brew._runtime_path
  if rtp ~= '' then
    return rtp
  end
  rtp = M.get_cache_path() .. '/.dein'
  brew._runtime_path = rtp
  if vim.fn.isdirectory(rtp)==0 then
    vim.fn.mkdir(rtp, 'p')
  end
  return rtp
end

function M.is_fish()
  return require 'dein/install'.is_async() and vim.fn.fnamemodify(vim.o.shell, ':t:r') == 'fish'
end
function M.is_powershell()
  local t = vim.fn.fnamemodify(vim.o.shell, ':t:r')
  return require 'dein/install'.is_async() and (t == 'powershell' or t == 'pwsh')
end
local function _msg2list(expr)
  if vim.tbl_islist(expr) then  -- type(expr) == 'table'
    return expr
  else
    return vim.split(expr, '\n')
  end
end

function M._error(msg)
  for _, s in ipairs(_msg2list(msg)) do
    local c = 'echomsg '..vim.fn.string("[dein] "..s)
    a.nvim_command('echohl WarningMsg')
    a.nvim_command(c)
    a.nvim_command('echohl None')
  end
end

local function _get_myvimrc()
  local vimrc = vim.env.MYVIMRC
  if vimrc == '' then
    vimrc = vim.fn.matchstr(vim.fn.split(vim.fn.execute('scriptnames'), '\n')[1], [[^\s*\d\+:\s\zs.*]])
  end
  return M.substitute_path(vimrc)
end

function M.clear_state()
  local base = brew.cache_directory or brew._base_path
  local caches = M.globlist(base..'/state_*.vim')
  vim.list_extend(caches, M.globlist(base..'/cache_*'))
  caches = vim.tbl_filter(function(v) return v~='' end, caches)
  for _, cache in ipairs(caches) do
    vim.fn.delete(cache)
  end
end

-- test cases: '~/Desktop/', '$HOME/Desktop/', 'C:\Users'
function M.expand(path)
  local p
  if path:find('^~') then
    p = vim.fn.fnamemodify(path, ':p')
  elseif path:find('^%$%w*') then
    p = vim.fn.expand(path)  -- :h expr-env-expand
  else
    p = path
  end

  if (is_windows and p:find([[\]])) then
    return M.substitute_path(p)
  else
    return p
  end
end

function M.execute_hook(plugin, hook)
  -- dein_log:write(vim.inspect({"_execute_hook", plugin.name, hook}), "\n")
  -- dein_log:flush()
  try {
    function()
      -- TODO 恢复 g:dein#plugin 提供的功能
      brew.plugin = plugin
      if type(hook) == 'string' then
        vim.fn.execute(vim.split(hook, '\n'))
      else
        vim.fn.call(hook, {})
      end
    end,
    catch {
      function(error)
        M._error('Error occurred while executing hook: ' .. vim.fn.get(plugin, 'name', ''))
        M._error(vim.v.exception)

        print('caught error: ' .. error)
      end
    }
  }
end
function M.check_clean()
  local plugins_directories = vim.tbl_map(function(v) return v.path end, vim.tbl_values(brew.get()))
  local path = M.substitute_path(vim.fn.globpath(brew._base_path, 'repos/*/*/*'))
  return vim.tbl_filter(
    function(v)
      return vim.fn.isdirectory(v) and vim.fn.fnamemodify(v, ':t') ~= 'dein.vim' and vim.fn.index(plugins_directories, v) < 0
    end,
    vim.split(path, "\n")
  )
end

local function _get_merged_plugins()
  local ftplugin_len = 0
  local _ftplugin = brew._ftplugin
  for _, ftplugin in ipairs(vim.tbl_values(_ftplugin)) do
    ftplugin_len = ftplugin_len + #ftplugin
  end
  local _plugins = brew._plugins
  local _merged_format = "{'repo': v:val.repo, 'rev': get(v:val, 'rev', '')}"
  local r1 = {brew._merged_format, vim.fn.string(ftplugin_len)}
  local r2 = vim.fn.sort(vim.fn.map(vim.tbl_values(_plugins), _merged_format))
  vim.list_extend(r1, r2)
  return r1
end

-- return 1 means outdated
function _check_vimrcs()
  local time = vim.fn.getftime(M.get_runtime_path())
  for _, v in ipairs(brew._vimrcs) do
    local vt = vim.fn.getftime(vim.fn.expand(v))
    if vt > time then
      M.clear_state()
      return 1
    end
  end

  return 0
end
local function _save_cache(vimrcs, is_state, is_starting)
  if M.get_cache_path() == '' or (is_starting==0) then
    -- Ignore
    return true
  end

  -- TODO: deepcopy
  local plugins = brew.get()

  for _, plugin in ipairs(vim.tbl_values(plugins)) do
    if is_state == 0 then
      plugin.sourced = false
    end
    if plugin.orig_opts ~= nil then
      plugin.orig_opts = nil
    end

    -- Hooks
    for _, hook in ipairs({'hook_add', 'hook_source',
      'hook_post_source', 'hook_post_update',}) do
      if plugin[hook] ~= nil and vim.fn.type(plugin[hook]) == 2 then
        plugin[hook] = nil
      end
    end
  end

  local base_path = brew._base_path
  if vim.fn.isdirectory(base_path) == 0 then
    vim.fn.mkdir(base_path, 'p')
  end

  local ftplugin = brew._ftplugin
  vim.fn.writefile({vim.fn.string(vimrcs), vim.fn.json_encode(plugins), vim.fn.json_encode(ftplugin)},
    (brew.cache_directory or base_path) ..'/cache_' .. brew._progname)
end

local function tsort_impl(target, mark, sorted)
  if vim.tbl_isempty(target) or mark[target.name]~=nil then
    return
  end

  mark[target.name] = 1
  if target.depends~=nil then
    for _, depend in ipairs(target.depends) do
      tsort_impl(brew.get(depend), mark, sorted)
    end
  end

  table.insert(sorted, target)
end
--@param plugins plugin list
local function _tsort(plugins)
  local sorted = {}
  local mark = {}
  for _, target in ipairs(plugins) do
    tsort_impl(target, mark, sorted)
  end

  return sorted
end
--@param ... {{{}, {}, ...}}
function M.call_hook(hook_name, ...)
  local args = ...
  local hook = 'hook_' .. hook_name
  local t
  if args and #args > 0 then t = args[1] else t = {} end
  local plugins = vim.tbl_filter(
    function(x)
      return ((hook_name ~= 'source' and hook_name ~= 'post_source')
        or x.sourced) and x[hook] ~= nil and vim.fn.isdirectory(x.path)==1
    end,
    M.get_plugins(t)
  )

  for _, plugin in ipairs(
    vim.tbl_filter(function(x) return x[hook] ~= nil end, _tsort(plugins))) do
    M.execute_hook(plugin, plugin[hook])
  end
end
function M.globlist(path)
  return vim.split(vim.fn.glob(path), '\n')
end
function M.add_after(rtps, path)
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
function M.get_lazy_plugins()
  local plugins = vim.tbl_values(brew._plugins)
  -- table.filter  https://gist.github.com/FGRibreau/3790217
  local rv = {}
  for _, t in ipairs(plugins) do
    if not t.sourced and t.rtp ~= '' then
      table.insert(rv, t)
    end
  end
  return rv
end

function M.check_lazy_plugins()
  local rv = {}
  for _, t in ipairs(M.get_lazy_plugins()) do
    if vim.fn.isdirectory(t.rtp) == 1
      and (t['local'] or 0) == 0
      and (t.hook_source or '') == ''
      and (t.hook_add or '') == ''
      and vim.fn.isdirectory(t.rtp..'/plugin') == 0
      and vim.fn.isdirectory(t.rtp..'/after/plugin') == 0 then
      table.insert(rv, t.name)
    end
  end
  return rv
end

function M.get_cache_path()
  local cache_path = brew._cache_path
  if cache_path ~= '' then
    return cache_path
  end

  cache_path = (brew.cache_directory or brew._base_path)
    ..'/.cache/'..vim.fn.fnamemodify(_get_myvimrc(), ':t')
  brew._cache_path = cache_path
  if vim.fn.isdirectory(cache_path) == 0 then
    vim.fn.mkdir(cache_path, 'p')
  end
  return cache_path
end

function M.substitute_path(path)
  if (is_windows or vim.fn.has('win32unix')==1) and path:find([[\]]) then
    return vim.fn.tr(path, [[\]], '/')
  else
    return path
  end
end

local function skipempty(string)
  return vim.tbl_filter(function(v) return v~='' end, vim.split(string, '\n'))
end

function M.save_state(is_starting)
  if brew._block_level ~= 0 then
    M._error('Invalid save_state() usage.')
    return 1
  end

  if M.get_cache_path() == '' or is_starting == 0 or brew._is_sudo then
    -- Ignore
    return 1
  end

  if (brew.auto_recache or 0) == 1 then
    _notify('auto recached')
    require 'dein/install'.recache_runtimepath()
  end

  brew._vimrcs = M.uniq(brew._vimrcs)
  vim.o.rtp = M.join_rtp(M.uniq(M.split_rtp(vim.o.rtp)), vim.o.rtp, '')

  _save_cache(brew._vimrcs, 1, is_starting)

  -- Version check

  local lines = {
--    'lua require "dein/autoload"',
--    'if luaeval("dein._cache_version") !=# ' .. brew._cache_version .. ' || ' ..
--    'luaeval("dein._init_runtimepath") !=# ' .. vim.fn.string(brew._init_runtimepath) ..
--         ' | throw "Cache loading error" | endif',
--    'let [plugins, ftplugin] = v:lua.load_cache_raw('..
--         vim.fn.string(brew._vimrcs) ..')',
--    "if empty(plugins) | throw 'Cache loading error' | endif",
--    'call luaeval("set_dein_plugins(_A)", plugins)',
--    'call luaeval("set_dein_ftplugin(_A)", ftplugin)',
--    'lua dein._base_path = ' .. vim.fn.string(brew._base_path),
--    'lua dein._runtime_path = ' .. vim.fn.string(brew._runtime_path),
--    'lua dein._cache_path = ' .. vim.fn.string(brew._cache_path),

    'lua<<EOF',
    'require "dein/autoload"',
    'local brew = require "dein"',
    'if brew._cache_version ~= '..brew._cache_version..' or brew._init_runtimepath ~= '..vim.inspect(brew._init_runtimepath)..
      ' then error("Cache outdated or runtimepath changed") end',
    'local plugins, ftplugin = load_cache_raw('.. vim.inspect(brew._vimrcs) ..')',
    'if vim.tbl_isempty(plugins) then error("Cache loading error") end',
    'brew._plugins = plugins',
    'brew._ftplugin = ftplugin',
    'brew._base_path = ' .. vim.fn.string(brew._base_path),
    'brew._runtime_path = ' .. vim.fn.string(brew._runtime_path),
    'brew._cache_path = ' .. vim.fn.string(brew._cache_path),
    'EOF',
    'let &runtimepath = ' .. vim.fn.string(vim.o.rtp),
  }

  if brew._off1 ~= '' then
    table.insert(lines, brew._off1)
  end
  if brew._off2 ~= '' then
    table.insert(lines, brew._off2)
  end

  -- Add dummy mappings/commands
  for _, plugin in ipairs(M.get_lazy_plugins()) do
    for _, command in ipairs(plugin.dummy_commands or {}) do
      table.insert(lines, 'silent! ' .. command[2])
    end
    for _, mapping in ipairs(plugin.dummy_mappings or {}) do
      table.insert(lines, 'silent! ' .. mapping[3])
    end
  end

  -- Add hooks
  if vim.fn.empty(brew._hook_add)==0 then
    vim.list_extend(lines, skipempty(brew._hook_add))
  end
  for _, plugin in ipairs(_tsort(vim.tbl_values(brew.get()))) do
    if plugin.hook_add~=nil and type(plugin.hook_add) == 'string' then
      vim.list_extend(lines, skipempty(plugin.hook_add))
    end

    -- Invalid hooks detection
    for k, v in pairs(plugin) do
      if vim.fn.stridx(k, 'hook_') == 0 and type(v) ~= 'string' then
        M._error(vim.fn.printf('%s: "%s" must be string to save state', plugin.name, k))
      end
    end
  end

  -- Add events
  for event, plugins in pairs(brew._event_plugins) do
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

  -- Add inline vimrcs
  for _, vimrc in ipairs(brew.inline_vimrcs or {}) do
    vim.list_extend(lines,
      vim.tbl_filter(
        function(v) return not (v:find('^%s*"') or v:find('^%s$')) end,
        vim.fn.readfile(M.expand(vimrc))
      ))
  end

  vim.fn.writefile(lines,
    (brew.cache_directory or brew._base_path) ..'/state_' .. brew._progname .. '.vim')
end
function M.edit_state_file()
  a.nvim_command(':e '..(brew.cache_directory or brew._base_path) ..'/state_' .. brew._progname .. '.vim')
end
function M.edit_cache_file()
  local base_path = brew._base_path
  a.nvim_command(':e '..(brew.cache_directory or base_path) ..'/cache_' .. brew._progname)
end

function M.edit_merged_file()
  a.nvim_command(':e '..M.get_cache_path() .. '/merged')
end

function M.writefile(path, list)
  if brew._is_sudo or (vim.fn.filewritable(M.get_cache_path())==0) then
    return 1
  end

  path = M.get_cache_path() .. '/' .. path
  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  return vim.fn.writefile(list, path)
end

-- plugins: { plugin_tbl1, ... } / { plugin_name1, ... } / plugin_name
-- NOTE: remove support for plugin_tbl
function M.get_plugins(plugins)
  if vim.tbl_isempty(plugins) then
    return vim.tbl_values(brew.get())
  else
    plugins = vim.tbl_map(
      function(v)
        if type(v)=='table' and not vim.tbl_islist(v) then
          return v
        else
          return brew.get(v)
        end
      end,
      M.convert2list(plugins)
    )
    local rv = {}
    for _, v in ipairs(plugins) do
      if not vim.tbl_isempty(v) then
        table.insert(rv, v)
      end
    end
    return rv
  end
end

function execute(expr)
  return vim.fn.execute(vim.split(expr, '\n'), '')
end
function M.map_filter(t, filterIter)
  local rv = {}

  for k, v in pairs(t) do
    if filterIter(k, v) then rv[k] = v end
  end

  return rv
end

function M.split_rtp(rtp)
  if vim.fn.stridx(rtp, [[\,]]) < 0 then
    return vim.split(rtp, ',')
  end

  local split = vim.fn.split(rtp, [[\\\@<!\%(\\\\\)*\zs,]])
  return vim.fn.map(split, [[substitute(v:val, '\\\([\\,]\)', '\1', 'g')]])
end
function M.join_rtp(list, runtimepath, rtp)
  if vim.fn.stridx(runtimepath, [[\,]]) < 0 and vim.fn.stridx(rtp, ',') < 0 then
    return vim.fn.join(list, ',')
  else
    return vim.fn.join(vim.tbl_map(escape, list), ',')
  end
end
function M.convert2list(expr)
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
function M.check_install(plugins)
  plugins = M.convert2list(plugins)
  if not vim.tbl_isempty(plugins) then
    local invalids = vim.tbl_filter(function(x) return vim.tbl_isempty(dein.get(x)) end, plugins)
    if not vim.tbl_isempty(invalids) then
      M._error('Invalid plugins: ' .. vim.fn.string(invalids))
      return -1
    end
    plugins = vim.tbl_map(function(v) return brew.get(v) end, plugins)
  else
    plugins = vim.tbl_values(brew.get())
  end
  plugins = vim.tbl_filter(function(x) return vim.fn.isdirectory(x.path)==0 end, plugins)
  if vim.tbl_isempty(plugins) then return 0 end
  _notify('Not installed plugins: ' .. vim.fn.string(vim.fn.map(plugins, 'v:val.name')))
  return 1
end

function _notify(msg)
  brew.enable_notification = brew.enable_notification or 0
  brew.notification_icon = brew.notification_icon or ''
  brew.notification_time = brew.notification_time or 2

  if brew.enable_notification==0 or msg == '' or vim.fn.has('vim_starting')==1 then
    M._error(msg)
    return
  end

  local icon = M.expand(brew.notification_icon)

  local title = '[dein]'
  local cmd = ''
  if vim.fn.executable('notify-send')==1 then
    cmd = vim.fn.printf('notify-send --expire-time=%d', brew.notification_time * 1000)
    if icon ~= '' then
      cmd = cmd.. ' --icon=' .. vim.fn.string(icon)
    end
    cmd = cmd.. ' ' .. vim.fn.string(title) .. ' ' .. vim.fn.string(msg)
  elseif M.is_windows() and vim.fn.executable('Snarl_CMD')==1 then
    cmd = vim.fn.printf('Snarl_CMD snShowMessage %d "%s" "%s"',
           brew.notification_time, title, msg)
    if icon ~= '' then
      cmd = cmd.. ' "' .. icon .. '"'
    end
  elseif M.is_mac() then
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
    _system(cmd)
  end
end

local function _get_vimrcs(vimrcs)
  if vim.fn.empty(vimrcs)==1 then
    return {_get_myvimrc()}
  else
    return vim.tbl_map(
      function(v)
        return vim.fn.expand(v)
      end,
      M.convert2list(vimrcs)
    )
  end
end

function _begin(path, vimrcs)
  if vim.fn.exists('#dein')==0 then
    brew._init()
  end

  if path == '' or brew._block_level ~= 0 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  brew._block_level = brew._block_level + 1
  brew._base_path = M.expand(path)
  if brew._base_path:sub(-1) == '/' then
    brew._base_path = brew._base_path:sub(1, -2)
  end
  M.get_runtime_path()
  M.get_cache_path()
  brew._vimrcs = _get_vimrcs(vimrcs)
  if brew.inline_vimrcs~=nil then
    brew._vimrcs = vim.tbl_extend('keep', brew._vimrcs, brew.inline_vimrcs)
  end
  brew._hook_add = ''

  if vim.fn.has('vim_starting')==1 then
    -- Filetype off
    if vim.g.did_load_filetypes~=nil or vim.fn.has('nvim')==1 then
      brew._off1 = 'filetype off'
      a.nvim_command(brew._off1)
    end
    if vim.b.did_indent~=nil or vim.b.did_ftplugin~=nil then
      brew._off2 = 'filetype plugin indent off'
      a.nvim_command(brew._off2)
    end
  else
    a.nvim_command('set rtp-='..vim.fn.fnameescape(brew._runtime_path))
    a.nvim_command('set rtp-='..vim.fn.fnameescape(brew._runtime_path..'/after'))
  end

  -- Insert dein runtimepath to the head in 'runtimepath'.
  local rtps = M.split_rtp(vim.o.rtp)
  local idx = vim.fn.index(rtps, vim.env.VIMRUNTIME)
  if idx < 0 then
    M._error('Invalid runtimepath.')
    return 1
  end
  if vim.fn.fnamemodify(path, ':t') == 'plugin' and vim.fn.index(rtps, vim.fn.fnamemodify(path, ':h')) >= 0 then
    M._error('You must not set the installation directory under "&runtimepath/plugin"')
    return 1
  end
  rtps = vim.fn.insert(rtps, brew._runtime_path, idx)
  rtps = M.add_after(rtps, brew._runtime_path..'/after')
  vim.o.runtimepath = M.join_rtp(rtps, vim.o.rtp, brew._runtime_path)
end

-- TODO: duplicate
-- [first, last]
function slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end
  return sliced
end
function M.save_merged_plugins()
  local merged = _get_merged_plugins()
  local h = slice(merged, 1, _merged_length - 1)
  local t = slice(merged, _merged_length)
  vim.list_extend(h, {vim.fn.string(t)})
  vim.fn.writefile(h, M.get_cache_path() .. '/merged')
end
function M.load_merged_plugins()
  local path = M.get_cache_path() .. '/merged'
  if vim.fn.filereadable(path)==0 then
    return {}
  end
  local merged = vim.fn.readfile(path)
  if #merged ~= _merged_length then
    return {}
  end
  -- TODO sandbox
  local h = slice(merged, 1, _merged_length - 1)
  local t = a.nvim_eval(merged[#merged])
  vim.list_extend(h, t)
  return h
end

function M.chomp(str)
  if str ~= '' and str:sub(-1) == '/' then
    return str:sub(1, -2)
  else
    return str
  end
end
function _end()
  if brew._block_level ~= 1 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  brew._block_level = brew._block_level - 1
  local vim_starting = vim.fn.has('vim_starting')==1

  if not vim_starting then
    require 'dein/autoload'
    local plugins = vim.tbl_filter(
      function(v)
        return v.lazy==0 and not v.sourced and v.rtp ~= ''
      end,
      vim.tbl_values(brew._plugins)
    )
    _source(plugins)
  end

  -- Add runtimepath
  local rtps = M.split_rtp(vim.o.rtp)
  local index = vim.fn.index(rtps, brew._runtime_path)
  if index < 0 then
    M._error('Invalid runtimepath.')
    return 1
  end

  local depends = {}
  local sourced = vim_starting and (vim.fn.exists('&loadplugins')==0 or vim.o.loadplugins)
  local _plugins = brew._plugins
  for _, plugin in ipairs(
    vim.tbl_filter(function (x) return x.lazy==0 and not x.sourced and x.rtp~='' end,
      vim.tbl_values(_plugins))) do
    -- Load dependencies
    if plugin.depends ~= nil then
      vim.list_extend(depends, plugin.depends)
    end

    if plugin.merged==0 then
      table.insert(rtps, index+1, plugin.rtp)
      if vim.fn.isdirectory(plugin.rtp..'/after')==1 then
        rtps = M.add_after(rtps, plugin.rtp..'/after')
      end
    end

    plugin.sourced = sourced
  end
  brew._plugins = _plugins
  vim.o.rtp = M.join_rtp(rtps, vim.o.rtp, '')

  if vim.fn.empty(depends)==0 then
    _source(depends)
  end

  if brew._hook_add ~= '' then
    M.execute_hook({}, brew._hook_add)
  end

  local _event_plugins = brew._event_plugins
  for event, plugins in pairs(_event_plugins) do
    if vim.fn.exists('##'..event) then
      local t = event .. ' *'
      a.nvim_command(
        vim.fn.printf('autocmd dein-events %s lua _on_event("%s", %s)',
        t, event, vim.inspect(plugins))
      )
    end
  end

  for _, vimrc in ipairs(brew.inline_vimrcs or {}) do
    vim.api.nvim_command("source "..M.expand(vimrc))
  end

  if not vim_starting then
    M.call_hook('add')
    M.call_hook('source')
    M.call_hook('post_source')
  end
end

function M.download(uri, outpath)
  local c
  if brew.download_command==nil then
    if vim.fn.executable('curl')==1 then
      c = 'curl --silent --location --output'
    elseif vim.fn.executable('wget')==1 then
      c = 'wget -q -O'
    else
      c = ''
    end
    brew.download_command = c
  end
  if c ~= '' then
    return vim.fn.printf('%s "%s" "%s"', c, outpath, uri)
  elseif M.is_windows() then
    -- Use powershell
    -- TODO: Proxy support
    local pscmd = vim.fn.printf("(New-Object Net.WebClient).DownloadFile('%s', '%s')", uri, outpath)
    return vim.fn.printf('powershell -Command "%s"', pscmd)
  else
    return 'E: curl or wget command is not available!'
  end
end
--@param list basic type list
function M.uniq(list)
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
