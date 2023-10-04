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
face global FileTreeEmptyName black,red

define-command filetree-switch-or-start -params .. -docstring '
filetree-switch-or-start: switch to the *filetree* buffer.
If the buffer does not exist, or the current kakoune directory has changed, it is generated from
scratch. In this case, all arguments are forwarded to the ''filetree'' command.
' -shell-script-candidates %{
    printf '%s\n' -files-first -dirs-first -consider-gitignore -no-empty-dirs -show-hidden -depth './' */
} %{
    try %{
        eval -try-client %opt{toolsclient} %{
            buffer *filetree*
            eval %sh{ [ "$kak_opt_filetree_root_directory" != "$PWD" ] && printf 'fail' }
        }
    } catch %{
        filetree %arg{@}
    }
}

define-command filetree -params .. -docstring '
filetree [<switches>] [<directory>]: open an interactive buffer representing the current directory
Switches:
    -files-first: for each level, show files before directories
    -dirs-first: for each level, show directories before files
    -consider-gitignore: do not show any entries matched by gitignore rules
    -no-empty-dirs: do not show empty directories
    -show-hidden: show hidden files and directories
    -depth <DEPTH>: only traverse the root directory up to <DEPTH> directories deep (unlimited by default)
    -only-dirs: only show directories, not files
    -no-report: do not show footer after the tree
