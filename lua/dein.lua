-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local a = vim.api
local M = {}
-- https://gist.github.com/cwarden/1207556
function catch(what)
  return what[1]
end

function try(what)
  status, result = pcall(what[1])
  if not status then
    what[2](result)
  end
  return result
end

-- try {
--   function()
--     -- error('oops')
--     vim.api.nvim_command('echo "xxxxxx"')
--   end,
--
--   catch {
--     function(error)
--       print('caught error: ' .. error)
--       return 1
--     end
--   }
-- }
function M._init()
  M._cache_version = 150
  M._merged_format = "{'repo': v:val.repo, 'rev': get(v:val, 'rev', '')}"
  M._merged_length = 3
  vim.g['dein#name'] = ''
  vim.g['dein#plugin'] = {}
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
  local SUDO_USER = vim.env['SUDO_USER']
  local USER = vim.env['USER']
  local HOME = vim.env['HOME']
  M._is_sudo = (SUDO_USER~=nil and USER ~= SUDO_USER
    and HOME ~= vim.fn.expand('~'..USER)
    and HOME == vim.fn.expand('~'..SUDO_USER))

  vim.api.nvim_exec([[
    augroup dein
      autocmd!
      autocmd FuncUndefined * call luaeval("require'dein/autoload'._on_func(_A)", expand('<afile>'))
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
function load_state(path, ...)
  if vim.fn.exists('#dein') == 0 then
    M._init()
  end
  local args = ...
  local sourced
  if #args > 0 then
    sourced = args[1]
  else
    sourced = vim.fn.has('vim_starting')==1 and vim.o.loadplugins
  end
  if (dein._is_sudo==1 or not sourced) then return 1 end
  dein._base_path = vim.fn.expand(path)

  local state = (vim.g['dein#cache_directory'] or dein._base_path)
    .. '/state_' .. dein._progname .. '.vim'
  if vim.fn.filereadable(state)==0 then return 1 end
  try {
    function()
      vim.api.nvim_command('source ' .. vim.fn.fnameescape(state))
    end,
    catch {
      function(error)
      -- if v:exception !=# 'Cache loading error'
      --   call dein#util#_error('Loading state error: ' . v:exception)
      -- end
        vim.fn['dein#clear_state']()
        print('caught error: ' .. error)
        return 1
      end
    }
  }
end
function load_cache_raw(vimrcs)
  dein._vimrcs = vimrcs
  local cache = (vim.g['dein#cache_directory'] or dein._base_path) ..'/cache_' .. dein._progname
  local time = vim.fn.getftime(cache)
  local t = vim.tbl_filter(
    function(v)
      return time < v
    end,
    vim.tbl_map(
      function(v)
       return vim.fn.getftime(vim.fn.expand(v))
      end,
      vim.deepcopy(dein._vimrcs)
    )
  )
  if #t~=0 then
    return {{}, {}}
  end
  local list = vim.fn.readfile(cache)
  if #list ~= 3 or vim.fn.string(dein._vimrcs) ~= list[1] then
    return {{}, {}}
  end
  return {vim.fn.json_decode(list[2]), vim.fn.json_decode(list[3])}
end

function tap(name)
  local _plugins = dein._plugins
  if _plugins.name==nil or vim.fn.isdirectory(_plugins[name].path)==0 then
    return 0
  end
  vim.g['dein#name'] = name
  vim.g['dein#plugin'] = _plugins[name]
  return 1
end
function is_sourced(name)
  local _plugins = dein._plugins
  return _plugins.name~=nil
    and vim.fn.isdirectory(_plugins[name].path)==1
    and _plugins[name].sourced==1
end
return M
