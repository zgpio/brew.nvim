-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local util = require 'dein/util'
local Job = require 'dein/job'
local isdir = vim.fn.isdirectory
local brew = dein
local M = {}

-- Global options definition.
brew.install_max_processes = brew.install_max_processes or 8
brew.install_progress_type = brew.install_progress_type or 'echo'
brew.install_message_type = brew.install_message_type or 'echo'
brew.install_process_timeout = brew.install_process_timeout or 120
brew.install_log_filename = brew.install_log_filename or ''
brew.install_github_api_token = brew.install_github_api_token or ''
brew.install_curl_command = brew.install_curl_command or 'curl'

-- Variables
local __global_context = {}
local var_log = {}
local var_updates_log = {}
local __progress = ''
local __timer

local function init_variables(context)
  __progress = ''
  __global_context = context
  var_log = {}
  var_updates_log = {}
end
local function iconv(expr, from, to)
  if from == '' or to == '' or string.lower(from) == string.lower(to) then
    return expr
  end

  if vim.tbl_islist(expr) then
    return vim.tbl_map(function(v) return vim.fn.iconv(v, from, to) end, vim.fn.copy(expr))
  else
    local result = vim.fn.iconv(expr, from, to)
    if result ~= '' then
      return result
    else
      return expr
    end
  end
end
local function init_context(plugins, update_type, async)
  local ctx = {}
  ctx.update_type = update_type
  ctx.async = async
  ctx.synced_plugins = {}
  ctx.errored_plugins = {}
  ctx.processes = {}
  ctx.number = 0
  ctx.prev_number = -1
  ctx.plugins = plugins
  ctx.max_plugins = vim.fn.len(ctx.plugins)
  if vim.fn.has('vim_starting')==1 and brew.install_progress_type ~= 'none' then
    ctx.progress_type = 'echo'
  else
    ctx.progress_type = brew.install_progress_type
  end
  if vim.fn.has('vim_starting')==1 and brew.install_message_type ~= 'none' then
    ctx.message_type = 'echo'
  else
    ctx.message_type = brew.install_message_type
  end
  ctx.laststatus = vim.o.laststatus
  ctx.showtabline = vim.o.showtabline
  ctx.tabline = vim.o.tabline
  ctx.title = vim.o.title
  ctx.titlestring = vim.o.titlestring
  return ctx
end
local function _status()
  return vim.v.shell_error
end
function M.is_async()
  return brew.install_max_processes > 1
end
-- FIXME: The logic is different from the `:h jobstart`
local function __convert_args(args)
  args = iconv(args, vim.o.encoding, 'char')
  if not vim.tbl_islist(args) then
    local rv = vim.api.nvim_eval('split(&shell) + split(&shellcmdflag)')
    table.insert(rv, args)
    args = rv
  end
  return args
end
local function append_log_file(msg)
  local fn = brew.install_log_filename
  if not fn or fn=='' then
    return
  end
  local logfile = util.expand(fn)

  -- Appends to log file.
  if vim.fn.filereadable(logfile)==1 then
    vim.fn.writefile(msg, logfile, 'a')
    return
  end

  local dir = vim.fn.fnamemodify(logfile, ':h')
  if isdir(dir)==0 then
    vim.fn.mkdir(dir, 'p')
  end
  vim.fn.writefile(msg, logfile)
end
local function log(msg)
  msg = util.convert2list(msg)
  table.insert(var_log, msg)
  append_log_file(msg)
end
local function _updates_log(msg)
  msg = util.convert2list(msg)

  table.insert(var_updates_log, msg)
  log(msg)
end

local function ERROR(msg)
  msg = util.convert2list(msg)
  if vim.fn.empty(msg)==1 then
    return
  end

  __echo(msg, 'error')
  _updates_log(msg)
end

function _system(command)
  -- Todo: use job API instead
  -- local job = Job:start()
  -- local exitval = job:wait()

  command = iconv(command, vim.o.encoding, 'char')
  local output = iconv(vim.fn.system(command), 'char', vim.o.encoding)
  return vim.fn.substitute(output, '\n$', '', '')
end
local function __get_rollback_directory()
  local parent = string.format('%s/rollbacks/%s', util.get_cache_path(), brew._progname)
  if isdir(parent)==0 then
    vim.fn.mkdir(parent, 'p')
  end
  return parent
end
function _rollback(date, plugins)
  local glob = __get_rollback_directory() .. '/' .. date .. '*'
  local rollbacks = vim.fn.reverse(vim.fn.sort(util.globlist(glob)))
  if vim.fn.empty(rollbacks)==1 then
    return
  end

  M.load_rollback(rollbacks[1], plugins)
end
local function check_rollback(plugin)
  return plugin['local']==nil and (plugin.frozen or 0)==0
end
local function get_revision_number(plugin)
  if isdir(plugin.path)==0 then
    return ''
  end

  local type = _get_type(plugin.type)
  if type.get_revision_number ~= nil then
    return type:get_revision_number(plugin)
  end
  if type.get_revision_number_command == nil then
    return ''
  end

  local cmd = type:get_revision_number_command(plugin)
  if vim.fn.empty(cmd)==1 then
    return ''
  end

  local rev = M.system_cd(cmd, plugin.path)

  -- If rev contains spaces, it is error message
  if rev:find('%s') then
    ERROR(plugin.name)
    ERROR('Error revision number: ' .. rev)
    return ''
  elseif rev == '' then
    ERROR(plugin.name)
    ERROR('Empty revision number: ' .. rev)
    return ''
  end
  return rev