' -shell-script-candidates %{
    printf '%s\n' -files-first -dirs-first -consider-gitignore -no-empty-dirs \
    -show-hidden -depth -only-dirs -no-report './' */
} %{
    eval -save-regs 't' %{
        eval %sh{
            sorting=''
            prune=''
            gitignore=''
            depth=''
            directory=''
            hidden=''
            only_dirs=''
            no_report=''

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
                    elif [ "$arg" = '-only-dirs' ]; then
                        only_dirs="-P '*/'"
                    elif [ "$arg" = '-no-report' ]; then
                        no_report="--noreport"
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
            if [ ! -d "$directory" ]; then
                printf "fail \"Directory '%%arg{%s}' does not exist\"" "$arg_num"
                exit 1
            fi
            fifo=$(mktemp -u)
            mkfifo "$fifo"
            # $kak_opt_filetree_indentation_level <- need to let the script access this var
            perl_script="${kak_opt_filetree_script_path%/*}/filetree.perl"
            (tree -p -v $only_dirs $no_report $hidden $sorting $prune $gitignore $depth "$directory" | perl "$perl_script" 'process' > "$fifo") < /dev/null > /dev/null 2>&1 &
            printf "set-register t '%s'" "$fifo"
        }
        try %{ delete-buffer *filetree* }
        set-option global filetree_highlight_dirty false

        edit -fifo %reg{t} *filetree*
        set-option buffer filetree_root_directory %sh{ printf '%s' "$PWD" }
        # put hook in double quotes to interpolate %reg{t}
        hook -always -once buffer BufCloseFifo .* "
            nop %%sh{ rm '%reg{t}' }
            exec ged
            set-option global filetree_highlight_dirty true
            filetree-refresh-files-highlight
        "

        # highlight tree part
        add-highlighter buffer/ regex '^[│ ]*[├└]─* ' 0:FileTreePipesColor
        # highlight directories (using the /)
        add-highlighter buffer/ regex '^(?:[│ ]*[├└]─* )?([^\n]*?)/$' 1:FileTreeDirColor
        add-highlighter buffer/ regex '^(?:[│ ]*[├└]─* )([^\n/]*?)$' 1:FileTreeFileName
        add-highlighter buffer/ regex '^(?:[│ ]*[├└]─* )(\n)' 1:FileTreeEmptyName
        add-highlighter buffer/ ranges filetree_open_files

        map buffer normal <ret> ': filetree-open-selected-files<ret>'
        map buffer normal <s-ret> ': filetree-open-selected-files -create<ret>'
        map buffer normal <a-up> ': filetree-select-prev-sibling<ret>'
        map buffer normal <a-down> ': filetree-select-next-sibling<ret>'
        map buffer normal <a-left> ': filetree-select-parent-directory<ret>'
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

define-command filetree-create-sibling %{
    # TODO handle root dir: forbid entirely?
    filetree-select-path-component
    try %{
        exec -draft '<a-k>/\z<ret>'
        exec 'xyP'
        exec -draft 'ghh/[├└]<ret>r├'
    } catch %{
        exec 'xyp'
        exec -draft 'ghh/[├└]<ret>r├<a-C><a-(>'
    }
    exec 'ghh/[├└]─* <ret>l'
    try %{ exec '<a-K>\n<ret>GLd' }
}

define-command filetree-create-child %{
    # TODO handle root dir
    filetree-select-path-component
    # fail if we're not on a directory
    try %{
        exec -draft '<a-k>/\z<ret>'
    } catch %{
        fail 'Cannot create child of a regular file'
    }
    exec 'xyp'                # copy line below
    exec 'ghh/[├└]─* <ret>'   # select end of pipe from the new line
    try %{ exec -draft 'l<a-K>\n<ret>GLd' } # remove filename
    exec 'yP'                 # copy-prepend it
    exec 'r<space><a-;>;k'    # replace it with space, and select the first character
    try %{
        exec '<a-k>├<ret>jr│' # select the one just above: if it's ├, turn into │
    } catch %{
        exec 'r└j'            # otherwise into └
    }
    exec '/[├└]<ret>'                 # select the real pipe connector
    try %{
        exec -draft 'j<a-k>[├└]<ret>' # and depending on whether it's the last child
        exec 'r├'                     # replace with ├
    } catch %{
        exec 'r└'                     # or └
    }
    exec 'gll'
}

define-command filetree-select-parent-directory -docstring '
filetree-select-next-sibling: in the *filetree* buffer, select the parent directory of the current element
' %{
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

define-command filetree-select-next-sibling -docstring '
filetree-select-next-sibling: in the *filetree* buffer, select the next element in the same directory
' %{
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
define-command filetree-select-prev-sibling -docstring '
filetree-select-prev-sibling: in the *filetree* buffer, select the previous element in the same directory
' %{
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

define-command filetree-select-first-child -docstring '
filetree-select-first-child: in the *filetree* buffer, select the first element in the selected directory
' %{
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

define-command filetree-select-direct-children -docstring '
filetree-select-direct-children: in the *filetree* buffer, select all elements in the selected directory
' %{
    eval -itersel -save-regs 'l' %{
        exec ';x'
        exec -draft '<a-k>/$<ret>'
        try %{
            exec -draft 'ghH<a-k>\A.\z<ret>'
            reg l '0'
            exec gh
        } catch %{
            exec 's^[ │]*[└├]─* <ret>'
            reg l %val{selection_length}
        }
        exec "gll/(^[│ ]{%reg{l}}[^\n]+\n)*|.<ret>"
        exec '<a-K>\A.\z<ret>'
        exec "<a-s><a-k>^[│ ]{%reg{l}}[└├]<ret>"
        filetree-select-path-component
    }
}

define-command filetree-select-all-children -docstring '
filetree-select-all-children: in the *filetree* buffer, select all elements which are descendents of the selected directory
' %{
    eval -itersel -save-regs 'l' %{
        exec ';x'
        exec -draft '<a-k>/$<ret>'
        try %{
            exec -draft 'ghH<a-k>\A.\z<ret>'
            reg l '0'
            exec gh
        } catch %{
            exec 's^[ │]*[└├]─* <ret>'
            reg l %val{selection_length}
        }
        exec "gll/(^[│ ]{%reg{l}}[^\n]*\n)*|.<ret>"
        exec '<a-K>\A.\z<ret>'
        exec '<a-s>'
        filetree-select-path-component
    }
}

define-command -hidden filetree-eval-on-fullpath -params 1 %{
    eval -save-regs 'p' %{
        eval -draft %{
            exec ','
            reg p %val{selection}
            try %{
                # TODO not exactly elegant
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
                filetree-select-parent-directory; reg p "%val{selection}%reg{p}"
            }
        }
        eval %arg{1}
    }
}

define-command -hidden filetree-open-selected-file -params ..1 %{
    filetree-eval-on-fullpath %sh{
        printf '%s' "try %{
            buffer %reg{p}
        } catch %{
            edit -existing %reg{p}
            reg e \"x%reg{e}\"
        } catch %{"
        if [ "$1" = '-create' ]; then
            printf '%s' "
                edit %reg{p}
                reg c \"x%reg{c}\"
            } catch %{"
        fi
        printf '%s' "reg f \"x%reg{f}\"
        }"
    }
}

