#compdef llm_copy.sh llm_git_diff.sh multitail.sh git_clean_branches.sh git_commit_separate.sh

case "$service" in
  llm_copy.sh)
    _values 'option' --string --save-path --ignore-gitignore --ignore_gitignore --help -h
    ;;
  llm_git_diff.sh)
    _values 'option' --save-path --exclude-untracked --string --help -h --
    ;;
  multitail.sh|git_clean_branches.sh|git_commit_separate.sh)
    _values 'option' --help -h
    ;;
esac
