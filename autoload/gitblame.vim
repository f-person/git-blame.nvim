function! gitblame#Update()

endfunction

function! gitblame#Init()
	lua require('gitblame').get_blame_info()

	"augroup gitblame
		"autocmd!
		"autocmd BufEnter,CursorMoved,CursorMovedI * :call gitblame#Update()
	"augroup END
endfunction
