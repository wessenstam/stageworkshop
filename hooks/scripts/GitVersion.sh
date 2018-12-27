# shellcheck disable=SC2148

pushd ~/Documents/github.com/mlavi/stageworkshop/ \
&& source scripts/lib.shell-convenience.sh 'quiet' || exit 1

if (( $(docker ps 2>&1 | grep Cannot | wc --lines) == 0 )); then
  docker run --rm -v "$(pwd):/repo" gittools/gitversion-fullfx:linux /repo \
  > ${RELEASE}
elif [[ ! -z $(which gitversion) ]]; then
  gitversion > ${RELEASE}
else
  echo "Error: Docker engine down and no native binary available on PATH."
fi

mv ${RELEASE} original.${RELEASE} && cat ${_} \
| jq ". + {\"PrismCentralStable\":\"${PC_STABLE_VERSION}\"} + {\"PrismCentralDev\":\"${PC_DEV_VERSION}\"}" \
> ${RELEASE} && rm -f original.${RELEASE}

git add ${RELEASE}
