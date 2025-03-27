"""
Julia package for creating new packages and updating existing ones, following common
practices and workflow recommendations.

**This package may overwrite existing files.** While care has been taken to ensure no data
loss, it may nevertheless happen. Keep backups, commit to a non-local git repository, and
**use at your own risk**.

[`PkgSkeleton.generate`](@ref) is the only exposed functionality.
"""
module PkgSkeleton

using ArgCheck: @argcheck
import Dates
using DocStringExtensions: SIGNATURES
import LibGit2
using UUIDs: uuid4, UUID
import Pkg
import TOML

####
#### utilities
####

"""
$(SIGNATURES)

Print `xs...` as a message of the given `:kind` (see the source for docs).

!!! NOTE
    The only function used to communicate with the user, everything (except errors) should
    go through this so that it can be modified at a single point if necessary.
"""
function msg(kind, xs...; header::Bool = false)
    color = getproperty((general = :white, # general/progress
                         dirty = :magenta, # (writing to) uncommitted files in repository
                         clean = :green,   # (writing to) committed files
                         same = :blue),    # files with same content
                        kind)
    printstyled(stderr, xs..., '\n'; color = color, bold = header)
    nothing
end

####
#### template values
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
Error type for git options not found in the global environment. Reporting with helpful error
message to the user.
"""
struct GitOptionNotFound <: Exception
    "The name for the option."
    option::String
    "What the option is used for (for the error message)."
    used_for::String
end

function Base.showerror(io::IO, e::GitOptionNotFound)
    print(io, """
    Could not find option “$(e.option)” in your global git configuration.

    It is necessary to set this for $(e.used_for).

    You can set this in the command line with

    git config --global $(e.option) "…"
    """)
end

"""
$(SIGNATURES)

Lookup UUIDs matching `pkg_name` in the local copy of registries in `DEPOT_PATH`.

Return a vector of strings.
"""
function lookup_UUIDs_in_registries(pkg_name)
    # Look up Registry.toml files in depots
    uuids = UUID[]
    for d in DEPOT_PATH
        regs = joinpath(d, "registries")
        if isdir(regs)
            for r in readdir(regs)
                toml_path = joinpath(regs, r, "Registry.toml")
                if isfile(toml_path)
                    toml = TOML.parsefile(toml_path)
                    if haskey(toml, "packages")
                        for (k, v) in toml["packages"]
                            if v["name"] == pkg_name
                                push!(uuids, UUID(k))
                            end
                        end
                    end
                end
            end
        end
    end
    uuids
end

"""
$(SIGNATURES)

Look up the UUID in the project file of `target_dir` and return it, or `nothing` if it is
not found or there is no project file.

When `pkg_name` is provided, an error is thrown if the project file has a different
name.
"""
function lookup_UUID_in_project(target_dir, pkg_name = nothing)
    toml_path = joinpath(target_dir, "Project.toml")
    if !isfile(toml_path)
        toml_path = joinpath(target_dir, "JuliaProject.toml")
        isfile(toml_path) || return nothing
    end
    toml = TOML.parsefile(toml_path)
    if pkg_name ≢ nothing && haskey(toml, "name")
        name = toml["name"]
        if name ≠ pkg_name
            error("name = $(name) in project file does not match $(pkg_name)")
        end
    end
    if haskey(toml, "uuid")
        UUID(toml["uuid"])
    else
        nothing
    end
end

"""
$(SIGNATURES)

Heuristic to find an existing UUID or generate a new one.

*If* there is a target directory, try to find a project file there with an UUID.

If this fails, check the registry, if matches are found, inform the user (printing the
UUIDs) and abort.

Otherwise, generate a random UUID.
"""
function existing_or_random_UUID(target_dir, pkg_name = nothing)
    if isdir(target_dir)
        uuid_project = lookup_UUID_in_project(target_dir, pkg_name)
        if uuid_project ≢ nothing
            msg(:general, "Found UUID from existing project file.")
            return uuid_project
        end
        uuids_registry = lookup_UUIDs_in_registries(pkg_name ≡ nothing ?
                                                    pkg_name_from_path(target_dir) : pkg_name)
        if length(uuids_registry) ≥ 1
            msg(:general, "Found the following UUIDs matching $(pkg_name) in the local registries:")
            for uuid in uuids_registry
                msg(:general, "  ", uuid)
            end
            error("Provide an UUID with Pkg.generate(target_dir, (UUID = Base.UUID(\"...\"), )).")
        end
    end
    uuid4()
end

"""
$(SIGNATURES)

Populate missing replacements in a `Dict{String,String}`, either from arguments or by
querying global settings and state. When a value is available in `user_replacements`, it is
used directly.

The following replacement values are populated by default:

$(REPLACEMENTS_DOCSTRING)

