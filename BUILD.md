# Building Heroku Base Images Locally

## Prepare your local environment

The build scripts in this repository require:

- bash 4+. To update to newer bash on OS X, see: https://johndjameson.com/blog/updating-your-shell-with-homebrew/
- Docker Desktop. To build multi-arch images (heroku-24 and beyond),
  the `containerd` snapshotter feature should be enabled.

## Build

To build the base images locally, run this from the repo root:

    bin/build.sh STACK_VERSION

For example:

    ./bin/build.sh 24

## Adding packages to the base image

Add the package you want to the appropriate `setup.sh` for example `heroku-24/setup.sh`:

```diff
+    libc6-dev
```

Once done, run `bin/build.sh` locally to generate the corresponding `installed-packages*` files. Multi-arch base images (heroku-24 and beyond) will produce an `installed-packages-$ARCH.txt` for each architecture.

The `*-build` variants include all the packages from the non-build variant by default. This means that if you're adding a package to both, you only need to add them to the non-build variant. The example above will add `libc6-dev` to both `heroku-24` and `heroku-24-build`.

# Releasing Base Images

We use GitHub Actions to build and release the base images:

* Any push to `main` will build the images (proves that images can be build)
* A nightly job pushes `nightly` tagged GitHub Container Registry variants (such as `ghcr.io/ninech/deploio-heroku:24-build.nightly`).
* A special release pipeline will run every 2 weeks automatically and create a new `stable`
  tag of the `run` and `build` images. A new tag and github release will also be created automatically. This
  pipeline can also be started manually to quickly release a new `stable` version.

The message attached to the github release will contain all changed Ubuntu
packages (and their versions) and messages made by the conventional commit
preambles `fix`, `feat` and `breaking change`.
