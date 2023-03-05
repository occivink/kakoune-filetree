declare-option -hidden str filetree_script_path %val{source}

provide-module filetree %{

declare-option -docstring "Name of the client in which all source code jumps will be executed" str jumpclient
declare-option -docstring "name of the client in which utilities display information" str toolsclient


declare-option -hidden bool filetree_highlight_dirty
declare-option -hidden str filetree_root_directory
declare-option -hidden range-specs filetree_open_files

declare-option int filetree_indentation_level 3

face global FileTreeOpenFiles black,yellow
face global FileTreePipesColor rgb:606060,default
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
            eval %sh{ [ "$kak_opt_filetree_root_directory" != "$(pwd)" ] && printf 'fail' }
        }
    } catch %{
        filetree %arg{@}
    }
}

define-command filetree -params .. -docstring '
filetree [<switches>] [directory]: TODO
Switches:
    -files-first: TODO
    -dirs-first: TODO
    -consider-gitignore: TODO
    -no-empty-dirs: TODO
    -show-hidden: TODO
    -depth: TODO
' -shell-script-candidates %{
    printf '%s\n' -files-first -dirs-first -consider-gitignore -no-empty-dirs -depth './' */
} %{
    eval -save-regs 't' %{
        eval %sh{
            sorting=''
            prune=''
            gitignore=''
            depth=''
            directory=''
            hidden=''

            arg_num=0
            accept_switch='y'
            while [ $# -ne 0 ]; do
                arg_num=$((arg_num + 1))
                arg=$1
                shift
                if [ $accept_switch = 'y' ]; then
                    got_switch='y'
                    if [ "$arg" = '-files-first' ]; then
                        sorting='--filesfirst'
                    elif [ "$arg" = '-dirs-first' ]; then
                        sorting='--dirsfirst'
                    elif [ "$arg" = '-no-empty-dirs' ]; then
                        prune='--prune'
                    elif [ "$arg" = '-show-hidden' ]; then
                        hidden='-a'
                    elif [ "$arg" = '-consider-gitignore' ]; then
                        gitignore='--gitignore'
                    elif [ "$arg" = '-depth' ]; then
                        if [ $# -eq 0 ]; then
                            echo 'fail "Missing argument to -depth"'
                            exit 1
                        fi
                        arg_num=$((arg_num + 1))
                        depth="-L $1"
                        shift
                    elif [ "$arg" = '--' ]; then
                        accept_switch='n'
                    else
                        got_switch='n'
                    fi
                    [ $got_switch = 'y' ] && continue
                fi
                if [ "$directory" != '' ]; then
                    printf "fail \"Unknown argument '%%arg{%s}'\"" "$arg_num"
                    exit 1
                elif [ "$arg" != '' ]; then
                    directory="$arg"
                else
                    printf "fail \"Invalid directory '%%arg{%s}'\"" "$arg_num"
                    exit 1
                fi
            done
            [ "$directory" = '' ] && directory='.'
            # strip trailing '/'
            while [ "$directory" != "${directory%/}" ]; do
                directory=${directory%/}
            done
            fifo=$(mktemp -u)
            mkfifo "$fifo"
            # $kak_opt_filetree_indentation_level <- need to let the script access this var
            perl_script="${kak_opt_filetree_script_path%/*}/filetree.perl"
            (tree -p $hidden $sorting $prune $gitignore $depth "$directory" | perl "$perl_script" 'process' > "$fifo") < /dev/null > /dev/null 2>&1 &
            printf "set-register t '%s'" "$fifo"
        }
        try %{ delete-buffer *filetree* }
        edit -fifo %reg{t} *filetree*
        set-option buffer filetree_root_directory %sh{ pwd }
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
    eval select -timestamp %sh{
        # TODO might not work with filenames containing '
        eval set -- "$kak_quoted_opt_filetree_open_files"
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
            exec -draft ';ghH<a-k>\n.<ret>'
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
        # TODO revisit when kakoune issue #4859 is fixed
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
            exec -draft 'ghH<a-k>\A.\z<ret>'
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
                # TODO not exactly elegant
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

define-command -hidden filetree-refresh-files-highlight %{
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
Edit the specified files. The completions are provided by the *filetree* buffer.
" %{
    edit %arg{@}
}

complete-command -menu filetree-edit shell-script-candidates %{
    echo "try %{ eval -buffer *filetree* %{ write '$kak_response_fifo' } } catch %{ echo -to-file '$kak_response_fifo' '' }" > "$kak_command_fifo"
    perl "${kak_opt_filetree_script_path%/*}/filetree.perl" 'flatten' < "$kak_response_fifo"
}

}

require-module filetree
