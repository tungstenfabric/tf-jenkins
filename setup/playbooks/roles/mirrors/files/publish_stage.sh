#!/bin/bash

[ $# -ne 1 ] && exit 1

DIST=$1
BASEDIR=/var/local/mirror/repos/${DIST}
pushd ${BASEDIR}
NEWLATEST=$(readlink stage)
rm -f latest || /bin/true
ln -s ${NEWLATEST} latest
popd
