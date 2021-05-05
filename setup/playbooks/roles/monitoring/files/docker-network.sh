#!/bin/bash -e

connected=$(docker network inspect monitoring_default | grep nginx-proxy | wc -l)
if [ $connected -eq 0 ]; then
    docker network connect monitoring_default nginx-proxy
    docker restart monitoring_nginx_1
fi
