"""
Julia package for creating new packages quickly. See [`PkgSkeleton.generate`](@ref).
"""
module PkgSkeleton

using ArgCheck: @argcheck
import Dates
using DocStringExtensions: SIGNATURES
import LibGit2
import UUIDs

####
####
####

####
#### Template values
####

"""
$(SIGNATURES)

Extract a package name using the last component of a path.

The following all result in `"Foo"`:

```julia
pkg_name_from_path("/tmp/Foo")
pkg_name_from_path("/tmp/Foo/")
pkg_name_from_path("/tmp/Foo.jl")
pkg_name_from_path("/tmp/Foo.jl/")
```
"""
function pkg_name_from_path(path::AbstractString)
    base, ext = splitext(basename(isdirpath(path) ? dirname(path) : path))
    @argcheck(isempty(ext) || ext == ".jl",
              "Invalid extension $(ext), specify package as a replacement value.")
    base
end

"Docstring for replacement values."
const REPLACEMENTS_DOCSTRING = """
- `UUID`: the package UUID; default: random
- `PKGNAME`: the package name; default: taken from the destination directory
- `GHUSER`: the github user; default: taken from Git options
- `USERNAME`: the user name; default: taken from Git options
- `USEREMAIL`: the user e-mail; default: taken from Git options
- `YEAR`: the calendar year; default: from system time
"""

"""
$(SIGNATURES)

Populate a vector of replacement pairs, either from arguments or by querying global settings
and state.

The following replacement values are used:

$(REPLACEMENTS_DOCSTRING)
"""
function fill_replacements(replacements; dest_dir)
    c = LibGit2.GitConfig()     # global configuration
    _getgitopt(opt, type = AbstractString) = begin
        value=nothing
        try
            value = LibGit2.get(type, c, opt)
        catch
            println("your .gitconfig file lacks the parameter \"" ,opt,"\" set a new value now,")
            print(opt," : ")
            nw = readline()
            LibGit2.set!(c,opt,nw)
            value = LibGit2.get(type, c, opt)
        end
        return value
    end
    _provided_values = propertynames(replacements)
    function _ensure_value(key, f)
        if key ∈ _provided_values
            # VERSION ≥ 1.2 could use hasproperty, but we support earlier versions too
            getproperty(replacements, key)
        else
            # we are lazy here so that the user can user an override when obtaining the
            # value from the environment would error
            f()
        end
    end
    defaults = (UUID = () -> UUIDs.uuid4(),
                PKGNAME = () -> pkg_name_from_path(dest_dir),
                GHUSER = () -> _getgitopt("github.user"),
                USERNAME = () -> _getgitopt("user.name"),
                USEREMAIL = () -> _getgitopt("user.email"),
                YEAR = () -> Dates.year(Dates.now()))
    NamedTuple{keys(defaults)}(map(_ensure_value, keys(defaults), values(defaults)))
end

####
#### Template application
####

"""
$(SIGNATURES)

Replace multiple pairs in `str`, using `replace` iteratively.

`replacements` should be an associative collection that supports `pairs` (eg `Dict`,
`NamedTuple`, …). They are wrapped in `{}`s for replacement in the templates.
"""
function replace_multiple(str, replacements)
    delimited_replacements = Dict(["{$(string(key))}" => string(value)
                                   for (key, value) in pairs(replacements)])
    foldl(replace, delimited_replacements; init = str)
end

