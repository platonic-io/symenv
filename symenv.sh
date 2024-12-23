#!/usr/bin/env bash
# shellcheck disable=SC2039
# ^-- Ignore warning about `local`s

{
  export SYMENV_REGISTRY=portal.platonic.io
  export SYMENV_DEBUG=0
  export SYMENV_DIR=$HOME/.symbiont
  export SYMENV_DEFAULT_INSTALL_LINK=https://raw.githubusercontent.com/symbiont-io/symenv/main/install.sh

  symenv_is_zsh() {
    [ -n "${ZSH_VERSION-}" ]
  }

  symenv_stdout_is_terminal() {
    [ -t 1 ]
  }

  symenv_status () {
      if [ "$2" = "info" ] ; then
          COLOR="96m";
          SIGN="ⓘ "
      elif [ "$2" = "success" ] ; then
          COLOR="92m";
          SIGN="✅"
      elif [ "$2" = "warning" ] ; then
          COLOR="93m";
          SIGN="⚠"
      elif [ "$2" = "error" ] ; then
          COLOR="91m";
          SIGN="❌"
      else
          COLOR="0m";
      fi
      STARTCOLOR="\e[$COLOR";
      ENDCOLOR="\e[0m";
      printf "$STARTCOLOR%b$ENDCOLOR\n" "$SIGN $1";
  }

  symenv_echo() {
    command printf %s\\n "$*" 2>/dev/null
  }

  symenv_debug() {
    if [ "1" = "${SYMENV_DEBUG}" ]; then
        >&2 echo "$*"
        echo "$*" >> symenv_debug.log
    fi
  }

  symenv_cd() {
    \cd "$@"
  }

  symenv_success() {
      symenv_debug "$@"
      >&2 symenv_status "$@" "success"
  }

  symenv_info() {
      symenv_debug "$@"
      >&2 symenv_status "$@" "info"
  }

  symenv_err() {
    symenv_debug "$@"
    >&2 symenv_status "$@" "error"
  }

  symenv_grep() {
    GREP_OPTIONS='' command grep "$@"
  }

  symenv_has() {
    type "${1-}" >/dev/null 2>&1
  }

  if ! symenv_has jq
  then
    symenv_err "'jq' could not be found - please make sure it is installed"
    return 101
  fi

  # Make zsh glob matching behave same as bash
  # This fixes the "zsh: no matches found" errors
  if [ -z "${SYMENV_CD_FLAGS-}" ]; then
    export SYMENV_CD_FLAGS=''
  fi
  if symenv_is_zsh; then
    SYMENV_CD_FLAGS="-q"
  fi

  unset SYMENV_SCRIPT_SOURCE 2>/dev/null
  mkdir -p "${SYMENV_DIR}/versions"

  symenv_print_sdk_version() {
    if symenv_has "sym"; then
      command printf "sym $(sym --version 2>/dev/null)"
    else
      symenv_err "No version of the SDK found locally"
    fi
  }

  symenv_has_system_sdk() {
    [ "$(symenv deactivate >/dev/null 2>&1 && command -v sym)" != '' ]
  }

  symenv_has_managed_sdk() {
    VERSION="${1-}"
    if [[ "" = "${VERSION}" ]]; then
      [ -e "${SYMENV_DIR}/versions/current" ]
    else
      [ -e "${SYMENV_DIR}/versions/${VERSION}" ]
    fi
  }

  symenv_local_versions() {
    if [ -e "${SYMENV_DIR}/versions" ]; then
      find "${SYMENV_DIR}/versions/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
    else
      symenv_debug "No managed versions/ folder in ${SYMENV_DIR}"
    fi
  }

  symenv_list_local_versions() {
    if [ -e "${SYMENV_DIR}/versions" ]; then
      symenv_echo "$(symenv_local_versions | tr " " "\n")"
    else
      symenv_err "No managed versions installed on this system."
    fi
  }

  symenv_fetch_remote_versions() {
    local REGISTRY
    REGISTRY_OVERRIDE=$1
    REGISTRY=$SYMENV_REGISTRY
    CONFIG_REGISTRY=$(symenv_config_get ~/.symenvrc registry)
    [ -n "$CONFIG_REGISTRY" ] && REGISTRY=${CONFIG_REGISTRY}
    [ -n "$REGISTRY_OVERRIDE" ] && REGISTRY=$REGISTRY_OVERRIDE

    symenv_debug "Using remote registry ${REGISTRY}"

    SYMENV_ACCESS_TOKEN="$(symenv_config_get ~/.symenvrc _auth_token)"
    PACKAGES_AVAILABLE=$(curl --silent --tlsv1.2 --proto '=https' --request GET 'https://'"${REGISTRY}"'/api/listSDKPackages' \
      --header "Authorization: Bearer ${SYMENV_ACCESS_TOKEN}")

    symenv_debug "Package response: ${PACKAGES_AVAILABLE}"

    HAS_ERROR=$(echo "${PACKAGES_AVAILABLE}" | jq --raw-output .error)
    if [ "Unauthorized" = "$HAS_ERROR" ]; then
      symenv_err "Authentication error - use '--force-auth' to authenticate"
      return 41
    elif [ "IncorrectPermissions" = "$HAS_ERROR" ]; then
      symenv_err "Permissions error - please contact administrator for the correct permissions"
      return 41
    fi


    if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
      # Linux
      OS_FILTER="linux"
    elif [[ $(echo "${OSTYPE}" | tr "[:upper:]" "[:lower:]") == "darwin"* ]]; then
      # Mac OSX
      OS_FILTER="macos"
    else
      symenv_debug "Using unsupported OS."
      symenv_err "Your OS is not supported."
      return 2;
    fi

    PACKAGES_EXTRACT=$(echo "${PACKAGES_AVAILABLE}" | jq .packages | jq '[.[] | .name]')
    symenv_debug "Found packages:"
    symenv_debug "${PACKAGES_EXTRACT}"

    PACKAGES_OF_INTEREST=$(echo "${PACKAGES_AVAILABLE}" | jq .packages | \
      jq '[.[] | select(.metadata.os=="'${OS_FILTER}'")]')
    symenv_debug "Packages for current OS (${OS_FILTER}): ${PACKAGES_OF_INTEREST}"

    local META_FILE
    META_FILE="${SYMENV_DIR}/versions/versions.meta"
    if [ ! -e "${SYMENV_DIR}/versions" ]; then
      mkdir -p "${SYMENV_DIR}/versions"
    fi
    symenv_debug "Caching versions resolution to ${META_FILE}"
    echo "" > "$META_FILE"
    for row in $(symenv_echo "${PACKAGES_OF_INTEREST}" |
                     jq -r '[.[] | select(.metadata.kind? == "release")]' |
                     jq -r 'group_by(.metadata.version) | [ .[] | sort_by(.name | capture("[a-z_]*/v[0-9]*.[0-9]*.[0-9]*(?<branch>[a-z_-]+)?-(?<counter>[0-9]+)") | .counter | tonumber) | reverse | .[0]  ]' |
                     jq -r '.[] | "\(.metadata.version)=\(.name)"'
                ); do
      symenv_debug "Caching release ${row}"
      echo "${row}" | sed "s/cicd_sdk\///g; s/sdk_packages_lite\///g; s/sdk_packages_full\///" >> "$META_FILE"
    done
    for row in $(symenv_echo "${PACKAGES_OF_INTEREST}" |
                     jq -r '[.[] | select(.metadata.kind != null and .metadata.kind? !="" and .metadata.kind? != "develop" and .metadata.kind? != "next" and .metadata.kind? != "release")]' |
                     jq -r 'group_by(.metadata.version)[] | group_by(.metadata.kind) | [ .[] | sort_by(.name | capture("[a-z_]*/v[0-9]*.[0-9]*.[0-9]*(?<branch>[a-z_-]+)?-(?<counter>[0-9]+)") | .counter | tonumber) | reverse | .[0]  ]' |
                     jq -r '.[] | "\(.metadata.version)-\(.metadata.kind)=\(.name)"'
                ); do
        key=$(echo "${row}" | sed "s/=.*$//")
        value=$(echo "${row}" | sed "s/^.*=//" | sed "s/cicd_sdk\///g; s/sdk_packages_lite\///g; s/sdk_packages_full\///")
        symenv_debug "Caching other ${key} = ${value}"
        symenv_config_set "$META_FILE" "$key" "$value"
    done
    for row in $(symenv_echo "${PACKAGES_OF_INTEREST}" | jq -r '[.[] | select(.metadata.kind? == "next")]' | jq -r '[.[]] | sort_by(.metadata.updated)' | jq -r '.[-1] | "next=\(.name)"'); do
      symenv_debug "Caching next ${row}"
      echo "${row}" | sed "s/cicd_sdk\///g; s/sdk_packages_lite\///g; s/sdk_packages_full\///" >> "$META_FILE"
    done
    symenv_echo "${PACKAGES_OF_INTEREST}"
  }

  symenv_list_remote_versions() {
    local SHOW_ALL
    local HAS_ERROR
    local REGISTRY_OVERRIDE
    local REGISTRY
    HAS_ERROR=""
    SHOW_ALL=0
    while [ $# -ne 0 ]; do
      case "$1" in
        --all) SHOW_ALL=1 ;;
        --debug);;
        --registry*)
          REGISTRY_OVERRIDE=$(echo "$1" | sed 's/\-\-registry\=//g')
          [ "" = "$REGISTRY_OVERRIDE" ] && symenv_err "Error: Missing argument for --registry=<registry>" && return 1
        ;;
      esac
      shift
    done

    REGISTRY=${SYMENV_REGISTRY}
    CONFIG_REGISTRY=$(symenv_config_get ~/.symenvrc registry)
    [ -n "$CONFIG_REGISTRY" ] && REGISTRY=${CONFIG_REGISTRY}
    [ -n "$REGISTRY_OVERRIDE" ] && REGISTRY=${REGISTRY_OVERRIDE}

    PACKAGES_OF_INTEREST=$(symenv_fetch_remote_versions "${REGISTRY}")
    [ -z "$PACKAGES_OF_INTEREST" ] && return 44
    # shellcheck disable=SC2216
    STATUS=$(echo "$PACKAGES_OF_INTEREST" | jq -e . >/dev/null 2>&1  | echo "${PIPESTATUS[1]}")
    if [[ ${STATUS} -eq 0 ]]; then
      symenv_debug "Sucessfully pulled packages ${PACKAGES_OF_INTEREST}"
    else
      symenv_err "Failed to parse packages ${PACKAGES_OF_INTEREST}"
      return 44
    fi
    LENGTH=$(echo "${PACKAGES_OF_INTEREST}" | jq length)
    symenv_debug "${LENGTH} packages found"
    if [ ${SHOW_ALL} -ne 1 ]; then
      symenv_debug "Filtering out to releases only"
      PACKAGES_OF_INTEREST=$(echo "${PACKAGES_OF_INTEREST}" |
                                jq '[.[] | select(.metadata.kind? != null and .metadata.kind == "release")]' |
                                jq -r 'group_by(.metadata.version) | [ .[] | sort_by(.name | capture("[a-z_]*/v[0-9]*.[0-9]*.[0-9]*(?<branch>[a-z_-]+)?-(?<counter>[1-9]+)") | .counter | tonumber) | reverse | .[0]  ]')
      RELEASE_VERSIONS=$(echo "${PACKAGES_OF_INTEREST}" | jq '[.[] | "\(.metadata.version)"]' | jq --raw-output '.[]')
      symenv_echo "${RELEASE_VERSIONS}"
    else
        symenv_debug "Filtering out to all packages"
        local META_FILE
        META_FILE="${SYMENV_DIR}/versions/versions.meta"
        VERSIONS="$(cat $META_FILE | sed '/^$/d' | sed 's/=.*$//')"
        symenv_echo "$VERSIONS"
    fi
  }

  symenv_deactivate() {
    if [ -e "${SYMENV_DIR}/versions/current" ]; then
      rm "${SYMENV_DIR}/versions/current"
      symenv_echo "Deactivated ${SYMENV_DIR}/versions/current"
    else
      symenv_debug "Current managed SDK version not found"
    fi
  }

  decode_base64_url() {
    local BASE64_DECODER_PARAM="-d" # option -d for Linux base64 tool
    echo AAAA | base64 -d > /dev/null 2>&1 || BASE64_DECODER_PARAM="-D" # option -D on MacOS
    local len=$((${#1} % 4))
    local result="$1"
    if [ $len -eq 2 ]; then result="$1"'=='
    elif [ $len -eq 3 ]; then result="$1"'='
    fi
    symenv_echo "$result" | tr '_-' '/+' | base64 $BASE64_DECODER_PARAM
  }

  decode_jose(){
    decode_base64_url "$(symenv_echo -n "$2" | cut -d "." -f "$1")" | jq .
  }

  decode_jwt_part(){
    decode_jose "$1" "$2" | jq 'if .iat then (.iatStr = (.iat|todate)) else . end | if .exp then (.expStr = (.exp|todate)) else . end | if .nbf then (.nbfStr = (.nbf|todate)) else . end'
  }

  decode_jwt(){
     decode_jwt_part 2 "$1"
  }

  symenv_validate_token() {
    local TOKEN
    local JWT_INFO
    local EXPIRY
    local IS_VALID
    TOKEN=${1-}

    if [[ -z $TOKEN ]]; then
      symenv_echo 0
    else
      JWT_INFO=$(decode_jwt "$TOKEN")
      if [[ -z $JWT_INFO ]]; then
        symenv_echo 0
      else
        EXPIRY=$(symenv_echo "$JWT_INFO" | jq .exp | tr -d \")
        NOW=$(date +"%s")
        IS_VALID=0
        [[ "${NOW}" < "${EXPIRY}" ]] && IS_VALID=1
        symenv_echo "${IS_VALID}"
      fi
    fi
  }

  symenv_send_token_request() {
    local TOKEN_RESPONSE
    TOKEN_RESPONSE=$(curl --silent --request POST \
      --url "https://$2/oauth/token" \
      --user-agent "symenv" \
      --header 'content-type: application/x-www-form-urlencoded' \
      --data grant_type=urn:ietf:params:oauth:grant-type:device_code \
      --data device_code="$1" \
      --data "client_id=$3")
    SYMENV_ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq .access_token | tr -d \")
    SYMENV_REFRESH_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq .refresh_token | tr -d \")
    symenv_debug "Using access token: ${SYMENV_ACCESS_TOKEN}, refresh token: ${SYMENV_REFRESH_TOKEN}"
    export SYMENV_ACCESS_TOKEN
    export SYMENV_REFRESH_TOKEN
    unset TOKEN_RESPONSE
  }

  symenv_refresh_access_token() {
    local TOKEN_RESPONSE
    TOKEN_RESPONSE=$(curl --silent --request POST \
      --url "https://$1/oauth/token" \
      --user-agent "symenv" \
      --header 'content-type: application/x-www-form-urlencoded' \
      --data grant_type=refresh_token \
      --data "client_id=$2" \
      --data "refresh_token=$3")
    symenv_debug "Got refresh token response ${TOKEN_RESPONSE}"
    SYMENV_ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq .access_token | tr -d \")
    SYMENV_REFRESH_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq .refresh_token | tr -d \")
    export SYMENV_ACCESS_TOKEN
    export SYMENV_REFRESH_TOKEN
    unset TOKEN_RESPONSE
  }

  symenv_do_auth() {
    local REFRESH
    REFRESH=0
    [[ $* == *--refresh* ]] && REFRESH=1

    REGISTRY=$1
    symenv_debug "Registry passed to do_auth ${REGISTRY}"
    CONFIG_REGISTRY=$(symenv_config_get ~/.symenvrc registry)
    [ -n "$CONFIG_REGISTRY" ] && REGISTRY=${CONFIG_REGISTRY}

    symenv_debug "Authenticating (refresh: ${REFRESH}) to registry ${REGISTRY}"

    CONFIG_RESPONSE=$(curl --silent --proto '=https' --tlsv1.2 --request GET \
                           --url "https://${REGISTRY}/api/config")

    if ! echo "$CONFIG_RESPONSE" | jq -e . >/dev/null 2>&1 ; then
        symenv_err "Unable to retrieve configuration from registry $REGISTRY"
        symenv_info "You can use a different registry using the --registry flag."
        SYMENV_ACCESS_TOKEN=""
        return 1
    fi

    SYMENV_AUTH0_CLIENT_DOMAIN=$(echo "${CONFIG_RESPONSE}" | jq .AUTH0_CLIENT_DOMAIN | tr -d \")
    SYMENV_AUTH0_CLIENT_AUDIENCE=$(echo "${CONFIG_RESPONSE}" | jq .AUTH0_CLIENT_AUDIENCE | tr -d \")
    SYMENV_AUTH0_CLIENT_ID=$(echo "${CONFIG_RESPONSE}" | jq .AUTH0_CLI_CLIENT_ID | tr -d \")

    symenv_debug "Got authentication config:"
    symenv_debug "${CONFIG_RESPONSE}"

    if [[ $REFRESH -ne 1 ]]; then
      # Normal authentication flow
      symenv_echo "You will now be authenticated - please use your Symbiont Portal credentials"
      local NEXT_WAIT_TIME
      unset SYMENV_ACCESS_TOKEN
      CODE_REQUEST_RESPONSE=$(curl --silent --proto '=https' --tlsv1.2  --request POST \
        --url "https://${SYMENV_AUTH0_CLIENT_DOMAIN}/oauth/device/code" \
        --user-agent "symenv" \
        --header 'content-type: application/x-www-form-urlencoded' \
        --data "client_id=${SYMENV_AUTH0_CLIENT_ID}" \
        --data scope='read:current_user offline_access' \
        --data audience="${SYMENV_AUTH0_CLIENT_AUDIENCE}")

      symenv_debug "Got authentication challenge:"
      symenv_debug "${CODE_REQUEST_RESPONSE}"

      DEVICE_CODE=$(echo "${CODE_REQUEST_RESPONSE}" | jq .device_code | tr -d \")
      USER_CODE=$(echo "${CODE_REQUEST_RESPONSE}" | jq .user_code | tr -d \")
      VERIFICATION_URL=$(echo "${CODE_REQUEST_RESPONSE}" | jq .verification_uri_complete | tr -d \")

      symenv_echo "If your browser doesn't automatically open, please navigate to ${VERIFICATION_URL}"
      symenv_echo "Please validate the user code: ${USER_CODE}"
      symenv_echo "Close the browser tab once a confirmation has appeared."
      sleep 3

      if symenv_has open
      then
        open "${VERIFICATION_URL}"
      elif symenv_has xdg-open
      then
        xdg-open "${VERIFICATION_URL}"
      fi
      NEXT_WAIT_TIME=1
      until [ ${NEXT_WAIT_TIME} -eq 30 ] || [[ ${SYMENV_ACCESS_TOKEN} != "null" && -n ${SYMENV_ACCESS_TOKEN} ]]; do
        symenv_send_token_request "${DEVICE_CODE}" "${SYMENV_AUTH0_CLIENT_DOMAIN}" "${SYMENV_AUTH0_CLIENT_ID}"
        NEXT_WAIT_TIME=$(( $NEXT_WAIT_TIME + 1 ))
        sleep 1
      done
      [ "${NEXT_WAIT_TIME}" -lt 30 ]

      if [[ ${SYMENV_ACCESS_TOKEN} == "null" || -z ${SYMENV_ACCESS_TOKEN} ]]; then
        symenv_err "🚫 Authentication did not complete in time"
        return 41
      fi
    else
      # Refresh authentication flow
      symenv_refresh_access_token "$SYMENV_AUTH0_CLIENT_DOMAIN" "$SYMENV_AUTH0_CLIENT_ID" "$SYMENV_REFRESH_TOKEN"
    fi
  }

  symenv_curl_libz_support() {
    curl -V 2>/dev/null | symenv_grep "^Features:" | symenv_grep -q "libz"
  }

  symenv_download() {
    local CURL_COMPRESSED_FLAG
    if symenv_has "curl"; then
      if symenv_curl_libz_support; then
        CURL_COMPRESSED_FLAG="--compressed"
      fi
      curl --proto '=https' --tlsv1.2 --fail ${CURL_COMPRESSED_FLAG:-} -q "$@"
    elif symenv_has "wget"; then
      # Emulate curl with wget
      ARGS=$(symenv_echo "$@" | command sed -e 's/--progress-bar /--progress=bar /' \
                              -e 's/--compressed //' \
                              -e 's/--fail //' \
                              -e 's/-L //' \
                              -e 's/-I /--server-response /' \
                              -e 's/-s /-q /' \
                              -e 's/-sS /-nv /' \
                              -e 's/-o /-O /' \
                              -e 's/-C - /-c /')
      # shellcheck disable=SC2086
      eval wget $ARGS
    fi
  }

  symenv_install_from_remote() {
    local FORCE_REINSTALL
    local HAS_ERROR
    local MAPPED_VERSION
    local PROVIDED_VERSION
    local REGISTRY_OVERRIDE
    local REGISTRY
    HAS_ERROR=""
    FORCE_REINSTALL=0
    while [ $# -ne 0 ]; do
      case "$1" in
        --registry*)
          REGISTRY_OVERRIDE=$(echo "$1" | sed 's/\-\-registry\=//g')
          [ "" = "$REGISTRY_OVERRIDE" ] && symenv_err "Error: Missing argument for --registry=<registry>" && return 1
          ;;
        --force) FORCE_REINSTALL=1 ;;
        --debug) ;;
        --force-auth) ;; 
        *)
          if [ -n "${1-}" ]; then
            PROVIDED_VERSION="$1"
          fi
        ;;
      esac
      shift
    done

    if [ -z "$PROVIDED_VERSION" ]; then
      symenv_err "A version is required: 'symenv install <version>'"
      return 44
    fi

    REGISTRY=${SYMENV_REGISTRY}
    CONFIG_REGISTRY=$(symenv_config_get ~/.symenvrc registry)
    [ -n "$CONFIG_REGISTRY" ] && REGISTRY=${CONFIG_REGISTRY}
    [ -n "$REGISTRY_OVERRIDE" ] && REGISTRY=${REGISTRY_OVERRIDE}
    symenv_debug "Installing version ${PROVIDED_VERSION} (force: ${FORCE_REINSTALL}, registry: ${REGISTRY})"

    PACKAGES_OF_INTEREST=$(symenv_fetch_remote_versions "${REGISTRY}")
    [ -z "$PACKAGES_OF_INTEREST" ] && return 44
    SYMENV_ACCESS_TOKEN="$(symenv_config_get ~/.symenvrc _auth_token)"
    if [ ! -e "${SYMENV_DIR}"/versions/versions.meta ]; then
      # shellcheck disable=SC2216
      STATUS=$(echo "$PACKAGES_OF_INTEREST" | jq -e . >/dev/null 2>&1  | echo "${PIPESTATUS[1]}")
      if [[ ${STATUS} -eq 0 ]]; then
        symenv_debug "Sucessfully pulled packages ${PACKAGES_OF_INTEREST}"
      else
        symenv_err "Failed to parse packages ${PACKAGES_OF_INTEREST}"
        return 44
      fi
    fi
    MAPPED_VERSION="$(symenv_config_get "${SYMENV_DIR}"/versions/versions.meta "${PROVIDED_VERSION}")"
    symenv_debug "Mapped version ${PROVIDED_VERSION} to package ${MAPPED_VERSION}"

    if [ -z "$MAPPED_VERSION" ]; then
      symenv_err "No such version found in the remote repo"
      return 44
    fi

    mkdir -p "${SYMENV_DIR}/versions/"
    TARGET_PATH=${SYMENV_DIR}/versions/${PROVIDED_VERSION}

    if [[ -e ${TARGET_PATH} && ${FORCE_REINSTALL} -ne 1 ]]; then
      symenv_err "Requested version (${PROVIDED_VERSION}) is already installed locally."
      symenv_err "To force reinstallation from remote use the \`--force\` argument"
      return 0
    fi
    if [[ -e ${TARGET_PATH} ]]; then
      rm -rf "${TARGET_PATH}"
    fi
    mkdir -p "${TARGET_PATH}"

    SIGNED_URL_RESPONSE=$(curl --proto '=https' --tlsv1.2  --silent --request GET "https://${REGISTRY}/api/getSDKPackage?package=${MAPPED_VERSION}" \
      --header "Authorization: Bearer ${SYMENV_ACCESS_TOKEN}")
    SIGNED_DOWNLOAD_URL=$(echo "${SIGNED_URL_RESPONSE}" | jq .signedUrl | tr -d \")
    symenv_debug "Got signed URL: ${SIGNED_DOWNLOAD_URL}"

    TARGET_FILE="${TARGET_PATH}/download.tar.gz"
#    curl --silent --request GET "${SIGNED_DOWNLOAD_URL}" -o "${TARGET_FILE}"
    symenv_download -L -C - --progress-bar "${SIGNED_DOWNLOAD_URL}" -o "${TARGET_FILE}"

    if [ ! -f "${TARGET_FILE}" ]; then
      symenv_err "SDK Failed to Download"
      return 44
    fi
    
    tar xzf "${TARGET_FILE}" --directory "${TARGET_PATH}" --strip-components=2
    rm "${TARGET_FILE}"

    if [[ -e "${SYMENV_DIR}/versions/current" ]]; then
      rm "${SYMENV_DIR}/versions/current"
    fi
    ln -s "${TARGET_PATH}" "${SYMENV_DIR}/versions/current"
  }

  symenv_config_set() {
    local FILE
    local KEY
    local VALUE
    FILE=${1-}
    if [ ! -e "${FILE}" ]; then
      symenv_err "Attempting to set in undefined file"
    fi
    KEY=${2-}
    if [[ "" == "${KEY}" ]]; then
      symenv_err "Attempting to set undefined field"
    fi
    VALUE=${3-}

    #if there's no match, sed will just output the key itself
    # otherwise set the key equal to the left size of the equal and set the value to the right side
    if [[ "$(echo $KEY | sed 's/^\(.*\)=\(.*\)$/\2/g' )" != $KEY && $VALUE == "" ]]; then 
      symenv_debug "Equals passed to ${KEY} and no value ${VALUE}"
      VALUE="$(echo $KEY | sed 's/\(.*\)=\(.*\)/\2/g' )"
      KEY="$(echo $KEY | sed 's/\(.*\)=\(.*\)/\1/g' )"
    fi

    symenv_debug "Setting config key ${KEY} to ${VALUE}"
    HAS_VALUE=$(grep -R "^[#]*\s*${KEY}=.*" "${FILE}")
    symenv_debug "Value existing: ${HAS_VALUE}"
    if [ -z "${HAS_VALUE}" ]; then
      echo "${KEY}=${VALUE}" >> "${FILE}"
    else
      sed -i'' -E "s/^[#]*\s*${KEY}=.*/${KEY}=${VALUE}/" "${FILE}"
    fi
  }

  symenv_config_get() {
    local FILE
    local KEY
    FILE=${1-}
    KEY=${2-}
    symenv_debug "Getting $KEY from $FILE"
    if [ ! -e "${FILE}" ]; then
      symenv_err "Attempting to get in undefined file"
    fi
    if [[ "" == "${KEY}" ]]; then
      symenv_err "Attempting to get undefined field"
    fi
    symenv_echo "$(sed -En "s/^${KEY}=(.*)$/\1/p" "${FILE}")"
  }

  symenv_config() {
    touch "${HOME}/.symenvrc"
    chmod 0600 "${HOME}/.symenvrc"
    while [ $# -ne 0 ]; do
      case "$1" in
        --debug);;
        get)
          symenv_echo "$(symenv_config_get "${HOME}/.symenvrc" "${@:2}")"
        ;;
        set)
          symenv_config_set "${HOME}/.symenvrc" "${@:2}"
        ;;
        ls)
          cat "${HOME}/.symenvrc"
        ;;
      esac
      shift
    done
  }

  symenv_export_registry_from_settings() {
    local OVERRIDE
    OVERRIDE="$(symenv_config_get "${HOME}/.symenvrc" registry)"
    if [ -n "$OVERRIDE" ]; then
      symenv_debug "Using custom registry from .symenvrc: ${OVERRIDE}"
      export SYMENV_REGISTRY=$OVERRIDE
    fi
    unset OVERRIDE
  }

  symenv_auth() {
    local FORCE_REAUTH
    local REGISTRY_OVERRIDE
    local IS_VALID
    FORCE_REAUTH=0
    while [ $# -ne 0 ]; do
      case "$1" in
        --debug);;
        --force-auth) FORCE_REAUTH=1 ;;
        --registry*)
          REGISTRY_OVERRIDE=$(echo "$1" | sed 's/\-\-registry\=//g')
          [ "" = "$REGISTRY_OVERRIDE" ] && symenv_err "Error: Missing argument for --registry=<registry>" && return 1
          symenv_debug "Using command-line auth registry override: $REGISTRY_OVERRIDE"
        ;;
      esac
      shift
    done
    REGISTRY=$SYMENV_REGISTRY
    [ -n "$REGISTRY_OVERRIDE" ] && REGISTRY=$REGISTRY_OVERRIDE
    # If we have a symenvrc file, check credentials in there
    if [[ -e "${HOME}/.symenvrc" && $FORCE_REAUTH -ne 1 ]]; then
      # Do we have a SYMENV_ACCESS_TOKEN? Check if the token has expired, if so trigger a re-auth
      SYMENV_ACCESS_TOKEN="$(symenv_config_get "${HOME}/.symenvrc" _auth_token)"
      SYMENV_REFRESH_TOKEN="$(symenv_config_get "${HOME}/.symenvrc" _refresh_token)"
      export SYMENV_REFRESH_TOKEN
      symenv_debug "Evaluating validity of access token ${SYMENV_ACCESS_TOKEN}"
      IS_VALID=0
      IS_VALID=$(symenv_validate_token "${SYMENV_ACCESS_TOKEN}")
      # We don't have a valid SYMENV_ACCESS_TOKEN - get a new one, and refresh the refresh token
      if [[ ${IS_VALID} == 0 ]]; then
        if [[ -n "${SYMENV_REFRESH_TOKEN}" ]]; then
          symenv_debug "Refreshing tokens using refresh token ${SYMENV_REFRESH_TOKEN}"
          # Our access token is invalid but we have a refresh token, let's refresh
          symenv_do_auth "$REGISTRY" --refresh
          [ "" = "${SYMENV_ACCESS_TOKEN}" ] && return 1
          symenv_debug "Setting access token ${SYMENV_ACCESS_TOKEN}"
          symenv_debug "Setting refresh token ${SYMENV_REFRESH_TOKEN}"
          symenv_config_set "${HOME}/.symenvrc" _auth_token "${SYMENV_ACCESS_TOKEN}"
          symenv_config_set "${HOME}/.symenvrc" _refresh_token "${SYMENV_REFRESH_TOKEN}"
        else
          symenv_auth --registry="$REGISTRY" --force-auth
          SYMENV_ACCESS_TOKEN="$(symenv_config_get "${HOME}/.symenvrc" _auth_token)"
        fi
      fi
    else
      # Otherwise, no file, means we go from scratch
      symenv_do_auth "$REGISTRY"
      if [ "" = "${SYMENV_ACCESS_TOKEN}" ] | [ null = "${SYMENV_ACCESS_TOKEN}" ]; then 
        return 1
      fi
      touch "${HOME}/.symenvrc"
      chmod 0600 "${HOME}/.symenvrc"
      symenv_config_set "${HOME}/.symenvrc" _auth_token "${SYMENV_ACCESS_TOKEN}"
      symenv_config_set "${HOME}/.symenvrc" _refresh_token "${SYMENV_REFRESH_TOKEN}"
      symenv_success "Authentication successful"
    fi
    export SYMENV_ACCESS_TOKEN
    unset FORCE_REAUTH
    unset REGISTRY_OVERRIDE
    unset IS_VALID
  }

  symenv_append_path()
  {
    if ! eval test -z "\"\${$1##*:$2:*}\"" -o -z "\"\${$1%%*:$2}\"" -o -z "\"\${$1##$2:*}\"" -o -z "\"\${$1##$2}\"" ; then
      eval "$1=\$$1:$2"
    fi
  }

  symenv_update()
  {
    CURRENT=$(pwd)
    cd "$SYMENV_DIR"
    git fetch --all --quiet
    LATEST_TAG=$(git describe --tags `git rev-list --tags --max-count=1`)
    CURRENT_TAG=$(git describe)
    symenv_debug "Currently on tag ${CURRENT_TAG}. ${LATEST_TAG} is latest available."
    if [[ "$CURRENT_TAG" != "$LATEST_TAG" ]]; then
      symenv_echo "Updating symenv to latest version found ($LATEST_TAG)"
      git checkout -q $LATEST_TAG
      . "$SYMENV_DIR/symenv.sh"
    fi
    cd "$CURRENT"
  }

  symenv() {
    if [ $# -lt 1 ]; then
      symenv --help
      return
    fi

    local DEFAULT_IFS
    DEFAULT_IFS=" $(symenv_echo t | command tr t \\t)
"
    if [ "${-#*e}" != "$-" ]; then
      set +e
      local EXIT_CODE
      IFS="${DEFAULT_IFS}" symenv "$@"
      EXIT_CODE=$?
      set -e
      return $EXIT_CODE
    elif [ "${IFS}" != "${DEFAULT_IFS}" ]; then
      IFS="${DEFAULT_IFS}" symenv "$@"
      return $?
    fi

    local COMMAND
    COMMAND="${1-}"
    shift

    for value in "$@"; do
        if [ "--debug" = "$value" ]; then
           export SYMENV_DEBUG=1
           symenv_debug "Using debug output"
        fi
    done

    # Override our default registry to use whatever the user has set in his `~/.symenvrc` file
    touch "${HOME}/.symenvrc"
    symenv_export_registry_from_settings
    SYMENV_AUTO_UPDATE="$(symenv_config_get "${HOME}/.symenvrc" auto_update)"

    if [ "${SYMENV_AUTO_UPDATE}" = "1" ]; then
        symenv_debug "Using auto_update. Verifying if we need to update."
        symenv_update
    fi

    symenv_debug "Executing " "$COMMAND" "$@"
    case $COMMAND in
      "help" | "--help")
        version=$(symenv --version)
        symenv_echo "$version"
        symenv_echo 'Usage:'
        symenv_echo '  symenv --help                                  Show this message'
        symenv_echo '  symenv --version                               Print out the version of symenv'
        symenv_echo '  symenv login                                   Authenticate to the provided portal'
        symenv_echo '  symenv current                                 Print out the installed version of the SDK'
        symenv_echo '  symenv config                                  Print out the configuration used by symenv'
        symenv_echo '    ls                                             List all key value pairs in configuration'
        symenv_echo '    get <key>                                      Print the value for <key>'
        symenv_echo '    set <key> <value>                              Set the value for <key>'
        symenv_echo '    eg.'
        symenv_echo '        auto_update 1                              Turn on symenv auto-update (this will not update the SDK)'
        symenv_echo '        registry iportal.symbiont.io               Points the asset registry to another hosted registry '
        symenv_echo '  symenv install [options] <version>             Download and install a <version> of the SDK'
        symenv_echo '    --registry=<registry>                          When downloading, use this registry'
        symenv_echo '    --force-auth                                   Refresh the user token before downloading'
        symenv_echo '  symenv use [options] <version>                 Use version <version> of the SDK'
        symenv_echo '    --silent                                       No output'
        symenv_echo '  symenv deactivate                              Remove the symlink binding the installed version to current'
        symenv_echo '  symenv ls | list | local                       List the installed versions of the SDK'
        symenv_echo '  symenv ls-remote | list-remote | remote        List the available remote versions of the SDK'
        symenv_echo '    --all                                          Include the non-release versions'
        symenv_echo '    --registry=<registry>                          Show versions from a specific registry'
        symenv_echo '    --force-auth                                   Refresh the user token before fetching versions'
        symenv_echo '  symenv check                                   Checks for updates on symenv (does not install)'
        symenv_echo '  symenv update                                  Updates symenv to the latest update available'
        symenv_echo '  symenv reset                                   Resets your environment to a fresh install of symenv'
      ;;
      "install" | "i")
        symenv_auth "$@"
        [ "" = "${SYMENV_ACCESS_TOKEN}" ] && return 1
        symenv_install_from_remote "$@"
      ;;
      "use" | "activate")
        local PROVIDED_VERSION
        local SYMENV_USE_SILENT
        SYMENV_USE_SILENT=0

        while [ $# -ne 0 ]; do
          case "$1" in
            --silent) SYMENV_USE_SILENT=1 ;;
            --) ;;
            --*) ;;
            *)
              if [ -n "${1-}" ]; then
                PROVIDED_VERSION="$1"
              fi
            ;;
          esac
          shift
        done

        VERSION="${PROVIDED_VERSION}"
        symenv_debug "Activating version: ${VERSION}"
        if [ -z "${VERSION}" ]; then
          >&2 symenv --help
          return 127
        elif [ "_${PROVIDED_VERSION}" = "_default" ]; then
          return 0
        fi

        # Version is system - deactivate our managed version for now
        if [ "_${PROVIDED_VERSION}" = '_system' ]; then
          if symenv_has_system_sdk && symenv deactivate >/dev/null 2>&1; then
            if [ $SYMENV_USE_SILENT -ne 1 ]; then
              symenv_echo "Now using system version of SDK: $(sym -v 2>/dev/null)$(symenv_print_sdk_version)"
            fi
            return
          elif [ $SYMENV_USE_SILENT -ne 1 ]; then
            symenv_err 'System version of node not found.'
          fi
          return 127
        fi

        # Check if the version is installed
        if symenv_has_managed_sdk "${PROVIDED_VERSION}"; then
          symenv_echo "Switching managed version to ${PROVIDED_VERSION}"
          rm "${SYMENV_DIR}/versions/current" 2>/dev/null
          ln -s "${SYMENV_DIR}/versions/${PROVIDED_VERSION}" "${SYMENV_DIR}/versions/current"
          symenv_append_path PATH "${SYMENV_DIR}/versions/current/bin"
          export PATH=$PATH
        else
          symenv_err "Version ${PROVIDED_VERSION} is not installed. Please install it before switching."
          return 127
        fi

      ;;
      "remote" | "ls-remote" | "list-remote")
        symenv_auth "$@"
        [ "" = "${SYMENV_ACCESS_TOKEN}" ] && return 1
        symenv_list_remote_versions "$@"
      ;;
      "login")
        symenv_auth "$@"
        [ "" = "${SYMENV_ACCESS_TOKEN}" ] && return 1
      ;;
      "list" | "ls" | "local")
        symenv_list_local_versions
      ;;
      "deactivate")
        symenv_deactivate
      ;;
      "reset")
        rm -rf "${SYMENV_DIR}"/versions 2>/dev/null
        rm "${HOME}"/.symenvrc 2>/dev/null
      ;;
      "current")
        if symenv_has_managed_sdk; then
          TARGET=$(readlink "${SYMENV_DIR}"/versions/current | sed "s|$SYMENV_DIR/versions/||g")
          if symenv_has "sym"; then
            VERSION=$(sym --version)
          else
            VERSION="sym not found on PATH. Is your PATH set correctly?"
          fi
          symenv_echo "current -> $TARGET ($VERSION)"
        else
          symenv_echo "Using system version of SDK: $(sym -v 2>/dev/null)$(symenv_print_sdk_version)"
          symenv_echo "$(which sym)"
        fi
      ;;
      "config")
        symenv_config "$@"
      ;;
      "version" | "-version" |  "--version")
        CURRENT=$(pwd)
        cd "$SYMENV_DIR"
        TAG=$(git describe --long --first-parent)
        symenv_echo "Symbiont Assembly SDK Manager (${TAG})"
        cd "$CURRENT"
      ;;
      "update")
        symenv_update
      ;;
      "check")
        CURRENT=$(pwd)
        cd "$SYMENV_DIR"
        git fetch --all --quiet
        LATEST_TAG=$(git describe --tags `git rev-list --tags --max-count=1`)
        CURRENT_TAG=$(git describe)
        if [[ "$CURRENT_TAG" != "$LATEST_TAG" ]]; then
            symenv_echo "symenv can be updated to version ${LATEST_TAG}, run \"symenv update\"."
        fi
        cd "$CURRENT"
      ;;
      *)
        >&2 symenv --help
        return 127
      ;;
    esac
  }

  symenv_auto() {
    symenv use --silent default >/dev/null
  }

  symenv_supports_source_options() {
    # shellcheck disable=SC1091,SC2240
    [ "_$( . /dev/stdin yes 2> /dev/null <<'EOF'
[ $# -gt 0 ] && symenv_echo $1
EOF
    )" = "_yes" ]
  }

  symenv_process_parameters() {
    local SYMENV_AUTO_MODE
    SYMENV_AUTO_MODE='use'
    if symenv_supports_source_options; then
      while [ $# -ne 0 ]; do
        case "$1" in
          install) SYMENV_AUTO_MODE='install' ;;
          --no-use) SYMENV_AUTO_MODE='none' ;;
        esac
        shift
      done
    fi
    symenv_auto "${SYMENV_AUTO_MODE}"
  }

  symenv_process_parameters "$@"
}
