## ninech/deploio-heroku Base Images

[![CI](https://github.com/ninech/heroku-stack-base-images/actions/workflows/ci.yml/badge.svg)](https://github.com/ninech/heroku-stack-base-images/actions/workflows/ci.yml)

This is a ninech fork of [heroku/base-images](https://github.com/heroku/base-images), adapted for use with [deplo.io](https://deplo.io).
The recipes are rendered into Docker images available on the GitHub Container Registry:

| Image                                              | Type           | OS           | Supported Architectures | Default `USER` | Status      |
|----------------------------------------------------|----------------|--------------|-------------------------|----------------|-------------|
| [ghcr.io/ninech/deploio-heroku:24][ninech-tags]     | Run Image      | Ubuntu 24.04 | AMD64 + ARM64           | `deploio`      | Recommended |
| [ghcr.io/ninech/deploio-heroku:24-build][ninech-tags] | Build Image    | Ubuntu 24.04 | AMD64 + ARM64           | `deploio`      | Recommended |

The build image variants use the run images as their base, but include additional packages needed
at build time such as development headers and compilation toolchains.

For images where the default `USER` is `deploio`, you will need to switch back to the `root` user when
modifying locations other than `/home/deploio` and `/tmp`. You can do this by adding `USER root` to
your `Dockerfile` when building images, or by passing `--user root` to any `docker run` invocations.

### Learn more

* [Lists of packages installed on current Heroku stacks](https://devcenter.heroku.com/articles/stack-packages)
* [Stack update policy](https://devcenter.heroku.com/articles/stack-update-policy)

See [BUILD.md](BUILD.md) for instructions on how to build the images yourself.

[ninech-tags]: https://github.com/ninech/heroku-stack-base-images/pkgs/container/deploio-heroku
[ubuntu-tags]: https://hub.docker.com/_/ubuntu?tab=tags
