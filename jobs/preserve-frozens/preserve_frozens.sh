#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

CONTAINER_REGISTRY_INSECURE=${CONTAINER_REGISTRY_INSECURE:-"true"}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"tf-nexus.tfci.progmaticlab.com:5001"}
CONTAINERS_INCLUDE_REGEXP=${CONTAINERS_INCLUDE_REGEXP:-"contrail-\|tf-"}

# tags of tf-dev-sandbox image to re-push
sandbox_image="tf-dev-sandbox"
sandbox_tags="stable frozen stable-ubi7"

result=0

function repush() {
  local image=$1
  if ! sudo docker pull $image ; then
    echo "INFO: there is no image $image"
    continue
  fi
  if ! sudo docker push $image ; then
    echo "ERROR: can't push image back $image"
    result=1
  fi
}

function run_with_retry() {
  local cmd=$@
  local attempt=0
  for attempt in {1..3} ; do
    if $cmd ; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# re-push sandbox iamge
for tag in $sandbox_tags ; do
  repush $CONTAINER_REGISTRY/$sandbox_image:$tag
done

# re-push all containers
frozen_tag=''
if curl -sIS "http://tf-nexus.tfci.progmaticlab.com:8082/frozen/tag" | grep -q "HTTP/1.1 200 OK" ; then
  frozen_tag=$(curl -s "http://tf-nexus.tfci.progmaticlab.com:8082/frozen/tag")
fi

if [[ -n "$frozen_tag" ]]; then
  src_scheme="http"
  [[ "$CONTAINER_REGISTRY_INSECURE" != 'true' ]] && src_scheme="https"
  container_registry_url="${src_scheme}://${CONTAINER_REGISTRY}"

  if raw_repos=$(run_with_retry curl -s --show-error ${container_registry_url}/v2/_catalog) ; then
    images=$(echo "$raw_repos" | jq -c -r '.repositories[]' | grep "$CONTAINERS_INCLUDE_REGEXP")
    if [[ -n "$images" ]] ; then
      for image in $images ; do
        repush $CONTAINER_REGISTRY/$image:$frozen_tag
      done
    else
      echo "INFO: Nothing to update:\nraw_repos=${raw_repos}\nrepos=$repos"
    fi
  else
    echo "ERROR: Failed to request repo list from docker registry ${CONTAINER_REGISTRY}"
  fi
else
  echo "INFO: there is no frozen tag stored"
fi

exit $result