"""
$(SIGNATURES)

Copy from `src_dir` to `dest_dir` recursively, making the substitutions of

1. file contents and

2. filenames

using `replacements`.

Existing files are not overwritten when `skip_existing_files = true` (the default).

Directory names are *not* replaced.

Return a list of `source => dest` path pairs, with `source ≡ nothing` when `dest` was not
overwritten.
"""
function copy_and_substitute(src_dir, dest_dir, replacements;
                             skip_existing_files::Bool = true)
    results = Vector{Pair{Union{String,Nothing},String}}()
    for (root, dirs, files) in walkdir(src_dir)
        sub_dir = relpath(root, src_dir)
        mkpath(normpath(dest_dir, sub_dir))
        for file in files
            srcfile = joinpath(root, file)
            destfile = normpath(joinpath(dest_dir, sub_dir,
                                         replace_multiple(file, replacements)))
            if isfile(destfile) && skip_existing_files
                push!(results, nothing => destfile)
            else
                push!(results, srcfile => destfile)
                srcstring = read(srcfile, String)
                deststring = replace_multiple(srcstring, replacements)
                write(destfile, deststring)
            end
        end
    end
    results
end

"""
$(SIGNATURES)

Return the template directory for `name`. Symbols refer to built-in templates, while strings
are considered paths. Directories are always verified to exist.
"""
function resolve_template_dir(name::Symbol)
    dir = abspath(joinpath(@__DIR__, "..", "templates", String(name)))
    @argcheck isdir(dir) "Could not find built-in template $(name)."
    dir
end

function resolve_template_dir(dir::AbstractString)
    @argcheck isdir(dir) "Could not find directory $(dir)."
    dir
end

####
#### exposed API
####

"""
$(SIGNATURES)

Generate the skeleton for a Julia package in `dest_dir`.

The directory is transformed with `expanduser`, replacing `~` in paths.

# Arguments

`template` specifies the template to use. Symbols (eg `:default`, which is the default)
refer to *built-in* templates delivered with this package. Strings are considered paths.

`replacements`: a `NamedTuple` that can be used to manually specify the replacements:

$(REPLACEMENTS_DOCSTRING)

Specifically, `PKGNAME` can be used to specify a package name, derived from `dest_dir` by
default: the package name is `"Foo"` for all of

1. `"/tmp/Foo"`, 2. `"/tmp/Foo/"`, 3. `"/tmp/Foo.jl"`, 4. `"/tmp/Foo.jl/"`.

Use a different name only when you know what you are doing.

`skip_existing_dir = true` (the default) aborts package generation for existing directories.

`skip_existing_files = true` (the default) prevents existing files from being overwritten.

`git_init = true` (the default) ensures that an *empty* repository is generated in
`dest_dir`. You still have to commit files yourself.

`docs_manifest` completes the `Manifest.toml` in the `docs` subdirectory. You usually want
this.
"""
function generate(dest_dir; template = :default,
                  replacements::NamedTuple = NamedTuple(),
                  skip_existing_dir::Bool = true,
                  skip_existing_files::Bool = true,
                  git_init::Bool = true, docs_manifest::Bool = true)
    dest_dir = expanduser(dest_dir)
    # preliminary checks
    @argcheck !isfile(dest_dir) "destination $(dest_dir) is a file."
    if skip_existing_dir && isdir(dest_dir)
        @warn "destination $(dest_dir) exists, skipping package generation.\nConsider `skip_existing_dir = false`."
        return false
    end

    # copy and substitute
    @info "getting template values"
    replacements = fill_replacements(replacements; dest_dir = dest_dir)
    @info "copy and substitute"
    results = copy_and_substitute(resolve_template_dir(template), dest_dir, replacements;
                                  skip_existing_files = skip_existing_files)
    for (src, dest) in results
        src ≡ nothing && println(stderr, "not overwriting $(dest)")
    end

    # git initialization
    if git_init
        @info "initializing git repository"
        LibGit2.init(dest_dir)
    end

    # docs manifest
    if docs_manifest
        @info "adding documenter (completing the Manifest.toml for docs)"
        docs = joinpath(dest_dir, "docs")
        cd(docs) do
            run(`$(Base.julia_cmd()) --project=$(docs) -e 'import Pkg; Pkg.add("Documenter"); Pkg.develop(Pkg.PackageSpec(; path = ".."))'`)
        end
    end

    # done
    @info "successfully generated $(replacements.PKGNAME)" dest_dir
    true
end

end # module
