#!/bin/bash -ue
set -o pipefail
source ../deployables/functions.sh

require_root

make install
pushd /usr/local/ssl
trap "(popd && stty sane)" EXIT

bold '------------------------------'
bold "YOU ARE ABOUT TO INSTALL CSRMAKE AND CREATE A FAKE CERT. IT DOESN'T MATTER WHAT YOU ENTER NEXT OTHER THAN THE DOMAIN NAME / COMMON NAME ARE THE SAME IN BLOTH PLACES"
bold '------------------------------'
./csrmake_sha256.sh
/usr/bin/openssl x509 -req -days 365 -in $(find ./certs/ -type f -name '*.csr.????????'|tail -1) -signkey $(find ./private/ -type f -name '*.key.????????' |tail -1) -out /tmp/cert


cat /tmp/cert
bold '------------------------------'
bold "USE THE ABOVE CERT FOR THE NEXT PART"
bold '------------------------------'
./install-pending-cert.sh $(find ./certs/ -type f -name '*.csr.????????' |tail -1)
