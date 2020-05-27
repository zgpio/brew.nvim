-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local util = require 'dein/util'

function clear_runtimepath()
  if _get_cache_path() == '' then
    util._error('Invalid base path.')
    return
  end

  local runtimepath = _get_runtime_path()

  -- Remove runtime path
  _rm(runtimepath)

  if vim.fn.isdirectory(runtimepath)==0 then
    -- Create runtime path
    vim.fn.mkdir(runtimepath, 'p')
  end
end
function append_log_file(msg)
  local fn = vim.g['dein#install_log_filename']
  if not fn or fn=='' then
    return
  end
  local logfile = _expand(fn)

  -- Appends to log file.
  if vim.fn.filereadable(logfile)==1 then
    vim.fn.writefile(msg, logfile, 'a')
    return
  end

  local dir = vim.fn.fnamemodify(logfile, ':h')
  if vim.fn.isdirectory(dir)==0 then
    vim.fn.mkdir(dir, 'p')
  end
  vim.fn.writefile(msg, logfile)
end
function merge_files(plugins, directory)
  local files = {}
  for _, plugin in ipairs(plugins) do
    local t = vim.tbl_filter(
      function(v) return vim.fn.isdirectory(v)==0 end,
      vim.fn.globpath(plugin.rtp, directory..'/**', 1, 1)
    )
    for _, file in ipairs(t) do
      vim.list_extend(files, vim.fn.readfile(file, ':t'))
    end
  end

  if not vim.tbl_isempty(files) then
    _writefile(string.format('.dein/%s/%s.vim', directory, directory), files)
  end
