using PkgSkeleton, Test, Dates, UUIDs

# import internals for testing
using PkgSkeleton: fill_replacement_values, resolve_template_dir, pkg_name_from_path,
    replace_multiple

####
#### Command line git should be installed for tests (so that they don't depend in LibGit2).
####

if !success(`git --help`)
    @info "Command line git should be installed for tests."
    exit(1)
end

####
#### For CI, set up environment, otherwise use local settings (and assume they are defined).
####

const CI = parse(Bool, lowercase(get(ENV, "CI", "false")))

function getgitopt(opt)
    try
        chomp(read(`git config --get $(opt)`, String))
    catch
        error("couldn't get git option $(opt)")
    end
end

setgitopt(name, value) = run(`git config --global --add $(name) $(value)`)

if CI
    USERNAME = "Joe H. User"
    USEREMAIL = "test@email.domain"
    GHUSER = "somethingclever"
    setgitopt("user.name", USERNAME)
    setgitopt("user.email", USEREMAIL)
    setgitopt("github.user", GHUSER)
else
    USERNAME = getgitopt("user.name")
    USEREMAIL = getgitopt("user.email")
    GHUSER = getgitopt("github.user")
end

####
#### test components
####

@testset "replacement values" begin
    @testset "using environment" begin
        d = fill_replacement_values(NamedTuple(); dest_dir = "/tmp/FOO.jl")
        @test d.PKGNAME == "FOO"
        @test d.UUID isa UUID
        @test d.GHUSER == GHUSER
        @test d.USERNAME == USERNAME
        @test d.USEREMAIL == USEREMAIL
        @test d.YEAR == year(now())
    end

    @testset "using explicit replacements" begin
        r = (PKGNAME = "bar", UUID = "1234", GHUSER = "someone", USERNAME = "Some O. N.",
             USEREMAIL = "foo@bar.baz", YEAR = 1643)
        r′ = fill_replacement_values(r; dest_dir = "irrelevant")
        @test sort(collect(pairs(r)), by = first) == sort(collect(pairs(r′)), by = first)
    end
end

@testset "template directories" begin
    default_template = abspath(joinpath(@__DIR__, "..", "templates", "default"))
    @test resolve_template_dir(:default) == default_template
    @test_throws ArgumentError resolve_template_dir(:nonexistent_builtin)
    @test resolve_template_dir(default_template) == default_template
    @test_throws ArgumentError resolve_template_dir(tempname()) # nonexistent
end

@testset "package name from path" begin
    @test pkg_name_from_path("/tmp/FooBar") == "FooBar"
    @test pkg_name_from_path("/tmp/FooBar.jl") == "FooBar"
    @test pkg_name_from_path("/tmp/FooBar/") == "FooBar"
    @test pkg_name_from_path("/tmp/FooBar.jl/") == "FooBar"
    @test_throws ArgumentError pkg_name_from_path("/tmp/FooBar.bin/")
end

@testset "multiple replaces" begin
    @test replace_multiple("{COLOR} {DISH}", (COLOR = "green", DISH = "curry")) ==
        "green curry"
end

####
#### test generation
####

function check_dest_dir(pkg_name, dest_dir;)
    # NOTE: very rudimentary check and should be improved, checking all valid substitutions
    readme = joinpath(dest_dir, "README.md")
    @test isfile(readme)
    @test occursin(pkg_name, read(readme, String))
    mainsrc = joinpath(dest_dir, "src", pkg_name * ".jl")
    @test isfile(mainsrc)
end

@testset "package generation and checks" begin
    mktempdir() do tempdir
        dest_dir = joinpath(tempdir, "Foo")

        # test generated structure
        @test PkgSkeleton.generate(dest_dir) == true
        check_dest_dir("Foo", dest_dir)

        # run various sanity checks (mostly test contents of the template, CI will error)
        cd(dest_dir) do
            @info "test documentation (instantiation)"
            run(`julia --project=docs -e 'using Pkg; Pkg.instantiate()'`)
            @info "test documentation (generation)"
            run(`julia --project=docs --color=yes docs/make.jl`)
            @info "test coverage (only instantiation)"
            run(`julia --project=test/coverage -e 'using Pkg; Pkg.instantiate()'`)
        end

        @test PkgSkeleton.generate(dest_dir) == false # will not overwrite
        @test PkgSkeleton.generate(dest_dir; skip_existing_dir = false) # will overwrite
    end
end
