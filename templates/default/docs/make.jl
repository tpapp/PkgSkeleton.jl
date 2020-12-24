# see documentation at https://juliadocs.github.io/Documenter.jl/stable/

using Documenter, {PKGNAME}

makedocs(
    modules = [{PKGNAME}],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "{USERNAME}",
    sitename = "{PKGNAME}.jl",
    pages = Any["index.md"]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/{GHUSER}/{PKGNAME}.jl.git",
    push_preview = true
)
