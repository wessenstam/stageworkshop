#!/usr/bin/env bash

CURL_OPTS='--insecure --header Content-Type:application/json --silent --show-error --max-time 5'
 SSH_OPTS='-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null'

function my_log {
  # Loging date format
  #TODO: Make logging format configurable
  #MY_LOG_DATE='date +%Y-%m-%d %H:%M:%S'
  #echo `$MY_LOG_DATE`" $1"

  echo $(date "+%Y-%m-%d %H:%M:%S") $1
}

function Dependencies {
  case "$1" in
    'install')
      my_log "Installing Dependencies"
      export PATH=${PATH}:${HOME}

      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        if [[ -z `which sshpass` ]]; then
          sudo rpm -ivh https://fr2.rpmfind.net/linux/epel/7/x86_64/Packages/s/sshpass-1.06-1.el7.x86_64.rpm
        else
          my_log "Dependencies: found sshpass!"
        fi

        if [[ -z `which jq` ]]; then
          wget --quiet https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 \
          && chmod u+x jq-linux64 && ln -s jq-linux64 jq;
        else
          my_log "Dependencies: found jq!"
        fi
      fi

      if [[ `uname -s` == "Darwin" ]]; then #MacOS
        if [[ -z `which sshpass` ]]; then
          brew install https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb;
        else
          my_log "Dependencies: found sshpass!"
        fi

        if [[ -z `which jq` ]]; then
          brew install jq;
        else
          my_log "Dependencies: found jq!"
        fi
      fi
      ;;
    'remove')
      my_log "Dependencies: removing..."
      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        sudo rpm -e sshpass
        rm -f jq jq-linux64
      fi
      ;;
    esac
}
