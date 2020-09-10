#!/bin/bash
set -ue -o pipefail

# To be used with csrmake (which generated a new private key and sent the CSR off to Laura for processing)
# For installing certificates that have been returned from the Certificate Authority


function main () {
  cerr "Checking the buckles..."

  # Root required.
  if [[ $EUID -ne 0 ]]; then
     err "This script must be run as root"
     exit 1
  fi

  # Some config.
  BASEDIR="/usr/local/ssl"
  CERTSDIR="$BASEDIR/certs"
  PRIVATEDIR="$BASEDIR/private"
  BACKUPDIR="$BASEDIR/backups"
  HOSTNAME=$(hostname)

  # Sanity check: Make sure the proper dirs are in place.
  if [ ! -d "$BASEDIR" ]; then
    err " Whoa - the $BASEDIR dir doesn't exist, and it should. Figure out what's up, and then come back and try again."
    exit 1
  fi
  if [ ! -d "$PRIVATEDIR" ]; then
    err " Whoa - the $PRIVATEDIR dir doesn't exist, and it should. Figure out what's up, and then come back and try again."
    exit 1
  fi
  if [ ! -d "$CERTSDIR" ]; then
    err " Whoa - the $CERTSDIR dir doesn't exist, and it should. Figure out what's up, and then come back and try again."
    exit 1
  fi
  if [ ! -d "$BACKUPDIR" ]; then
    cerr "Creating dir for backups: $BACKUPDIR"
    mkdir -p "$BACKUPDIR"
    chmod 700 "$BACKUPDIR"
  fi

  cerr ""

  # Arguments
  PENDING_CSR="${1:-}" # i.e. certs/www.example.com.csr.20150131

  CSR_LIMIT_DAYS=90

  while [ ! -f "$PENDING_CSR" ]; do
    CSR_LIST=$(find "$CERTSDIR" -type f -name '*.csr.*' -mtime -$CSR_LIMIT_DAYS)
    CSR_LIST_COUNT=$(find "$CERTSDIR" -type f -name '*.csr.*' -mtime -$CSR_LIMIT_DAYS -printf '.' | wc -c)
    #cerr "CSR_LIST: $CSR_LIST"
    #cerr "CSR_LIST_COUNT: $CSR_LIST_COUNT"
    if [ "$CSR_LIST_COUNT" -eq 0 ]; then
      cerr "There don't appear to be any CSRs (created within the last $CSR_LIMIT_DAYS days) waiting to be processed."
      exit 1
    elif [ "$CSR_LIST_COUNT" -eq 1 ]; then
      PENDING_CSR="$CSR_LIST"
    elif [ "$CSR_LIST_COUNT" -gt 1 ]; then
      bold "Which CSR do you want to process:"
      CSR_LIST_AS_STRING=$(echo -n "$CSR_LIST" | tr '\n' ' ')
      PENDING_CSR=$(multiple_choice "$CSR_LIST_AS_STRING")
    else
      err "Could not determine PENDING_CSR from CSR_LIST"
      exit 1
    fi
  done

  # strip off everything from the path name except the common name
  COMMON_NAME=$(echo "$PENDING_CSR" | sed 's/\.csr\.[0-9]\{8\}$//g' | sed 's/.*certs\///g')
  DATE_PART=$(echo "$PENDING_CSR" | sed 's/.*certs\/.*\.csr\.//g')

  NEW_PRIVATE_KEY="$PRIVATEDIR/$COMMON_NAME.key.$DATE_PART"
  # Check to make sure that private/<cn>.key.yyyymmdd exist
  if [ ! -f "$NEW_PRIVATE_KEY" ]; then
    err "Woops - there doesn't seem to be a corresponding new private key file at $NEW_PRIVATE_KEY"
    cerr "You'll have to put your new certificate in place manually."
    exit 1
  fi



  cerr "Buckles look tight!"
  cerr ""
  cerr "o) Pasting in contents of certificates is terminated by multiple consecutive"
  cerr "   newline characters. If you paste in the contents of a certificate but nothing "
  cerr "   seems to happen, try hitting enter once or twice until the script continues."
  cerr "   We do things this way to tolerate (and ultimately remove) multiple newlines "
  cerr "   that come along for the ride from various sources when they aren't invited."
  if [ -d "/etc/nginx" ]; then
    cerr ""
    cerr "o) Intermediate cert bundles that come from the CA are are quite often wrong. You may"
    cerr "   have to update them manually afterward. If this is the case, don't forget to update "
    cerr "   the intermediate(s) in both the .intermediates.pem, and in the .fullchain.pem files. The .fullchain.pem bundle is "
    cerr "   simply a concatenation of the .cert and .intermediates.pem files. Even when not using apache, we "
    cerr "   still keep a copy of each so we can distinguish them from one another, since there is"
    cerr "   no such thing as a comment in a certificate file."
  fi
  cerr ""
  cerr "o) You can press CTRL+C at any point to abort the process. No work will be done"
  cerr "   without a final confirmation."
  cerr ""

  # Some feedback for the user ... if anything looks wrong, hopefully they notice and bail out.
  cerr "  Common name:                 $COMMON_NAME"
  cerr "  Date of CSR:                 $DATE_PART"


  # New certificate contents
  cerr ""
  cerr "Paste in the new cert content now. Input will terminate after two consecutive empty lines:"
  NEW_CERT_CONTENTS=""
  EMPTY_CONSECUTIVE_LINES=0
  while read -r line
  do
    if [ -z "$line" ]; then
      EMPTY_CONSECUTIVE_LINES=$((EMPTY_CONSECUTIVE_LINES + 1))
    else
      # reset counter
      EMPTY_CONSECUTIVE_LINES=0
      # concatenate the existing content, a newline character (literally), and then the newly entered line
      # The indention looks funny here because it is literal: It has to be un-indented so we don't inject extra spaces in front of each line of the certificate content.
      NEW_CERT_CONTENTS="$NEW_CERT_CONTENTS
  $line"
    fi
    # break after finding 2 newlines - this tolerates the infuriating extra lines that come along for the ride when pasting in content from Thawte certificate files.
    if [ $EMPTY_CONSECUTIVE_LINES -gt 1 ]; then
       break
    fi
  done



  # Shave the artificially inserted first newline off the contents
  NEW_CERT_CONTENTS=$(echo "$NEW_CERT_CONTENTS" | tail -n +2)

  # Make sure the cert content ends in a new line, since we've been manipulating them in the 'read'
  NEW_CERT_CONTENTS="$NEW_CERT_CONTENTS
  "

  # Make sure the new cert looks like a cert
  if grep -q "BEGIN CERTIFICATE" <<< "$NEW_CERT_CONTENTS"; then
    : # 'Begin Cert' was in the string
  else
    err "The certificate contents you pasted don't look valid. Please try again."
    exit 1
  fi
  if grep -q "END CERTIFICATE" <<< "$NEW_CERT_CONTENTS"; then
    : # 'End Cert' was in the string
  else
    err "The certificate contents you pasted don't look valid. Please try again."
    exit 1
  fi


  BUNDLEPROMPT="Do you have any new intermediate cert bundles to accompany your new certificate? [y/n]: "
  >&2 printf "%s" "$BUNDLEPROMPT"
  while read -r options; do
    case "$options" in
      "y") SUPPLY_INTERMEDIATES=1; break ;;
      "n") SUPPLY_INTERMEDIATES=0; break ;;
      *) >&2 printf "%s" "$BUNDLEPROMPT" ;;
    esac
  done



  # Read in new bundle content if it's needed
  if [ $SUPPLY_INTERMEDIATES -eq 1 ]; then
    cerr ""
    cerr "Paste in the new intermediate bundle contents now. If there is more than one "
    cerr "intermediate, please ensure there is no more than one empty line between them, "
    cerr "since multiple empty lines terminate input:"
    NEW_BUNDLE_CONTENTS=""
    EMPTY_CONSECUTIVE_LINES=0
    while read -r line
    do
    if [ -z "$line" ]; then
      EMPTY_CONSECUTIVE_LINES=$((EMPTY_CONSECUTIVE_LINES + 1))
    else
      # reset counter
      EMPTY_CONSECUTIVE_LINES=0
      # concatenate the existing content, a newline character (literally), and then the newly entered line
      # The indention looks funny here - this is so we don't inject extra spaces in to the certificate.
      NEW_BUNDLE_CONTENTS="$NEW_BUNDLE_CONTENTS
  $line"
    fi
    # break after finding 2 newlines - this tolerates the infuriating extra lines that come along for the ride when pasting in content from Thawte certificate files.
    if [ $EMPTY_CONSECUTIVE_LINES -gt 1 ]; then
       break
    fi
    done
    # Trim the unwanted newline off the top.
    NEW_BUNDLE_CONTENTS=$(echo "$NEW_BUNDLE_CONTENTS" | tail -n +2)


    # Make sure the new cert looks like a cert
    if grep -q "BEGIN CERTIFICATE" <<< "$NEW_BUNDLE_CONTENTS"; then
      : # 'Begin Cert' was in the string
    else
      err "The certificate contents you pasted don't look valid. Please try again."
      exit 1
    fi
    if grep -q "END CERTIFICATE" <<< "$NEW_BUNDLE_CONTENTS"; then
      : # 'End Cert' was in the string
    else
      err "The bundle contents you pasted don't look valid. Please try again."
      exit 1
    fi
  fi

  cerr ""
  cerr "So far so good. Enter anything to save new cert contents to disk, or CTRL+C to abort."
  # shellcheck disable=SC2034
  read -r DRAMATIC_PAUSE

  # Define canonical paths to the final destinations, and make backups
  cerr ""
  cerr "Backing up existing resources..."
  PRIVATE_KEY="$PRIVATEDIR/$COMMON_NAME.key"
  if [ -f "$PRIVATE_KEY" ]; then
    PRIVATE_BACKUP="$BACKUPDIR/$(basename "$PRIVATE_KEY").bak.$(date +%Y%m%d)"
    cp -av "$PRIVATE_KEY" "$PRIVATE_BACKUP"
  fi
  CSR_FILE="$CERTSDIR/$COMMON_NAME.csr"
  if [ -f "$CSR_FILE" ]; then
    CSR_BACKUP="$BACKUPDIR/$(basename "$CSR_FILE").bak.$(date +%Y%m%d)"
    cp -av "$CSR_FILE" "$CSR_BACKUP"
  fi
  CERT_FILE="$CERTSDIR/$COMMON_NAME.cert"
  if [ -f "$CERT_FILE" ]; then
    CERT_BACKUP="$BACKUPDIR/$(basename "$CERT_FILE").bak.$(date +%Y%m%d)"
    cp -av "$CERT_FILE" "$CERT_BACKUP"
  fi
  INTERMEDIATES_FILE="$CERTSDIR/$COMMON_NAME.intermediates.pem"
  if [ -f "$INTERMEDIATES_FILE" ]; then
    BUNDLE_BACKUP="$BACKUPDIR/$(basename "$INTERMEDIATES_FILE").bak.$(date +%Y%m%d)"
    cp -av "$INTERMEDIATES_FILE" "$BUNDLE_BACKUP"
  fi
  LEGACY_BUNDLE="$CERTSDIR/$COMMON_NAME.bundle"
  if [ -f "$LEGACY_BUNDLE" ]; then
    # 'Bundle' files are old school. Now we use the canoncial 'intermediates.pem', but still supply the '.bundle' as a symlink
    BUNDLE_BACKUP="$BACKUPDIR/$(basename "$LEGACY_BUNDLE").bak.$(date +%Y%m%d)"
    mv -v "$LEGACY_BUNDLE" "$BUNDLE_BACKUP"
  fi
  NGINX_COMBINED="$CERTSDIR/$COMMON_NAME.fullchain.pem"
  if [ -f "$NGINX_COMBINED" ]; then
    NGINX_BACKUP="$BACKUPDIR/$(basename "$NGINX_COMBINED").bak.$(date +%Y%m%d)"
    cerr "Backing up existing nginx cert bundle to $NGINX_BACKUP"
    cp -a "$NGINX_COMBINED" "$NGINX_BACKUP"
  fi


  cerr ""
  cerr "Putting new resources in place..."
  mv -fv "$PENDING_CSR" "$CSR_FILE" || {
    err "Could not write to file. Aborting."
    exit 1
  }
  echo -n "$NEW_CERT_CONTENTS" > "$CERT_FILE" || {
    err "Failed to save contents to $CERT_FILE - aborting."
    exit 1
  }
  if [ $SUPPLY_INTERMEDIATES -eq 1 ]; then
    echo -n "$NEW_BUNDLE_CONTENTS" > "$INTERMEDIATES_FILE" || {
      err "Failed to save contents to $INTERMEDIATES_FILE - aborting."
      exit 1
    }
  fi
  if [ -f "$INTERMEDIATES_FILE" ] && [ ! -L "$LEGACY_BUNDLE" ]; then
    ln -sv "$INTERMEDIATES_FILE" "$LEGACY_BUNDLE"
  fi
  mv -fv "$NEW_PRIVATE_KEY" "$PRIVATE_KEY"|| {
    err "Could not write to file. Aborting."
    exit 1
  }
  if [ -d "/etc/nginx" ]; then
    cat "$CERT_FILE" "$INTERMEDIATES_FILE" > "$NGINX_COMBINED"
    cerr ""
  fi

  cerr "-------------------------------"
  cerr "Your new certificate resources:"
  cerr "-------------------------------"
  cerr "Private key:            $PRIVATE_KEY"
  cerr "Full chain (for NGINX): $NGINX_COMBINED"
  cerr "Bare cert (for Apache): $CERT_FILE"
  if [ $SUPPLY_INTERMEDIATES -eq 1 ]; then
    cerr "Intermediates bundle:   $INTERMEDIATES_FILE"
  fi
  if [ -L "$LEGACY_BUNDLE" ]; then
    cerr "                        $LEGACY_BUNDLE  (legacy symlink)"
  fi
  cerr "CSR:                    $CSR_FILE"

  cerr ""
  cerr "All done. You can now configure and reload the web server."
  cerr "Recommended verification tools:"
  cerr "- Fast, with links to missing intermediates: https://cryptoreport.websecurity.symantec.com/checker/"
  cerr "- Exhaustive: https://www.ssllabs.com/ssltest/"
  cerr ""

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

