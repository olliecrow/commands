#!/usr/bin/env bash
# Shared by the policy scanner and LLM bundle filter.
# shellcheck disable=SC2034 # Read by the scripts that source this file.
readonly KNOWN_TOKEN_REGEX='(^|[^A-Za-z0-9_-])((ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|sk-(ant-(oat01|api03|admin01)-|proj-|svcacct-|admin-)[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{3,}\.[A-Za-z0-9_-]{16,})'
