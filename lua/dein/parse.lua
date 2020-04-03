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

function _add(repo, options)
  local _plugins = dein_plugins
  local plugin = _dict(vim.fn['dein#parse#_init'](repo, options))
  if (_plugins[plugin.name]~=nil
        and _plugins[plugin.name].sourced==1)
        or (plugin['if'] or 1)==0 then
    -- Skip already loaded or not enabled plugin.
    return {}
  end

  if plugin.lazy==1 and plugin.rtp ~= '' then
    plugin = parse_lazy(plugin)
  end

  if _plugins[plugin.name]~=nil and _plugins[plugin.name].sourced==1 then
    plugin.sourced = 1
  end
  _plugins[plugin.name] = plugin
  if plugin['hook_add']~=nil then
    vim.fn['dein#util#_execute_hook'](plugin, plugin.hook_add)
  end
  if plugin['ftplugin']~=nil then
    merge_ftplugin(plugin.ftplugin)
  end
  dein_plugins = _plugins
  return plugin
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
  local event_plugins = dein_event_plugins
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
  dein_event_plugins = event_plugins

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
function add_dein_vimrcs(s)
  table.insert(dein_vimrcs, s)
end

function merge_ftplugin(ftplugin)
  local _ftplugin = dein_ftplugin
  -- TODO
  _ftplugin[true]=nil
  for ft, val in pairs(ftplugin) do
    if _ftplugin[ft] == nil then
      _ftplugin[ft] = val
    else
      _ftplugin[ft] = _ftplugin[ft] .. '\n' .. val
    end
  end
  _ftplugin = vim.tbl_map(
    function(v)
      return vim.fn.substitute(v, [=[\n\s*\\\|\%(^\|\n\)\s*"[^\n]*]=], '', 'g')
    end,
    _ftplugin
  )
  dein_ftplugin = _ftplugin
end

function _dict(plug)
  plugin = vim.tbl_extend('force', { rtp='', sourced=0 }, plug)

  if plugin.name == nil then
    plugin.name = vim.fn['dein#parse#_name_conversion'](plugin.repo)
  end

  if plugin.normalized_name == nil then
    plugin.normalized_name = vim.fn.substitute(
          vim.fn.fnamemodify(plugin.name, ':r'),
          [[\c^n\?vim[_-]\|[_-]n\?vim$]], '', 'g')
  end

  if plug.name==nil and vim.g['dein#enable_name_conversion']==1 then
    -- Use normalized name.
    plugin.name = plugin.normalized_name
  end

  if plugin.path==nil then
    if plugin.path:find('^%a:[/\\]') or plugin.path:find('^/') then
      plugin.path = plugin.repo
    else
      plugin.path = _get_base_path()..'/repos/'..plugin.name
    end
  end

  require 'dein/util'
  plugin.path = _chomp(vim.fn['dein#util#_expand'](plugin.path))
  if (plugin.rev or '') ~= '' then
    -- Add revision path
    plugin.path = plugin.path ..'_'.. vim.fn.substitute(plugin.rev, '[^[:alnum:].-]', '_', 'g')
  end

  -- Check relative path
  if (plug.rtp==nil or plug.rtp ~= '')
         and not (plugin.rtp:find('^[~/]') or plugin.rtp:find('^%a+:')) then
    plugin.rtp = plugin.path..'/'..plugin.rtp
  end
  -- TODO ?_? dein use [0:]
  if plugin.rtp == '~' then
    plugin.rtp = vim.fn['dein#util#_expand'](plugin.rtp)
  end
  plugin.rtp = _chomp(plugin.rtp)
  if vim.g['dein#_is_sudo']==1 and not (plugin.trusted==1) then
    plugin.rtp = ''
  end

  if plugin.script_type ~= nil then
    -- Add script_type.
    plugin.path = plugin.path..'/'.. plugin.script_type
  end

  if plugin.depends~=nil and type(plugin.depends) ~= 'table' then
    plugin.depends = {plugin.depends}
  end

  -- Deprecated check.
  for _, key in ipairs({'directory', 'base'}) do
    if plugin[key] ~= nil then
      require 'dein/util'._error('plugin name = ' .. plugin.name)
      require 'dein/util'._error(vim.fn.string(key) .. ' is deprecated.')
    end
  end

  if plugin.lazy==nil then
    plugin.lazy = plugin.on_i ~= nil
          or plugin.on_idle ~= nil
          or plugin.on_ft ~= nil
          or plugin.on_cmd ~= nil
          or plugin.on_func ~= nil
          or plugin.on_map ~= nil
          or plugin.on_path ~= nil
          or plugin.on_if ~= nil
          or plugin.on_event ~= nil
          or plugin.on_source ~= nil
    if plugin.lazy then plugin.lazy = 1 else plugin.lazy = 0 end
  end

  if plug.merged==nil then
    plugin.merged = plugin.lazy==0
      and plugin.normalized_name ~= 'dein'
      and plugin['local']==nil
      and plugin['build']==nil
      and plugin['if']==nil
      and vim.fn.stridx(plugin.rtp, _get_base_path()) == 0
    if plugin.merged then plugin.merged = 1 else plugin.merged = 0 end
  end

  if plugin['if']~=nil and type(plugin['if']) == 'string' then
    plugin['if'] = vim.api.nvim_eval(plug['if'])
  end

  -- Hooks
  for _, hook in ipairs({
    'hook_add', 'hook_source',
    'hook_post_source', 'hook_post_update',
    }) do
    if plugin[hook] ~= nil and type(plugin[hook]) == 'string' then
      plugin[hook] = vim.fn.substitute(plugin[hook], [=[\n\s*\\\|\%(^\|\n\)\s*"[^\n]*]=], '', 'g')
    end
  end

  return plugin
end

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