end
function _get_default_ftplugin()
  return {
    [[if exists("g:did_load_ftplugin")]],
    [[  finish]],
    [[endif]],
    [[let g:did_load_ftplugin = 1]],
    [[]],
    [[augroup filetypeplugin]],
    [[  autocmd FileType * call s:ftplugin()]],
    [[augroup END]],
    [[]],
    [[function! s:ftplugin()]],
    [[  if exists("b:undo_ftplugin")]],
    [[    silent! execute b:undo_ftplugin]],
    [[    unlet! b:undo_ftplugin b:did_ftplugin]],
    [[  endif]],
    [[]],
    [[  let filetype = expand("<amatch>")]],
    [[  if filetype !=# ""]],
    [[    if &cpoptions =~# "S" && exists("b:did_ftplugin")]],
    [[      unlet b:did_ftplugin]],
    [[    endif]],
    [[    for ft in split(filetype, '\.')]],
    [[      execute "runtime! ftplugin/" . ft . ".vim"]],
    [[      \ "ftplugin/" . ft . "_*.vim"]],
    [[      \ "ftplugin/" . ft . "/*.vim"]],
    [[    endfor]],
    [[  endif]],
    [[  call s:after_ftplugin()]],
    [[endfunction]],
    [[]],
  }
end
function __get_revision_remote(plugin)
  local type = vim.fn['dein#util#_get_type'](plugin.type)

  -- TODO !has_key(type, 'get_revision_remote_command')
  if vim.fn.isdirectory(plugin.path)==0 or type.name ~= 'git' then
    return ''
  end

  local cmd = get_revision_remote_command(type, plugin)
  if vim.fn.empty(cmd)==1 then
    return ''
  end

  local rev = __system_cd(cmd, plugin.path)
  -- If rev contains spaces, it is error message
  if rev:find('%s')==nil then
    return rev
  else
    return ''
  end
end
function __get_updated_log_message(plugin, new_rev, old_rev)
  local type = vim.fn['dein#util#_get_type'](plugin.type)

  -- TODO has_key(type, 'get_log_command')
  local cmd = ''
  if type.name == 'git' then
    cmd = get_log_command(type, plugin, new_rev, old_rev)
  end
  local log = ''
  if vim.fn.empty(cmd)==0 then
    log = __system_cd(cmd, plugin.path)
  end
  if log ~= '' then
    return log
  else
    if old_rev == new_rev then
      return ''
    else
      return old_rev..' -> '..new_rev
    end
  end
end
function __get_revision_number(plugin)
  local type = vim.fn['dein#util#_get_type'](plugin.type)

  -- TODO !has_key(type, 'get_revision_number_command')
  if vim.fn.isdirectory(plugin.path)==0 or type.name ~= 'git' then
    return ''
  end

  local cmd = get_revision_number_command(type, plugin)
  if vim.fn.empty(cmd)==1 then
    return ''
  end

  local rev = __system_cd(cmd, plugin.path)

  -- If rev contains spaces, it is error message
  if rev:find('%s') then
    __error(plugin.name)
    __error('Error revision number: ' .. rev)
    return ''
  elseif rev == '' then
    __error(plugin.name)
    __error('Empty revision number: ' .. rev)
    return ''
  end
  return rev
end
function __system_cd(command, path)
  local cwd = vim.fn.getcwd()
  local rv = ''
  try {
    function()
      _cd(path)
      rv = vim.fn['dein#install#_system'](command)
    end,
    catch {
      function(e)
        print('caught error: ' .. e)
      end
    }
  }
  _cd(cwd)
  return rv
end
-- Helper functions
function _cd(path)
  if vim.fn.isdirectory(path)==0 then
    return
  end

  try {
    function()
      local d
      if vim.fn.haslocaldir()==1 then
        d = 'lcd'
      else
        d = 'cd'
      end
      vim.api.nvim_command('noautocmd execute '..vim.fn.string(d..vim.fn.fnameescape(path)))
    end,
    catch {
      function(e)
        __error('Error cd to: ' .. path)
        __error('Current directory: ' .. vim.fn.getcwd())
        __error(vim.v.exception)
        __error(vim.v.throwpoint)
        print('caught error: ' .. e)
      end
    }
  }
end
function _rm(path)
  if vim.fn.isdirectory(path)==0 and vim.fn.filereadable(path)==0 then
    return
  end

  -- Todo: use :python3 instead.

  -- Note: delete rf is broken
  -- if has('patch-7.4.1120')
  --   try
  --     call delete(a:path, 'rf')
  --   catch
  --     call v:lua.__error('Error deleting directory: ' . a:path)
  --     call v:lua.__error(v:exception)
  --     call v:lua.__error(v:throwpoint)
  --   endtry
  --   return
  -- endif

  -- Note: In Windows, ['rmdir', '/S', '/Q'] does not work.
  -- After Vim 8.0.928, double quote escape does not work in job.  Too bad.
  local cmdline = ' "' .. path .. '"'
  if _is_windows() then
    -- Note: In rm command, must use "\" instead of "/".
    cmdline = vim.fn.substitute(cmdline, '/', '\\\\', 'g')
  end

  local rm_command
  if _is_windows() then
    rm_command = 'cmd /C rmdir /S /Q'
  else
    rm_command = 'rm -rf'
  end
  cmdline = rm_command .. cmdline
  local result = vim.fn.system(cmdline)
  if vim.v.shell_error~=0 then
    _error(result)
  end

  -- Error check.
  if vim.fn.getftype(path) ~= '' then
    _error(string.format('"%s" cannot be removed.', path))
    _error(string.format('cmdline is "%s".', cmdline))
  end
end

function __install_blocking(context)
  try {
    function()
      while true do
        vim.fn['dein#install#__check_loop'](context)

        if vim.fn.empty(context.processes)==1 and context.number == context.max_plugins then
          break
        end
      end
    end
  }
  __done(context)

  return vim.fn.len(context.errored_plugins)
end
function __done(context)
  __restore_view(context)

  if vim.fn.has('vim_starting')==0 then
    __notify(__get_updated_message(context, context.synced_plugins))
    __notify(__get_errored_message(context.errored_plugins))
  end

  if context.update_type ~= 'check_update' then
    _recache_runtimepath()
  end

  if vim.fn.empty(context.synced_plugins)==0 then
    vim.fn['dein#call_hook']('done_update', context.synced_plugins)
    vim.fn['dein#source'](vim.tbl_map(function(v) return v.name end, vim.fn.copy(context.synced_plugins)))
  end

  __notify(vim.fn.strftime('Done: (%Y/%m/%d %H:%M:%S)'))

  -- Disable installation handler
  vim.g.__global_context = {}
  vim.g.__progress = ''
  vim.api.nvim_exec([[
    augroup dein-install
      autocmd!
    augroup END
  ]], false)
  if vim.fn.exists('g:__timer')==1 then
    vim.fn.timer_stop(vim.g.__timer)
    vim.g.__timer = nil
  end
end

function _each(cmd, plugins)
  local plugins = vim.tbl_filter(function(v) return vim.fn.isdirectory(v.path)==1 end, _get_plugins(plugins))

  local global_context_save = vim.g.__global_context

  local context = __init_context(plugins, 'each', 0)
  __init_variables(context)

  local cwd = vim.fn.getcwd()
  local error = 0
  try {
    function()
      for _, plugin in ipairs(plugins) do
        _cd(plugin.path)

        if vim.fn['dein#install#_execute'](cmd)~=0 then
          error = 1
        end
      end
    end,
    catch {
      function(e)
        __error(vim.v.exception .. ' ' .. vim.v.throwpoint)
        error = 1
        print('caught error: ' .. e)
      end
    }
  }

  vim.g.__global_context = global_context_save
  _cd(cwd)

  return error
end

function __helptags()
  if dein._runtime_path == '' or dein._is_sudo then
    return ''
  end

  try {
    function()
      local tags = _get_runtime_path() .. '/doc'
      if vim.fn.isdirectory(tags)==0 then
        vim.fn.mkdir(tags, 'p')
      end
      __copy_files(vim.tbl_filter(function(v) return v.merged==0 end, vim.tbl_values(dein.get())), 'doc')
      vim.api.nvim_command('silent execute "helptags" '..vim.fn.string(vim.fn.fnameescape(tags)))
    end,
    catch {
      function(error)
        -- catch /^Vim(helptags):E151:/
        -- Ignore an error that occurs when there is no help file
        __error('Error generating helptags:')
        __error(vim.v.exception)
        __error(vim.v.throwpoint)
        print('caught error: ' .. error)
      end
    }
  }
end
function __update_loop(context)
  local errored = 0
  try {
    function()
      if vim.fn.has('vim_starting')==1 then
        while vim.fn.empty(vim.g.__global_context)==0 do
          errored = vim.fn['dein#install#__install_async'](context)
          vim.api.nvim_command('sleep 50ms')
          vim.api.nvim_command('redraw')
        end
      else
        errored = __install_blocking(context)
      end
    end,
    catch {
      function(error)
        __error(vim.v.exception)
        __error(vim.v.throwpoint)
        print('caught error: ' .. error)
        errored = 1
      end
    }
  }
  return errored
end
function _build(plugins)
  local error = 0
  for _, plugin in ipairs(vim.tbl_filter(
    function(v)
      return vim.fn.isdirectory(v.path)==1 and vim.fn.has_key(v, 'build')==1
    end,
    _get_plugins(plugins))) do
    __print_progress_message('Building: ' .. plugin.name)
    if _each(plugin.build, plugin)==1 then
      error = 1
    end
  end
  return error
end
function __generate_ftplugin()
  -- Create after/ftplugin
  local after = _get_runtime_path() .. '/after/ftplugin'
  if vim.fn.isdirectory(after)==0 then
    vim.fn.mkdir(after, 'p')
  end

  -- Merge dein._ftplugin
  local ftplugin = {}
  for key, string in pairs(dein._ftplugin) do
    local fts = {'_'}
    if key ~= '_' then
      fts = vim.fn.split(key, '_')
    end
    for _, ft in ipairs(fts) do
      if not ftplugin.ft then
        if ft == '_' then
          ftplugin[ft] = {}
        else
          ftplugin[ft] = {
               "if exists('b:undo_ftplugin')",
               "  let b:undo_ftplugin .= '|'",
               'else',
               "  let b:undo_ftplugin = ''",
               'endif',
             }
        end
      end
      for _,v in ipairs(vim.fn.split(string, '\n')) do table.insert(ftplugin[ft], v) end
    end
  end

  -- Generate ftplugin.vim
  local content = _get_default_ftplugin()
  table.insert(content, 'function! s:after_ftplugin()')
  for _,v in ipairs(ftplugin['_'] or {}) do table.insert(content, v) end
  table.insert(content, 'endfunction')
  vim.fn.writefile(content, _get_runtime_path() .. '/ftplugin.vim')

  -- Generate after/ftplugin
  for filetype, list in pairs(ftplugin) do
    if filetype ~= '_' then
      vim.fn.writefile(list, string.format('%s/%s.vim', after, filetype))
    end
  end
end
function _direct_install(repo, options)
  local opts = vim.fn.copy(options)
  opts.merged = 0

  local plugin = vim.fn['dein#add'](repo, opts)
  if vim.fn.empty(plugin)==1 then
    return
  end

  _update(plugin.name, 'install', 0)
  vim.fn['dein#source'](plugin.name)

  -- Add to direct_install.vim
  local file = vim.fn['dein#get_direct_plugins_path']()
  local line = vim.fn.printf('call dein#add(%s, %s)', vim.fn.string(repo), vim.fn.string(opts))
  if vim.fn.filereadable(file)==0 then
    vim.fn.writefile({line}, file)
  else
    vim.fn.writefile(vim.fn.add(vim.fn.readfile(file), line), file)
  end
end

function __copy_files(plugins, directory)
  local dir = ''
  if directory ~= '' then
    dir = '/' .. directory
  end
  local srcs = vim.tbl_filter(
    function(v) return vim.fn.isdirectory(v)==1 end,
    vim.tbl_map(function(v) return v.rtp .. dir end, vim.fn.copy(plugins)))
  local stride = 50
  for start=1, vim.fn.len(srcs), stride do
    _copy_directories(slice(srcs, start, start+stride-1), _get_runtime_path() .. dir)
  end
end
function _copy_directories(srcs, dest)
  if vim.fn.empty(srcs)==1 then
    return 0
  end

  local status = 0
  local result
  if _is_windows() then
    if vim.fn.executable('robocopy')==0 then
      _error('robocopy command is needed.')
      return 1
    end

    local temp = vim.fn.tempname() .. '.bat'
    local exclude = vim.fn.tempname()

    -- TODO try finally
    local lines = {'@echo off'}
    local format = 'robocopy.exe %s /E /NJH /NJS /NDL /NC /NS /MT /XO /XD ".git"'
    for _, src in ipairs(srcs) do
      table.insert(lines, string.format(format, vim.fn.substitute(string.format('"%s" "%s"', src, dest), '/', '\\', 'g')))
    end
    vim.fn.writefile(lines, temp)
    result = vim.fn['dein#install#_system'](temp)
    vim.fn.delete(temp)

    -- For some baffling reason robocopy almost always returns between 1 and 3
    -- upon success
    status = vim.fn['dein#install#_status']()
    if status <= 3 then
      status = 0
    end

    if status~=0 then
      _error('copy command failed.')
      _error(vim.fn['dein#install#__iconv'](result, 'char', vim.o.encoding))
      _error('cmdline: ' .. temp)
      _error('tempfile: ' .. vim.fn.string(lines))
    end
  else -- Not Windows
    local srcs = vim.tbl_map(
      function(v)
        return vim.fn.shellescape(v .. '/')
      end,
      vim.tbl_filter(
        function(v)
          return vim.fn.len(__list_directory(v))>0
        end,
        vim.fn.copy(srcs)
      )
    )
    local is_rsync = vim.fn.executable('rsync')==1
    local cmdline
    if is_rsync then
      cmdline = string.format("rsync -a -q --exclude '/.git/' %s %s", vim.fn.join(srcs), vim.fn.shellescape(dest))
      result = vim.fn['dein#install#_system'](cmdline)
      status = vim.fn['dein#install#_status']()
    else
      for _, src in ipairs(srcs) do
        cmdline = string.format('cp -Ra %s* %s', src, vim.fn.shellescape(dest))
        result = vim.fn['dein#install#_system'](cmdline)
        status = vim.fn['dein#install#_status']()
        if status~=0 then
          break
        end
      end
    end
    if status~=0 then
      _error('copy command failed.')
      _error(result)
      _error('cmdline: ' .. cmdline)
    end
  end

  return status
end
function __list_directory(directory)
  return _globlist(directory .. '/*')
end
function __get_rollback_directory()
  local parent = string.format('%s/rollbacks/%s', _get_cache_path(), dein._progname)
  if vim.fn.isdirectory(parent)==0 then
    vim.fn.mkdir(parent, 'p')
  end
  return parent
end
function __get_errored_message(plugins)
  if vim.fn.empty(plugins)==1 then
    return ''
  end

  local msg = "Error installing plugins:\n"..vim.fn.join(vim.tbl_map(function(v) return '  ' .. v.name end, vim.fn.copy(plugins)), "\n")
  msg = msg.."\n"
  msg = msg.."Please read the error message log with the :message command.\n"

  return msg
end

function _reinstall(plugins)
  local plugins = _get_plugins(plugins)

  for _, plugin in ipairs(plugins) do
    repeat
      -- Remove the plugin
      if plugin.type == 'none' or (plugin['local'] or 0)==1 or (plugin.sourced==1 and vim.fn.index({'dein'}, plugin.normalized_name) >= 0) then
        _error(vim.fn.printf('|%s| Cannot reinstall the plugin!', plugin.name))
        break
      end

      -- Reinstall.
      __print_progress_message(vim.fn.printf('|%s| Reinstalling...', plugin.name))

      if vim.fn.isdirectory(plugin.path)==1 then
        _rm(plugin.path)
      end
    until true
  end

  _update(_convert2list(plugins), 'install', 0)
end
function __start()
  __notify(vim.fn.strftime('Update started: (%Y/%m/%d %H:%M:%S)'))
end
function __get_progress_message(plugin, number, max)
  -- FIXME 去掉math.modf外的圆括号会报错 E118: Too many arguments for function: repeat
  return vim.fn.printf('(%'..vim.fn.len(max)..'d/%'..vim.fn.len(max)..'d) [%s%s] %s',
         number, max,
         vim.fn['repeat']('+', (math.modf(number*20/max))),
         vim.fn['repeat']('-', (20 - math.modf(number*20/max))),
         plugin.name)
end
function __get_plugin_message(plugin, number, max, message)
  return vim.fn.printf('(%'..vim.fn.len(max)..'d/%d) |%-20s| %s',
         number, max, plugin.name, message)
end
function __get_short_message(plugin, number, max, message)
  return vim.fn.printf('(%'..vim.fn.len(max)..'d/%d) %s', number, max, message)
end

function __get_updated_message(context, plugins)
  if vim.fn.empty(plugins)==1 then
    return ''
  end
  function t(v)
    local changes = ''
    if v.commit_count==1 then
      changes = '(1 change)'
    else
      changes = string.format('(%d changes)', v.commit_count)
    end
    local updated = ''
    if context.update_type ~= 'check_update' and v.old_rev ~= '' and v.uri:find('^%a%w*://github.com/') then
      updated = "\n" .. string.format('    %s/compare/%s...%s',
        vim.fn.substitute(vim.fn.substitute(v.uri, [[\.git$]], '', ''), [[^\h\w*:]], 'https:', ''), v.old_rev, v.new_rev)
    end
    return '  ' .. v.name .. changes .. updated
  end

  return "Updated plugins:\n" .. vim.fn.join(vim.tbl_map(t, vim.fn.copy(plugins)), "\n")
end
function __init_variables(context)
  vim.g.__progress = ''
  vim.g.__global_context = context
  vim.g.__log = {}
  vim.g.__updates_log = {}
end
function __restore_view(context)
  if context.progress_type == 'tabline' then
    vim.o.showtabline = context.showtabline
    vim.o.tabline = context.tabline
  elseif context.progress_type == 'title' then
    vim.o.title = context.title
    vim.o.titlestring = context.titlestring
  end
end
function __init_context(plugins, update_type, async)
  local context = {}
  context.update_type = update_type
  context.async = async
  context.synced_plugins = {}
  context.errored_plugins = {}
  context.processes = {}
  context.number = 0
  context.prev_number = -1
  context.plugins = plugins
  context.max_plugins = vim.fn.len(context.plugins)
  if vim.fn.has('vim_starting')==1 and vim.g['dein#install_progress_type'] ~= 'none' then
    context.progress_type = 'echo'
  else
    context.progress_type = vim.g['dein#install_progress_type']
  end
  if vim.fn.has('vim_starting')==1 and vim.g['dein#install_message_type'] ~= 'none' then
    context.message_type = 'echo'
  else
    context.message_type = vim.g['dein#install_message_type']
  end
  context.laststatus = vim.o.laststatus
  context.showtabline = vim.o.showtabline
  context.tabline = vim.o.tabline
  context.title = vim.o.title
  context.titlestring = vim.o.titlestring
  return context
end

function __print_progress_message(msg)
  local msg = _convert2list(msg)
  local context = vim.g.__global_context
  if vim.fn.empty(msg)==1 or vim.fn.empty(context)==1 then
    return
  end

  local progress_type = context.progress_type
  if progress_type == 'tabline' then
    vim.o.showtabline=2
    vim.o.tabline = vim.fn.join(msg, "\n")
  elseif progress_type == 'title' then
    vim.o.title=true
    vim.o.titlestring = vim.fn.join(msg, "\n")
  elseif progress_type == 'echo' then
    __echo(msg, 'echo')
  end

  __log(msg)

  vim.g.__progress = vim.fn.join(msg, "\n")
end

function __error(msg)
  local msg = _convert2list(msg)
  if vim.fn.empty(msg)==1 then
    return
  end

  __echo(msg, 'error')
  __updates_log(msg)
end

function __echo(expr, mode)
  local msg = vim.tbl_map(
    function(v)
      return '[dein] ' ..  v
    end,
    vim.tbl_filter(function(v) return v~='' end, _convert2list(expr)))
  if vim.fn.empty(msg)==1 then
    return
  end

  local more_save = vim.o.more
  local showcmd_save = vim.o.showcmd
  local ruler_save = vim.o.ruler
  vim.o.more = false
  vim.o.showcmd = false
  vim.o.ruler = false

  local height = math.max(1, vim.o.cmdheight)
  vim.api.nvim_command("echo ''")
  for i=1,vim.fn.len(msg),height do
    vim.api.nvim_command("redraw")

    local m = vim.fn.join(slice(msg, i, i+height-1), "\n")
    __echo_mode(m, mode)
    if vim.fn.has('vim_starting')==1 then
      vim.api.nvim_command("echo ''")
    end
  end

  vim.o.more = more_save
  vim.o.showcmd = showcmd_save
  vim.o.ruler = ruler_save
end
function __notify(msg)
  local msg = _convert2list(msg)
  local context = vim.g.__global_context
  if vim.fn.empty(msg)==1 or vim.fn.empty(context)==1 then
    return
  end

  if context.message_type == 'echo' then
    _notify(msg)
  end

  __updates_log(msg)
  vim.g.__progress = vim.fn.join(msg, "\n")
end

function __updates_log(msg)
  local msg = _convert2list(msg)

  table.insert(vim.g['__updates_log'], msg)
  __log(msg)
end

function __log(msg)
  local msg = _convert2list(msg)
  table.insert(vim.g['__log'], msg)
  append_log_file(msg)
end

function __echo_mode(m, mode)
  for _, m in ipairs(vim.fn.split(m, [[\r\?\n]], 1)) do
    if vim.fn.has('vim_starting')==0 and mode~='error' then
      m = __truncate_skipping(m, vim.o.columns - 1, vim.o.columns/3, '...')
    end

    if mode == 'error' then
      vim.api.nvim_command(string.format("echohl WarningMsg | echomsg %s | echohl None", vim.fn.string(m)))
    elseif mode == 'echomsg' then
      vim.api.nvim_command(string.format("echomsg %s", vim.fn.string(m)))
    else
      vim.api.nvim_command(string.format("echo %s", vim.fn.string(m)))
    end
  end
end

function __truncate_skipping(str, max, footer_width, separator)
  local width = vim.fn.strwidth(str)
  local ret
  if width <= max then
    ret = str
  else
    local header_width = max - vim.fn.strwidth(separator) - footer_width
    ret = __strwidthpart(str, header_width) .. separator
           .. __strwidthpart_reverse(str, footer_width)
  end

  return ret
end

-- TODO local
function __strwidthpart(str, width)
  if width <= 0 then
    return ''
  end
  local ret = str
  local w = vim.fn.strwidth(str)
  while w > width do
    local char = vim.fn.matchstr(ret, '.$')
    ret = ret:sub(1, vim.fn.len(ret)-vim.fn.len(char))
    w = w - vim.fn.strwidth(char)
  end

  return ret
end
-- TODO local
function __strwidthpart_reverse(str, width)
  if width <= 0 then
    return ''
  end
  local ret = str
  local w = vim.fn.strwidth(str)
  while w > width do
    local char = vim.fn.matchstr(ret, '^.')
    ret = ret:sub(vim.fn.len(char)+1)
    w = w - vim.fn.strwidth(char)
  end

  return ret
end
function _recache_runtimepath()
  if dein._is_sudo then
    return
  end

  -- Clear runtime path.
  clear_runtimepath()

  local plugins = vim.tbl_values(dein.get())

  local merged_plugins = vim.tbl_filter(function(v) return v.merged==1 end, vim.fn.copy(plugins))

  __copy_files(vim.tbl_filter(function(v) return v.lazy~=0 end, vim.fn.copy(merged_plugins)), '')
  -- Remove plugin directory
  _rm(_get_runtime_path() .. '/plugin')
  _rm(_get_runtime_path() .. '/after/plugin')

  __copy_files(vim.tbl_filter(function(v) return v.lazy==0 end, vim.fn.copy(merged_plugins)), '')

  __helptags()

  __generate_ftplugin()

  -- Clear ftdetect and after/ftdetect directories.
  _rm(_get_runtime_path()..'/ftdetect')
  _rm(_get_runtime_path()..'/after/ftdetect')

  merge_files(plugins, 'ftdetect')
  merge_files(plugins, 'after/ftdetect')

  vim.api.nvim_command('silent call dein#remote_plugins()')

  vim.fn['dein#call_hook']('post_source')

  _save_merged_plugins()

  vim.fn['dein#install#_save_rollback'](__get_rollback_directory() .. '/' .. vim.fn.strftime('%Y%m%d%H%M%S'), {})

  _clear_state()

  __log(vim.fn.strftime('Runtimepath updated: (%Y/%m/%d %H:%M:%S)'))
end
function __get_sync_command(plugin, update_type, number, max)
  local type = vim.fn['dein#util#_get_type'](plugin.type)
  local cmd

  -- TODO has_key(type, 'get_fetch_remote_command')
  if update_type == 'check_update' and type.name == 'git' then
    cmd = get_fetch_remote_command(type, plugin)
  elseif type.name == 'git' then  -- TODO has_key(type, 'get_sync_command')
    cmd = get_sync_command(type, plugin)
  else
    return {'', ''}
  end

  if vim.fn.empty(cmd)==1 then
    return {'', ''}
  end

  local message = __get_plugin_message(plugin, number, max, vim.fn.string(cmd))

  return {cmd, message}
end
function _update(plugins, update_type, async)
  if dein._is_sudo then
    __error('update/install is disabled in sudo session.')
    return
  end

  local plugins = _get_plugins(plugins)

  if update_type == 'install' then
    plugins = vim.tbl_filter(function(v) return vim.fn.isdirectory(v.path)==0 end, plugins)
  elseif update_type == 'check_update' then
    plugins = vim.tbl_filter(function(v) return vim.fn.isdirectory(v.path)==1 end, plugins)
  end

  if async==1 and vim.fn.empty(vim.g.__global_context)==0
    and vim.fn.confirm('The installation has not finished. Cancel now?', "yes\nNo", 2) ~= 1 then
    return
  end

  -- Set context.
  local context = __init_context(plugins, update_type, async)

  __init_variables(context)

  if vim.fn.empty(plugins)==1 then
    if update_type ~= 'check_update' then
      __notify('Target plugins are not found.')
      __notify('You may have used the wrong plugin name, or all of the plugins are already installed.')
    end
    vim.g.__global_context = {}
    return
  end

  __start()

  if async==0 or vim.fn.has('vim_starting')==1 then
    return __update_loop(context)
  end

  vim.api.nvim_exec([[
    augroup dein-install
      autocmd!
    augroup END
  ]], false)

  if vim.fn.exists('g:__timer')==1 then
    vim.fn.timer_stop(vim.g.__timer)
    vim.g.__timer=nil
  end

  vim.g.__timer = vim.fn.timer_start(1000, 'dein#install#_timer_handler', {['repeat']=-1})
end
