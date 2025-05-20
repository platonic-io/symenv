#!/usr/bin/env bash

{ # this ensures the entire script is downloaded #

symenv_has() {
  type "$1" > /dev/null 2>&1
}

symenv_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

symenv_grep() {
  GREP_OPTIONS='' command grep "$@"
}

symenv_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.symbiont" || printf %s "${XDG_CONFIG_HOME}/.symbiont"
}

symenv_install_dir() {
  if [ -n "$SYMENV_DIR" ]; then
    printf %s "${SYMENV_DIR}"
  else
    symenv_default_install_dir
  fi
}

symenv_latest_version() {
  symenv_echo "v1.2.18"
}

symenv_profile_is_bash_or_zsh() {
  local TEST_PROFILE
  TEST_PROFILE="${1-}"
  case "${TEST_PROFILE-}" in
    *"/.bashrc" | *"/.bash_profile" | *"/.zshrc")
      return
    ;;
    *)
      return 1
    ;;
  esac
}

symenv_source() {
  local SYMENV_GITHUB_REPO
  SYMENV_GITHUB_REPO="${SYMENV_INSTALL_GITHUB_REPO:-symbiont-io/symenv}"
  local SYMENV_VERSION
  SYMENV_VERSION="${SYMENV_INSTALL_VERSION:-$(symenv_latest_version)}"
  local SYMENV_METHOD
  SYMENV_METHOD="$1"
  local SYMENV_SOURCE_URL
  SYMENV_SOURCE_URL="$SYMENV_SOURCE"
  if [ "_$SYMENV_METHOD" = "_script-symenv-bash-completion" ]; then
    SYMENV_SOURCE_URL="https://raw.githubusercontent.com/${SYMENV_GITHUB_REPO}/${SYMENV_VERSION}/bash_completion"
  elif [ -z "$SYMENV_SOURCE_URL" ]; then
    if [ "_$SYMENV_METHOD" = "_script" ]; then
      SYMENV_SOURCE_URL="https://raw.githubusercontent.com/${SYMENV_GITHUB_REPO}/${SYMENV_VERSION}/symenv.sh"
    elif [ "_$SYMENV_METHOD" = "_git" ] || [ -z "$SYMENV_METHOD" ]; then
      SYMENV_SOURCE_URL="https://github.com/${SYMENV_GITHUB_REPO}.git"
    else
      symenv_echo >&2 "Unexpected value \"$SYMENV_METHOD\" for \$SYMENV_METHOD"
      return 1
    fi
  fi
  symenv_echo "$SYMENV_SOURCE_URL"
}

