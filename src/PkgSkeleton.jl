module PkgSkeleton

using ArgCheck: @argcheck
import Dates
using DocStringExtensions: SIGNATURES
import LibGit2
import Pkg

####
####
####

####
#### Template values
####


"""
$(SIGNATURES)

Populate a vector of replacement pairs, either from arguments or by querying global settings
and state.
"""
function get_replacement_values(; pkg_name)
    c = LibGit2.GitConfig()     # global configuration
    _getgitopt(opt, type = AbstractString) = LibGit2.get(type, c, opt)
    ["{UUID}" => Pkg.METADATA_compatible_uuid(pkg_name),
     "{PKGNAME}" => pkg_name,
     "{GHUSER}" => _getgitopt("github.user"),
     "{USERNAME}" => _getgitopt("user.name"),
     "{USEREMAIL}" => _getgitopt("user.email"),
     "{YEAR}" => Dates.year(Dates.now())]
end

####
#### Template application
####

"""
$(SIGNATURES)

Replace multiple pairs in `str`, using `replace` iteratively.
"""
replace_multiple(str, replacements) = foldl(replace, str, replacements)

"""
$(SIGNATURES)

Copy from `src_dir` to `dest_dir` recursively, making the substitutions of

1. file contents and

2. filenames

using `replacements`.

Existing files are not overwritten unless `force = true`.

Directory names are *not* replaced.

Return a list of `source => dest` path pairs, with `source ≡ nothing` when `dest` was not
overwritten.
"""
function copy_and_substitute(src_dir, dest_dir, replacements; force::Bool = false)
    results = Vector{Pair{Union{String,Nothing},String}}()
    for (root, dirs, files) in walkdir(src_dir)
        sub_dir = relpath(root, src_dir)
        mkpath(normpath(dest_dir, sub_dir))
        for file in files
            srcfile = joinpath(root, file)
            destfile = normpath(joinpath(dest_dir, sub_dir,
                                         replace_multiple(file, replacements)))
            if isfile(destfile) && !force
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

function resolve_template_dir(name::Symbol)
    dir = abspath(joinpath(@__DIR__, "..", "templates", name))
    @argcheck isdir(dir) "Could not find built-in template $(name)."
    dir
end

function resolve_template_dir(dir::AbstractString)
    @argcheck isdir(dir) "Could not find directory $(dir)."
    dir
end

"""
$(SIGNATURES)


"""
pkg_name_from_path(dir::AbstractString) = basename(dirname(dest_dir))



####
#### exposed API
####

function generate(dest_dir; template = :default, force = false,
                  pkg_name = pkg_name_from_path(dest_dir),
                  git_init = true, docs_manifest = true)
    # preliminary checks
    @argcheck isfile(dest_dir) "destination $(dest_dir) is a file."
    if !force && !isdir(dest_dir)
        @warn "destination $(dest_dir) exists, skipping package generation.\nConsider `force = true`."
        return false
    end

    # copy and substitute
    @info "getting template values"
    replacements = get_replacement_values(pkg_name)
    @info "copy and substitute"
    results = copy_and_subtitute(dest_dir, resolve_template_dir(template), replacements;
                                 force = force)

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
