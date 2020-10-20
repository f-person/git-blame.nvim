lua require('gitblame').init()
highlight default link gitblame Comment

autocmd CursorMoved  * lua require('gitblame').show_blame_info()
autocmd CursorMovedI * lua require('gitblame').clear_virtual_text()
autocmd TextChanged  * lua require('gitblame').load_blames()
autocmd TextChangedI * lua require('gitblame').load_blames()
autocmd TextChangedP * lua require('gitblame').load_blames()
