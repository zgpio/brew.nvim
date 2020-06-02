# brew.nvim

TODO: Build Status
NOTE: Under development, some features are broken

brew.nvim is a Neovim plugin manager, rewrite dein with neovim builtin lua.

<!-- vim-markdown-toc GFM -->

- [Requirements](#requirements)
- [Quick start](#quick-start)
  - [Unix/Linux or Mac OS X](#unixlinux-or-mac-os-x)
- [Features](#features)
- [Future works (TODO)](#future-works-todo)
  - [Options](#options)

<!-- vim-markdown-toc -->

## Requirements

- NeoVim.
- "xcopy" command in $PATH (Windows)
- "git" command in $PATH (if you want to install github or vim.org plugins)

## Quick start

**Note**: You must define the installation directory before to use.  The
directory that you will want to use depends on your usage.

For example, `~/.vim/bundles` or `~/.cache/brew` or `~/.local/share/brew`.
brew.vim does not define a default installation directory.
You must **not** set the installation directory as `~/.vim/plugin` or
`~/.config/nvim/plugin`.

### Unix/Linux or Mac OS X

1. Run below script.

```sh
curl https://raw.githubusercontent.com/zgpio/brew.nvim/master/bin/installer.sh > installer.sh
# For example, we just use `~/.cache/brew` as installation directory
sh ./installer.sh ~/.cache/brew
```

2. Edit your .vimrc like this.

```vim
" Add the brew installation directory into runtimepath
set runtimepath+=~/.cache/brew/repos/github.com/zgpio/brew.nvim

if brew#load_state('~/.cache/brew')
  call brew#begin('~/.cache/brew')

  call brew#add('~/.cache/brew/repos/github.com/zgpio/brew.nvim')

  call brew#end()
  call brew#save_state()
endif

filetype plugin indent on
syntax enable
```

3. Open nvim and install brew

```vim
:call brew#install()
```

## Features

- Simple

- No commands, Functions only to simplify the implementation

- Easy to test and maintain

- No Vundle/NeoBundle compatibility

- neovim asynchronous API installation support

- Local plugin support

- Non github plugins support

- Go like clone directory name ex:"github.com/{user}/{repository}"

- Merge the plugins directories automatically to avoid long 'runtimepath'

## Future works (TODO)

- Other types support (zip, svn, hg, ...)

- Metadata repository support

### Options

Some common options. For a more detailed list, run `:h brew-options`

| Option   | Type                 | Description                                                                           |
| -------- | -------------------- | ------------------------------------------------------------------------------------- |
| `name`   | `string`             | The name for a plugin. If it is omitted, the tail of the repository name will be used |
| `rev`    | `string`             | The revision number or branch/tag name for the repo                                   |
| `build`  | `string`             | Command to run after the plugin is installed                                          |
| `on_ft`  | `string` or `list`   | Load a plugin for the current filetype                                                |
| `on_cmd` | `string` or `list`   | Load the plugin for these commands                                                    |
| `rtp`    | `string`             | You can use this option when the repository has the Vim plugin in a subdirectory               |
| `if`     | `string` or `number` | If it is String, brew.nvim will eval it.                                                   |
| `merged` | `number`             | If set to 0, brew.nvim doesn't merge the plugin directory.                                 |
