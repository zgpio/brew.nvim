-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local is_windows = _is_windows()
if is_windows then
  function __is_absolute(path)
    return path:find('^[\\/]')~=nil or path:find('^%a:')~=nil
  end
else
  function __is_absolute(path)
    return path:find('^/')~=nil
  end
end

function __join_paths(path1, path2)
  -- Joins two paths together, handling the case where the second path
  -- is an absolute path.
  if __is_absolute(path2) then
    return path2
  end
  local p1, p2
  if is_windows then
    p1 = '[\\/]$'
    p2 = '^[\\/]'
  else
    p1 = '/$'
    p2 = '^/'
  end
  if path1:find(p1) or path2:find(p2) then
    -- the appropriate separator already exists
    return path1 .. path2
  else
    -- note: I'm assuming here that '/' is always valid as a directory
    -- separator on Windows. I know Windows has paths that start with \\?\ that
    -- diasble behavior like that, but I don't know how Vim deals with that.
    return path1 .. '/' .. path2
  end
end
