# PkgSkeleton.jl

![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)<!--
![Lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg)
![Lifecycle](https://img.shields.io/badge/lifecycle-stable-green.svg)
![Lifecycle](https://img.shields.io/badge/lifecycle-retired-orange.svg)
![Lifecycle](https://img.shields.io/badge/lifecycle-archived-red.svg)
![Lifecycle](https://img.shields.io/badge/lifecycle-dormant-blue.svg) -->
[![Build Status](https://travis-ci.com/tpapp/PkgSkeleton.jl.svg?branch=master)](https://travis-ci.com/tpapp/PkgSkeleton.jl)
[![codecov.io](http://codecov.io/github/tpapp/PkgSkeleton.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/PkgSkeleton.jl?branch=master)

Julia package for creating new packages quickly. This is the successor of [skeleton.jl](https://github.com/tpapp/skeleton.jl).

## Installation

The package is currently not registered. Add with

```julia
pkg> add https://github.com/tpapp/Pkgskeleton.jl
```

## Usage

```julia
import PkgSkeleton
PkgSkeleton.generate("destination/directory") # uses default template
```

Then

1. files in template will be copied recursively, with various substitutions (as described below).

2. A git repo is initialized.

If the destination directory exists, the script aborts.

After this, you probably want to `pkg> dev destination/directory` in Julia, and add your Github repository as a remote.

See `?PkgSkeleton.generate` for details.

## Prerequisites

For the default template, you need to set the `git` configuration variables `user.name`, `user.email`, and `github.user`.

## Substitutions

Design follows [KISS](https://en.wikipedia.org/wiki/KISS_principle): do nothing more than substitute strings into templates. For me, this covers 99% of the use cases; the rest I edit manually.

Templates replace the following in files *and filenames*:

| string        | replacement                             |
|---------------|-----------------------------------------|
| `{PKGNAME}`   | name of the package                     |
| `{UUID}`      | an UUID (METADATA-compatible or random) |
| `{GHUSER}`    | `git config --get github.user`          |
| `{USERNAME}`  | `git config --get user.name`            |
| `{USEREMAIL}` | `git config --get user.email`           |
| `{YEAR}`      | the current year                        |
