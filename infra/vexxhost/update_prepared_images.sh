set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

for i in "${!OS_IMAGE_USERS[@]}"; do
  if [[ ${IMAGE_TYPE^^} != 'ALL' && ${IMAGE_TYPE^^} != ${i^^} ]]; then
    continue
  fi

  packer build -machine-readable -var "os_image=${i,,}" -var "ssh_user=${OS_IMAGE_USERS[$i]}" \
      ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/packer/vexxhost.json
  OLD_IMAGES=$(openstack image list --tag prepared-${i,,} -c Name -f value | sort -nr | tail -n +4)
  for o in $OLD_IMAGES; do
    openstack image delete $o
  done
done
