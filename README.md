# git-blame.nvim

A git blame plugin for Neovim written in Lua

## Table of Contents

- [Installation](#installation)
- [Requirements](#requirements)
- [The Why](#the-why)
- [Demo](#demo)
- [Configuration](#configuration)
  - [Using Lua](#using-lua)
  - [Enabled](#enabled)
  - [Message template](#message-template)
  - [Date format](#date-format)
  - [Message when not committed yet](#message-when-not-committed-yet)
  - [Highlight group](#highlight-group)
  - [nvim_buf_set_extmark optional parameters](#nvim_buf_set_extmark-optional-parameters)
  - [Virtual text enabled](#virtual-text-enabled)
  - [Ignore by Filetype](#ignore-by-filetype)
  - [Visual delay for displaying the blame info](#visual-delay-for-displaying-the-blame-info)
  - [Start virtual text at column](#start-virtual-text-at-column)
- [Commands](#commands)
  - [Open the commit URL in browser](#open-the-commit-url-in-browser)
  - [Enable/Disable git blame messages](#enabledisable-git-blame-messages)
  - [Copy SHA hash](#copy-sha-hash)
  - [Copy Commit URL](#copy-commit-url)
  - [Open file URL in browser](#open-file-url-in-browser)
  - [Copy file URL](#copy-file-url)
- [Statusline integration](#statusline-integration)
- [Changing the timeago-format language](#changing-the-timeago-format-language)
- [Thanks To](#thanks-to)
- [Contributors <3](#contributors-3)
- [Support](#support)


## Installation

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'f-person/git-blame.nvim'
```

## Requirements

* Neovim >= 0.5.0
* git

## The Why

There were several Vim plugins providing this functionality, but most of them
were written in VimScript and didn't work well for me. [coc-git](https://github.com/neoclide/coc-git)
also had option for showing blame info, it worked really well for me, I like it.
However, recently I decided to switch to Neovim's builtin LSP instead of using CoC
and having something running on Node.js just for git blame was not the best thing.

## Demo

![demo](assets/demo.png?raw=true)

## Configuration

### Using Lua

You can use `setup` to configure the plugin in Lua. This is the recommended way
if you're using Lua for your configs. Read the documentation below to learn
more about specific options (*NOTE:* options in the `setup` function don't
have the `gitblame_` prefix).

> **NOTE:** you don't have to call `setup` if you don't want to customize the
> default behavior.

```lua
require('gitblame').setup {
     --Note how the `gitblame_` prefix is omitted in `setup`
    enabled: false,
}
```

### Enabled

Enables git-blame.nvim on Neovim startup.
You can toggle git blame messages on/off with the `:GitBlameToggle` command.

Default: `1`

```vim
let g:gitblame_enabled = 0
```

### Message template

The template for the blame message that will be shown.

Default: `'  <author> • <date> • <summary>'`

Available options: `<author>`, `<committer>`, `<date>`, `<committer-date>`,
`<summary>`, `<sha>`

```vim
let g:gitblame_message_template = '<summary> • <date> • <author>'
```

### Date format

The [format](https://www.lua.org/pil/22.1.html) of the date fields.

Default: `%c`

Available options:

```
%r  relative date (e.g., 3 days ago)
%a  abbreviated weekday name (e.g., Wed)
%A  full weekday name (e.g., Wednesday)
%b  abbreviated month name (e.g., Sep)
%B  full month name (e.g., September)
%c  date and time (e.g., 09/16/98 23:48:10)
%d  day of the month (16) [01-31]
%H  hour, using a 24-hour clock (23) [00-23]
%I  hour, using a 12-hour clock (11) [01-12]
%M  minute (48) [00-59]
%m  month (09) [01-12]
%p  either "am" or "pm" (pm)
%S  second (10) [00-61]
%w  weekday (3) [0-6 = Sunday-Saturday]
%x  date (e.g., 09/16/98)
%X  time (e.g., 23:48:10)
%Y  full year (1998)
%y  two-digit year (98) [00-99]
%%  the character `%´
```

```vim
let g:gitblame_date_format = '%r'
```

### Message when not committed yet

The blame message that will be shown when the current modification hasn't
been committed yet.

Supports the same template options as `g:gitblame_message_template`.

Default: `'  Not Committed Yet'`

```vim
let g:gitblame_message_when_not_committed = 'Oh please, commit this !'
```


### Highlight group

The highlight group for virtual text.

Default: `Comment`

```vim
let g:gitblame_highlight_group = "Question"
```

### `nvim_buf_set_extmark` optional parameters

`nvim_buf_set_extmark` is the function used for setting the virtual text.
You can view an up-to-date full list of options in the
[Neovim documentation](https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()).

**Warning**: overwriting `id` and `virt_text` will break the plugin behavior.

```vim
let g:gitblame_set_extmark_options = {
    \ 'priority': 7,
    \ }
```

### Virtual text enabled

If the blame message should be displayed as virtual text.

You may want to disable this if you display the blame message in statusline.

Default: `1`

```vim
let g:gitblame_display_virtual_text = 0
```

### Ignore by Filetype

A list of filetypes for which gitblame information will not be displayed.

Default: `[]`

```vim
let g:gitblame_ignored_filetypes = ['lua', 'c']
```

### Visual delay for displaying the blame info

The delay in milliseconds after which the blame info will be displayed.

Note that this doesn't affect the performance of the plugin.

Default: `0`

```vim
let g:gitblame_delay = 1000 " 1 second
```

### Start virtual text at column

Have the blame message start at a given column instead of EOL. If the current
line is longer than the specified column value the blame message will default
to being displayed at EOL.

Default: `v:null`

```vim
let g:gitblame_virtual_text_column = 80
```

## Commands

### Open the commit URL in browser

`:GitBlameOpenCommitURL` opens the commit URL of commit under the cursor.
Tested to work with GitHub and GitLab.

### Enable/Disable git blame messages

* `:GitBlameToggle` toggles git blame on/off,
* `:GitBlameEnable` enables git blame messages,
* `:GitBlameDisable` disables git blame messages.

### Copy SHA hash

`:GitBlameCopySHA` copies the SHA hash of current line's commit into
the system's clipboard.

### Copy Commit URL

`:GitBlameCopyCommitURL` copies the commit URL of current line's commit into
the system clipboard.

### Open file URL in browser

`:GitBlameOpenFileURL` opens the file (with a mark set on the current line) in
the browser.

### Copy file URL

`:GitBlameCopyFileURL` copies the file URL into the system clipboard.


## Statusline integration

The plugin provides you with two functions which you can incorporate into your
statusline of choice:

```lua
-- Lua
local git_blame = require('gitblame')

git_blame.is_blame_text_available() -- Returns a boolean value indicating whether blame message is available
git_blame.get_current_blame_text() --  Returns a string with blame message
```

Here is an example of integrating with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim):

```Lua
-- Lua
vim.g.gitblame_display_virtual_text = 0 -- Disable virtual text
local git_blame = require('gitblame')

require('lualine').setup({
    sections = {
            lualine_c = {
                { git_blame.get_current_blame_text, cond = git_blame.is_blame_text_available }
            }
    }
})
```

## Changing the timeago-format language

The plugin uses [lua-timeago](https://github.com/f-person/lua-timeago) for
displaying commit dates in a relative time ago format. Take a look at the
[languages](https://github.com/f-person/git-blame.nvim/tree/master/lua/lua-timeago/languages)
directory for a list of pre-installed languages. If you wish to use a language
that's not built into lua-timeago, you can
[do that](https://github.com/f-person/lua-timeago#language) too;
please consider opening a PR to lua-timeago if you choose to do so :)

To set a language, call the `set_language` method:

```lua
-- Lua
require('lua-timeago').set_language(require('lua-timeago/languages/hy'))
```

```vim
" Vimscript
:lua require('lua-timeago').set_language(require('lua-timeago/languages/hy'))
```

## Thanks To

* [coc-git](https://github.com/neoclide/coc-git) for some parts of code.
* [blamer.nvim](https://github.com/APZelos/blamer.nvim) for documentation inspiration.

## Contributors <3

[![](https://contrib.rocks/image?repo=f-person/git-blame.nvim)](https://github.com/f-person/git-blame.nvim/graphs/contributors)

Made with [contrib.rocks](https://contrib.rocks).

## Support
If you enjoy the plugin and want to support what I do


<a href="https://www.buymeacoffee.com/fperson" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41"  width="174"></a>
