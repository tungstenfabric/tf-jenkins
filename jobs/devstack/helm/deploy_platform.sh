#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

function set_locale() {
  sudo localectl set-locale LANG=en-US.UTF-8
  . /etc/locale.conf
  export LC_ALL=en_US.UTF-8
  cat /etc/environment
  # If /etc/environment already contain LANG, LC_ALL we need replace it by "sudo sed ..."
  if ! (grep "LANG" /etc/environment); then
    if ! (grep "LC_ALL" /etc/environment); then
      sudo sh -c "echo -e 'LANG=en_US.utf-8\nLC_ALL=en_US.utf-8' >> /etc/environment"
      cat /etc/environment
    fi
  fi
}
export -f set_locale

${my_dir}/../common/deploy_platform.sh helm
