# bash completion for commands repo scripts. Needs bash-completion.

# Complete options when the word starts with "-". Otherwise leave COMPREPLY
# empty, so "complete -o default" falls back to file name completion.
_commands_complete_options() {
  # shellcheck disable=SC2034 # _init_completion sets these.
  local cur prev words cword option
  _init_completion || return
  COMPREPLY=()
  [[ "$cur" == -* ]] || return 0
  while IFS= read -r option; do
    COMPREPLY+=("$option")
  done < <(compgen -W "$1" -- "$cur")
}

_llm_copy_sh_completion() {
  _commands_complete_options "--string --save-path --ignore-gitignore --allow-sensitive --help -h"
}

_llm_git_diff_sh_completion() {
  _commands_complete_options "--save-path --exclude-untracked --string --help -h --"
}

_git_clean_branches_sh_completion() {
  _commands_complete_options "--dry-run -n --help -h"
}

_commands_help_only_completion() {
  _commands_complete_options "--help -h"
}

complete -o default -F _llm_copy_sh_completion llm_copy.sh
complete -o default -F _llm_git_diff_sh_completion llm_git_diff.sh
complete -o default -F _git_clean_branches_sh_completion git_clean_branches.sh
complete -o default -F _commands_help_only_completion multitail.sh clear_notebook_outputs.sh
