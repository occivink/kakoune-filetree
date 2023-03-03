declare-option -docstring "Name of the client in which all source code jumps will be executed" str jumpclient
declare-option -docstring "name of the client in which utilities display information" str toolsclient

declare-option -hidden str filetree_script_path %val{source}

declare-option -hidden bool filetree_highlight_dirty
declare-option -hidden str filetree_directory
declare-option -hidden range-specs filetree_open_files

declare-option int filetree_indentation_level 3

face global FileTreeOpenFiles black,yellow
face global FileTreePipesColor rgb:909090,default
face global FileTreeDirColor blue,default+b
face global FileTreeFileName default,default

define-command filetree-switch-or-start -params .. -docstring "
Switch to the *filetree* buffer.
If the *filetree* buffer does not exist, or the kakoune directory has changed,
it is generated from scratch.
" %{
    try %{
        eval -try-client %opt{toolsclient} %{
            buffer *filetree*
            eval %sh{ [ "$kak_opt_filetree_directory" != "$(pwd)" ] && printf 'fail' }
        }
    } catch %{
        filetree %arg{@}
    }
}

define-command filetree -params .. -docstring '
' %{
    eval -save-regs 't' %{
        # TODO relative dirs
        try %{ delete-buffer *filetree* }
        set-register t %sh{
            fifo=$(mktemp -u)
            mkfifo "$fifo"
            perl_script="${kak_opt_filetree_script_path%/*}/filetree.perl"
            # TODO args
            # -dirs-first
            # -files-first
            # -consider-gitignore
            # -max-depth
            # -no-empty-dirs
            # $kak_opt_filetree_indentation_level
            (tree -p --filesfirst | perl "$perl_script" 'process' > "$fifo") < /dev/null > /dev/null 2>&1 &
            printf '%s' "$fifo"
        }
        edit -fifo %reg{t} *filetree*
        set-option buffer filetree_directory %sh{ pwd }
        hook -always -once buffer BufCloseFifo .* "nop %%sh{ rm '%reg{t}' }; exec ged; filetree-refresh-files-highlight"

        # highlight tree part
        add-highlighter buffer/ regex '^([│├──└ ]+) ' 1:FileTreePipesColor
        # highlight directories (using the /)
        add-highlighter buffer/ regex '^([│├──└ ]+ )?([^\n]*?)/$' 2:FileTreeDirColor
        add-highlighter buffer/ regex '^([│├──└ ]+ )([^\n/]*?)$' 2:FileTreeFileName
        add-highlighter buffer/ ranges filetree_open_files

        map buffer normal <ret> ': filetree-open-files<ret>'
        map buffer normal <a-up> ': filetree-select-prev-sibling<ret>'
        map buffer normal <a-down> ': filetree-select-next-sibling<ret>'
        map buffer normal <a-left> ': filetree-select-parent-dir<ret>'
        map buffer normal <a-right> ': filetree-select-first-child<ret>'
    }
}

define-command filetree-select-open-files %{
    eval echo -debug -- -timestamp %sh{
        eval set -- $kak_opt_filetree_open_files
        printf '''%s''' "$1"
        shift
        for val do
            printf ' ''%s''' "${val%|*}"
        done
    }
}

define-command filetree-create-file %{
}

define-command filetree-create-directory %{
}

define-command filetree-select-parent-dir %{
    eval -itersel %{
        try %{
            # TODO top parent is not always ./
            exec -draft ';x<a-K>^./\n<ret>'
        } catch %{
            fail 'Already at top parent'
        }
        try %{
            exec ';x1s(^[│ ]+)[└├]─* <ret>'
            exec "<a-/>^(?!%val{selection})([^\n]*?)/$<ret>"
            filetree-select-path-component
        } catch %{
            exec ggxH
        }
    }
}

