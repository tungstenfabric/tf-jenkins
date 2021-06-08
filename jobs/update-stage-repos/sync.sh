#!/bin/bash -e

[ $# -ne 1 ] && exit 1

DIST=$1
BASEDIR=/var/local/mirror/repos/

envopts=""
if [[ -n ${RHEL_USER+x} && -n ${RHEL_PASSWORD+x} && -n ${RHEL_POOL_ID+x} ]] ; then
  envopts="-e RHEL_USER=${RHEL_USER} -e RHEL_PASSWORD=${RHEL_PASSWORD} -e RHEL_POOL_ID=${RHEL_POOL_ID}"
fi

envopts+=" -e CI_DOMAIN=$CI_DOMAIN -e SLAVE_REGION=$SLAVE_REGION"

sudo docker run --rm --name ${DIST}repos -v ${BASEDIR}:/repos ${envopts} ${DIST}repos
