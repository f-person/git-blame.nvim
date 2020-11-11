# git-blame.nvim
A git blame plugin for Neovim written in Lua

## Installation
### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'f-person/git-blame.nvim'
```

## The Why
There were Vim plugins providing this functionality, however most of them were
written in VimScript and work well for me. [coc-git](https://github.com/neoclide/coc-git) also had
option for showing blame info, it worked really well for me, I like it. However,
recently I decided to switch to Neovim's builtin LSP instead of using CoC and having
something running on Node.js just for git blame was not the best thing.

## Demo
![demo](assets/demo.png?raw=true)

# TODO

* Customizable blame text format
* Blame loading delay
