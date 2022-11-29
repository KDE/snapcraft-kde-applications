#!/bin/bash -x

if [ -n "$http_proxy" ]; then
  gem install --http-proxy="$http_proxy" tty
else
  gem install tty
fi
