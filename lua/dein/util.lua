-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
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
  local rtp = vim.g['dein#_runtime_path']
  if rtp ~= '' then
    return rtp
  end
  rtp = _get_cache_path() .. '/.dein'
  vim.g['dein#_runtime_path'] = rtp
  if vim.fn.isdirectory(rtp)==0 then
    vim.fn.mkdir(rtp, 'p')
  end
  return rtp
end
-- TODO: review
function _save_cache(vimrcs, is_state, is_starting)
  if _get_cache_path() == '' or (is_starting==0) then
    -- Ignore
    return true
  end

  local plugins = vim.fn['dein#get']()

  for i, plugin in ipairs(vim.tbl_values(plugins)) do
    if is_state == 0 then
      plugin.sourced = 0
    end
    if plugin['orig_opts'] ~= nil then
      plugin['orig_opts'] = nil
    end

    -- Hooks
    for i, hook in ipairs({'hook_add', 'hook_source',
      'hook_post_source', 'hook_post_update',}) do
      if plugin[hook] ~= nil and vim.fn.type(plugin[hook]) == 2 then
        plugin[hook] = nil
      end
    end
  end

  local base_path = vim.g['dein#_base_path']
  if not vim.fn.isdirectory(base_path) == 1 then
    vim.fn.mkdir(base_path, 'p')
  end

  local ftplugin = vim.g['dein#_ftplugin']
  vim.fn.writefile({vim.inspect(vimrcs), vim.fn.json_encode(plugins), vim.fn.json_encode(ftplugin)},
    (vim.g['dein#cache_directory'] or base_path) ..'/cache_' .. vim.g['dein#_progname'])
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
  local cache_path = vim.g['dein#_cache_path']
  if cache_path ~= '' then
    return cache_path
  end

  cache_path = (vim.g['dein#cache_directory'] or vim.g['dein#_base_path'])
    ..'/.cache/'..vim.fn.fnamemodify(vim.fn['dein#util#_get_myvimrc'](), ':t')
  vim.g['dein#_cache_path'] = cache_path
  if vim.fn.isdirectory(cache_path) == 0 then
    vim.fn.mkdir(cache_path, 'p')
  end
  return cache_path
end

-- function! dein#util#_substitute_path(path) abort
--   return ((s:is_windows || has('win32unix')) && a:path =~# '\\') ?
--         \ tr(a:path, '\', '/') : a:path
-- endfunction

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
function _error(msg)
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
function msg2list(expr)
  if type(expr) == 'table' then
    return expr
  else
    return vim.split(expr, '\n')
  end
end
