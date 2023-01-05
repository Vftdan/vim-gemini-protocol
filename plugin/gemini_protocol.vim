if !has_key(g:, 'gemini_follow_redirects')
	" Do not set to false with the current gmni version
	" It doesn't output redirect header to stdout
	" Only use with submodule version
	let g:gemini_follow_redirects = v:true
endif
if !has_key(g:, 'gemini_max_redirects')
	let g:gemini_max_redirects = 5
endif
if !has_key(g:, 'gemini_gmni_command')
	let g:gemini_gmni_command = shellescape(get(split(globpath(&rtp, 'gmni/gmni'), '\n'), 0, 'gmni'))
endif
if !has_key(g:, 'gemini_connect_with')
	let g:gemini_connect_with = 'gmni'
endif

let s:url_regexp = '\v^[^:]+:\/\/%([^\@]+\@)?([^:\/]+)%(:(\d+))?%(\/.*)?$'

function! s:construct_command(url)
	if g:gemini_connect_with ==? 'gmni'
		return g:gemini_gmni_command . ' -j once -iN ' . (g:gemini_follow_redirects ? '-R ' . g:gemini_max_redirects . ' -L ' : '') . shellescape(a:url) . ' 2>/dev/null'
	endif

	let l:domain = substitute(a:url, s:url_regexp, '\1', '')
	let l:port = substitute(a:url, s:url_regexp, '\2', '')
	if l:port == ''
		let l:port = '1965'
	endif

	if g:gemini_connect_with ==? 'openssl'
		return 'echo ' . shellescape(a:url . "\r") . ' | openssl s_client -connect ' . shellescape(l:domain . ':' . l:port) . ' -quiet 2>/dev/null'
	endif

	if g:gemini_connect_with ==? 'ncat'
		return 'echo ' . shellescape(a:url) . ' | ncat -C --ssl --no-shutdown ' . shellescape(l:domain) . ' ' . shellescape(l:port)
	endif

	echoerr 'Gemini: invalid gemini_connect_with value: ' . shellescape(g:gemini_connect_with)
	return 'echo'
endfunction

let s:redirects = 0
function! s:read_gemini(url)
	let l:svpos = winsaveview()
	setlocal bl ro noswapfile bh=hide fenc=
	if &ft == ''
		setlocal ft=gmi
	else
		let &ft=&ft
	endif
	exe '%read ++bin !' . escape(s:construct_command(a:url), '%#\')
	keepjumps normal! ggJ
	let l:header = getline(1)
	let b:gemini_header = l:header
	keepjumps 1delete _
	keepjumps call winrestview(l:svpos)
	if l:header[0] == '3'
		let l:new_url = trim(l:header[3:])
		if has_key(g:, 'Gemini_redirect_function') && s:redirects < g:gemini_max_redirects
			let s:redirects += 1
			let l:new_url = g:Gemini_redirect_function(l:new_url)
			if type(l:new_url) == 1
				" String was returned
				0file
				exe 'file ' . fnameescape(l:new_url)
				return s:read_gemini(l:new_url)
			endif
		else
			" This plugin doesn't know, how to join urls,
			" '/...', '//...' are not handled properly by :find
			call append(0, '=> ' . l:new_url . ' Redirect')
		endif
		let s:redirects = 0
		return
	endif
	let s:redirects = 0
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
