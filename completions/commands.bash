# bash completion for commands repo scripts

_llm_copy_sh_completion() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=( $(compgen -W "--string --save-path --ignore-gitignore --ignore_gitignore --help -h" -- "${cur}") )
}

_llm_git_diff_sh_completion() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=( $(compgen -W "--save-path --exclude-untracked --string --help -h --" -- "${cur}") )
}

_multitail_sh_completion() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
}

_git_clean_branches_sh_completion() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
}

_git_commit_separate_sh_completion() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
}

complete -F _llm_copy_sh_completion llm_copy.sh
complete -F _llm_git_diff_sh_completion llm_git_diff.sh
complete -F _multitail_sh_completion multitail.sh
complete -F _git_clean_branches_sh_completion git_clean_branches.sh
complete -F _git_commit_separate_sh_completion git_commit_separate.sh
