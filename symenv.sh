{
  symenv_SCRIPT_SOURCE="$_"

  if ! command -v jq &> /dev/null
  then
    symenv_err "'jq' could not be found - please make sure it is installed"
    return 101
  fi

  # export SYMENV_CLIENT_ID=KHKUQ2CpJQ0YjUyvtoIweUZMBRldAyqx
  export SYMENV_CLIENT_ID=v6VhzaOcbtcJovxph1qqQiqafLfoRrvT
  # export SYMENV_TENANT=sym-dev.eu.auth0.com
  export SYMENV_TENANT=internal-portal.us.auth0.com

  symenv_is_zsh() {
    [ -n "${ZSH_VERSION-}" ]
  }

  symenv_stdout_is_terminal() {
    [ -t 1 ]
  }

  symenv_echo() {
    command printf %s\\n "$*" 2>/dev/null
  }

  symenv_cd() {
    \cd "$@"
  }

  symenv_err() {
    >&2 symenv_echo "$@"
  }

  symenv_grep() {
    GREP_OPTIONS='' command grep "$@"
  }

  symenv_has() {
    type "${1-}" >/dev/null 2>&1
  }

  # Make zsh glob matching behave same as bash
  # This fixes the "zsh: no matches found" errors
  if [ -z "${SYMENV_CD_FLAGS-}" ]; then
    export SYMENV_CD_FLAGS=''
  fi
  if symenv_is_zsh; then
    SYMENV_CD_FLAGS="-q"
  fi

  # Auto detect the SYMENV_DIR when not set
  if [ -z "${SYMENV_DIR-}" ]; then
    # shellcheck disable=SC2128
    if [ -n "${BASH_SOURCE-}" ]; then
      # shellcheck disable=SC2169
      SYMENV_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    fi
#    SYMENV_DIR="$(symenv_cd ${SYMENV_CD_FLAGS} "$(dirname "${SYMENV_SCRIPT_SOURCE:-$0}")" >/dev/null && \pwd)"
    SYMENV_DIR=~/.symbiont
    export SYMENV_DIR
  else
    # https://unix.stackexchange.com/a/198289
    case $SYMENV_DIR in
      *[!/]*/)
        SYMENV_DIR="${SYMENV_DIR%"${SYMENV_DIR##*[!/]}"}"
        export SYMENV_DIR
        symenv_err "Warning: \$SYMENV_DIR should not have trailing slashes"
      ;;
    esac
  fi
  unset SYMENV_SCRIPT_SOURCE 2>/dev/null
  mkdir -p ${SYMENV_DIR}/versions

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
      [ -e "${SYMENV_DIR}/current" ]
    else
      [ -e "${SYMENV_DIR}/versions/${VERSION}" ]
    fi
  }

  symenv_local_versions() {
    if [ -e "${SYMENV_DIR}/versions" ]; then
      find "${SYMENV_DIR}/versions/" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 basename
    fi
  }

  symenv_list_local_versions() {
    if [ -e "${SYMENV_DIR}/versions" ]; then
      # symenv_echo "Available versions:"
      symenv_echo $(symenv_local_versions) | tr " " "\n"
    else
      symenv_err "No managed versions installed on this system."
    fi
  }

  symenv_build_remote_versions_resolution() {
    local META_FILE
    DATA=${1}

    META_FILE="${SYMENV_DIR}/versions/versions.meta"
    echo "" > $META_FILE
    for row in $(symenv_echo ${DATA} | jq -r '[.[] | select(.preRelease=="release" or .preRelease=="")]' | jq -r '.[] | "\(.version)=assembly-sdk/\(.version)/\(.name)"'); do
      echo ${row} >> $META_FILE
    done
    for row in $(symenv_echo ${DATA} | jq -r '[.[] | select(.preRelease!="")]' | jq -r '.[] | "\(.version)-\(.preRelease)=assembly-sdk/\(.version)/\(.name)"'); do
      echo ${row} >> $META_FILE
    done
  }

  symenv_fetch_remote_versions() {
    SYMENV_ACCESS_TOKEN="$(symenv_config_get ~/.symenvrc _auth_token)"
    PACKAGES_AVAILABLE=$(curl --silent --request GET 'https://iportal.waf-symbiont.io/api/listPackages' \
      --header "Authorization: Bearer ${SYMENV_ACCESS_TOKEN}")

    HAS_ERROR=`echo ${PACKAGES_AVAILABLE} | jq --raw-output .error`
    if [ "Unauthorized" = "$HAS_ERROR" ]; then
      symenv_err "Authentication error"
      return 401
    fi

    if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
      # Linux
      OS_FILTER="linux"
    elif [[ "${OSTYPE}" == "darwin"* ]]; then
      # Mac OSX
      OS_FILTER="mac"
    else
      echo "Your OS is not supported."
      return 2;
    fi

    PACKAGES_OF_INTEREST=`echo ${PACKAGES_AVAILABLE} | jq .packages | jq '."assembly-sdk"' | \
      jq '[.[] | select(.platform=="'${OS_FILTER}'")]'`
    symenv_build_remote_versions_resolution "${PACKAGES_OF_INTEREST}"
    symenv_echo "${PACKAGES_OF_INTEREST}"
  }

  symenv_list_remote_versions() {
    local SHOW_ALL
    local HAS_ERROR
    HAS_ERROR=""
    SHOW_ALL=0
    while [ $# -ne 0 ]; do
      case "$1" in
        --all) SHOW_ALL=1 ;;
      esac
      shift
    done
    PACKAGES_OF_INTEREST=$(symenv_fetch_remote_versions)
    if [ ${SHOW_ALL} -ne 1 ]; then
      PACKAGES_OF_INTEREST=`echo ${PACKAGES_OF_INTEREST} | jq '[.[] | select(.preRelease=="release" or .preRelease=="" and .version !="develop")]'`
      DISPLAY_VERSIONS=`echo ${PACKAGES_OF_INTEREST} | jq '[.[] | "\(.version)"]' | jq --raw-output '.[]'`
      symenv_echo "${DISPLAY_VERSIONS}"
    else
      RELEASE_VERSIONS=`echo ${PACKAGES_OF_INTEREST} | jq -r '[.[] | select(.preRelease=="release" or .preRelease=="")]' | \
        jq '[.[] | "\(.version)"]' | jq --raw-output '.[]'`
      DISPLAY_VERSIONS=`echo ${PACKAGES_OF_INTEREST} | jq -r '[.[] | select(.preRelease!="release" and .preRelease!="")]' | \
        jq '[.[] | "\(.version)-\(.preRelease)"]' | jq --raw-output '.[]'`
      symenv_echo "${RELEASE_VERSIONS}"
      symenv_echo "${DISPLAY_VERSIONS}"
    fi

  }

  symenv_deactivate() {
    if [ -e "${SYMENV_DIR}/current" ]; then
      rm "${SYMENV_DIR}/current"
      symenv_echo "Deactivated ${SYMENV_DIR}/current"
    fi
  }

  symenv_decode_base64_url() {
    local len=$((${#1} % 4))
    local result="$1"
    if [ $len -eq 2 ]; then result="$1"'=='
    elif [ $len -eq 3 ]; then result="$1"'='
    fi
    symenv_echo "$result" | tr '_-' '/+' | openssl enc -d -base64
  }

  symenv_decode_jwt(){
     symenv_decode_base64_url $(echo -n $2 | cut -d "." -f $1) | jq .
  }

  symenv_validate_token() {
    TOKEN=${1-}
    # TODO
    # symenv_echo "$(symenv_decode_jwt 2 ${TOKEN})"
    # symenv_echo "Validating ${TOKEN}"
  }

  symenv_send_token_request() {
    TOKEN_RESPONSE=$(curl --silent --request POST \
      --url "https://${SYMENV_TENANT}/oauth/token" \
      --header 'content-type: application/x-www-form-urlencoded' \
      --data grant_type=urn:ietf:params:oauth:grant-type:device_code \
      --data device_code="$1" \
      --data "client_id=${SYMENV_CLIENT_ID}")
    SYMENV_ACCESS_TOKEN=`echo ${TOKEN_RESPONSE} | jq .access_token | tr -d \"`
    export SYMENV_ACCESS_TOKEN
  }

  symenv_do_auth() {
    local NEXT_WAIT_TIME
    unset SYMENV_ACCESS_TOKEN
    CODE_REQUEST_RESPONSE=$(curl --silent --request POST \
      --url "https://${SYMENV_TENANT}/oauth/device/code" \
      --header 'content-type: application/x-www-form-urlencoded' \
      --data "client_id=${SYMENV_CLIENT_ID}" \
      --data scope='read:current_user update:current_user_metadata' \
      --data audience=https://iportal.symbiont.io)

    DEVICE_CODE=`echo ${CODE_REQUEST_RESPONSE} | jq .device_code | tr -d \"`
    USER_CODE=`echo ${CODE_REQUEST_RESPONSE} | jq .user_code | tr -d \"`
    VERIFICATION_URL=`echo ${CODE_REQUEST_RESPONSE} | jq .verification_uri_complete | tr -d \"`

    if symenv_has open
    then
        open ${VERIFICATION_URL}
    else
      echo "Please authenticate using the following URL: ${VERIFICATION_URL}"
    fi
    NEXT_WAIT_TIME=1
    until [ ${NEXT_WAIT_TIME} -eq 30 ] || [[ ${SYMENV_ACCESS_TOKEN} != "null" && ! -z ${SYMENV_ACCESS_TOKEN} ]]; do
      symenv_send_token_request ${DEVICE_CODE}
      sleep $((NEXT_WAIT_TIME++))
    done
    [ ${NEXT_WAIT_TIME} -lt 30 ]

    if [[ ${SYMENV_ACCESS_TOKEN} == "null" || -z ${SYMENV_ACCESS_TOKEN} ]]; then
      symenv_err "🚫 Authentication did not complete in time"
      return 401
    fi
  }

  symenv_install_from_remote() {
    local FORCE_REINSTALL
    local HAS_ERROR
    local MAPPED_VERSION
    local PROVIDED_VERSION
    HAS_ERROR=""
    FORCE_REINSTALL=0
    while [ $# -ne 0 ]; do
      case "$1" in
        --force) FORCE_REINSTALL=1 ;;
        *)
          if [ -n "${1-}" ]; then
            PROVIDED_VERSION="$1"
          fi
        ;;
      esac
      shift
    done

    echo "Installing version ${PROVIDED_VERSION} (force: ${FORCE_REINSTALL})"

    SYMENV_ACCESS_TOKEN="$(symenv_config_get ~/.symenvrc _auth_token)"
    if [ ! -e ${SYMENV_DIR}/versions/versions.meta ]; then
      PACKAGES=$(symenv_fetch_remote_versions)
    fi
    MAPPED_VERSION="$(symenv_config_get ${SYMENV_DIR}/versions/versions.meta ${PROVIDED_VERSION})"
    # TODO: Handle negative cases

    mkdir -p ${SYMENV_DIR}/versions/
    TARGET_PATH=${SYMENV_DIR}/versions/${PROVIDED_VERSION}

    if [[ -e ${TARGET_PATH} && ${FORCE_REINSTALL} -ne 1 ]]; then
      symenv_echo "Requested version (${PROVIDED_VERSION}) is already installed locally."
      symenv_echo "To force reinstallation from remote use the \`--force\` argument"
      return 0
    fi
    if [[ -e ${TARGET_PATH} ]]; then
      rm -rf ${TARGET_PATH}
    fi
    mkdir -p ${TARGET_PATH}

    SIGNED_URL_RESPONSE=$(curl --silent --request GET "https://iportal.waf-symbiont.io/api/getPackage?package=${MAPPED_VERSION}" \
      --header "Authorization: Bearer ${SYMENV_ACCESS_TOKEN}")
    SIGNED_DOWNLOAD_URL=`echo ${SIGNED_URL_RESPONSE} | jq .signedUrl | tr -d \"`

    TARGET_FILE="${TARGET_PATH}/download.tbz2"
    curl --silent --request GET "${SIGNED_DOWNLOAD_URL}" -o "${TARGET_FILE}"
    tar xf "${TARGET_FILE}" --directory "${TARGET_PATH}"
    rm ${TARGET_FILE}

    if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
      # Linux
      CONTAINING_FOLDER=`find ${TARGET_PATH} -mindepth 2 -maxdepth 2 -type d`
      mv "${CONTAINING_FOLDER}"/* ${TARGET_PATH}
    elif [[ "${OSTYPE}" == "darwin"* ]]; then
      # Mac OSX
      INSTALLER_NAME=`ls ${TARGET_PATH} | grep .pkg`
      sudo installer -pkg ${TARGET_PATH}/${INSTALLER_NAME} -target ${TARGET_PATH}
    fi

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
    if ! grep -R "^[#]*\s*${KEY}=.*" ${FILE} > /dev/null; then
      echo "${KEY}=${VALUE}" >> ${FILE}
    else
      sed -i '' -r "s/^[#]*\s*${KEY}=.*/${KEY}=${VALUE}/" ${FILE}
    fi
  }

  symenv_config_get() {
    local FILE
    local KEY
    FILE=${1-}
    if [ ! -e "${FILE}" ]; then
      symenv_err "Attempting to get in undefined file"
    fi
    KEY=${2-}
    if [[ "" == "${KEY}" ]]; then
      symenv_err "Attempting to get undefined field"
    fi
    symenv_echo "$(sed -rn "s/^${KEY}=(.*)$/\1/p" ${FILE})"
  }

  symenv_auth() {
    local FORCE_REAUTH
    FORCE_REAUTH=0
    while [ $# -ne 0 ]; do
      case "$1" in
        --force-auth) FORCE_REAUTH=1 ;;
      esac
      shift
    done
    # TODO: From local directory, find up
    if [[ -e "${HOME}/.symenvrc" && $FORCE_REAUTH -ne 1 ]]; then
      # Check if the token has expired, if so trigger a re-auth
      TOKEN="$(symenv_config_get "${HOME}/.symenvrc" _auth_token)"
      symenv_validate_token ${TOKEN}
      export SYMENV_ACCESS_TOKEN=TOKEN
    else
      symenv_do_auth
      touch "${HOME}/.symenvrc"
      symenv_config_set "${HOME}/.symenvrc" _auth_token ${SYMENV_ACCESS_TOKEN}
      symenv_echo "✅ Authentication successful"
    fi
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

#    symenv_echo "COMMAND: ${COMMAND}"
    case $COMMAND in
      'help' | '--help')
        symenv_echo "Symbiont Assembly SDK Manager (v0.0.1)"
        # TODO: Add help
      ;;
      'install' | 'i')
        symenv_auth "$@"
        symenv_install_from_remote "$@" ${PROVIDED_VERSION}
      ;;
      "use")
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
        # symenv_echo "VERSION ${VERSION}"
        if [ -z "${VERSION}" ]; then
          >&2 symenv --help
          return 127
        elif [ "_${PROVIDED_VERSION}" = "_default" ]; then
          return 0
        fi

        # symenv_err "TODO: USE ${PROVIDED_VERSION} silent: ${SYMENV_USE_SILENT}"

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
        if symenv_has_managed_sdk ${PROVIDED_VERSION}; then
          symenv_echo "Switching used version to ${PROVIDED_VERSION}"
          rm ${SYMENV_DIR}/current 2>/dev/null
          ln -s ${SYMENV_DIR}/versions/${PROVIDED_VERSION} ${SYMENV_DIR}/current
        else
          symenv_err "Version ${PROVIDED_VERSION} is not installed. Please install it before switching."
          return 127
        fi

      ;;
      "remote" | "ls-remote" | "list-remote")
        symenv_auth "$@"
        symenv_list_remote_versions "$@"
      ;;
      "list" | "ls" | "local")
        symenv_list_local_versions
      ;;
      "deactivate")
        symenv_deactivate
      ;;
      "current")
        if symenv_has_managed_sdk; then
          symenv_echo "Using managed version of SDK: $(sym -v 2>/dev/null)$(symenv_print_sdk_version)"
          symenv_echo $(ls -l ${SYMENV_DIR}/current)
        else
          symenv_echo "Using system version of SDK: $(sym -v 2>/dev/null)$(symenv_print_sdk_version)"
          symenv_echo $(which sym)
        fi
      ;;
      "version" | "-version" |  "--version")
        # TODO
        symenv_err "TODO: Version"
      ;;
      *)
        >&2 symenv --help
        return 127
      ;;
    esac
  }

  symenv_auto() {
    #TODO
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
