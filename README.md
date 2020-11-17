# git-blame.nvim
A git blame plugin for Neovim written in Lua

## Installation
### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'f-person/git-blame.nvim'
```

## The Why
There were several Vim plugins providing this functionality, however most of them were
written in VimScript and didn't work well for me. [coc-git](https://github.com/neoclide/coc-git) also had
option for showing blame info, it worked really well for me, I like it. However,
recently I decided to switch to Neovim's builtin LSP instead of using CoC and having
something running on Node.js just for git blame was not the best thing.

## Demo
![demo](assets/demo.png?raw=true)

## Configuration
#### Enabled
Enables git-blame.nvim on neovim startup.
You can toggle git blame messages on/off with the `:GitBlameToggle` command.

Default: `1`

```vim
let g:gitblame_enabled  = 0
```

#### Message template
The template for the blame message that will be shown.

Default: `'  <author> • <date> • <summary>'`

Available options: `<author>`, `<date>`, `<summary>`

```vim
let g:gitblame_message_template = '<summary> • <date> • <author>'
```

# TODO

* Customizable info message format
* Date ago format for dates
