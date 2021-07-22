if !has('g:gemini_follow_redirects')
	" Do not set to false with the current gmni version
	" It doesn't output redirect header to stdout
	" Only use with submodule version
	let g:gemini_follow_redirects = v:true
endif
if !has('g:gemini_max_redirects')
	let g:gemini_max_redirects = 5
endif
if !has('g:gemini_gmni_command')
	let g:gemini_gmni_command = shellescape(get(split(globpath(&rtp, 'gmni/gmni'), '\n'), 0, 'gmni'))
endif

function! s:read_gemini(url)
	let l:svpos = winsaveview()
	setlocal bl ro noswapfile bh=hide fenc=
	if &ft == ''
		setlocal ft=gmi
	else
		let &ft=&ft
	endif
	exe '%read ++bin !' . g:gemini_gmni_command . ' -j once -iN ' . (g:gemini_follow_redirects ? '-R ' . g:gemini_max_redirects . ' -L ' : '') . shellescape(a:url) . ' 2>/dev/null'
	keepjumps normal! ggJ
	let l:header = getline(1)
	let b:gemini_header = l:header
	keepjumps 1delete _
	keepjumps call winrestview(l:svpos)
	if l:header[0] == '3'
		" This plugin doesn't know, how to join urls,
		" '/...', '//...' are not handled properly by :find
		call append(0, '=> ' . l:header[3:] . ' Redirect')
		return
	endif
	if l:header[0] == '1'
		let l:url = matchstr(a:url, '\v^[^\?\#]+') . '?' . s:uriencode(input(l:header[3:] . ': '))
		0file
		exe 'file ' . fnameescape(l:url)
		return s:read_gemini(l:url)
	endif
	if l:header[0] == '2'
		return
	endif
	if l:header == ''
		let l:header = 'No data'
	endif
	" Output doesn't seem to work from autocommands
	function! s:error_message(...) closure
		redraw
		echohl WarningMsg
		echomsg 'Gemini: ' . l:header
		echohl None
	endfunction
	call timer_start(0, funcref('s:error_message'))
	return
endfunction

function! s:uriencode(str)
	let l:res = ''
	let l:digits = '0123456789ABCDEF'
	for l:i in range(len(a:str))
		let l:c = a:str[l:i]
		if match(l:c, '\v^[A-Za-z0-9_]$') == -1
			let l:n = char2nr(l:c)
			let l:lo = l:digits[l:n % 16]
			let l:hi = l:digits[l:n / 16]
			let l:c = '%' . l:hi . l:lo
		endif
		let l:res .= l:c
	endfor
	return l:res
endfunction

aug GeminiProtocol
	au!
	au BufReadCmd   gemini://*	exe "sil doau BufReadPre ".fnameescape(expand("<amatch>"))|call s:read_gemini(expand("<amatch>"))|exe "sil doau BufReadPost ".fnameescape(expand("<amatch>"))
	au FileReadCmd  gemini://*	exe "sil doau FileReadPre ".fnameescape(expand("<amatch>"))|call s:read_gemini(expand("<amatch>"))|exe "sil doau FileReadPost ".fnameescape(expand("<amatch>"))
aug END