`target_dir` is used as a path, and does not have to exist as a directory for this function
to work.
"""
function fill_replacements!(user_replacements::Dict{String,String}; target_dir)
    c = LibGit2.GitConfig()     # global configuration
    function _getgitopt(opt, used_for)
        try
            LibGit2.get(AbstractString, c, opt)
        catch e
            if e isa LibGit2.GitError # assume it is not found
                throw(GitOptionNotFound(opt, used_for))
            else
                rethrow(e)
            end
        end
    end
    function _ensure(key, f)
        if !haskey(user_replacements, key)
            # we are lazy here so that the user can use an override when obtaining
            # the value from the environment would error
            user_replacements[key] = f()
        end
    end
    _ensure("PKGNAME", () -> pkg_name_from_path(target_dir))
    _ensure("UUID",
            () -> string(existing_or_random_UUID(target_dir, get(user_replacements, "PKG_NAME", nothing))))
    _ensure("GHUSER", () -> _getgitopt("github.user", "your Github username")),
    _ensure("USERNAME" ,
            () -> _getgitopt("user.name", "your name (as the package author)"))
    _ensure("USEREMAIL",
            () -> _getgitopt("user.email", "your e-mail (as the package author)"))
    _ensure("YEAR", () -> string(Dates.year(Dates.now())))
    user_replacements
end

####
#### Template application
####

"""
$(SIGNATURES)

Return the template directory for `name`. Symbols refer to built-in templates, while strings
are considered paths. Directories are always verified to exist.
"""
function resolve_template_directory(name::Symbol)
    dir = abspath(joinpath(@__DIR__, "..", "templates", string(name)))
    @argcheck isdir(dir) "Could not find built-in template $(name)."
    dir
end

function resolve_template_directory(dir::AbstractString)
    @argcheck isdir(dir) "Could not find directory $(dir)."
    dir
end

"""
$(SIGNATURES)

Read a template directory, and return as a vector of `relative_path => content` pairs,
sorted on the relative path for consistency.
"""
function read_template_directory(template_dir)
    template = Vector{Pair{String,String}}()
    for (root, dirs, files) in walkdir(template_dir)
        for file in files
            absolute_path = joinpath(root, file)
            relative_path = relpath(absolute_path, template_dir)
            push!(template, relative_path => read(absolute_path, String))
        end
    end
    sort!(template, by = first)
end

"""
$(SIGNATURES)

Wrap replacements in `{}`s for use in the templates.

!!! NOTE
    This function is the sole place where the template logic is encoded. If templates syntax
    changes, nothing else needs to be rewritten.
"""
function delimited_replacements(replacements)
    ["{$(string(key))}" => string(value) for (key, value) in pairs(replacements)]
end

"""
$(SIGNATURES)

Replace multiple pairs in `str`, using `replace` iteratively.

`delimited_replacements` should be an iterable, it is applied in the given order.
"""
function replace_multiple(str, delimited_replacements)
    foldl(replace, delimited_replacements; init = str)
end

"""
$(SIGNATURES)

Apply the replacements in `template`, returning a vector of `relpath => content` pairs, in
the same order.
"""
function apply_replacements(template, delimited_replacements)
    _replace(x) = replace_multiple(x, delimited_replacements)
    [_replace(relpath) => _replace(content) for (relpath, content) in template]
end

"""
$(SIGNATURES)

Compare files in the applied template with the target directory.

Three vectors of `relpath => content` pairs are returned in a `NamedTuple`:

- `same_files`: files with identical content in the applied template.
- `dirty_files`: files with different content, which are not committed in the repository.
- `clean_files`: empty files or files which would change but are committed.
"""
function compare_with_target(target_dir, applied_template)
    repository = LibGit2.GitRepo(target_dir)
    same_files = Vector{Pair{String,String}}()
    dirty_files = Vector{Pair{String,String}}()
    clean_files = Vector{Pair{String,String}}()
    for relpath_content in applied_template
        relpath, content = relpath_content
        abspath = joinpath(target_dir, relpath)
        already_exists = ispath(abspath)
        already_exists && (@argcheck isfile(abspath) "$(abspath) is not a file, aborting.")
        if already_exists && read(abspath, String) == content
            push!(same_files, relpath_content)
        elseif already_exists && LibGit2.status(repository, relpath) ≠ 0
            push!(dirty_files, relpath_content)
        else
            push!(clean_files, relpath_content)
        end
    end
    # FIXME replace with compact (; ...) syntax once we only support VERSION ≥ 1.5
    (same_files = same_files, dirty_files = dirty_files, clean_files = clean_files)
end

"""
$(SIGNATURES)