end
function _save_rollback(rollbackfile, plugins)
  local revisions = {}
  for _, plugin in ipairs(vim.fn.filter(check_rollback, util.get_plugins(plugins))) do
    local rev = get_revision_number(plugin)
    if rev ~= '' then
      revisions[plugin.name] = rev
    end
  end

  vim.fn.writefile({vim.fn.json_encode(revisions)}, vim.fn.expand(rollbackfile))
end
function M.load_rollback(rollbackfile, plugins)
  local revisions = vim.fn.json_decode(vim.fn.readfile(rollbackfile)[1])

  plugins = util.get_plugins(plugins)
  -- TODO has_key(v:lua._get_type(v:val.type), 'get_rollback_command')
  plugins = vim.tbl_filter(
    function(v)
      return revisions[v.name]~=nil
        and _get_type(v.type).name == 'git'
        and check_rollback(v)
        and get_revision_number(v) ~= revisions[v.name]
    end,
    plugins)
  if vim.fn.empty(plugins)==1 then
    return
  end

  for _, plugin in ipairs(plugins) do
    local typ = _get_type(plugin.type)
    local cmd = typ:get_rollback_command(_get_type(plugin.type), revisions[plugin.name])
    _each(cmd, {plugin})
  end

  M.recache_runtimepath()
  ERROR('Rollback to '..vim.fn.fnamemodify(rollbackfile, ':t')..' version.')
end
local function merge_files(plugins, directory)
  local files = {}
  for _, plugin in ipairs(plugins) do
    local t = vim.tbl_filter(
      function(v) return isdir(v)==0 end,
      vim.fn.globpath(plugin.rtp, directory..'/**', 1, 1)
    )
    for _, file in ipairs(t) do
      vim.list_extend(files, vim.fn.readfile(file, ':t'))
    end
  end

  if not vim.tbl_isempty(files) then
    util.writefile(string.format('.dein/%s/%s.vim', directory, directory), files)
  end
end
local function get_default_ftplugin()
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

local function get_updated_log_message(plugin, new_rev, old_rev)
  local type = _get_type(plugin.type)

  -- TODO has_key(type, 'get_log_command')
  local cmd = ''
  if type.name == 'git' then
    cmd = type:get_log_command(plugin, new_rev, old_rev)
  end
  local msg = ''
  if vim.fn.empty(cmd)==0 then
    msg = M.system_cd(cmd, plugin.path)
  end
  if msg ~= '' then
    return msg
  else
    if old_rev == new_rev then
      return ''
    else
      return old_rev..' -> '..new_rev
    end
  end
end

