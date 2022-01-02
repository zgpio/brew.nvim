-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local a = vim.api
local M = {}

function M._init()
  M.plugin = {}
  M._cache_version = 150
  M._plugins = {}
  M._cache_path = ''
  M._base_path = ''
  M._runtime_path = ''
  M._hook_add = ''
  M._ftplugin = {}
  M._off1 = ''
  M._off2 = ''
  M._vimrcs = {}
  M._block_level = 0
  M._event_plugins = {}
  M._progname = vim.fn.fnamemodify(vim.v.progname, ':r')
  M._init_runtimepath = vim.o.rtp
  local SUDO_USER = vim.env.SUDO_USER
  local USER = vim.env.USER
  local HOME = vim.env.HOME
  M._is_sudo = (SUDO_USER~=nil and USER ~= SUDO_USER
    and HOME ~= vim.fn.expand('~'..USER)
    and HOME == vim.fn.expand('~'..SUDO_USER))
  M._loaded_rplugins = false

  if (M.lazy_rplugins or false) then
    -- Disable remote plugin loading
    vim.g.loaded_remote_plugins = 1
  end

  a.nvim_exec([[
    augroup dein
      autocmd!
      autocmd FuncUndefined *
          \ if stridx(expand('<afile>'), 'remote#') != 0 |
          \   call luaeval("require'dein/autoload'._on_func(_A)", expand('<afile>')) |
          \ endif
      autocmd BufRead *? lua _on_default_event('BufRead')
      autocmd BufNew,BufNewFile *? lua _on_default_event('BufNew')
      autocmd VimEnter *? lua _on_default_event('VimEnter')
      autocmd FileType *? lua _on_default_event('FileType')
      autocmd BufWritePost *.vim,*.toml,vimrc,.vimrc lua _check_vimrcs()
    augroup END
    augroup dein-events | augroup END
  ]], true)

  if vim.fn.exists('##CmdUndefined')==0 then return end
  a.nvim_command([[autocmd dein CmdUndefined *  call v:lua._on_pre_cmd(expand('<afile>'))]])
end
function M.get(...)
  local args = {...}
  if vim.tbl_isempty(args) then
    return vim.deepcopy(M._plugins)
  else
    return (vim.deepcopy(M._plugins[args[1]]) or {})
  end
end
function M.install(...)
  local install = require 'dein/install'
  local args = {...}
  return _update((args[1] or {}), 'install', install.is_async())
end
function M.update(...)
  local install = require 'dein/install'
  local args = {...}
  if #args > 0 and type(args[1]) == 'table' then
    args = args[1]
  end
  return _update(args, 'update', install.is_async())
end
function M.build(...)
  require 'dein/install'
  local args = {...}
  local plugins = {}
  if #args > 0 then
    plugins = args[1]
  end
  return _build(plugins)
end
function M.check_clean()
  return require'dein/util'.check_clean()
end
function M.source(...)
  return _source({...})
end
function M.check_install(...)
  local args = {...}
  return require 'dein/util'.check_install((args[1] or {}))
end
function M.check_update(...)
  local install = require 'dein/install'
  local args = {...}
  return _check_update((args[2] or {}), (args[1] or false), install.is_async())
end
function M.direct_install(repo, ...)
  local args = {...}
  local opts = {}
  if #args > 0 then
    opts = args[1]
  end
  require 'dein/install'.direct_install(repo, opts)
end
function M.reinstall(...)
  local args = {...}
  if #args > 0 and type(args[1]) == 'table' then
    args = args[1]
  end
  require 'dein/install'.reinstall(args)
end
function M.remote_plugins()
  return require 'dein/install'.remote_plugins()
end
function M.recache_runtimepath()
  require 'dein/install'.recache_runtimepath()
end
function M.check_lazy_plugins()
  return require 'dein/util'.check_lazy_plugins()
end
function M.get_direct_plugins_path()
  return (M.cache_directory or M._base_path).."/direct_install.vim"
end
function M.begin(path, ...)
  require 'dein/util'
  local args = {...}
  return _begin(path, (args[1] or {}))
end
function M.End()
  require 'dein/util'
  return _end()
