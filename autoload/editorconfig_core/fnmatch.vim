vim9script noclear

import autoload './util.vim'

# autoload/editorconfig_core/fnmatch.vim: Globbing for
# editorconfig-vim.  Ported from the Python core's fnmatch.py.

# Copyright (c) 2012-2019 EditorConfig Team {{{1
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE. }}}1

#Filename matching with shell patterns.
#
#fnmatch(FILENAME, PATH, PATTERN) matches according to the local convention.
#fnmatchcase(FILENAME, PATH, PATTERN) always takes case in account.
#
#The functions operate by translating the pattern into a regular
#expression.  They cache the compiled regular expressions for speed.
#
#The function translate(PATTERN) returns a regular expression
#corresponding to PATTERN.  (It does not compile it.)

# variables {{{1
if !exists('g:editorconfig_core_vimscript_debug')
    g:editorconfig_core_vimscript_debug = false
endif
# }}}1
# === Regexes =========================================================== {{{1
const LEFT_BRACE: string = '\v[\\]@8<!\{'
# 8 is an arbitrary byte-count limit to the lookbehind (micro-optimization)
#LEFT_BRACE = re.compile(
#    r"""
#
#    (?<! \\ ) # Not preceded by "\"
#
#    \{                  # "{"
#
#    """, re.VERBOSE
#)

const RIGHT_BRACE: string = '\v[\\]@8<!\}'
# 8 is an arbitrary byte-count limit to the lookbehind (micro-optimization)
#RIGHT_BRACE = re.compile(
#    r"""
#
#    (?<! \\ ) # Not preceded by "\"
#
#    \}                  # "}"
#
#    """, re.VERBOSE
#)

const NUMERIC_RANGE: string = '\v([+-]?\d+)' .. '\.\.' .. '([+-]?\d+)'
#NUMERIC_RANGE = re.compile(
#    r"""
#    (               # Capture a number
#        [+-] ?      # Zero or one "+" or "-" characters
#        \d +        # One or more digits
#    )
#
#    \.\.            # ".."
#
#    (               # Capture a number
#        [+-] ?      # Zero or one "+" or "-" characters
#        \d +        # One or more digits
#    )
#    """, re.VERBOSE
#)
#
# }}}1
# === Internal functions ================================================ {{{1

# Dump the bytes of text.  For debugging use.
def Dump_bytes(text: string)
    var idx: number
    while idx < strlen(text)
        var byte_val: number = text[idx]->char2nr()
        echomsg printf('%10s%-5d%02x %s', '', idx, byte_val, text[idx])
        ++idx
    endwhile
enddef #Dump_bytes

# Dump the characters of text and their codepoints.  For debugging use.
def Dump_chars(text: string)
    var out1: string
    var out2: string
    for char: string in text
        out1 ..= printf('%5s', char)
        out2 ..= printf('%5x', char2nr(char))
    endfor

    echomsg out1
    echomsg out2
enddef #Dump_chars

# }}}1
# === Translating globs to patterns ===================================== {{{1

# Escaper for very-magic regexes
def Re_escape(text: string): string
    # Backslash-escape any character below U+0080;
    # replace all others with a %U escape.
    # See https://vi.stackexchange.com/a/19617/1430 by yours truly
    # (https://vi.stackexchange.com/users/1430/cxw).

    return text
        ->substitute('\v([^0-9a-zA-Z_])',
            (m: list<string>): string => m[1]->char2nr() >= 128
            ? printf('%%U%08x', m[1]->char2nr())
            : '\' .. m[1],
            'g'
        )
enddef