install_symenv_from_git() {
  local INSTALL_DIR
  INSTALL_DIR="$(symenv_install_dir)"
  local SYMENV_VERSION
  SYMENV_VERSION="${SYMENV_INSTALL_VERSION:-$(symenv_latest_version)}"
  if [ -n "${SYMENV_INSTALL_VERSION:-}" ]; then
    echo "Installing custom version: ${SYMENV_INSTALL_VERSION}"
    # Check if version is an existing ref
    if command git ls-remote "$(symenv_source "git")" "$SYMENV_VERSION" | symenv_grep -q "$SYMENV_VERSION" ; then
      :
    # Check if version is an existing changeset
    elif ! symenv_download -o /dev/null "$(symenv_source "symenv.sh")"; then
      symenv_echo >&2 "Failed to find '$SYMENV_VERSION' version."
      exit 1
    fi
  fi

  local fetch_error
  if [ -d "$INSTALL_DIR/.git" ]; then
    # Updating repo
    symenv_echo "=> symenv is already installed in $INSTALL_DIR, trying to update using git"
    command printf '\r=> '
    fetch_error="Failed to update symenv with $SYMENV_VERSION, run 'git fetch' in $INSTALL_DIR yourself."
  else
    fetch_error="Failed to fetch origin with $SYMENV_VERSION. Please report this!"
    symenv_echo "=> Downloading symenv from git to '$INSTALL_DIR'"
    command printf '\r=> '
    mkdir -p "${INSTALL_DIR}"
    if [ "$(ls -A "${INSTALL_DIR}")" ]; then
      # Initializing repo
      command git init "${INSTALL_DIR}" || {
        symenv_echo >&2 'Failed to initialize symenv repo. Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" remote add origin "$(symenv_source)" 2> /dev/null \
        || command git --git-dir="${INSTALL_DIR}/.git" remote set-url origin "$(symenv_source)" || {
        symenv_echo >&2 'Failed to add remote "origin" (or set the URL). Please report this!'
        exit 2
      }
    else
      # Cloning repo
      command git clone "$(symenv_source)" --depth=1 "${INSTALL_DIR}" || {
        symenv_echo >&2 'Failed to clone symenv repo. Please report this!'
        exit 2
      }
    fi
  fi
  # Try to fetch tag
  if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin tag "$SYMENV_VERSION" --depth=1 2>/dev/null; then
    :
  # Fetch given version
  elif ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin "$SYMENV_VERSION" --depth=1; then
    symenv_echo >&2 "$fetch_error"
    exit 1
  fi
  command git -c advice.detachedHead=false --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" checkout -f --quiet FETCH_HEAD || {
    symenv_echo >&2 "Failed to checkout the given version $SYMENV_VERSION. Please report this!"
    exit 2
  }
  if [ -n "$(command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" show-ref refs/heads/master)" ]; then
    if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet 2>/dev/null; then
      command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet -D master >/dev/null 2>&1
    else
      symenv_echo >&2 "Your version of git is out of date. Please update it!"
      command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch -D master >/dev/null 2>&1
    fi
  fi

  symenv_echo "=> Compressing and cleaning up git repository"
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" reflog expire --expire=now --all; then
    symenv_echo >&2 "Your version of git is out of date. Please update it!"
  fi
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" gc --auto --aggressive --prune=now ; then
    symenv_echo >&2 "Your version of git is out of date. Please update it!"
  fi
  return
}

symenv_download() {
  if symenv_has "curl"; then
    curl --fail --tlsv1.2 --proto '=https' --compressed -q "$@"
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

install_symenv_as_script() {
  local INSTALL_DIR
  INSTALL_DIR="$(symenv_install_dir)"
  local SYMENV_SOURCE_LOCAL
  SYMENV_SOURCE_LOCAL="$(symenv_source script)"
  local SYMENV_BASH_COMPLETION_SOURCE
  SYMENV_BASH_COMPLETION_SOURCE="$(symenv_source script-symenv-bash-completion)"

  # Downloading to $INSTALL_DIR
  mkdir -p "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/symenv.sh" ]; then
    symenv_echo "=> symenv is already installed in $INSTALL_DIR, trying to update the script"
  else
    symenv_echo "=> Downloading symenv as script to '$INSTALL_DIR'"
  fi
  symenv_download -s "$SYMENV_SOURCE_LOCAL" -o "$INSTALL_DIR/symenv.sh" || {
    symenv_echo >&2 "Failed to download '$SYMENV_SOURCE_LOCAL'"
    return 1
  } &
  symenv_download -s "$SYMENV_BASH_COMPLETION_SOURCE" -o "$INSTALL_DIR/bash_completion" || {
    symenv_echo >&2 "Failed to download '$SYMENV_BASH_COMPLETION_SOURCE'"
    return 2
  } &
  for job in $(jobs -p | command sort)
  do
    wait "$job" || return $?
  done
}

