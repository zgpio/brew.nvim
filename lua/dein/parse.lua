-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
function unique(items)
  flags = {}
  rv = {}
  for i=1,#items do
     if not flags[items[i]] then
        table.insert(rv, items[i])
        flags[items[i]] = true
     end
  end
  return rv
end

function parse_lazy(plugin)
  -- Auto convert2list.
  for i, key in ipairs({'on_ft', 'on_path', 'on_cmd', 'on_func', 'on_map',
      'on_source', 'on_event'}) do
    if plugin[key] ~= nil and type(plugin[key]) ~= 'table' then
        plugin[key] = {plugin[key]}
    end
  end

  if plugin['on_i'] ~= nil and plugin['on_i'] ~= 0 then
    plugin.on_event = {'InsertEnter'}
  end
  if plugin['on_idle'] ~= nil and plugin['on_idle'] ~= 0 then
    plugin.on_event = {'FocusLost', 'CursorHold'}
  end
  local event_plugins = vim.g['dein#_event_plugins']
  -- TODO: https://github.com/neovim/neovim/issues/12048
  event_plugins[true] = nil
  if plugin['on_event'] ~= nil then
    for i, event in ipairs(plugin.on_event) do
      if event_plugins[event] == nil then
        event_plugins[event] = {plugin.name}
      else
        table.insert(event_plugins[event], plugin.name)
        event_plugins[event] = unique(event_plugins[event])
      end
    end
  end
  vim.g['dein#_event_plugins'] = event_plugins

  if plugin['on_cmd'] ~= nil then
    generate_dummy_commands(plugin)
  end
  if plugin['on_map'] ~= nil then
    generate_dummy_mappings(plugin)
  end
  return plugin
end

function generate_dummy_commands(plugin)
  plugin.dummy_commands = {}
  for i, name in ipairs(plugin.on_cmd) do
    -- Define dummy commands.
    local raw_cmd = 'command -complete=customlist,dein#autoload#_dummy_complete -bang -bar -range -nargs=* ' .. name
      .. vim.fn.printf(" call dein#autoload#_on_cmd(%s, %s, <q-args>, expand('<bang>'), expand('<line1>'), expand('<line2>'))",
       vim.fn.string(name), vim.fn.string(plugin.name))

    table.insert(plugin.dummy_commands, {name, raw_cmd})
    vim.api.nvim_command('silent! '..raw_cmd)
  end
end

function table.slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end
  return sliced
end

function generate_dummy_mappings(plugin)
  plugin.dummy_mappings = {}
  local items = {}
  if vim.tbl_islist(plugin.on_map) then
    for i, map in ipairs(plugin.on_map) do
      if vim.tbl_islist(map) then
        table.insert(items, {vim.split(map[1], ''), table.slice(map, 2)})
      else
        table.insert(items, {{'n', 'x'}, {map}})
      end
    end
  else
    for mode, map in pairs(plugin.on_map) do
      if vim.tbl_islist(map) then
        table.insert(items, {vim.split(mode, ''), map})
      else
        table.insert(items, {vim.split(mode, ''), {map}})
      end
    end
  end

  for i, item in ipairs(items) do
    local modes, mappings = unpack(item)
    if mappings[1] == '<Plug>' then
      -- Use plugin name.
      mappings = {'<Plug>(' .. plugin.normalized_name}
      if plugin.normalized_name:find('-') then
        -- The plugin mappings may use "_" instead of "-".
        table.insert(mappings, '<Plug>(' .. plugin.normalized_name:gsub('-', '_'))
      end
    end

    for i, mapping in ipairs(mappings) do
      -- Define dummy mappings.
      local prefix = string.format('v:lua._on_map("%s", "%s",',
        mapping:gsub('<', '<lt>'), plugin.name)
      for i, mode in ipairs(modes) do
        local t
        if mode == 'c' then
          t = [[ \<C-r>=]]
        elseif mode == 'i' then
          t = [[ \<C-o>:call ]]
        else
          t = vim.api.nvim_eval([[" :\<C-u>call "]])
        end
        local raw_map = mode..'noremap <unique><silent> '..mapping
            .. t .. prefix .. '"'.. mode.. '"'.. ')<CR>'
        table.insert(plugin.dummy_mappings, {mode, mapping, raw_map})
        vim.api.nvim_command('silent! '..raw_map)
      end
    end
  end
end
-- TODO: 临时的
function set_dein_hook_add(s)
  dein_hook_add = s
end

-- TODO
function merge_ftplugin(ftplugin)
  print(ftplugin)
  for ft, val in pairs(ftplugin) do
    if not vim.g['dein#_ftplugin'][ft] ~= nil then
      vim.g['dein#_ftplugin'][ft] = val
    else
      vim.g['dein#_ftplugin'][ft] = vim.g['dein#_ftplugin'][ft] .. "\n" .. val
    end
  end
  print(vim.inspect(vim.g['dein#_ftplugin']))
  for ft, val in pairs(vim.g['dein#_ftplugin']) do
    print(val)
    vim.g['dein#_ftplugin'][ft] = val:gsub('^%s*"[^\n]*', '')
    vim.g['dein#_ftplugin'][ft] = val:gsub('\n%s*"[^\n]*', '')
    vim.g['dein#_ftplugin'][ft] = val:gsub('\n%s*\\', '')
  end
end

-- function check_type(repo, options)
--   local plugin = {}
--   for type in values(dein#parse#_get_types()) do
--     let plugin = type.init(repo, options)
--     if !empty(plugin)
--       break
--     end
--   end
--
--   if #plugin == 0 then
--     plugin.type = 'none'
--     plugin.local = 1
--     plugin.path = isdirectory(repo) ? repo : ''
--   end
--
--   return plugin
-- end

-- local types
-- function get_types()
--   if types == nil then
--     -- Load types.
--     local types = {}
--     vim.fn.split(vim.fn.globpath(vim.o.runtimepath, 'autoload/dein/types/*.vim', 1), '\n')
--     for type in filter(map(split(globpath(&runtimepath, 'autoload/dein/types/*.vim', 1), '\n'),
--           "dein#types#{fnamemodify(v:val, ':t:r')}#define()"),
--           '!empty(v:val)')
--       types[type.name] = type
--     end
--   end
--   return types
-- end
