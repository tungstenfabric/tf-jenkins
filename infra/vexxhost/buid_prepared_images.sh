set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

for i in "${!OS_IMAGE_USERS[@]}"; do
  packer build -machine-readable -var "OS_IMAGE=${i,,}" -var "SSH_USER=${OS_IMAGE_USERS[$i]}" ../packer/vexxhost.json
done
