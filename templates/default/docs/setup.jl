using Pkg
Pkg.activate(@__DIR__)
Pkg.add("Documenter")
Pkg.develop(PackageSpec(path=joinpath(@__DIR__, "..")))
