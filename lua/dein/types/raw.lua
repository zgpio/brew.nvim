require 'dein/util'
local M = {
  name='raw',
}

function M.init(repo, options)
  -- No auto detect.
  if vim.fn.match(repo, [[^https://.*\.vim$]])==-1 or not options.script_type then
    return {}
  end

  local directory = vim.fn.substitute(vim.fn.fnamemodify(repo, ':h'), [[\.git$]], '', '')
  directory = vim.fn.substitute(directory, [[^https:/\+\|^git@]], '', '')
  directory = vim.fn.substitute(directory, ':', '/', 'g')

  return { ['name']=_name_conversion(repo), ['type']='raw',
          ['path']=dein._base_path..'/repos/'..directory }
end

function M.get_sync_command(plugin)
  local path = plugin.path
  if vim.fn.isdirectory(path)==0 then
    -- Create script type directory.
    vim.fn.mkdir(path, 'p')
  end

  local outpath = path .. '/' .. vim.fn.fnamemodify(plugin.repo, ':t')
  return _download(plugin.repo, outpath)
end
return M
