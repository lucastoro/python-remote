#!/bin/bash

# requires pytest, docker

image='ssh-server'
port=2222
host='test'
user='test'
root=$(dirname $(realpath $0))

pytest_version=$(pytest --version 2>&1) || {
  echo 'missing pytest'
  exit 1
}

(echo $pytest_version | grep 'python3') &>/dev/null || {
  echo 'python version used by pytest must be 3.x'
  exit 1
}

[ -f $root/remote.py ] || {
  echo 'hmmmm... invalid directory'
  exit 1
}

[ "$PWD" != "$root" ] && cd $root

templog=$(mktemp) || {
  echo 'could not create a temp. log file'
  exit 1
}

function remove_log {
  echo 'cleaning up the mess'
  rm -f $templog
}

[ "$(stat -c %a ./ssh-key)" != '600' ] && {
  echo 'adjusting key permissions'
  chmod 600 ./ssh-key &>$templog || {
    echo 'could not change key permissions:'
    cat $templog
    exit 1
  }
}

trap remove_log EXIT

echo 'building (or updating) the image'
docker build -t $image . &>$templog || {
  echo 'Image build failed:'
  cat $templog
  exit 1
}

echo 'starting the container'
docker run --rm -d -h $host -p $port:22 $image &>$templog || {
  echo 'Could not start the container:'
  cat $templog
  exit 1
}

echo 'executing the tests'
pytest -vv $@; result=$?

echo 'stopping (and removing) the container'
for container in $(docker ps | grep $image | cut -d' ' -f1); do
  docker stop $container &>$templog || {
    echo "Error while stopping container $container:"
    cat $templog
  }
done

exit $result
