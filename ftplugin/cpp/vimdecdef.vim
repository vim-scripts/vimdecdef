map <buffer> <unique> <Plug>vimdecdef :call <SID>VimDecDef()<CR>

if !exists("b:buddyFile")
	let b:buddyFile = ''
endif

let b:goBack = 0

if exists("*s:GetScope")
	finish
endif

if !exists("g:vimdecdefSourceExtension")
	let g:vimdecdefSourceExtension = "cpp"
endif

if !exists("g:vimdecdefSourcePrefix")
	let g:vimdecdefSourcePrefix = "src/"
endif

function! s:GetScope()
	let lineNo = line('.')
	let colNo = col('.')
	let scope = ''
	let templateArgs = ''
	while 1
		if searchpair('{', '', '}', 'bW', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\\|comment"') > 0
			call setpos('.', [0, line('.') - 1, 1, 0])
			let template = ''
			if search('template<.', 'cWe', line('.')) != 0
				let template = s:ParseArguments()
				let templateArgs = template . ', ' . templateArgs
				let template = '<' . s:DropTypes(template) . '>'
			endif
			let tmpScope = matchstr(strpart(getline('.'), col('.') - 1), '\(class\|namespace\|struct\)\s\+\zs[a-zA-Z_][a-zA-Z0-9_]*')
			if tmpScope == ''
				call setpos('.', [0, lineNo, colNo, 0])
				return [ '-INVALID-', '' ]
			endif
			let scope = tmpScope . template . '::' . scope
		else
			break
		endif
	endwhile
	
	call setpos('.', [0, lineNo, colNo, 0])

	return [ scope, strpart(templateArgs, 0, strlen(templateArgs) - 2) ]
endfunction

function! s:CheckClass()
	let lineNo = line('.')
	let colNo = col('.')
	let retVal = 0
	if searchpair('{', '', '}', 'bW', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\\|comment"') > 0
		call setpos('.', [0, line('.') - 1, 1, 0])
		if search('\(class\|struct\)\s\+\zs[a-zA-Z_][a-zA-Z0-9_]*', 'cW', line('.')) > 0
			let retVal = 1
		endif
	endif
	call setpos('.', [0, lineNo, colNo, 0])
	return retVal
endfunction

function! s:ParseDeclaration()
	normal 1|

	let retVal = [ 0, 0, 'type', 'identifier', '' ]

	if matchstr(getline('.'), '.\%>' . ( match(getline('.'), '[;{]') + 1 ) . 'c') != ';'
		return retVal
	endif
	
	let scope = s:GetScope()

	if scope[0] == '-INVALID-'
		return retVal
	endif

	if search('template<.', 'cWe', line('.')) != 0
		let retVal[4] = s:ParseArguments() 
		let retVal[1] = 1
		if scope[1] != ''
			let retVal[4] = scope[1] . ', ' . retVal[4]
		endif
	elseif scope[1] != ''
		let retVal[1] = 1
		let retVal[4] = scope[1]
	endif

	let modifiers = ''
	let modifiersStart = -1
	if search('\(\(inline\|static\|virtual\|explicit\|friend\|extern\)\s\+\)\+', 'cW', line('.'))
		let modifiersStart = col('.') - 1
		call search('\(\(inline\|static\|virtual\|explicit\|friend\|extern\)\s\+\)\+', 'cWe', line('.'))
		call search('\h\s', 'Wbec', line('.'))
		let modifiers = strpart(getline('.'), modifiersStart, col('.') - modifiersStart - 1)
	endif
	call search('[a-zA-Z_~]', 'Wc', line('.'))

	if match(modifiers, 'friend') != -1
		return [ 0, 0, 'type', 'identifier', '' ]
	endif

	let typeStart = col('.') - 1

	let operators = '+\|++\|+=\|-\|--\|-=\|\*\|\*=\|/\|/=\|%\|%=\|<\|<=\|>\|>=\|!=\|==\|!\|&&\|||\|<<\|<<=\|>>\|>>=\|\~\|&\|&=\||\||=\|^\|^=\|=\|()\|\[\]\|\*\|&\|->\|->\*\|[a-zA-Z_][a-zA-Z0-9_]\+\|,\|new\|new\s*\[\]\|delete\|delete\s*\[\]\|'
	let functionMatch = '\(operator\s*\(' . operators . '\)\|[a-zA-Z_~][a-zA-Z0-9_]*\)\s*('
	
	if search(functionMatch, 'cW', line('.')) && synIDattr(synID(line("."), col("."), 0), "name") !~? "comment\\|string"
		let retVal[0] = 1
		if match(modifiers, 'inline') != -1
			let retVal[1] = 1
		endif

		let identifierStart = col('.') - 1

		call search('[^\S]\s', 'Wbe', line('.'))
		let retVal[2] = strpart(getline('.'), typeStart, col('.') - typeStart - 1)

		call search(functionMatch . '.', 'cWe', line('.'))
		let retVal[3] = scope[0] . strpart(getline('.'), identifierStart, col('.') - identifierStart - 2)

		let retVal[3] = retVal[3] . '(' . s:ParseArguments() . ')'

		if search('const', 'W', line('.'))
			let retVal[3] = retVal[3] . ' const'
		endif

		if search('=0', 'W', line('.'))
			return [ 0, 0, 'type', 'identifier', '' ]
		endif

	elseif search('[a-zA-Z_][a-zA-Z0-9_]*\(\[\]\)\==\=[0-9a-fA-Fx]*;', 'cW', line('.'))
		if match(modifiers, 'static') != -1 || s:CheckClass() == 0
			let retVal[0] = 2
		endif

		let identifierStart = col('.') - 1
		call search('[^\S]\s', 'Wbe', line('.'))
		let retVal[2] = strpart(getline('.'), typeStart, col('.') - typeStart - 1)
		call search('[a-zA-Z_][a-zA-Z0-9_]*\(\[\]\)\=\ze=\=[0-9a-fA-Fx]*;', 'cWe', line('.'))
		
		let retVal[3] = scope[0] . strpart(getline('.'), identifierStart, col('.') - identifierStart)
	endif

	return retVal
endfunction

function! s:ParseArguments()
	let argumentsStart = col('.') - 1
	call searchpair('[<(]', '', '[>)]', 'Wc', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "comment\\|string"')
	let argumentsEnd = col('.')
	let retVal = ''

	call setpos('.', [0, line('.'), argumentsStart, 0])
	while search('\s*=', 'W', line('.')) && col('.') <= argumentsEnd
		let retVal = retVal . strpart(getline('.'), argumentsStart, col('.') - argumentsStart - 1)
		call search('[,<()]', 'W', line('.') )
		if matchstr(getline('.'), '.\%>' . (col('.')) . 'c') =~ '[<(]'
			call setpos('.', [0, line('.'), col('.') + 1, 0])
			call searchpair('[(<]', '', '[)>]', 'Wc', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "comment\\|string"')
			call search('[),]', 'Wc', line('.'))
			let argumentsStart = col('.')
		else
			let argumentsStart = col('.') - 1
		endif
	endwhile
	let retVal = retVal . strpart(getline('.'), argumentsStart, argumentsEnd - argumentsStart - 1)
	call setpos('.', [0, line('.'), argumentsEnd, 0])

	return retVal
endfunction

function! s:DropTypes(arguments)
	let retVal = ''
	let pos = 0

	while 1
		let strng = matchstr(a:arguments, '[a-zA-Z_][a-zA-Z0-9_]*\ze\s*\(,\|$\)', pos)
		if strng == ''
			break
		else
			let pos = match(a:arguments, '[a-zA-Z_][a-zA-Z0-9_]*\s*\zs\(,\|$\)', pos)
			let retVal = retVal . ', ' . strng
		endif
	endwhile

	return strpart(retVal, 2)
endfunction

function! s:SwapDecDef()
	let declaration = s:ParseDeclaration()
	let headerFileName =  expand("%:.")

	if declaration[0] != 0
		if declaration[1] == 1
			silent exec 'e ' . fnameescape(s:GetBuddyFile())
			let b:buddyFile = headerFileName
			call s:GotoOrDropBack(declaration[3], declaration[2], declaration[4], declaration[0])
		else
			silent exec 'e ' . fnameescape(s:GetBuddyFile())
			let b:buddyFile = headerFileName
			call s:GotoOrCreate(declaration[3], declaration[2], declaration[4], declaration[0])
		endif
	else
		silent exec 'e ' . fnameescape(s:GetBuddyFile())
		let b:buddyFile = headerFileName
		echo 'Switching to source file (' . expand("%:.") . ')'
	endif
endfunction

function! s:CheckForDefinition(identifier, template)
	let lineNo = line('.')
	let colNo = col('.')
	call cursor(1, 1)

	let searchPattern = a:identifier
	if a:template != ''
		let searchPattern = 'template<' . a:template . '> \.\*' . searchPattern
	endif

	let retVal = search('\V' . searchPattern . '\m\([^a-zA-Z0-9_]\|$\)', 'W')

	call cursor(lineNo, colNo)

	return retVal
endfunction

function! s:GotoOrDropBack(identifier, type, template, brackets)
	let lineNo = s:CheckForDefinition(a:identifier, a:template)

	if lineNo > 0
		silent exec lineNo
		silent normal zz
		echo 'Found inline/template definition in source file (' . expand("%:.") . ')'
	else
		silent exec 'e ' . b:buddyFile
		call s:GotoOrCreate(a:identifier, a:type, a:template, a:brackets)
	endif
endfunction

function! s:GotoOrCreate(identifier, type, template, brackets)
	if expand("%:e") != g:vimdecdefSourceExtension
		let b:goBack = line('.')
	endif
	let lineNo = s:CheckForDefinition(a:identifier, a:template)

	if lineNo == 0
		let definition = a:identifier
		if a:type != ''
			let definition = a:type . ' ' . definition
		endif
		if a:template != ''
			let definition = 'template<' . a:template . '> ' . definition
		endif
		let lineNo = line('$')
		let addEndIf = 0
		if getline(lineNo) == '#endif'
			let addEndIf = 1
		else
			let lineNo = lineNo + 2
		endif
		call setline(lineNo - 1, '')
		call setline(lineNo, definition)
		if a:brackets == 1
			call setline(lineNo + 1, '{')
			call setline(lineNo + 2, '}')
		endif
		if addEndIf == 1
			call setline(lineNo + 3, '')
			call setline(lineNo + 4, '#endif')
		endif

		if b:goBack != 0
			echo 'Adding definition to header file (' . expand("%:.") . ')'
		else
			echo 'Adding definition to source file (' . expand("%:.") . ')'
		endif
	else
		if b:goBack != 0
			echo 'Found definition in header file (' . expand("%:.") . ')'
		else
			echo 'Found definition in source file (' . expand("%:.") . ')'
		endif
	endif

	silent exec lineNo
	silent normal zz
endfunction

function! s:GetBuddyFile()
	return g:vimdecdefSourcePrefix . expand("%:t:r") . '.' . g:vimdecdefSourceExtension
endfunction

function! s:VimDecDef()
	if expand("%:e") == g:vimdecdefSourceExtension
		silent exec 'e ' . b:buddyFile
		echo 'Returning to header file (' . expand("%:.") . ')'
	elseif b:goBack != 0
		silent exec b:goBack
		let b:goBack = 0
		silent normal zz
		echo 'Returning to declaration section of header file (' . expand("%:.") . ')'
	else
		call s:SwapDecDef()
	endif
endfunction
