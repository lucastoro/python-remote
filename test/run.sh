#!/bin/bash

port=2222
image_server='python-remote/server:latest'
image_client='python-remote/client:latest'
server_hostname='test-server'
client_hostname='test-client'
root=$(realpath $(dirname $0)/..)
test=$root/test

[ "$PWD" != "$test" ] && cd $test

[ -f ./test_all.py ] || {
  echo 'hmmmm... invalid directory'
  exit 1
}

templog=$(mktemp) || {
  echo 'could not create a temp. log file'
  exit 1
}

function remove_log {
  rm -f $templog
}

trap remove_log EXIT

function stage {
  local before=$(date +%s)
  local label=$1
  shift
  stdbuf -o 0 echo -n "$label... "
  $@ &>$templog
  local ret=$?
  let "elapsed = $(date +%s) - $before"
  [ $elapsed -eq 0 ] && elapsed='<1'
  if [ $ret -eq 0 ]; then
    echo "ok ($elapsed sec)"
  else
    echo "FAILED ($elapsed sec):"
    cat $templog
  fi
  return $ret
}

stage 'building (or updating) the server image' \
  docker build -t $image_server -f Dockerfile.server . || exit 1

stage 'building (or updating) the client image' \
  docker build -t $image_client -f Dockerfile.client . || exit 1

echo 'starting the server container'
server_id=$(docker run --rm -d -h $server_hostname -p $port:22 $image_server) || exit 1
server_ip=$(docker inspect $server_id | grep '"Gateway"' | head -1 | sed -r 's/\s*"Gateway": "([^"]+)",/\1/g')

echo 'executing the tests'
docker run --rm -e TEST_SERVER=$server_ip -h $client_hostname \
  -v $root/remote:/home/client/test/remote \
  -v $test/test_all.py:/home/client/test/test_all.py \
  $image_client $@
result=$?

stage 'stopping (and removing) the server container' \
  docker stop $server_id || true

exit $result