"""
function msg_and_write(kind, header, target_dir, relpath_content_pairs)
    isempty(relpath_content_pairs) && return nothing
    msg(kind, header; header = true)
    for (relpath, content) in relpath_content_pairs
        msg(kind, "  $(relpath)")
        if target_dir ≢ nothing
            abspath = joinpath(target_dir, relpath)
            mkpath(dirname(abspath))
            write(abspath, content)
        end
    end
    nothing
end

"""
$(SIGNATURES)

Convert argument to `Dict{String,String}`, always ensuring that it is an independent copy.
"""
function convert_replacements(user_replacements::Dict{String,String})
    copy(user_replacements)
end

function convert_replacements(user_replacements::Union{NamedTuple,AbstractDict})
    Dict((string(k) => string(v))::Pair{String,String}
         for (k, v) in pairs(user_replacements))
end

####
#### exposed API
####

"The default templates. Not exported, for internal use."
const DEFAULT_TEMPLATES = [:default, :github]

"""
$(SIGNATURES)

Generate the skeleton for a Julia package in `target_dir`. The directory is transformed with
`expanduser`, replacing `~` in paths. Print a summary of what changed.

!!! NOTE
    If a package already exists at `target_dir`, it is strongly recommended that the
    repository is in a clean state (no untracked files or uncommitted changes).

# Examples

## Generate the template for a new package

```julia
import PkgSkeleton
PkgSkeleton.generate("/tmp/Foo")
```

## Update the Github-specific part (workflows, etc)

```julia
import PkgSkeleton
PkgSkeleton.generate("/path/to/pkg"; templates = [:github])
```

# Keyword arguments and defaults

- `templates = $(DEFAULT_TEMPLATES)`: specifies the templates to use. Symbols refer to
  *built-in* templates delivered with this package. Strings are used as paths. Can be a
   vector or a single element.

- `user_replacements = Dict{String,String}()`: a `Dict{String,String}`, or anything that
  that supports `pairs` with keys and values that can be converted to strings. It can be
  used to manually specify the replacements (see below).

- `overwrite_uncommitted = false`: Existing files which are not committed in the repository
  are not overwritten unless this is `true`, generation is aborted with an error. **It is
  strongly advised that you just commit or delete exising files instead of using this
  flag.**

# Replacements

The following replacements are added to `user_replacements` when missing:

$(REPLACEMENTS_DOCSTRING)

Specifically, `PKGNAME` can be used to specify a package name, derived from `target_dir` by
default: the package name is `"Foo"` for all of

1. `"/tmp/Foo"`,
2. `"/tmp/Foo/"`,
3. `"/tmp/Foo.jl"`,
4. `"/tmp/Foo.jl/"`.

Use a different name only when you know what you are doing.

Users can add custom strings to be replaced. `Dict("CUSTOM" => "42")` will replace
`{CUSTOM}` with `42` in the template. Use strings if possible, but conversion to strings
will be attempted with `string`.
"""
function generate(target_dir; templates = DEFAULT_TEMPLATES,
                  user_replacements = Dict{String,String}(),
                  overwrite_uncommitted::Bool = false)
    target_dir = expanduser(target_dir)
    msg(:general, "getting template replacement values")
    replacements = fill_replacements!(convert_replacements(user_replacements);
                                      target_dir = target_dir)

    if !(templates isa AbstractVector)
        templates = [templates]
    end
    applied_templates = map(templates) do template_name
        template_dir = resolve_template_directory(template_name)
        msg(:general, "reading template $(template_name) from $(template_dir)")
        template = read_template_directory(template_dir)
        apply_replacements(template, delimited_replacements(replacements))
    end

    if ispath(target_dir)
        @argcheck isdir(target_dir) "destination $(target_dir) is not a directory."
    end
    if isdir(target_dir)
        try
            LibGit2.GitRepo(target_dir)
        catch
            error("target $(target_dir) exists, but is not a valid git repository")
        end
    else
        msg(:general, "target $(target_dir) does not exist, creating with a git repository")
        mkpath(target_dir)
        LibGit2.init(target_dir)
    end

    for (template_name, applied_template) in zip(templates, applied_templates)
        msg(:general, "applying template $(template_name)")

        (; same_files, dirty_files, clean_files) =
            compare_with_target(target_dir, applied_template)

        if overwrite_uncommitted
            msg_and_write(:dirty,
                          "OVERWRITING the following uncommitted files as requested:",
                          target_dir, dirty_files)
        else
            msg_and_write(:dirty, "SKIPPING uncommitted changes in the following files:",
                          nothing, dirty_files)
        end

        msg_and_write(:clean,
                      "(OVER)WRITING the following files (missing or committed in the repository):",
                      target_dir, clean_files)

        msg_and_write(:same, "SKIPPING the following files as they would not change:",
                      nothing, same_files)

    end

    # done
    msg(:general, "successfully generated $(replacements["PKGNAME"])")

    nothing
end

end # module
