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

function _confirm_default(prompt, default)
    print("$prompt ($default)> ")
    val = readline()
    val == "" ? default : val
end


"""
$(SIGNATURES)

Populate a vector of replacement pairs, either from arguments or by querying global settings
and state.
"""
function get_replacement_values(; pkg_name)
    c = LibGit2.GitConfig()     # global configuration
    _getgitopt(opt, type = AbstractString) = try
        LibGit2.get(type, c, opt)
    catch
        ""
    end
    println("Confirm default values by pressing RETURN, or enter a customized value")
    replacements = [
        "{UUID}" => UUIDs.uuid4(),
        "{PKGNAME}" => pkg_name,
        "{USERNAME}" => _confirm_default("Author name", _getgitopt("user.name")),
        "{USEREMAIL}" => _confirm_default("Author email", _getgitopt("user.email")),
        "{GHUSER}" => _confirm_default("Github user name", _getgitopt("github.user")),
        "{YEAR}" => _confirm_default("Copyright year", Dates.year(Dates.now()))]

    @info "parameters:" [Symbol(k)=>v for (k,v) in replacements]...
    if _confirm_default("Confirm", "Y") in ("Y", "y")
        replacements
    else
        nothing
    end
end

####
#### Template application
####

"""
$(SIGNATURES)

Replace multiple pairs in `str`, using `replace` iteratively.
"""
replace_multiple(str, replacements) = foldl(replace, replacements; init = str)

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
    @argcheck isempty(ext) || ext == ".jl" "Invalid extension $(ext), specify package name manually."
    base
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

`skip_existing_dir = true` (the default) aborts package generation for existing directories.

`skip_existing_files = true` (the default) prevents existing files from being overwritten.

`pkg_name` can be used to specify a package name. Note that it is derived from `dest_dir`:
the package name is `"Foo"` for all of

1. `"/tmp/Foo"`,
2. `"/tmp/Foo/"`,
3. `"/tmp/Foo.jl"`,
4. `"/tmp/Foo.jl/"`,

Use a different name only when you know what you are doing.

`git_init = true` (the default) ensures that an *empty* repository is generated in
`dest_dir`. You still have to commit files yourself.

`docs_manifest` completes the `Manifest.toml` in the `docs` subdirectory. You usually want
this.
"""
function generate(dest_dir; template = :default,
                  skip_existing_dir::Bool = true,
                  skip_existing_files::Bool = true,
                  pkg_name = pkg_name_from_path(dest_dir),
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
    replacements = get_replacement_values(; pkg_name = pkg_name)
    if replacements === nothing
        @warn "aborting"
        return false
    end
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
        run(`$(Base.julia_cmd()) --project=$(docs) -e 'import Pkg; Pkg.add("Documenter")'`)
    end

    # done
    @info "successfully generated $(pkg_name)" dest_dir
    true
end

end # module
