#!/bin/bash -e

nexus_rest_url="http://tf-nexus.progmaticlab.com/service/rest/v1"
registries="tungsten_ci tungsten_gate_cache"
image_name="tf-dev-sandbox"

for registry in registries ; do
  echo "INFO: registry = ${registry}"
  for id in $(curl -s "${nexus_rest_url}/search?repository=${registry}&name=${image_name}" | jq -r .items[].id) ; do
    echo "INFO: id = $id"
    curl -X DELETE "${nexus_rest_url}/components/${id}"
  done
done

echo "INFO: image ${image_name} has been deleted from registries"
