#!/bin/bash

REMOTEHOST="$1"
REMOTEDIR="/tmp/csrmake-install"
LOCALFILES="Makefile csrmake_sha256.sh install-pending-cert.sh"


if [[ ! "$REMOTEHOST" ]]; then
  echo "What server do you want to deploy to?"
  exit 1
fi

ssh -tq "$REMOTEHOST" "if [ ! -d '$REMOTEDIR' ]; then mkdir -p '$REMOTEDIR'; fi" || {
  echo "Could not create directory $REMOTEDIR on $REMOTEHOST."
  exit 2
}

rsync $LOCALFILES "$REMOTEHOST":"$REMOTEDIR/" || {
  echo "Could not upload files to $REMOTEDIR on $REMOTEHOST."
  exit 3
}

ssh -tq "$REMOTEHOST" "cd '$REMOTEDIR' && sudo make -s install" || {
  echo "Could not sudo make install on $REMOTEHOST."
  exit 4
}

ssh -tq "$REMOTEHOST" "rm -rf '$REMOTEDIR'" || {
  echo "Warning: I could not clean up $REMOTEDIR from $REMOTEHOST."
}

echo ""
echo "-----------------------------"
echo "CSRMAKE deployed succesfully."
echo "-----------------------------"
echo "#############################"
echo "###### NOW DO THIS to make sure the shared functions also get installed:"
echo "###    cd ../"
echo "###    ./deploy.sh $REMOTEHOST"