#def translate(pat, nested=0):
#    Translate a shell PATTERN to a regular expression.
#    There is no way to quote meta-characters.
export def Translate(_pat: string, nested = false): list<any>
    if g:editorconfig_core_vimscript_debug
        echomsg '- fnmatch#translate: pattern ' .. _pat
        echomsg printf('- %d chars', _pat->substitute('.', 'x', 'g')->strlen())
        Dump_chars(_pat)
    endif

    var pat: string = _pat   # TODO remove if we wind up not needing this

    # Note: the Python sets MULTILINE and DOTALL, but Vim has \_.
    # instead of DOTALL, and \_^ / \_$ instead of MULTILINE.

    var is_escaped: bool

    # Find out whether the pattern has balanced braces.
    var left_braces: list<number>
    var right_braces: list<number>
    substitute(pat, LEFT_BRACE, '\=!!add(left_braces, 1)', 'g')
    substitute(pat, RIGHT_BRACE, '\=!!add(right_braces, 1)', 'g')
    # Thanks to http://jeromebelleman.gitlab.io/posts/productivity/vimsub/
    var matching_braces: bool = (len(left_braces) == len(right_braces))

    # Unicode support (#2).  Indexing pat[index] returns bytes, per
    # https://github.com/neovim/neovim/issues/68#issue-28114985 .
    # Instead, use split() per vimdoc to break the input string into an
    # array of *characters*, and process that.
    var characters: list<string> = split(_pat, '\zs')

    var index: number     # character index
    var length: number = len(characters)
    var brace_level: number
    var in_brackets: bool

    var result: string
    var numeric_groups: any = []

    while index < length
        var current_char: string = characters[index]
        ++index

        #         if g:editorconfig_core_vimscript_debug
        #             echomsg ' - fnmatch#translate: ' .. current_char .. '@' ..
        #                 (index - 1) .. '; result ' .. result
        #         endif

        var pos: number
        if current_char == '*'
            pos = index
            if pos < length && characters[pos] == '*'
                result ..= '\_.*'
                ++index    # skip the second star
            else
                result ..= '[^/]*'
            endif

        elseif current_char == '?'
            result ..= '\_[^/]'

        elseif current_char == '['
            if in_brackets
                result ..= '\['
            else
                pos = index
                var has_slash: bool
                while pos < length && characters[pos] != ']'
                    if characters[pos] == '/' && characters[pos - 1] != '\'
                        has_slash = true
                        break
                    endif
                    ++pos
                endwhile
                if has_slash
                    # POSIX IEEE 1003.1-2017 sec. 2.13.3: '/' cannot occur
                    # in a bracket expression, so [/] matches a literal
                    # three-character string '[' . '/' . ']'.
                    result ..= '\['
                        .. characters[index : pos - 1]->join('')->Re_escape()
                        .. '\/'
                        # escape the slash
                    index = pos + 1
                        # resume after the slash
                else
                    if index < length && characters[index] =~ '\v%(\^|\!)'
                        ++index
                        result ..= '[^'
                    else
                        result ..= '['
                    endif
                    in_brackets = true
                endif
            endif

        elseif current_char == '-'
            if in_brackets
                result ..= current_char
            else
                result ..= '\' .. current_char
            endif

        elseif current_char == ']'
            if in_brackets && !is_escaped
                result ..= ']'
                in_brackets = false
            elseif is_escaped
                result ..= '\]'
                is_escaped = false
            else
                result ..= '\]'
            endif

        elseif current_char == '{'
            pos = index
            var has_comma: bool
            while pos < length && (characters[pos] != '}' || is_escaped)
                if characters[pos] == ',' && ! is_escaped
                    has_comma = true
                    break
                endif
                is_escaped = characters[pos] == '\' && ! is_escaped
                ++pos
            endwhile
            if !has_comma && pos < length
                var num_range: list<string> = characters[index : pos - 1]
                    ->join('')
                    ->matchlist(NUMERIC_RANGE)
                if len(num_range) > 0     # Remember the ranges
                    numeric_groups
                        ->add([num_range[1]->str2nr(), num_range[2]->str2nr()])
                    result ..= '([+-]?\d+)'
                else
                    var inner_xlat: list<any> = characters[index : pos - 1]
                        ->join('')
                        ->Translate(true)
                    var inner_result: string = inner_xlat[0]
                    var inner_groups: number = inner_xlat[1]
                    result ..= '\{' .. inner_result .. '\}'
                    numeric_groups += inner_groups
                endif
                index = pos + 1
            elseif matching_braces
                result ..= '%('
                ++brace_level
            else
                result ..= '\{'
            endif

        elseif current_char == ','
            if brace_level > 0 && ! is_escaped
                result ..= '|'
            else
                result ..= '\,'
            endif

        elseif current_char == '}'
            if brace_level > 0 && ! is_escaped
                result ..= ')'
                --brace_level
            else
                result ..= '\}'
            endif

        elseif current_char == '/'
            if characters[index : (index + 2)]->join('') == '**/'
                result ..= '%(/|/\_.*/)'
                index += 3
            else
                result ..= '\/'
            endif

        elseif current_char != '\'
            result ..= Re_escape(current_char)
        endif

        if current_char == '\'
            if is_escaped
                result ..= Re_escape(current_char)
            endif
            is_escaped = ! is_escaped
        else
            is_escaped = false
        endif

        if current_char == '\'
            if is_escaped
                result ..= Re_escape(current_char)
            endif
            is_escaped = !is_escaped
        else
            is_escaped = false
        endif

    endwhile

    if !nested
        result ..= '\_$'
    endif

    return [result, numeric_groups]