function M.system_cd(command, path)
  local cwd = vim.fn.getcwd()
  local rv = ''
  try {
    function()
      _cd(path)
      rv = _system(command)
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
  if isdir(path)==0 then
    return
  end

  try {
    function()
      local d = (vim.fn.haslocaldir()==1) and 'lcd' or 'cd'
      vim.api.nvim_command('noautocmd execute '..vim.fn.string(d..' '..vim.fn.fnameescape(path)))
    end,
    catch {
      function(e)
        ERROR('Error cd to: ' .. path)
        ERROR('Current directory: ' .. vim.fn.getcwd())
        ERROR(vim.v.exception)
        ERROR(vim.v.throwpoint)
        print('caught error: ' .. e)
      end
    }
  }
end
local function _rm(path)
  if isdir(path)==0 and vim.fn.filereadable(path)==0 then
    return
  end

  -- Note: delete rf is broken before Vim 8.1.1378
  if vim.fn.has('patch-8.1.1378')==1 then
    try {
      function()
        vim.fn.delete(path, 'rf')
      end,
      catch {
        function(e)
          ERROR('Error deleting directory: ' .. path)
          ERROR(vim.v.exception)
          ERROR(vim.v.throwpoint)
        end
      }
    }
    return
  end

  -- Note: In Windows, ['rmdir', '/S', '/Q'] does not work.
  -- After Vim 8.0.928, double quote escape does not work in job.  Too bad.
  local cmdline = ' "' .. path .. '"'
  if util.is_windows() then
    -- Note: In rm command, must use "\" instead of "/".
    cmdline = vim.fn.substitute(cmdline, '/', '\\\\', 'g')
  end

  local rm_command = util.is_windows() and 'cmd /C rmdir /S /Q' or 'rm -rf'
  cmdline = rm_command .. cmdline
  local result = vim.fn.system(cmdline)
  if vim.v.shell_error~=0 then
    util._error(result)
  end

  -- Error check.
  if vim.fn.getftype(path) ~= '' then
    util._error(string.format('"%s" cannot be removed.', path))
    util._error(string.format('cmdline is "%s".', cmdline))
  end
end

local function get_plugin_message(plugin, number, max, message)
  return vim.fn.printf('(%'..vim.fn.len(max)..'d/%d) |%-20s| %s',
         number, max, plugin.name, message)
end

local function lock_revision(process)
  local num = process.number
  local max = process.max_plugins
  local plugin = process.plugin

  local typ = _get_type(plugin['type'])
  -- TODO !has_key(type, 'get_revision_lock_command')
  if typ.name ~= 'git' then
    return 0
  end

  local cmd = typ:get_revision_lock_command(plugin)

  if vim.fn.empty(cmd)==1 then
    -- Skipped.
    return 0
  elseif type(cmd) == 'string' and cmd:find('^E: ') then
    -- Errored.
    ERROR(plugin.path)
    ERROR(cmd:sub(4))
    return -1
  end

  if (plugin.rev or '') ~= '' then
    log(get_plugin_message(plugin, num, max, 'Locked'))
  end

  local result = M.system_cd(cmd, plugin.path)
  local status = _status()

  if status~=0 then
    ERROR(plugin.path)
    ERROR(result)
    return -1
  end
end
local function _get_short_message(plugin, number, max, message)
  return vim.fn.printf('(%'..vim.fn.len(max)..'d/%d) %s', number, max, message)
end
local RUNNING = -1
local function async_get(process)
  local async = process.async
  -- Check job status
  local status = RUNNING
  if process.job.__exitval then
    async.eof = 1
    status = process.job.__exitval
  end

  local candidates = process.job.candidates or {}
  local output
  if async.eof==1 then
    output = vim.fn.join(candidates, "\n")
  else
    output = vim.fn.join(slice(candidates, 1, #candidates-1), "\n")
  end
  if output ~= '' then
    process.output = output
    process.start_time = vim.fn.localtime()
    log(_get_short_message(process.plugin, process.number,
          process.max_plugins, output))
  end
  async.candidates = (async.eof==1) and {} or {candidates[#candidates]}

  local is_timeout = (vim.fn.localtime() - process.start_time)
                     >= (process.plugin.timeout or brew.install_process_timeout)

  local is_skip = true
  if async.eof==1 then
    is_timeout = false
    is_skip = false
  end

  if is_timeout then
    process.job:stop()
    status = RUNNING
  end

  return is_timeout, is_skip, status
end
local function call_post_update_hooks(plugins)
    local cwd = vim.fn.getcwd()
    try {
      function()
        -- Reload plugins to execute hooks
        vim.api.nvim_command('runtime! plugin/*.vim')
        for _, plugin in ipairs(plugins) do
          _cd(plugin.path)
          util.call_hook('post_update', {plugin})
        end
      end,
      catch {
        function(e)
          print('caught error: ' .. e)
        end
      }
    }
    _cd(cwd)
end


local function check_output(context, process)
  local is_timeout, is_skip, status
  if context.async then
    is_timeout, is_skip, status = async_get(process)
  else
    is_timeout, is_skip, status = false, false, process.status
  end

  if is_skip and not is_timeout then
    return
  end

  local num = process.number
  local max = process.max_plugins
  local plugin = process.plugin

  if isdir(plugin.path)==1
         and (plugin.rev or '') ~= ''
         and (plugin['local'] or 0)==0 then
    -- Restore revision.
    lock_revision(process)
  end

  local new_rev = get_revision_number(plugin)

  if is_timeout or status==1 then
    log(get_plugin_message(plugin, num, max, 'Error'))
    ERROR(plugin.path)
    if process.installed==0 then
      if isdir(plugin.path)==0 then
        ERROR('Maybe wrong username or repository.')
      elseif isdir(plugin.path)==1 then
        ERROR('Remove the installed directory:' .. plugin.path)
        _rm(plugin.path)
      end
    end

    if is_timeout then
      ERROR(vim.fn.strftime('Process timeout: (%Y/%m/%d %H:%M:%S)'))
    else
      ERROR(vim.split(process.output, '\n'))
    end

    table.insert(context.errored_plugins, plugin)
  elseif process.rev == new_rev then
    log(get_plugin_message(plugin, num, max, 'Same revision'))
  else
    log(get_plugin_message(plugin, num, max, 'Updated'))

    local log_messages = vim.fn.split(get_updated_log_message(plugin, new_rev, process.rev), '\n')
    plugin.commit_count = vim.fn.len(log_messages)
    log(vim.tbl_map(function(v) return _get_short_message(plugin, num, max, v) end, log_messages))

    plugin.old_rev = process.rev
    plugin.new_rev = new_rev

    local type = _get_type(plugin.type)
    -- TODO has_key(type, 'get_uri')
    if type.name == 'git' then
      plugin.uri = type:get_uri(plugin.repo, plugin)
    else
      plugin.uri = ''
    end

    if _build({plugin.name})~=0 then
      log(get_plugin_message(plugin, num, max, 'Build failed'))
      ERROR(plugin.path)
      -- Remove.
      table.insert(context.errored_plugins, plugin)
    else
      table.insert(context.synced_plugins, plugin)
    end
  end

  process.eof = 1
end
local function print_progress_message(msg)
  msg = util.convert2list(msg)
  local context = __global_context
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

  log(msg)

  __progress = vim.fn.join(msg, "\n")
end

local function get_progress_message(name, number, max)
  return vim.fn.printf('(%'..vim.fn.len(max)..'d/%'..vim.fn.len(max)..'d) [%s%s] %s',
         number, max,
         vim.fn['repeat']('+', (math.modf(number*20/max))),
         vim.fn['repeat']('-', (20 - math.modf(number*20/max))),
         name)
end
local function check_loop(context)
  while context.number < context.max_plugins
         and vim.fn.len(context.processes) < brew.install_max_processes do

    local plugin = context.plugins[context.number+1]
    __sync(plugin, context)

    if context.async==false then
      print_progress_message(
             get_progress_message(plugin.name,
               context.number, context.max_plugins))
    end
  end

  -- 检查每个处理进程是否完成
  --for _, process in pairs(context.processes) do
  --  check_output(context, process)
  --end

  -- Filter eof processes.
  context.processes = vim.tbl_filter(function(v) return v.eof==0 end, context.processes)
  return context
end

local function clear_runtimepath()
  if util.get_cache_path() == '' then
    util._error('Invalid base path.')
    return
  end

  local runtimepath = util.get_runtime_path()

  -- Remove runtime path
  _rm(runtimepath)

  if isdir(runtimepath)==0 then
    -- Create runtime path
    vim.fn.mkdir(runtimepath, 'p')
  end
end
local function install_blocking(context)
  try {
    function()
      while true do
        check_loop(context)

        if vim.fn.empty(context.processes)==1 and context.number == context.max_plugins then
          break
        end
        -- FIXME
        assert(false)
      end
    end,
    catch {
      function(e)
        print('caught error: ' .. e)
      end
    }
  }
  __done(context)

  return vim.fn.len(context.errored_plugins)
end
local function get_errored_message(plugins)
  if vim.tbl_isempty(plugins) then
    return ''
  end

  local msg = "Error installing plugins:\n"..vim.fn.join(vim.tbl_map(function(v) return '  ' .. v.name end, vim.fn.copy(plugins)), "\n")
  msg = msg.."\n"
  msg = msg.."Please read the error message log with the :message command.\n"

  return msg
end

local function restore_view(context)
  if context.progress_type == 'tabline' then
    vim.o.showtabline = context.showtabline
    vim.o.tabline = context.tabline
  elseif context.progress_type == 'title' then
    vim.o.title = context.title
    vim.o.titlestring = context.titlestring
  end
end
local function get_updated_message(context, plugins)
  if vim.fn.empty(plugins)==1 then
    return ''
  end
  local function t(v)
    local changes = ''
    if v.commit_count==1 then
      changes = '(1 change)'
    else
      changes = string.format('(%d changes)', v.commit_count)
    end
    local updated = ''
    if v.old_rev ~= '' and v.uri:find('^%a%w*://github.com/') then
      updated = "\n" .. string.format('    %s/compare/%s...%s',
        vim.fn.substitute(vim.fn.substitute(v.uri, [[\.git$]], '', ''), [[^\h\w*:]], 'https:', ''), v.old_rev, v.new_rev)
    end
    return '  ' .. v.name .. changes .. updated
  end

  return "Updated plugins:\n" .. vim.fn.join(vim.tbl_map(t, vim.fn.copy(plugins)), "\n")
end
function __done(context)
  restore_view(context)

  if vim.fn.has('vim_starting')==0 then
    __notify(get_updated_message(context, context.synced_plugins))
    __notify(get_errored_message(context.errored_plugins))
  end

  M.recache_runtimepath()

  if vim.fn.empty(context.synced_plugins)==0 then
    _source(vim.tbl_map(function(v) return v.name end, vim.fn.copy(context.synced_plugins)))

    -- Execute post_update hooks
    local post_update_plugins = vim.tbl_filter(function (v) return v.hook_post_update ~= nil end,
      vim.fn.copy(context.synced_plugins))
    if not vim.tbl_isempty(post_update_plugins) then
      call_post_update_hooks(post_update_plugins)
    end

    util.call_hook('done_update', {context.synced_plugins})
  end

  vim.api.nvim_command('redraw')
  vim.api.nvim_command('echo ""')

  __notify(vim.fn.strftime('Done: (%Y/%m/%d %H:%M:%S)'))

  -- Disable installation handler
  __global_context = {}
  __progress = ''
  vim.api.nvim_exec([[
    augroup dein-install
      autocmd!
    augroup END
  ]], false)
  if __timer then
    vim.fn.timer_stop(__timer)
    __timer = nil
  end
end

-- job_id -> job object
local job_execute = {}
local function job_execute_on_out(job_id, data, event)
  for _, line in ipairs(data) do
    print(line)
  end

  local candidates = job_execute[job_id].candidates
  if vim.tbl_isempty(candidates) then
    table.insert(candidates, data[1])
  else
    -- TODO How to access the last element of the list
    candidates[#candidates] = candidates[#candidates] .. data[1]
  end
  vim.list_extend(candidates, slice(data, 2))
end
function _execute(command)
  local job = Job:start(command, {on_init=function (obj) obj.candidates = {} end, on_stdout=job_execute_on_out,
    on_stderr=function (job_id, data, event)
      print('on_stderr:', job_id, vim.inspect(data), event)
    end
  })
  job_execute[job.id] = job
  return job:wait(brew.install_process_timeout * 1000)
end
-- plugins must be { plugin_tbl1, ... }
function _each(cmd, plugins)
  plugins = vim.tbl_filter(function(v) return isdir(v.path)==1 end, util.get_plugins(plugins))

  local global_context_save = __global_context

  local context = init_context(plugins, 'each', 0)
  init_variables(context)

  local cwd = vim.fn.getcwd()
  local error = 0
  try {
    function()
      for _, plugin in ipairs(plugins) do
        _cd(plugin.path)

        if _execute(cmd)~=0 then
          error = 1
        end
      end
    end,
    catch {
      function(e)
        ERROR(vim.v.exception .. ' ' .. vim.v.throwpoint)
        error = 1
        print('caught error: ' .. e)
      end
    }
  }

  __global_context = global_context_save
  _cd(cwd)

  return error
end

local function copy_files(plugins, directory)
  local dir = (directory == '') and '' or ('/' .. directory)
  local srcs = vim.tbl_filter(
    function(v) return isdir(v)==1 end,
    vim.tbl_map(function(v) return v.rtp .. dir end, vim.fn.copy(plugins)))
  local stride = 50
  for start=1, vim.fn.len(srcs), stride do
    M.copy_directories(slice(srcs, start, start+stride-1), util.get_runtime_path() .. dir)
  end
end
local function helptags()
  if brew._runtime_path == '' or brew._is_sudo then
    return ''
  end

  try {
    function()
      local tags = util.get_runtime_path() .. '/doc'
      if isdir(tags)==0 then
        vim.fn.mkdir(tags, 'p')
      end
      copy_files(vim.tbl_filter(function(v) return v.merged==0 end, vim.tbl_values(brew.get())), 'doc')
      vim.api.nvim_command('silent execute "helptags" '..vim.fn.string(vim.fn.fnameescape(tags)))
    end,
    catch {
      function(e)
        -- catch /^Vim(helptags):E151:/
        -- Ignore an error that occurs when there is no help file
        ERROR('Error generating helptags:')
        ERROR(vim.v.exception)
        ERROR(vim.v.throwpoint)
        print('caught error: ' .. e)
      end
    }
  }
end
local function install_async(ctx)
  if vim.fn.empty(ctx)==1 then
    return
  end

  check_loop(ctx)

  if vim.fn.empty(ctx.processes)==1 and ctx.number == ctx.max_plugins then
    __done(ctx)
  elseif ctx.number ~= ctx.prev_number and ctx.number < vim.fn.len(ctx.plugins) then
    local plugin = ctx.plugins[ctx.number+1]
    print_progress_message(get_progress_message(plugin.name, ctx.number, ctx.max_plugins))
    ctx.prev_number = ctx.number
  end

  return vim.fn.len(ctx.errored_plugins), ctx
end
local function update_loop(context)
  local errored = 0
  try {
    function()
      if vim.fn.has('vim_starting')==1 then
        while vim.fn.empty(__global_context)==0 do
          errored, _ = install_async(context)
          vim.api.nvim_command('sleep 50ms')
          vim.api.nvim_command('redraw')
        end
      else
        errored = install_blocking(context)
      end
    end,
    catch {
      function(e)
        ERROR(vim.v.exception)
        ERROR(vim.v.throwpoint)
        print('caught error: ' .. e)
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
      return isdir(v.path)==1 and v.build~=nil
    end,
    util.get_plugins(plugins))) do
    print_progress_message('Building: ' .. plugin.name)
    if _each(plugin.build, {plugin})==1 then
      error = 1
    end
  end
  return error
end
local function generate_ftplugin()
  -- Create after/ftplugin
  local after = util.get_runtime_path() .. '/after/ftplugin'
  if isdir(after)==0 then
    vim.fn.mkdir(after, 'p')
  end

  -- Merge brew._ftplugin
  local ftplugin = {}
  for key, string in pairs(brew._ftplugin) do
    local fts = (key == '_') and {'_'} or vim.split(key, '_')
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
      for _,v in ipairs(vim.split(string, '\n')) do table.insert(ftplugin[ft], v) end
    end
  end

  -- Generate ftplugin.vim
  local content = get_default_ftplugin()
  table.insert(content, 'function! s:after_ftplugin()')
  for _,v in ipairs(ftplugin['_'] or {}) do table.insert(content, v) end
  table.insert(content, 'endfunction')
  vim.fn.writefile(content, util.get_runtime_path() .. '/ftplugin.vim')

  -- Generate after/ftplugin
  for filetype, list in pairs(ftplugin) do
    if filetype ~= '_' then
      vim.fn.writefile(list, string.format('%s/%s.vim', after, filetype))
    end
  end
end
function M.direct_install(repo, options)
  local opts = vim.fn.copy(options)
  opts.merged = 0

  local plugin = _add(repo, opts)
  if vim.fn.empty(plugin)==1 then
    return
  end

  _update(plugin.name, 'install', 0)
  _source({plugin.name})

  -- Add to direct_install.vim
  local file = brew.get_direct_plugins_path()
  local line = vim.fn.printf('lua dein.add(%s, %s)', vim.fn.string(repo), vim.fn.string(opts))
  if vim.fn.filereadable(file)==0 then
    vim.fn.writefile({line}, file)
  else
    vim.fn.writefile(vim.fn.add(vim.fn.readfile(file), line), file)
  end
end

local function list_directory(directory)
  return util.globlist(directory .. '/*')
end
function M.copy_directories(srcs, dest)
  if vim.fn.empty(srcs)==1 then
    return 0
  end

  local status = 0
  local result
  if util.is_windows() then
    if vim.fn.executable('robocopy')==0 then
      util._error('robocopy command is needed.')
      return 1
    end

    local temp = vim.fn.tempname() .. '.bat'
    --local exclude = vim.fn.tempname()

    -- TODO try finally
    local lines = {'@echo off'}
    local format = 'robocopy.exe %s /E /NJH /NJS /NDL /NC /NS /MT /XO /XD ".git"'
    for _, src in ipairs(srcs) do
      table.insert(lines, string.format(format, vim.fn.substitute(string.format('"%s" "%s"', src, dest), '/', '\\', 'g')))
    end
    vim.fn.writefile(lines, temp)
    result = _system(temp)
    vim.fn.delete(temp)

    -- Robocopy returns between 0 and 7 upon success
    status = _status()
    if status <= 7 then
      status = 0
    end

    if status~=0 then
      util._error('copy command failed.')
      util._error(iconv(result, 'char', vim.o.encoding))
      util._error('cmdline: ' .. temp)
      util._error('tempfile: ' .. vim.fn.string(lines))
    end
  else -- Not Windows
    srcs = vim.tbl_map(
      function(v)
        return vim.fn.shellescape(v .. '/')
      end,
      vim.tbl_filter(
        function(v)
          return vim.fn.len(list_directory(v))>0
        end,
        vim.fn.copy(srcs)
      )
    )
    local is_rsync = vim.fn.executable('rsync')==1
    local cmdline
    if is_rsync then
      cmdline = string.format("rsync -a -q --exclude '/.git/' %s %s", vim.fn.join(srcs), vim.fn.shellescape(dest))
      result = _system(cmdline)
      status = _status()
    else
      for _, src in ipairs(srcs) do
        cmdline = string.format('cp -Ra %s* %s', src, vim.fn.shellescape(dest))
        result = _system(cmdline)
        status = _status()
        if status~=0 then
          break
        end
      end
    end
    if status~=0 then
      util._error('copy command failed.')
      util._error(result)
      util._error('cmdline: ' .. cmdline)
    end
  end

  return status
end

function job_check_update_on_out(job_id, data, event, candidates)
  if vim.tbl_isempty(candidates) then
    table.insert(candidates, data[1])
  else
    candidates[#candidates] = candidates[#candidates] .. data[1]
  end
  vim.list_extend(candidates, slice(data, 2))
end

local WIN_QUERY = [[a%d:repository(owner:\\""%s\\"", name:\\""%s\\""){ pushedAt nameWithOwner }]]
local LIN_QUERY = [[a%d:repository(owner:\"%s\", name:\"%s\"){ pushedAt nameWithOwner }]]
local QUERY = util.is_windows() and WIN_QUERY or LIN_QUERY
function _check_update(plugins, force, async)
  if brew.install_github_api_token == '' then
    ERROR('You need to set brew.install_github_api_token to check updated plugins.')
    return
  end
  if vim.fn.executable(brew.install_curl_command)==0 then
    ERROR('curl must be executable to check updated plugins.')
    return
  end

  __global_context.progress_type = 'echo'
  local query_max = 100
  plugins = util.get_plugins(plugins)
  local processes = {}
  for index = 1, #plugins, query_max do
    vim.api.nvim_command('redraw')
    print_progress_message(
      get_progress_message('', index, #plugins))

    local query = ''
    for plug_index = index,
        math.min(index + query_max, #plugins) do
      local plugin_names = vim.split(plugins[plug_index].repo, '/')
      local gitee = string.find(plugins[plug_index].repo, 'gitee')
      if not gitee and vim.fn.len(plugin_names) >= 2 then
        -- Invalid repository name when < 2.

        -- Note: "repository" API is faster than "search" API
        query = query .. vim.fn.printf(QUERY,
          plug_index, plugin_names[#plugin_names - 1], plugin_names[#plugin_names])
      end
    end

    local commands = {
      brew.install_curl_command, '-H', '"Authorization: bearer ' ..
      brew.install_github_api_token..'"',
      '-X', 'POST', '-d',
      '"{ ""query"": ""query {' .. query .. '}"" }"',
      'https://api.github.com/graphql'
    }
    commands = vim.fn.join(commands, ' ')

    local process = {candidates={}}
    local job = Job:start(commands, {
      on_stdout=function(job_id, data, event)
        job_check_update_on_out(job_id, data, event, process.candidates) end
      })
    process.job = job

    table.insert(processes, process)
  end

  -- Get outputs
  local results = {}
  for _, process in ipairs(processes) do
    process.job:wait(brew.install_process_timeout * 1000)
    if not vim.tbl_isempty(process.candidates) then
      try {
        function()
          local json = vim.fn.json_decode(process.candidates[1])
          results = vim.tbl_extend('keep', results,
            util.map_filter(json['data'], function(k, v)
                return type(v) == "table" and v.pushedAt ~= nil end))
        end,
        catch {
          function(e)
            ERROR('json output decode error: ' .. vim.fn.string(process.candidates) .. e)
          end
        }
      }
    end
  end

  -- Get pushed time.
  local check_pushed = {}
  for _, node in pairs(results) do
    if node ~= nil then
      check_pushed[node.nameWithOwner] =
        vim.fn.strptime('%Y-%m-%dT%H:%M:%SZ', node.pushedAt)
    end
  end

  -- Get the last updated time by rollbackfile timestamp.
  -- Note: .git timestamp may be changed by git commands.
  local rollbacks = vim.fn.reverse(vim.fn.sort(util.globlist(
    __get_rollback_directory() .. '/*')))
  local rollback_time = vim.fn.empty(rollbacks)==1 and -1 or vim.fn.getftime(rollbacks[1])

  -- Compare with .git directory updated time.
  local updated = {}
  for _, plugin in ipairs(plugins) do
    if check_pushed[plugin.repo]~=nil then
      local git_path = plugin.path .. '/.git'
      local repo_time = (vim.fn.isdirectory(plugin.path)==1
        and vim.fn.getftime(git_path) or -1)

      if math.min(repo_time, rollback_time) < check_pushed[plugin.repo] then
        table.insert(updated, plugin)
      end
    end
  end

  vim.api.nvim_command('redraw | echo ""')
  -- Clear global context
  __global_context = {}

  if vim.tbl_isempty(updated) then
    _notify(vim.fn.strftime('Done: (%Y/%m/%d %H:%M:%S)'))
    return
  end

  _notify('Updated plugins: ' ..
    vim.fn.string(vim.tbl_map(function(v) return v.name end, updated)))
  if not force and vim.fn.confirm('Updated plugins are exists. Update now?',
    "yes\nno", 2) ~= 1 then
    return
  end

  _update(updated, 'update', async)
end
function M.reinstall(plugins)
  plugins = util.get_plugins(plugins)

  for _, plugin in ipairs(plugins) do
    repeat
      -- Remove the plugin
      if plugin.type == 'none' or (plugin['local'] or 0)==1 or (plugin.sourced and vim.fn.index({'dein'}, plugin.normalized_name) >= 0) then
        util._error(vim.fn.printf('|%s| Cannot reinstall the plugin!', plugin.name))
        break
      end

      -- Reinstall.
      print_progress_message(vim.fn.printf('|%s| Reinstalling...', plugin.name))

      if isdir(plugin.path)==1 then
        _rm(plugin.path)
      end
    until true
  end

  _update(util.convert2list(plugins), 'install', 0)
end

function __echo(expr, mode)
  local msg = vim.tbl_map(
    function(v)
      return '[dein] ' ..  v
    end,
    vim.tbl_filter(function(v) return v~='' end, util.convert2list(expr)))
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
  msg = util.convert2list(msg)
  local context = __global_context
  if vim.fn.empty(msg)==1 or vim.fn.empty(context)==1 then
    return
  end

  if context.message_type == 'echo' then
    _notify(msg)
  end

  _updates_log(msg)
  __progress = vim.fn.join(msg, "\n")
end

local function strwidthpart(str, width)
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
local function strwidthpart_reverse(str, width)
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
local function truncate_skipping(str, max, footer_width, separator)
  local width = vim.fn.strwidth(str)
  if width <= max then
    return str
  else
    local header_width = max - vim.fn.strwidth(separator) - footer_width
    return strwidthpart(str, header_width) .. separator .. strwidthpart_reverse(str, footer_width)
  end
end
function __echo_mode(m, mode)
  for _, m in ipairs(vim.fn.split(m, [[\r\?\n]], 1)) do
    if vim.fn.has('vim_starting')==0 and mode~='error' then
      m = truncate_skipping(m, vim.o.columns - 1, vim.o.columns/3, '...')
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

function M.recache_runtimepath()
  if brew._is_sudo then
    return
  end

  -- Clear runtime path.
  clear_runtimepath()

  local plugins = vim.tbl_values(brew.get())

  local merged_plugins = vim.tbl_filter(function(v) return v.merged==1 end, vim.fn.copy(plugins))

  copy_files(vim.tbl_filter(function(v) return v.lazy~=0 end, vim.fn.copy(merged_plugins)), '')
  -- Remove plugin directory
  local runtimepath = util.get_runtime_path()
  _rm(runtimepath .. '/plugin')
  _rm(runtimepath .. '/after/plugin')

  copy_files(vim.tbl_filter(function(v) return v.lazy==0 end, vim.fn.copy(merged_plugins)), '')

  helptags()

  generate_ftplugin()

  -- Clear ftdetect and after/ftdetect directories.
  _rm(runtimepath..'/ftdetect')
  _rm(runtimepath..'/after/ftdetect')

  merge_files(plugins, 'ftdetect')
  merge_files(plugins, 'after/ftdetect')

  -- TODO: silent
  M.remote_plugins()

  util.call_hook('post_source')

  util.save_merged_plugins()

  -- FIXME
  -- _save_rollback(__get_rollback_directory() .. '/' .. vim.fn.strftime('%Y%m%d%H%M%S'), {})

  util.clear_state()

  log(vim.fn.strftime('Runtimepath updated: (%Y/%m/%d %H:%M:%S)'))
end
local function get_sync_command(plugin, update_type, number, max)
  require 'dein/parse'
  local type = _get_type(plugin.type)
  local cmd

  if type.get_sync_command ~= nil then
    cmd = type:get_sync_command(plugin)
  else
    return '', ''
  end

  if vim.fn.empty(cmd)==1 then
    return '', ''
  end

  local message = get_plugin_message(plugin, number, max, vim.fn.string(cmd))

  return cmd, message
end
-- 轮询
local function polling()
  local _, new_context = install_async(__global_context)
  __global_context = new_context
end
-- update_type: install or update
function _update(plugins, update_type, async)
  if brew._is_sudo then
    ERROR('update/install is disabled in sudo session.')
    return
  end

  plugins = util.get_plugins(plugins)

  if update_type == 'install' then
    local installed_plugins = vim.tbl_filter(function(v) return isdir(v.path)==1 end, plugins)
    if not vim.tbl_isempty(installed_plugins) then
      util._error('Already installed: '..vim.inspect(vim.tbl_map(function(v) return v.name end, installed_plugins)))
    end
    plugins = vim.tbl_filter(function(v) return isdir(v.path)==0 end, plugins)
  end

  if async and vim.fn.empty(__global_context)==0
    and vim.fn.confirm('The installation has not finished. Cancel now?', "yes\nNo", 2) ~= 1 then
    return
  end

  -- Set context.
  local context = init_context(plugins, update_type, async)

  init_variables(context)

  if vim.fn.empty(plugins)==1 then
    __notify('Target plugins are not found.')
    __notify('You may have used the wrong plugin name, or all of the plugins are already installed.')
    __global_context = {}
    return
  end

  __notify(vim.fn.strftime('Update started: (%Y/%m/%d %H:%M:%S)'))

  if not async or vim.fn.has('vim_starting')==1 then
    return update_loop(context)
  end

  vim.api.nvim_exec([[
    augroup dein-install
      autocmd!
    augroup END
  ]], false)

  if __timer then
    vim.fn.timer_stop(__timer)
    __timer = nil
  end

  __timer = vim.fn.timer_start(50, polling, {['repeat']=-1})
end
local function __init_job(process, context, cmd)
  process.start_time = vim.fn.localtime()

  if not context.async then
    process.output = _system(cmd)
    process.status = _status()
    return process
  end

  process.async = {eof=0}
  process.job = Job:start(cmd, {on_init=function (obj)
      obj.context = context
    end,
    on_exit=function (job_id, data, event)
      print('job_id:', job_id, 'event:', event, 'data:', vim.inspect(data))
      check_output(context, process)
    end,
    on_stdout=function (job_id, data, event)
      print('job_id:', job_id, 'event:', event, 'data:', vim.inspect(data))
    end
  })
  process.job.candidates = {}
  process.id = process.job.pid
  return process
end
function M.remote_plugins()
  if vim.fn.has('vim_starting')==1 then
    -- Note: UpdateRemotePlugins is not defined in vim_starting
    vim.api.nvim_command('autocmd dein VimEnter * silent lua dein.remote_plugins()')
    return
  end

  if vim.fn.exists(':UpdateRemotePlugins') ~= 2 then
    return
  end

  -- Load not loaded neovim remote plugins
  local remote_plugins = vim.tbl_filter(
    function(v) return isdir(v.rtp .. '/rplugin')==1 and not v.sourced end,
    vim.tbl_values(brew.get()))

  require 'dein/autoload'
  _source(remote_plugins)

  log('loaded remote plugins: ' .. vim.fn.string(vim.tbl_map(function(v) return v.name end, vim.fn.copy(remote_plugins))))

  vim.o.rtp = util.join_rtp(util.uniq(util.split_rtp(vim.o.rtp)), vim.o.rtp, '')

  local result = vim.fn.execute('UpdateRemotePlugins', '')
  log(result)
end
local function __init_process(plugin, context, cmd)
  local process = {}

  local cwd = vim.fn.getcwd()
  local lang_save = vim.env.LANG
  local prompt_save = vim.env.GIT_TERMINAL_PROMPT
  try {
    function()
      vim.env.LANG = 'C'
      -- Disable git prompt (git version >= 2.3.0)
      vim.env.GIT_TERMINAL_PROMPT = 0

      _cd(plugin.path)

      local rev = get_revision_number(plugin)

      process = {
        number=context.number,
        max_plugins=context.max_plugins,
        rev=rev,
        plugin=plugin,
        output='',
        status=-1,
        eof=0,
        installed=isdir(plugin.path),
      }

      local rev_save = plugin.rev or ''
      if isdir(plugin.path)==1 and (plugin['local'] or 0)==0 and rev_save~='' then
        try {
          function()
            -- Force checkout HEAD revision.
            -- The repository may be checked out.
            plugin.rev = ''

            lock_revision(process)
          end,
          catch {
            function(e)
              print('caught error: ' .. e)
            end
          }
        }
        plugin.rev = rev_save
      end

      process = __init_job(process, context, cmd)
    end,
    catch {
      function(e)
        print('caught error: ' .. e)
      end
    }
  }

  vim.env.LANG = lang_save
  vim.env.GIT_TERMINAL_PROMPT = prompt_save
  _cd(cwd)

  return process
end
function __sync(plugin, context)
  context.number = context.number + 1

  local num = context.number
  local max = context.max_plugins

  -- if not plugin then return end
  if isdir(plugin.path)==1 and (plugin.frozen or 0)==1 then
    -- Skip frozen plugin
    log(get_plugin_message(plugin, num, max, 'is frozen.'))
    return
  end

  local cmd, message = get_sync_command(plugin, context.update_type, context.number, context.max_plugins)

  if vim.fn.empty(cmd)==1 then
    -- Skip
    log(get_plugin_message(plugin, num, max, message))
    return
  end

  if type(cmd) == 'string' and cmd:find('^E: ') then
    -- Errored.

    print_progress_message(get_plugin_message(plugin, num, max, 'Error'))
    ERROR(cmd:sub(4))
    table.insert(context.errored_plugins, plugin)
    return
  end

  if context.async==false then
    print_progress_message(message)
  end

  local process = __init_process(plugin, context, cmd)
  if vim.fn.empty(process)==0 then
    table.insert(context.processes, process)
  end
  -- call luaeval('dein_log:write(vim.inspect(_A), "\n")', [a:context])
  -- lua dein_log:flush()
  return context
end
function M.get_progress()
  return __progress
end
function M.get_context()
  return __global_context
end
function M.get_updates_log()
  return var_updates_log
end
function M.get_log()
  return var_log
end

if _TEST then
  M.__convert_args = __convert_args
  M._strwidthpart = strwidthpart
  M._strwidthpart_reverse = strwidthpart_reverse
  M._truncate_skipping = truncate_skipping
  M.__echo_mode = __echo_mode
  M._var_updates_log = var_updates_log
  M._updates_log = _updates_log
  M._var_log = var_log
  M._append_log_file = append_log_file
  M._log = log
  M._iconv = iconv
  M._ERROR = ERROR
  M._get_sync_command = get_sync_command
end

return M