end
function M.load_toml(filename, ...)
  local args = {...}
  return require 'dein/parse'.load_toml(filename, (args[1] or {}))
end
function M.save_state()
  return require'dein/util'.save_state(vim.fn.has('vim_starting'))
end
function M.get_log()
  return vim.fn.join(require 'dein/install'.get_log(), "\n")
end
function M.get_progress()
  return require 'dein/install'.get_progress()
end
function M.each(command, ...)
  require 'dein/install'
  local args = {...}
  local plugins = {}
  if #args > 0 then
    plugins = args[1]
  end
  return _each(command, plugins)
end
function M.load_dict(dict, ...)
  local args = {...}
  return require 'dein/parse'.load_dict(dict, (args[1] or {}))
end
function M.add(repo, ...)
  local args = {...}
  return require 'dein/parse'._add(repo, (args[1] or {}), false)
end
function M.get_updates_log()
  return vim.fn.join(require 'dein/install'.get_updates_log(), "\n")
end
function M.clear_state()
  require 'dein/util'.clear_state()
end
function M.load_rollback(rollbackfile, ...)
  local args = {...}
  local plugins = {}
  if #args > 0 then
    plugins = args[1]
  end
  require 'dein/install'.load_rollback(rollbackfile, plugins)
end
function M.save_rollback(rollbackfile, ...)
  require 'dein/install'
  local args = {...}
  local plugins = {}
  if #args > 0 then
    plugins = args[1]
  end
  _save_rollback(rollbackfile, plugins)
end
function M.rollback(date, ...)
  require 'dein/install'
  local args = {...}
  local plugins = {}
  if #args > 0 then
    plugins = args[1]
  end
  _rollback(date, plugins)
end
function M.Local(dir, ...)
  require 'dein/parse'
  local args = {...}
  return _local(dir, (args[1] or {}), (args[2] or {'*'}))
end
function M.call_hook(hook_name, ...)
  return require 'dein/util'.call_hook(hook_name, {...})
end
function M.load_state(path, ...)
  if vim.fn.exists('#dein') == 0 then
    M._init()
  end
  local args = {...}
  local sourced
  if #args > 0 then
    sourced = args[1]
  else
    sourced = vim.fn.has('vim_starting')==1 and vim.o.loadplugins
  end
  if (M._is_sudo or not sourced) then return 1 end
  M._base_path = vim.fn.expand(path)

  local state = (M.cache_directory or M._base_path)
    .. '/state_' .. M._progname .. '.vim'
  if vim.fn.filereadable(state)==0 then return 1 end

  local status, result = pcall(function() a.nvim_command('source ' .. vim.fn.fnameescape(state)) end)
  if not status then
    local util = require 'dein/util'
    if vim.v.exception ~= 'Cache loading error' then
      util._error('Loading state error: ' .. vim.v.exception)
    end
    util.clear_state()
    print('caught error: ' .. result)
    return 1
  end

  return 0
end
function load_cache_raw(vimrcs)
  M._vimrcs = vimrcs
  local cache = (M.cache_directory or M._base_path) ..'/cache_' .. M._progname
  local time = vim.fn.getftime(cache)
  local t = vim.tbl_filter(
    function(v)
      return time < v
    end,
    vim.tbl_map(
      function(v)
       return vim.fn.getftime(vim.fn.expand(v))
      end,
      vim.deepcopy(M._vimrcs)
    )
  )
  if #t~=0 then
    return {}, {}
  end
  local list = vim.fn.readfile(cache)
  if #list ~= 3 or vim.fn.string(M._vimrcs) ~= list[1] then
    return {}, {}
  end
  return vim.fn.json_decode(list[2]), vim.fn.json_decode(list[3])
end

function M.tap(name)
  local _plugins = M._plugins
  if _plugins.name==nil or vim.fn.isdirectory(_plugins[name].path)==0 then
    return 0
  end
  M.plugin = _plugins[name]
  return 1
end
function M.is_sourced(name)
  local _plugins = M._plugins
  return _plugins.name~=nil
    and vim.fn.isdirectory(_plugins[name].path)==1
    and _plugins[name].sourced
end
dein = M
return M