# Prompts the user to select from a list of values. Will not return until the user chooses one.
# Arg 1 (Required): A space separated list of values to choose from. I.e: "foo bar ding bat"
# Arg 2 (Optional): A pipe-separated list of titles. If supplied, will be shown to the user instead of the values. I.e: "Title 1|Title 2|Something Else|Last Option".
# Arg 3 (Optional): If values need to be split on something other than a space, specify the delimiter.
# Arg 4 (Optional): The maximum number of selections to accept. Default is 1. Specify 0 to accept multiple selections (up to the amount of values there are), or another number for an arbitrary maximum.
multiple_choice() {
  local CHOICE_VALUES_AS_STRING="$1"
  #cerr "CHOICE_VALUES_AS_STRING: $CHOICE_VALUES_AS_STRING"
  local CHOICE_TITLES_AS_STRING="${2:-}"
  #cerr "CHOICE_TITLES_AS_STRING: $CHOICE_TITLES_AS_STRING"
  test -z "$CHOICE_TITLES_AS_STRING" && {
    # if no titles were supplied, use values as titles, turning whitespace into pipes like the title string should have.
    CHOICE_TITLES_AS_STRING="$(echo -n "$CHOICE_VALUES_AS_STRING" | tr '[:space:]' '|')"
  }
  local CHOICE_VALUE_DELIMITER="${3:-}"
  test -z "$CHOICE_VALUE_DELIMITER" && CHOICE_VALUE_DELIMITER="$IFS"

  local MAX_SELECTIONS="${4:-1}"
  #cerr "MAX_SELECTIONS: $MAX_SELECTIONS"
  if ! is_positive_integer "$MAX_SELECTIONS"; then
    err "multiple_choice: expected an  integer >= 0 ; got '$MAX_SELECTIONS' instead."
  fi

  # turn the strings into arrays
  OLDIFS="$IFS"
  local CHOICE_VALUES_AS_ARRAY
  IFS="$CHOICE_VALUE_DELIMITER" read -r -a CHOICE_VALUES_AS_ARRAY <<< "$CHOICE_VALUES_AS_STRING"
  local CHOICE_TITLES_AS_ARRAY
  IFS='|' read -r -a CHOICE_TITLES_AS_ARRAY <<< "$CHOICE_TITLES_AS_STRING"
  IFS="$OLDIFS"

  # Sanity check - make sure we have the same number of items in each list.
  local CHOICE_VALUES_COUNT="${#CHOICE_VALUES_AS_ARRAY[@]}"
  if [ "$MAX_SELECTIONS" -eq 0 ]; then
    MAX_SELECTIONS=$CHOICE_VALUES_COUNT
  fi
  #cerr "CHOICE_VALUES_COUNT: $CHOICE_VALUES_COUNT"
  local CHOICE_TITLES_COUNT="${#CHOICE_TITLES_AS_ARRAY[@]}"
  #cerr "CHOICE_TITLES_COUNT: $CHOICE_TITLES_COUNT"
  if [ "$CHOICE_VALUES_COUNT" -ne "$CHOICE_TITLES_COUNT" ]; then
    warn "multiple_choice() - The number of choice values did not match number of choice titles... results may be unpredictable"
  fi

  # Present the choices
  local CHOICE_COUNT=0
  for ((LOOP=0; LOOP < "${#CHOICE_VALUES_AS_ARRAY[*]}"; LOOP++)); do
    CHOICE_COUNT=$((CHOICE_COUNT+1))
    local CHOICE_VALUE="${CHOICE_VALUES_AS_ARRAY[$LOOP]}"
    local CHOICE_TITLE="${CHOICE_TITLES_AS_ARRAY[$LOOP]}"
    if [[ "${CHOICE_TITLE}" == "${CHOICE_VALUE}" ]]; then
      cerr "[${CHOICE_COUNT}] ${CHOICE_TITLE}"
    else
      cerr "[${CHOICE_COUNT}] ${CHOICE_TITLE} (${CHOICE_VALUE})"
    fi
  done

  # Collect and validate chocies
  local PROMPT_TEXT
  if [ "$MAX_SELECTIONS" -eq 1 ]; then
    PROMPT_TEXT="Please select: "
  else
    PROMPT_TEXT="Enter up to $MAX_SELECTIONS selections, separated by space or comma: "
  fi
  local RETURNED_OUTPUT=''
  VALID_SELECTION_COUNT=0
  while [ $VALID_SELECTION_COUNT -lt 1 ]; do
    #cerr "VALID_SELECTION_COUNT: $VALID_SELECTION_COUNT"
    >&2 echo -n "$PROMPT_TEXT"
    local USER_INPUT=''
    read -r USER_INPUT
    #cerr "USER_INPUT: $USER_INPUT"
    USER_INPUT=$(echo "$USER_INPUT" |tr --squeeze ',' ' ')
    #cerr "USER_INPUT: $USER_INPUT"
    for NUMBER in $USER_INPUT; do
      #cerr "NUMBER: $NUMBER"
      #cerr "CHOICE_VALUES_COUNT: $CHOICE_VALUES_COUNT"
      if is_positive_integer "$NUMBER" \
        && [ "$NUMBER" -le "$CHOICE_VALUES_COUNT" ] \
        && [ "$NUMBER" -gt 0 ]; then
        VALID_SELECTION_COUNT=$((VALID_SELECTION_COUNT + 1))
        RETURNED_OUTPUT="$RETURNED_OUTPUT ${CHOICE_VALUES_AS_ARRAY[$((NUMBER - 1))]}"
        #cerr "RETURNED_OUTPUT: $RETURNED_OUTPUT"
        #cerr "VALID_SELECTION_COUNT: $VALID_SELECTION_COUNT"
        #cerr "MAX_SELECTIONS; $MAX_SELECTIONS"
        if [ $VALID_SELECTION_COUNT -ge "$MAX_SELECTIONS" ]; then
          break 2;
        fi
      else
        cerr "Invalid choice: $NUMBER"
        VALID_SELECTION_COUNT=0
        RETURNED_OUTPUT=''
      fi
    done
  done

  # Send the value to STDOUT for the caller to capture
  echo "$RETURNED_OUTPUT" | awk '{$1=$1};1' # Trim leading/trailing space
}

# Zero is a positive integer too.
is_positive_integer() {
  local WHAT="$*"
  if [[ "$WHAT" =~ ^[0-9]+$ ]]; then
    true
  else
    false
  fi
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
