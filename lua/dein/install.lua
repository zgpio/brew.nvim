-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
require 'dein/util'

function append_log_file(msg)
  local logfile = vim.fn['dein#util#_expand'](vim.g['dein#install_log_filename'])
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
