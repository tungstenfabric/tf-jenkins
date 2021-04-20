#!/bin/bash

# script assumes that it can be run only by admin user to configure initial state of the nexus
# script checks password first and changes it if non-default password is provided
# script is idempotent

username='admin'
default_password='admin123'
url='http://localhost:8081'
create_update_groovy_script='complex-script/addUpdateScript.groovy'
grape_config='complex-script/grapeConfig.xml'
debug='false'

function usage() {
    printf "$0"
    printf "Configure TF CI Nexus tool\\n"
    printf "Options:\\n"
    printf "\\t[--password $password]\\n"
    printf "\\t[--url $url]\\n"
    printf "\\t[--create_update_groovy_script $create_update_groovy_script]\\n"
    printf "\\t[--grape_config $grape_config]\\n"
    printf "\\t[--debug]\\n"
}

while [[ -n "$1" ]] ; do
    case $1 in
        '--op')
            op="$2"
            ;;
        '--password')
            input_password="$2"
            ;;
        '--url')
            url="$2"
            ;;
        '--create_update_groovy_script')
            create_update_groovy_script="$2"
            ;;
        '--grape_config')
            grape_config="$2"
            ;;
        '--debug')
            debug="true"
            shift 1
            continue
            ;;
        *)
            echo "ERROR: unknown options '$1'"
            usage
            exit -1
            ;;
    esac
    shift 2
done

[[ "${debug}" == 'true' ]] && set -x

function create_and_run_script {
  local name=$1
  local file=$2
  shift 2
  # using grape config that points to local Maven repo and Central Repository , default grape config fails on some downloads although artifacts are in Central
  # change the grapeConfig file to point to your repository manager, if you are already running one in your organization
  groovy \
    -Dgroovy.grape.report.downloads=true \
    -Dgrape.config=$grape_config \
    $create_update_groovy_script \
    -u "$username" -p "$password" -n "$name" -f "$file" -h "$url" &> /dev/null
  printf "\nPublished $file as $name with result $?\n\n"
  # Run script
  curl -s -X POST -u $username:$password \
    --header "Content-Type: text/plain" \
    "$url/service/rest/v1/script/$name/run" $@
  printf "\nExecuted $name script with result $?\n\n\n"
}

if curl -s -I -u $username:$default_password "$url/service/rest/v1/read-only" | grep -q "200 OK" ; then
  password=$default_password
  if [[ -n "$input_password" && "$input_password" != "$default_password" ]]; then
    create_and_run_script tfci_setadminpassword tfCISetAdminPassword.groovy -d $input_password
    password="$input_password"
  fi
elif [[ -n "$input_password" && "$input_password" != "$default_password" ]]; then
  if curl -s -I -u $username:$input_password "$url/service/rest/v1/read-only" | grep -q "200 OK" ; then
    password="$input_password"
  else
    echo "ERROR: neither default password nor provided are invalid."
    exit 1
  fi
else
  echo "ERROR: default password doesn't work and no password provided."
  exit 1
fi

# order is important, e.g. repos creation uses cleanup policy
case $op in
    'cleanup')
        create_and_run_script tfci_cleanup tfCICleanupPolicy.groovy
        ;;
    'repos')
        create_and_run_script tfci_repos tfCIRepositories.groovy
        ;;
    'compact')
        create_and_run_script tfci_compact tfCIStorageCompactTask.groovy
        ;;
    'roles')
        create_and_run_script tfci_roles tfCIRoles.groovy
        ;;
    *)
        echo "ERROR: unknown operation $op"
        exit -1
        ;;
esac

