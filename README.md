# Readme

## Usage

The simplest way to get up and running is with
[Docker](https://www.docker.com/products/docker-desktop/).

1. Pull the most recent version of the symenv image.

   ```shell
   docker pull ghcr.io/platonic-io/symenv:latest
   ```

2. Run the container on your local system with either bash or zsh.

   ```shell
   # Use Bash
   docker run --name symenv -it "ghcr.io/platonic-io/symenv:$(git describe --tags --abbrev=0)" bash

   # Use zsh -- Note that zsh is not officially supported.
   docker run --name symenv -it "ghcr.io/platonic-io/symenv:$(git describe --tags --abbrev=0)" zsh
   ```

3. Use the shell provided by the container to authenticate.

   ```shell
   symenv login --registry=portal.platonic.io
   ```

4. List the available versions.

   ```shell
   symenv ls-remote
   ```

   This should produce a list of available versions similar to the following.

   ```shell
   v2.0.0
   v2.0.1
   v2.0.2
   v2.0.3
   v3.0.0
   v4.0.0
   v4.1.0
   ```

5. Install one or more of the available versions.

   ```shell
   symenv install v4.1.0
   ```

6. Use the assembly.

## Development

Prerequisites:

- `curl` or `wget`
- `jq`
- an account for Symbiont's portal

### Development Usage

1. Prepare the environment.

   ```shell
   source ./test.sh
   ```

   You should see output similar to this.

   ```shell
   => Downloading symenv as script to '/root/.symbiont'
   [1]-  Done                    symenv_download -s "$SYMENV_SOURCE_LOCAL" -o "$INSTALL_DIR/symenv.sh" || { symenv_echo "Failed to download '$SYMENV_SOURCE_LOCAL'" 1>&2; return 1; }
   [2]+  Done                    symenv_download -s "$SYMENV_BASH_COMPLETION_SOURCE" -o "$INSTALL_DIR/bash_completion" || { symenv_echo "Failed to download '$SYMENV_BASH_COMPLETION_SOURCE'" 1>&2; return 2; }

   => Append to profile file then close and reopen your terminal to start using symenv or run the following to use it now:

   export SYMENV_DIR="$HOME/.symbiont"
   [ -s "$SYMENV_DIR/symenv.sh" ] && \. "$SYMENV_DIR/symenv.sh"  # This loads symenv
   [ -s "$SYMENV_DIR/versions/current" ] && export PATH="$SYMENV_DIR/versions/current/bin":$PATH  # This loads symenv managed SDK
   [ -s "$SYMENV_DIR/bash_completion" ] && \. "$SYMENV_DIR/bash_completion"  # This loads symenv bash_completion
   ```

2. Choose a registry by appending the `--registry=portal.platonic.io` flag to commands
   that perform remote operations.

   > Note that you will also need to use a token created by said registry
   > in order for authentication to work.
   >
   > If need be, use `symenv reset` to clear your authentication token.

3. Install the environment.

   ```shell
   symenv install --registry=portal.platonic.io v4.1.0
   ```

### Docker Usage

You can find information on how to build and run a container with symenv [here](docker/README.md).

## Installation

Prerequisites:

- `curl` or `wget`
- `jq`
- an account for Symbiont's portal

Remotely

```shell
curl --proto '=https' --tlsv1.2 -sSf https://<host>/<path>/install.sh | bash

# Example

curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/symbiont-io/symenv/main/install.sh | bash
```

### Commands

```help
Usage:
  symenv --help                                  Show this message
  symenv --version                               Print out the version of symenv
  symenv current                                 Print out the installed version of the SDK
  symenv config ls                               Print out the configuration used by symenv
  symenv install [options] <version>             Download and install a <version> of the SDK
    --registry=<registry>                          When downloading, use this registry
    --force-auth                                   Refresh the user token before downloading
  symenv use [options] <version>                 Use version <version> of the SDK
    --silent                                       No output
  symenv deactivate                              Remove the symlink binding the installed version to current
  symenv ls | list | local                       List the installed versions of the SDK
  symenv ls-remote | list-remote | remote        List the available remote versions of the SDK
    --all                                          Include the non-release versions
  symenv reset                                   Resets your environment to a fresh install of symenv
```
