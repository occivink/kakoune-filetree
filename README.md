# kakoune-filetree

[Kakoune](http://kakoune.org) plugin to view and navigate files, using `tree`.

[![Demo](https://asciinema.org/a/568907.png)](https://asciinema.org/a/568907)

## Setup

Add `filetree.kak` and `filetree.perl` to your `autoload` directory: `~/.config/kak/autoload/`, or source the kakoune file manually.
The two files must be in the same directory for the plugin to function.

The plugin has a dependency on `tree` as well as `perl`.

## Basic usage

Simply call `:filetree`. A new buffer will be open with all files found below the specified directory (Kakoune's current directory by default), presented in a tree-like structure.

From the `*filetree*` buffer, you can open files by pressing <kbd>Return</kbd> (calling the command `filetree-open-selected-files`).

The files that are open in buffers are highlighted with a special face.

## Navigation

The `filetree-edit` command can be used for opening files, using the fuzzy matching engine of Kakoune. The completions are generated using the content of the `*filetree*` buffer: any file in the tree is proposed as a possible completion. This command can be used from any context, as long as the `*filetree*` buffer exists.

The following commands can be used to navigate the files and directories depending on their relationship:  
* `filetree-select-prev-sibling`: select next entry in the same directory as the selected entry (`<a-up>`)  
* `filetree-select-next-sibling`: select previous entry in the same directory as the selected entry (`<a-down>`)  
* `filetree-select-parent-directory`: select parent directory of the selected entry (`<a-left>`)  
* `filetree-select-first-child`: select first entry in the selected directory (`<a-right>`)  
* `filetree-select-direct-children`: select all entries directly in the selected directory  
* `filetree-select-all-children`: select all entries in all subdirectories of the selected directory  

The `filetree-select-open-files` command can be used to select all files currently opened in buffers.

## Manipulation

The `*filetree*` buffer can be modified by hand as long as the general tree-structure is preserved (for example, certain irrelevant files or directories can be filtered out by deleting the corresponding lines).

The `*filetree*` buffer supports limited manipulation of the filesystem with the commands `filetree-create-child` and `filetree-create-sibling`. 
Note that the two commands do not create the files themselves, they only adjust the buffer to keep the tree structure valid. The desired filename can then be typed out, and then opened with `filetree-open-selected-files -create`.

It is currently not possible (nor planned) to rename, move or delete files using this plugin.

## Customization

The `filetree` command offers various switches to control which files are shown in the tree and in which order.
* `-files-first`: for each level, show files before directories  
* `-dirs-first`: for each level, show directories before files  
* `-consider-gitignore`: do not show any entries matched by gitignore rules  
* `-no-empty-dirs`: do not show empty directories  
* `-show-hidden`: show hidden files and directories  
* `-depth <DEPTH>`: only traverse the root directory up to <DEPTH> directories deep (unlimited by default)  
* `-only-dirs`: only show directories, not files  

In addition, the following options and faces can be changed to affect the style of the tree:
* option `filetree_indentation_level`: number of padding characters for each depth level (>=0, default 3)  
* face `FileTreePipes`: used for the indentation lines of the tree (`rgb:606060,default`)  
* face `FileTreeDirName`: used for directories (`blue,default+b`)  
* face `FileTreeFileName`: used for files (`default,default`)  
* face `FileTreeOpenFiles`: used for files that have an open buffer (`black,yellow`)  
* face `FileTreeEmptyName`: used for highlighting empty (and therefore invalid) entries, such as when creating them (`default,red`)  

## License

[Unlicense](http://unlicense.org)