enddef # Translate

var _cache: dict<list<any>>
def Cached_translate(pat: string): list<any>
    if !has_key(_cache, pat)
        #regex = re.compile(res)
        _cache[pat] = Translate(pat)
            # we don't compile the regex
    endif
    writefile([_cache->typename()], '/tmp/typename/_cache', 'a')
    return _cache[pat]
enddef # Cached_translate

# }}}1
# === Matching functions ================================================ {{{1

export def Fnmatch(name: string, _path: string, _pattern: string): number
#def fnmatch(name, pat):
#    """Test whether FILENAME matches PATH/PATTERN.
#
#    Patterns are Unix shell style:
#
#    - ``*``             matches everything except path separator
#    - ``**``            matches everything
#    - ``?``             matches any single character
#    - ``[seq]``         matches any character in seq
#    - ``[!seq]``        matches any char not in seq
#    - ``{s1,s2,s3}``    matches any of the strings given (separated by commas)
#
#    An initial period in FILENAME is not special.
#    Both FILENAME and PATTERN are first case-normalized
#    if the operating system requires it.
#    If you don't want this, use fnmatchcase(FILENAME, PATTERN).
#    """
#
    # Note: This throws away the backslash in '\.txt' on Cygwin, but that
    # makes sense since it's Windows under the hood.
    # We don't care about shellslash since we're going to change backslashes
    # to slashes in just a moment anyway.
    var localname: string = fnamemodify(name, ':p')

    var path: string
    var pattern: string
    if util.Is_win()      # normalize
        localname = localname
            ->tolower()
            ->substitute('\v\\', '/', 'g')
        path = _path
            ->tolower()
            ->substitute('\v\\', '/', 'g')
        pattern = tolower(_pattern)
    else
        localname = localname
        path = _path
        pattern = _pattern
    endif

    if g:editorconfig_core_vimscript_debug
        echomsg printf(
            '- fnmatch#fnmatch testing <%s> against <%s> wrt <%s>',
            localname,
            pattern,
            path
        )
    endif

    return Fnmatchcase(localname, path, pattern)
enddef # Fnmatch

export def Fnmatchcase(name: string, path: string, pattern: string): number
#def fnmatchcase(name, pat):
#    """Test whether FILENAME matches PATH/PATTERN, including case.
#
#    This is a version of fnmatch() which doesn't case-normalize
#    its arguments.
#    """
#
    var [regex: string, num_groups: list<any>] = Cached_translate(pattern)

    var escaped_path: string = Re_escape(path)
    regex = '\v' .. escaped_path .. regex

    if g:editorconfig_core_vimscript_debug
        echomsg '- fnmatch#fnmatchcase: regex    ' .. regex
        Dump_chars(regex)
        echomsg '- fnmatch#fnmatchcase: checking ' .. name
        Dump_chars(name)
    endif

    var match_groups: list<string> = matchlist(name, regex)[1 :]   # [0] = full match

    if g:editorconfig_core_vimscript_debug
        echomsg printf('  Got %d matches', len(match_groups))
    endif

    if len(match_groups) == 0
        return 0
    endif

    # Check numeric ranges
    # TODO(lgc): Why can't we use `true`?
    var pattern_matched: number = 1
    for idx: number in range(0, len(match_groups))
        var num: string = match_groups[idx]
        if num == ''
            break
        endif

        var [min_num: number, max_num: number] = num_groups[idx]
        if (min_num > num->str2nr()) || (num->str2nr() > max_num)
            pattern_matched = 0
            break
        endif

        # Reject leading zeros without sign.  This is very odd ---
        # see editorconfig/editorconfig#371.
        if match(num, '\v^0') != -1
            pattern_matched = 0
            break
        endif
    endfor

    if g:editorconfig_core_vimscript_debug
        echomsg '- fnmatch#fnmatchcase: ' .. (pattern_matched ? 'matched' : 'did not match')
    endif

    return pattern_matched
enddef # Fnmatchcase

# }}}1
# === Copyright notices ================================================= {{{1
# Based on code from fnmatch.py file distributed with Python 2.6.
# Portions Copyright (c) 2001-2010 Python Software Foundation;
# All Rights Reserved.  Licensed under PSF License (see LICENSE.PSF file).
#
# Changes to original fnmatch:
#
# - translate function supports ``*`` and ``**`` similarly to fnmatch C library
# }}}1

# vi: set fdm=marker:
