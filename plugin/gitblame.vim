highlight default link gitblame Comment

lua require('gitblame').init()

augroup gitblame
	autocmd!
	autocmd CursorMoved  * lua require('gitblame').show_blame_info()
	autocmd CursorMovedI * lua require('gitblame').clear_virtual_text()
	autocmd TextChanged  * lua require('gitblame').load_blames()
	autocmd InsertLeave * lua require('gitblame').load_blames()
	autocmd InsertLeave * lua require('gitblame').show_blame_info()
	autocmd BufEnter * lua require('gitblame').check_file_in_git_repo()
	autocmd BufDelete * lua require('gitblame').cleanup_file_data()
augroup END