define-command filetree-open-selected-files -params ..1 -docstring '
filetree-open-selected-files [-create]: open the files currently selected
' -shell-script-candidates %{
    printf "%s\n" '-create'
} %{
    eval -save-regs 'cef' %{
        reg e ''
        reg c ''
        reg f ''
        filetree-select-path-component
        exec '<a-K>/\z<ret>'
        try %{
            # open all non-main selections in a draft context
            eval -draft %{
                exec '<a-,>'
                eval -itersel %{ eval -draft -verbatim filetree-open-selected-file %arg{@} }
            }
        }
        filetree-open-selected-file %arg{@}
        eval %sh{
            # echo some "helpful" info
            num_opened="${#kak_reg_e}"
            num_created="${#kak_reg_c}"
            num_failed="${#kak_reg_f}"
            total=$(( num_opened + num_created + num_failed ))
            [ "$total" -eq 0 ] && exit

            str_opened="${num_opened} existing file"
            [ "$num_opened" -ne 1 ] && str_opened="${str_opened}s"
            str_created="${num_created} new file"
            [ "$num_created" -ne 1 ] && str_created="${str_created}s"
            str_failed="${num_failed} file"
            [ "$num_failed" -ne 1 ] && str_failed="${str_failed}s"

            printf "echo '"
            if [ "$num_opened" -eq "$total" ]; then
                printf "Opened %s" "$str_opened"
            elif [ "$num_created" -eq "$total" ]; then
                printf "Opened %s" "$str_created"
            elif [ "$num_failed" -eq "$total" ]; then
                printf "Failed to open %s" "$str_failed"
            elif [ "$num_failed" -eq 0 ]; then # opened + created
                printf "Opened %s, and %s" "$str_opened" "$str_created"
            elif [ "$num_created" -eq 0 ]; then # opened + failed
                printf "Opened %s, and failed to open %s" "$str_opened" "$str_failed"
            elif [ "$num_opened" -eq 0 ]; then # created + failed
                printf "Opened %s, and failed to open %s" "$str_created" "$str_failed"
            else
                printf "Opened %s, %s, and failed to open %s" "$str_opened" "$str_created" "$str_failed"
            fi
            printf "'"
        }
    }
}

define-command filetree-select-path-component %{
    exec ';x1s^[│ ]*[├└]─* (.*)\n<ret>'
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
                script="${kak_opt_filetree_script_path%/*}/filetree.perl"
                echo "write '$kak_response_fifo'" > "$kak_command_fifo"
                eval set -- "$kak_quoted_buflist"
                perl "$script" 'match-buffers' "$@" < "$kak_response_fifo"
            }
            filetree-select-path-component

            set-option buffer filetree_open_files %val{timestamp}
            eval -no-hooks -draft -itersel %{
                set -add buffer filetree_open_files "%val{selection_desc}|FileTreeOpenFiles"
            }
        }
    }
}

define-command filetree-edit -params 1.. -docstring '
filetree-edit: edit the specified files.
The completions are provided by the *filetree* buffer.
' %{
    edit %arg{@}
}

complete-command -menu filetree-edit shell-script-candidates %{
    echo "try %{ eval -buffer *filetree* %{ write '$kak_response_fifo' } } catch %{ echo -to-file '$kak_response_fifo' '' }" > "$kak_command_fifo"
    perl "${kak_opt_filetree_script_path%/*}/filetree.perl" 'flatten-nodirs' < "$kak_response_fifo"
}

define-command filetree-goto -params 1.. -docstring '
filetree-goto: select the specified path elements in the *filetree* buffer
' %{
    buffer *filetree*
    eval select %sh{
        script="${kak_opt_filetree_script_path%/*}/filetree.perl"
        echo "write '$kak_response_fifo'" > "$kak_command_fifo"
        perl "$script" 'match-buffers' "$@" < "$kak_response_fifo"
    }
    filetree-select-path-component
}

complete-command -menu filetree-goto shell-script-candidates %{
    echo "try %{ eval -buffer *filetree* %{ write '$kak_response_fifo' } } catch %{ echo -to-file '$kak_response_fifo' '' }" > "$kak_command_fifo"
    perl "${kak_opt_filetree_script_path%/*}/filetree.perl" 'flatten-all' < "$kak_response_fifo"
}

}

require-module filetree