define-command filetree-select-next-sibling %{
    eval -itersel -save-regs '/' %{
        exec ';x'
        exec '1s^([ │]*)[└├]<ret>'
        try %{
            exec '<a-k>\A[└├]\z<ret>'
            reg slash "\n(([^\n]*\n)*?(^[└├]))?"
        } catch %{
            reg slash "\n((^%val{selection}[^\n]*\n)*?(^%val{selection}[└├]))?"
        }
        exec 'gh/<ret>'
        exec '<a-K>\A\n\z<ret>' # if we didn't match anything, fail
        exec ';'
        filetree-select-path-component
    }
}
define-command filetree-select-prev-sibling %{
    eval -itersel -save-regs '/' %{
        exec ';x'
        exec '1s^([ │]*)[└├]<ret>'
        try %{
            exec '<a-k>\A[└├]\z<ret>'
            reg slash "((^├[^\n]*\n)(^[^\n]*\n)*?)?^."
        } catch %{
            reg slash "((^%val{selection}├[^\n]*\n)(^%val{selection}[^\n]*\n)*?)?^."
        }
        exec 'gl<a-/><ret>'
        exec '<a-K>\A^.\z<ret>' # if we didn't match anything, fail
        exec '<a-;>;'
        filetree-select-path-component
    }
}

define-command filetree-select-first-child %{
    eval -itersel %{
        exec ';x'
        exec -draft '<a-k>/$<ret>'
        try %{
            exec -draft 'ghHs\A.\z<ret>'
            exec 'j'
        } catch %{
            exec 's^[ │]*[└├]─* <ret>'
            exec "jx<a-k>\A^[│ ]{%val{selection_length}}<ret>"
        }
        filetree-select-path-component
    }
}

define-command -hidden filetree-open-file %{
    eval -save-regs 'p' %{
        eval -draft %{
            exec ','
            reg p %val{selection}
            try %{
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
                filetree-select-parent-dir; reg p "%val{selection}%reg{p}"
            }
        }
        edit -existing %reg{p}
    }
}

define-command filetree-open-files %{
    filetree-select-path-component
    exec '<a-K>/\z<ret>'
    try %{
        # open all non-main selections in a draft context
        eval -draft %{
            exec '<a-,>'
            eval -itersel %{ eval -draft filetree-open-file }
        }
    }
    filetree-open-file
}

define-command filetree-select-path-component %{
    exec ';x1s^[│├─└ ]+ ([^\n]*)$<ret>'
}

hook global WinDisplay '^\*filetree\*$' %{
    try %{
        eval %sh{ [ "$kak_opt_filetree_highlight_dirty" = 'false' ] && printf 'fail' }
        filetree-refresh-files-highlight
        set global filetree_highlight_dirty false
    }
}

hook global BufCreate .* %{ set global filetree_highlight_dirty true }
hook global BufClose  .* %{ set global filetree_highlight_dirty true }

define-command filetree-refresh-files-highlight %{
    try %{
        eval -draft -buffer *filetree* %{
            eval select %sh{
                # $kak_quoted_buflist
                script="${kak_opt_filetree_script_path%/*}/filetree.perl"
                echo "write '$kak_response_fifo'" > "$kak_command_fifo"
                perl "$script" 'match-buffers' < "$kak_response_fifo"
            }
            filetree-select-path-component

            set-option buffer filetree_open_files %val{timestamp}
            eval -no-hooks -draft -itersel %{
                set -add buffer filetree_open_files "%val{selection_desc}|FileTreeOpenFiles"
            }
        }
    }
}

define-command filetree-edit -params 1.. -docstring "
Edit the specified file. The completions are provided by the *filetree* buffer.
" %{
    edit %arg{@}
}

complete-command -menu filetree-edit shell-script-candidates %{
    echo "try %{ eval -buffer *filetree* %{ write '$kak_response_fifo' } } catch %{ echo -to-file '$kak_response_fifo' '' }" > "$kak_command_fifo"
    perl "${kak_opt_filetree_script_path%/*}/filetree.perl" 'flatten' < "$kak_response_fifo"
}

