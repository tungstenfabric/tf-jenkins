#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

function add_deployrc() {
  local file="$1"
  cat <<EOF >> "$file"
  # Openstack Helm installation requires set locale, otherwise get UnicodeDecodeError on Vexx
  sudo localectl set-locale LANG=en-US.UTF-8
  . /etc/locale.conf
  export LC_ALL=en_US.UTF-8
  if ! (grep "LANG" /etc/environment); then
    if ! (grep "LC_ALL" /etc/environment); then
      sudo sh -c "echo -e 'LANG=en_US.utf-8\nLC_ALL=en_US.utf-8' >> /etc/environment"
    fi
  fi
EOF
}
export -f add_deployrc

${my_dir}/../common/deploy_platform.sh helm
