#!/bin/bash -e

MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

mkdir -p ${MIRRORDIR}/ubuntu18/${DATE}
cd ${MIRRORDIR}/ubuntu18

sed -i "s|%MIRRORDIR%|${MIRRORDIR}/ubuntu18/${DATE}|" /etc/apt/mirror.list
apt-mirror && (rm -f stage; ln -s ${DATE} stage)

