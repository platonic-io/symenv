# Symenv Docker Build

If you'd like to customize the container you're running symenv in, you may
build a new one with this process.

1. Build the Docker image to run locally.

   ```shell
   docker build --build-arg=DATE="$(date +%Y-%m-%d)" --build-arg=VERSION="$(git describe --tags --abbrev=0-)" \
      -t ghcr.io/platonic-io/symenv:"$(git describe --tags --abbrev=0)" -f docker/Dockerfile \
      --progress plain .
   ```

2. Run a container named `symenv` with the image we just built.

   ```shell
   # Use Bash
   docker run --name symenv -it "ghcr.io/platonic-io/symenv:$(git describe --tags --abbrev=0)" bash

   # Use zsh
   docker run --name symenv -it "ghcr.io/platonic-io/symenv:$(git describe --tags --abbrev=0)" zsh
   ```

3. From the running container you can list the remote versions available to install.

   ```shell
   symenv ls-remote --registry=portal.platonic.io --force-auth
   ```

   1. Follow the instructions to complete your login.
   2. Then attend to the list of available versions produced.

      ```shell
      ✅ Authentication successful
      v2.0.0
      v2.0.1
      v2.0.2
      v2.0.3
      v3.0.0
      v4.0.0
      v4.1.0
      ```

4. Now install one or more of them.

   ```shell
   symenv install --registry=portal.platonic.io v4.1.0
   ```

You are now ready to deploy resources to the cloud of your choice.
