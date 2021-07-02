###### Development

Prerequisites:
- `curl` or `wget`
- `jq`
- an account for Symbiont's portal

```shell
source ./test.sh
```

For usage against the staging portal, append a `--registry=<registry>` to commands that perform remote operations. Note that 
you will also need to use a token created by said registry in order for authentication to work. If need be, use `symenv reset` 
to clear your authentication token. 
```shell
symenv install --registry=portal-staging.waf-symbiont.io
```

###### Installation

Prerequisites:
- `curl` or `wget`
- `jq`
- an account for Symbiont's portal

Remotely
```shell
curl --proto '=https' --tlsv1.2 -sSf https://<host>/<path>/install.sh | sh
```

eg. 
```shell
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/symbiont-io/symenv/main/install.sh | sh
```

###### Commands

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
  symenv vscode                                  Installs the VSCode extension for SymPL (requires "code" in your path)
  symenv reset                                   Resets your environment to a fresh install of symenv
```

