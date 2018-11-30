#!/usr/bin/env bats

@test "addition using bc" {
  result="$(echo 2+2 | bc)"
  [ "$result" -eq 4 ]
}

# source scripts/lib.common.sh ; ATTEMPTS=2 SLEEP=2 TRIES=3 PE_HOST=10.21.82.37 prism_check 'PE'
@test "Is PE up?" {
  result="$(source ./scripts/lib.common.sh ; \
  ATTEMPTS=2 SLEEP=2 TRIES=3 PE_HOST=10.21.82.37 PE_PASSWORD='tbd' prism_check 'PE' )"
  [ "$result" -ne 0 ]
}
