# PkgSkeleton.jl

![lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg) <!--
![lifecycle](https://img.shields.io/badge/lifecycle-stable-green.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-retired-orange.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-archived-red.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-dormant-blue.svg) -->
[![build](https://github.com/tpapp/PkgSkeleton.jl/workflows/CI/badge.svg)](https://github.com/tpapp/PkgSkeleton.jl/actions?query=workflow%3ACI)
[![codecov.io](http://codecov.io/github/tpapp/PkgSkeleton.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/PkgSkeleton.jl?branch=master)

Julia package for creating new packages and updating existing ones, following common practices and workflow recommendations.

**This package may overwrite existing files.** While care has been taken to ensure no data loss, it may nevertheless happen. Keep backups, commit to a non-local git repository, and **use at your own risk**.

## Installation

The package is registered. Add with

```julia
pkg> add PkgSkeleton
```

## Usage

```julia
import PkgSkeleton
PkgSkeleton.generate("target_directory") # uses default template
```

Then

1. Various defaults [(described below)](@ref substitutions) are collected from your environment, eg your name, e-mail address, and Github account name (from `git` global settings). You can override these using a keyword argument.

2. If `target_directory` does not exist, it is created with an empty git repository. Conversely, if the directory exits but is not a git repository, generation is aborted.

3. Files in template are copied recursively, with various [substitutions (as described below)](@ref substitutions). Unless you are explicitly allowing overwrites, uncommitted files in the repository are not modified.

After this, you probably want to `pkg> dev destination/directory` in Julia, and add your Github repository as a remote.

See `?PkgSkeleton.generate` for details.

### Updating existing packages

Best practices and recommended setups change with time. The recommended workflow for updating *existing* packages using templates from this package is the following.

1. Make sure that this package is of the latest version, eg with `pkg> up`.

2. Make sure that *everything* that is part of a template is committed in version control. This is very important: when files are overwritten, work may be lost, so `PkgSkeleton.generate` prefers not to overwrite existing files.

3. Run
    ```julia
    PkgSkeleton.generate("/path/to/pkg")
    ```
    and see the output for what was modified.

4. Use your favorite git interface for reviewing the change. Pick and commit what you like, discard the rest of the changes.

### Custom templates

Just create directories with text (code, Markdown, TOML) files, [substitutions](@ref substitutions) between `{}`s will be replaced in *filenames* and their *contents*.

## [Substitutions](@id substitutions)

For the default template, you need to set the `git` configuration variables `user.name`, `user.email`, and `github.user`.

Templates replace the following in files *and filenames*:

| string        | replacement                    |
|---------------|--------------------------------|
| `{PKGNAME}`   | name of the package            |
| `{UUID}`      | a random UUID                  |
| `{GHUSER}`    | `git config --get github.user` |
| `{USERNAME}`  | `git config --get user.name`   |
| `{USEREMAIL}` | `git config --get user.email`  |
| `{YEAR}`      | the current year               |

## Design principles

1. [Keep it simple](https://en.wikipedia.org/wiki/KISS_principle): do nothing more than substitute strings into templates, with a few safeguards. This keeps the code simple: currently [less than 300 LOC](src/PkgSkeleton.jl) without docstrings. For me, this covers 99% of the use cases; the rest I edit manually.

2. Tread ligthly: don't modify uncommitted files (unless asked to), or files with the same content (to preserve timestamps).

3. Assume that tooling for packages will keep changing, make it easy to update.
