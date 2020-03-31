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
    let g:dein#_hook_add = ''
  ]], true)

  if path == '' or vim.g['dein#_block_level'] ~= 0 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  vim.g['dein#_block_level'] = vim.g['dein#_block_level'] + 1
  vim.g['dein#_base_path'] = vim.fn['dein#util#_expand'](path)
  if vim.g['dein#_base_path']:sub(-1) == '/' then
    vim.g['dein#_base_path'] = vim.g['dein#_base_path']:sub(1, -2)
  end
  _get_runtime_path()
  _get_cache_path()
  vim.g['dein#_vimrcs'] = vim.fn['dein#util#_get_vimrcs'](vimrcs)
  vim.g['dein#_hook_add'] = ''

  -- Filetype off
  if vim.fn.exists('g:did_load_filetypes')==1 or vim.fn.has('nvim')==1 then
    vim.g['dein#_off1'] = 'filetype off'
    vim.api.nvim_command('filetype off')
  end
  if vim.fn.exists('b:did_indent')==1 or vim.fn.exists('b:did_ftplugin')==1 then
    vim.g['dein#_off2'] = 'filetype plugin indent off'
    vim.api.nvim_command('filetype plugin indent off')
  end

  if vim.fn.has('vim_starting')==0 then
    vim.api.nvim_command('set rtp-='..vim.fn.fnameescape(vim.g['dein#_runtime_path']))
    vim.api.nvim_command('set rtp-='..vim.fn.fnameescape(vim.g['dein#_runtime_path']..'/after'))
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
  rtps = vim.fn.insert(rtps, vim.g['dein#_runtime_path'], idx)
  rtps = _add_after(rtps, vim.g['dein#_runtime_path']..'/after')
  vim.o.runtimepath = _join_rtp(rtps, vim.o.rtp, vim.g['dein#_runtime_path'])
end

function _end()
  if vim.g['dein#_block_level'] ~= 1 then
    M._error('Invalid begin/end block usage.')
    return 1
  end

  vim.g['dein#_block_level'] = vim.g['dein#_block_level'] - 1

  if vim.fn.has('vim_starting')==0 then
    -- TODO
    -- vim.fn['dein#source'](vim.fn.filter(vim.fn.values(vim.g['dein#_plugins']), "!v:val.lazy && !v:val.sourced && v:val.rtp !=# ''"))
    a.nvim_command([[call dein#source(filter(values(g:dein#_plugins), "!v:val.lazy && !v:val.sourced && v:val.rtp !=# ''"))]])
  end

  -- Add runtimepath
  rtps = _split_rtp(vim.o.rtp)
  local index = vim.fn.index(rtps, vim.g['dein#_runtime_path'])
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

  if vim.g['dein#_hook_add'] ~= '' then
    vim.fn['dein#util#_execute_hook']({}, vim.g['dein#_hook_add'])
  end

  local _event_plugins = vim.g['dein#_event_plugins']
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

return M
