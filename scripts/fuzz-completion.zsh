# Tab completion for scripts/fuzz (zsh). Load it from ~/.zshrc:
#   source /path/to/BETTER-G2FUZZ/scripts/fuzz-completion.zsh
# Campaign names come from eval/, filtered to the ones each command can use.

(( $+functions[compdef] )) || { autoload -Uz compinit && compinit; }

_FUZZ_EVAL=${${(%):-%x}:A:h:h}/eval

_fuzz() {
  local -a cmds all fuzzed seeded names
  cmds=(
    'new:create a campaign folder'
    'reuse:new campaign with seeds and generators from another'
    'run:background run (seed generation if needed, then fuzz)'
    'shell:interactive container in a campaign'
    'watch:live view of a campaign'
    'status:one campaign'"'"'s numbers once'
    'results:final summary of a campaign'
    'stop:stop and remove a container'
    'list:all campaigns'
    'help:show usage'
  )
  if (( CURRENT == 2 )); then
    _describe command cmds
    return
  fi

  all=($_FUZZ_EVAL/*(N/:t))
  fuzzed=($_FUZZ_EVAL/*/*_output/default/queue(N/:h:h:h:t))
  if (( CURRENT == 3 )); then
    case $words[2] in
      reuse)   seeded=($_FUZZ_EVAL/*/initial_seeds(N/:h:t))                     # has seeds and generators
               names=($_FUZZ_EVAL/*/*_output/default/generators(N/:h:h:h:t)); names=(${names:*seeded}) ;;
      run)     names=(${all:|fuzzed}) ;;                                         # not fuzzed yet
      results) names=($_FUZZ_EVAL/*/*_output/default/fuzzer_stats(N:h:h:h:t)) ;;
      stop)    names=(${${(f)"$(docker ps -a --filter name=g2f- --format '{{.Names}}' 2>/dev/null)"}#g2f-}) ;;
      watch)   names=(${${(f)"$(docker ps --filter name=g2f- --format '{{.Names}}' 2>/dev/null)"}#g2f-}) ;;  # running
      shell|status) names=($all) ;;
      *) return 1 ;;
    esac
    _describe campaign names
  elif [[ $words[2] == (run|shell) ]]; then
    compadd -- --test
  fi
}

compdef _fuzz fuzz
