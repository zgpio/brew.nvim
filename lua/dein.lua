-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
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
function load_state(path, ...)
  if vim.fn.exists('#dein') == 0 then
    vim.fn['dein#_init']()
  end
  local args = ...
  local sourced
  if #args > 0 then
    sourced = args[1]
  else
    sourced = vim.fn.has('vim_starting')==1 and vim.o.loadplugins
  end
  if (vim.g['dein#_is_sudo']==1 or not sourced) then return 1 end
  dein_base_path = vim.fn.expand(path)

  local state = (vim.g['dein#cache_directory'] or dein_base_path)
    .. '/state_' .. dein_progname .. '.vim'
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
  dein_vimrcs = vimrcs
  local cache = (vim.g['dein#cache_directory'] or dein_base_path) ..'/cache_' .. dein_progname
  local time = vim.fn.getftime(cache)
  local t = vim.tbl_filter(
    function(v)
      return time < v
    end,
    vim.tbl_map(
      function(v)
       return vim.fn.getftime(vim.fn.expand(v))
      end,
      vim.deepcopy(dein_vimrcs)
    )
  )
  if #t~=0 then
    return {{}, {}}
  end
  local list = vim.fn.readfile(cache)
  if #list ~= 3 or vim.fn.string(dein_vimrcs) ~= list[1] then
    return {{}, {}}
  end
  return {vim.fn.json_decode(list[2]), vim.fn.json_decode(list[3])}
end

function tap(name)
  local _plugins = dein_plugins
  if _plugins.name==nil or vim.fn.isdirectory(_plugins[name].path)==0 then
    return 0
  end
  vim.g['dein#name'] = name
  vim.g['dein#plugin'] = _plugins[name]
  return 1
end
function is_sourced(name)
  local _plugins = dein_plugins
  return _plugins.name~=nil
    and vim.fn.isdirectory(_plugins[name].path)==1
    and _plugins[name].sourced==1
end
return M
