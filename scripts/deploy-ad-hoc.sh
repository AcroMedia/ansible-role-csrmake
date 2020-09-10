#!/bin/bash
set -ue -o pipefail

TEMPDIR="/tmp/install-acromedia-csrmake.$(date +%s)"
LOCALDIR=$(dirname "$(readlink -f "$0")")


REMOTEHOST="${1:-}"
if [ -z "$REMOTEHOST" ]; then
  echo "What server do you want to deploy to?"
  exit 1
fi

ssh -tq "$REMOTEHOST" "if [ ! -d '$TEMPDIR' ]; then mkdir -p '$TEMPDIR'; fi" || {
  echo "Could not create directory $TEMPDIR on $REMOTEHOST."
  if ssh "$REMOTEHOST" "exit 0"; then
    echo "SSH worked, dir creation failed."
  fi
  exit 2
}

rsync -v "$LOCALDIR"/* "$REMOTEHOST":"$TEMPDIR/" || {
  echo "Could not upload files to $TEMPDIR on $REMOTEHOST."
  exit 3
}


ssh -tq "$REMOTEHOST" "which make || sudo -i apt-get -y install make || sudo -i yum -y install make" || {
  echo "Make is not present or could not be installed on $REMOTEHOST."
  exit 4
}

ssh -tq "$REMOTEHOST" "cd '$TEMPDIR' && sudo make -s install" || {
  echo "Could not sudo make install on $REMOTEHOST."
  exit 5
}

# Clean up
ssh -tq "$REMOTEHOST" "rm -Rf '$TEMPDIR'" || {
  echo "Could not remove $REMOTEHOST:$TEMPDIR"
  # Not a big deal, no need to exit.
}

echo ""
echo "-------------------------------------------------"
echo "csrmake deployed to $REMOTEHOST succesfully."
echo "-------------------------------------------------"