symenv_try_profile() {
  if [ -z "${1-}" ] || [ ! -f "${1}" ]; then
    return 1
  fi
  symenv_echo "${1}"
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
symenv_detect_profile() {
  if [ "${PROFILE-}" = '/dev/null' ]; then
    # the user has specifically requested NOT to have symenv touch their profile
    return
  fi

  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    symenv_echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''

  if [ -n "${BASH_VERSION-}" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ -n "${ZSH_VERSION-}" ]; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    for EACH_PROFILE in ".profile" ".bashrc" ".bash_profile" ".zshrc"
    do
      if DETECTED_PROFILE="$(symenv_try_profile "${HOME}/${EACH_PROFILE}")"; then
        break
      fi
    done
  fi

  if [ -n "$DETECTED_PROFILE" ]; then
    symenv_echo "$DETECTED_PROFILE"
  fi
}

#
# Unsets the various functions defined
# during the execution of the install script
#
symenv_reset() {
  unset -f symenv_has symenv_install_dir symenv_latest_version symenv_profile_is_bash_or_zsh \
    symenv_source symenv_node_version symenv_download install_symenv_from_git symenv_install_node \
    install_symenv_as_script symenv_try_profile symenv_detect_profile symenv_check_global_modules \
    symenv_do_install symenv_reset symenv_default_install_dir symenv_grep
}

symenv_do_install() {
  touch "${HOME}/.symenvrc"
  if [ -n "${SYMENV_DIR-}" ] && ! [ -d "${SYMENV_DIR}" ]; then
    if [ -e "${SYMENV_DIR}" ]; then
      symenv_echo >&2 "File \"${SYMENV_DIR}\" has the same name as installation directory."
      exit 1
    fi

    if [ "${SYMENV_DIR}" = "$(symenv_default_install_dir)" ]; then
      mkdir "${SYMENV_DIR}"
    else
      symenv_echo >&2 "You have \$SYMENV_DIR set to \"${SYMENV_DIR}\", but that directory does not exist. Check your profile files and environment."
      exit 1
    fi
  fi
  if [ -z "${METHOD}" ]; then
    # Autodetect install method
    if symenv_has git; then
      install_symenv_from_git
    elif symenv_has symenv_download; then
      install_symenv_as_script
    else
      symenv_echo >&2 'You need curl, or wget to install symenv'
      exit 1
    fi
  elif [ "${METHOD}" = 'git' ]; then
    if ! symenv_has git; then
      symenv_echo >&2 "You need git to install symenv"
      exit 1
    fi
    install_symenv_from_git
  elif [ "${METHOD}" = 'script' ]; then
    if ! symenv_has symenv_download; then
      symenv_echo >&2 "You need curl or wget to install symenv"
      exit 1
    fi
    install_symenv_as_script
  else
    symenv_echo >&2 "The environment variable \$METHOD is set to \"${METHOD}\", which is not recognized as a valid installation method."
    exit 1
  fi

  symenv_echo

  local SYMENV_PROFILE
  local PROFILE_INSTALL_DIR
  PROFILE_INSTALL_DIR="$(symenv_install_dir | command sed "s:^$HOME:\$HOME:")"

  SOURCE_STR="\\nexport SYMENV_DIR=\"${PROFILE_INSTALL_DIR}\"\\n[ -s \"\$SYMENV_DIR/symenv.sh\" ] && \\. \"\$SYMENV_DIR/symenv.sh\"  # This loads symenv\\n"
  SDK_STR='[ -s "$SYMENV_DIR/versions/current" ] && export PATH="$SYMENV_DIR/versions/current/bin":$PATH  # This loads symenv managed SDK\n'
  # shellcheck disable=SC2016
  COMPLETION_STR='[ -s "$SYMENV_DIR/bash_completion" ] && \. "$SYMENV_DIR/bash_completion"  # This loads symenv bash_completion\n'

  # shellcheck source=/dev/null
  \. "$(symenv_install_dir)/symenv.sh"

  symenv_reset
  symenv_echo "=> Append to profile file then close and reopen your terminal to start using symenv or run the following to use it now:"
  command printf "${SOURCE_STR}"
  command printf "${SDK_STR}"
  command printf "${COMPLETION_STR}"
  symenv_echo
}

[ "_$SYMENV_ENV" = "_testing" ] || symenv_do_install

} # this ensures the entire script is downloaded #
