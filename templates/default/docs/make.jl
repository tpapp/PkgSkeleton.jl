using Documenter, {PKGNAME}

makedocs(
    modules = [{PKGNAME}],
    format = :html,
    checkdocs = :exports,
    sitename = "{PKGNAME}.jl",
    pages = Any["index.md"]
)

deploydocs(
    repo = "github.com/{GHUSER}/{PKGNAME}.jl.git",
)
