
function sync_repo() {
  local r=$1
  reposync --gpgcheck -l --repoid=$r --download_path=/var/www/html --downloadcomps --download-metadata
  cd /var/www/html/$r
  createrepo --workers=2 -v /var/www/html/${r}/ -g comps.xml
}

function update_repos() {
  local r
  for r in $@ ; do
    sync_repo $r
  done
}
