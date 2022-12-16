#!/bin/bash -x

if [ -n "$http_proxy" ]; then
  gem install --http-proxy="$http_proxy" tty-command
else
  gem install tty-command
fi
