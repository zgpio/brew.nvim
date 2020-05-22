-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local util = require 'dein/util'

function clear_runtimepath()
  if _get_cache_path() == '' then
    util._error('Invalid base path.')
    return
  end

  local runtimepath = _get_runtime_path()

  -- Remove runtime path
  vim.fn['dein#install#_rm'](runtimepath)

  if vim.fn.isdirectory(runtimepath)==0 then
    -- Create runtime path
    vim.fn.mkdir(runtimepath, 'p')
  end
end
function append_log_file(msg)
  local logfile = _expand(vim.g['dein#install_log_filename'])
  if logfile == '' then
    return
  end

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
