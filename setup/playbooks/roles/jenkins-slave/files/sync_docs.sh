#!/bin/bash -e
date
cd /docs
if ! git pull | grep "Already up to date." ; then
  /usr/bin/tox -e docs
  cd _build/html
  aws s3 sync . s3://docs.opensdn.io --delete --profile osdnwebsite
  "Successfully synced"
fi
