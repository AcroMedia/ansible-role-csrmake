#!/bin/bash
set -eu -o pipefail

# Generate a Certificate Signing Request

function main () {
  # Root required.
  if [[ $EUID -ne 0 ]]; then
     err "This script must be run as root."
     exit 1
  fi

  # Some config.
  THIS_DIR=$(dirname "$(readlink -f "$0")")
  BASEDIR="/usr/local/ssl"
  CERTSDIR="$BASEDIR/certs"
  PRIVATEDIR="$BASEDIR/private"
  DATE=$(date +%Y%m%d)
  HOSTNAME=$(hostname)
  EMAILMESSAGE="/tmp/$(basename "$0").$DATE.email.txt"
  DEFAULT_RECIPIENT="root@localhost"
  LOCAL_CONF="$THIS_DIR/.csrmake"

  # Sanity check: Make sure the proper dirs are in place.
  if [ ! -d "$BASEDIR" ]; then
    err "The $BASEDIR dir doesn't exist, and it should. Figure out what's up, and then come back and try again."
    exit 1
  fi
  if [ ! -d "$PRIVATEDIR" ]; then
    err "The $PRIVATEDIR dir doesn't exist, and it should. Figure out what's up, and then come back and try again."
    exit 1
  fi
  if [ ! -d "$CERTSDIR" ]; then
    err "The $CERTSDIR dir doesn't exist, and it should. Figure out what's up, and then come back and try again."
    exit 1
  fi

  # sanity check , make sure we can create our message file
  touch "$EMAILMESSAGE" || {
    err "Could not create temporary file for email content at: $EMAILMESSAGE"
    exit 1
  }

  #Sanity Check: Warn if mail doesn't work.
  if type mail >/dev/null 2>&1; then
    MAIL_WORKS=1
  else
    MAIL_WORKS=0
    warn "I couldn't find 'mail' in PATH. You will need to deliver your new CSR manually."
    cerr "Install the  'mailutils' (debian) or 'mailx' (redhat) package if you want the CSR to get sent automatically."
  fi

  # Look for a local config file to override settings (mainly for custom default recipient)
  if [ $MAIL_WORKS -eq 1 ]; then
    if [ -f "$LOCAL_CONF" ]; then
      # Make sure the config is owned by root (user and group). It's not safe for root to execute files that were created by others.
      CONF_OWNER=$(find "$LOCAL_CONF" -maxdepth 0 -type f -printf '%u %g\n') || {
        warn "Could not determine permissions with the version of 'find' installed on this server."
      }
      if [[ "$CONF_OWNER" == "root root" ]]; then
        cerr "Reading DEFAULT_RECIPIENT from $LOCAL_CONF"
        # shellcheck disable=SC1090
        source "$LOCAL_CONF"
      else
        warn "Ignoring local $LOCAL_CONF because it is not owned by root:root, or permissions could not be determined."
      fi
    else
      cerr "Hint: create a file at $LOCAL_CONF to permanently set DEFAULT_RECIPIENT"
    fi

    bold "Before we begin, who would you like your cert delivered to?"
    while [[ ! "${RECIPIENT:-}" =~ .+@.+ ]]; do
      read -r -e -p "Enter a new email address, or press enter to accept the default [$DEFAULT_RECIPIENT]: " RECIPIENT
      if [[ -z "$RECIPIENT" ]]; then
        RECIPIENT="$DEFAULT_RECIPIENT"
        break
      fi
    done
    cerr "Will deliver to $RECIPIENT."

  else
    RECIPIENT=$DEFAULT_RECIPIENT
  fi


  cerr ""
  cerr "For a non-wildcard cert, enter the fully qualified domain name - www.example.com"
  cerr "For a wildcard cert, enter the naked domain name - example.com"
  while [[ ! "${DOMAIN:-}" =~ ([a-z]\.)+[a-z] ]]; do
    read -r -e -p "Certificate domain name: " DOMAIN
  done

  PRIVATEKEYFILE="$PRIVATEDIR/$DOMAIN.key.$DATE"
  CSRFILE="$CERTSDIR/$DOMAIN.csr.$DATE"

  # Private file should only be readable by group, and writeable by root
  umask 027

  cerr ""
  # Generate the new private key.
  openssl genrsa -out "$PRIVATEKEYFILE" 2048 || {
    err "Could not create private key file. Aborting."
    exit 1
  }
  cerr "New private key: $PRIVATEKEYFILE"

  # Ok to go back to normal umask
  umask 022

  cerr ""
  cerr "This rest of this script is a call to openssl to generate the CSR."
  cerr "  Openssl will gather all the information that gets embedded in the CSR + SSL certificate."
  cerr "  - Country:    2 letter abbreviation"
  cerr "  - State/Prov: full name; no abberviations"
  cerr "  - Locality:   full city name"
  cerr "  - Org Name:   full legal company name"
  cerr "  - Org Unit:   leave blank"
  cerr "  - Common Name / FQDN:"
  cerr "    - regular (non-wildcard) cert: whole domain name - www.example.com"
  cerr "    - wildcard cert: asterisk and the nakded domain  - *.example.com"
  cerr "  - Email:      leave blank"
  cerr "  - Challenge:  leave blank"
  cerr "  - Optional company: leave blank"
  cerr -n "  Got it? (enter to continue) "
  # shellcheck disable=SC2034
  read -r DRAMATIC_PAUSE

  cerr ""
  openssl req -new -key "$PRIVATEKEYFILE" -sha256 -out "$CSRFILE" || {
    err "Could not create csr file. Aborting."
    exit 1
  }
  cerr ""
  cerr "New CSR: $CSRFILE"


  # Compose & send an email containing the CSR
  echo "A CSR has been generated for the domain $DOMAIN, dated $DATE on $HOSTNAME" > "$EMAILMESSAGE"
  echo "" >> "$EMAILMESSAGE"
  # This is intentionally echo'd and not quoted, so as to trim off the leading space in the message.
  # shellcheck disable=SC2046
  # shellcheck disable=SC2005
  echo "# $(openssl req -in "$CSRFILE" -noout -text | grep "Subject:")" | tee -a "$EMAILMESSAGE"
  echo "" >> "$EMAILMESSAGE"
  cat "$CSRFILE" >> "$EMAILMESSAGE"
  cerr ""
  if [ $MAIL_WORKS -eq 1 ] && (set -x && mail -s "CSR Generated for $DOMAIN" "$RECIPIENT" < "$EMAILMESSAGE"); then
    cerr " OK"
  else
    bold "****************************************************************"
    bold "Could not send email. You will need to deliver the following manually."
    bold "****************************************************************"
    >&2 cat "$EMAILMESSAGE"
    cerr "****************************************************************"
  fi

  rm "$EMAILMESSAGE"

  cerr "All done. When the certificate comes back from the CA in a few days, run 'install-pending-cert.sh' to put it in place."

}




function err () {
  bold_feedback "Err" "$*"
}

function warn () {
  bold_feedback "Warn" "$*"
}

function bold () {
  cerr "${BOLD}${*}${UNBOLD}"
}

function bold_feedback () {
  local PREFIX
  PREFIX="${1:-"bold_feedback received no arguments"}"
  shift || true
  local MESSAGE="$*"
  cerr "${BOLD}${PREFIX}:${UNBOLD} ${MESSAGE}"
}

function cerr () {
  >&2 echo "$@"
}

if [ -t 1 ] ; then
  # Only print fancy colors and text effects when running with a terminal
  BOLD=$(tput bold 2>/dev/null) || BOLD=''
  UNBOLD=$(tput sgr0 2>/dev/null) || UNBOLD=''
else
  # If running via cron, or through a pipe, then the colors get turned into codes, and cause readability issues
  BOLD=''
  UNBOLD=''
fi


main "$@"
