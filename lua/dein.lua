-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local M = {}
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
  vim.g['dein#_base_path'] = vim.fn.expand(path)

  local state = (vim.g['dein#cache_directory'] or vim.g['dein#_base_path'])
    .. '/state_' .. vim.g['dein#_progname'] .. '.vim'
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

return M
