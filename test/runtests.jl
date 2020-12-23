using PkgSkeleton, Test, Dates, UUIDs

# import internals for testing
using PkgSkeleton: fill_replacements, resolve_template_directory, pkg_name_from_path,
    delimited_replacements, replace_multiple, read_template_directory, GitOptionNotFound,
    generate

####
#### some templates for testing
####

const TEST_TEMPLATES = joinpath(@__DIR__, "test_templates")

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

# set and unset only under CI
setgitopt(name, value) = CI && run(`git config --global --add $(name) $(value)`)
setgitopt(name, ::Nothing) = CI && run(`git config --global --unset-all $(name)`)

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

@testset "git option error" begin
    @test sprint(showerror, GitOptionNotFound("user.name", "the project file")) ==
"""
Could not find option “user.name” in your global git configuration.

It is necessary to set this for the project file.

You can set this in the command line with

git config --global user.name "…"
"""
end

@testset "replacement values" begin
    # also see tests at the end for the error
    @testset "using environment" begin
        d = fill_replacements(NamedTuple(); target_dir = "/tmp/FOO.jl")
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
        r′ = fill_replacements(r; target_dir = "irrelevant")
        @test sort(collect(pairs(r)), by = first) == sort(collect(pairs(r′)), by = first)
    end
end

@testset "template directories" begin
    default_template = abspath(joinpath(@__DIR__, "..", "templates", "default"))
    @test resolve_template_directory(:default) == default_template
    @test_throws ArgumentError resolve_template_directory(:nonexistent_builtin)
    @test resolve_template_directory(default_template) == default_template
    @test_throws ArgumentError resolve_template_directory(tempname()) # nonexistent
end

@testset "package name from path" begin
    @test pkg_name_from_path("/tmp/FooBar") == "FooBar"
    @test pkg_name_from_path("/tmp/FooBar.jl") == "FooBar"
    @test pkg_name_from_path("/tmp/FooBar/") == "FooBar"
    @test pkg_name_from_path("/tmp/FooBar.jl/") == "FooBar"
    @test_throws ArgumentError pkg_name_from_path("/tmp/FooBar.bin/")
end

@testset "multiple replaces" begin
    @test replace_multiple("{COLOR} {DISH}",
                           delimited_replacements((COLOR = "green",
                                                   DISH = "curry"))) == "green curry"
end

@testset "read template" begin
    @test read_template_directory(joinpath(TEST_TEMPLATES, "AB")) ==
        ["a.md" => "aa\n", "b/bb.md" => "bb\n"]
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
        generate(dest_dir)
        check_dest_dir("Foo", dest_dir)

        # run various sanity checks (mostly test contents of the template, CI will error)
        cd(dest_dir) do
            @info "test documentation (instantiation)"
            run(`julia --startup-file=no --project=docs -e 'using Pkg; Pkg.instantiate(); Pkg.develop(PackageSpec(path=pwd()))'`)
            @test isfile(joinpath(dest_dir, "docs", "Manifest.toml"))
            @info "test documentation (generation)"
            run(`julia --startup-file=no --project=docs --color=yes docs/make.jl`)
            @test isfile(joinpath(dest_dir, "docs", "build", "index.html"))
            @info "test coverage (only instantiation)"
            run(`julia --startup-file=no --project=test/coverage -e 'using Pkg; Pkg.instantiate()'`)
            @test isfile(joinpath(dest_dir, "test", "coverage", "Manifest.toml"))
        end
    end
end

@testset "uncomitted file handling" begin
    year = "2000"
    template = joinpath(TEST_TEMPLATES, "git_overwrite_test")

    @testset "no overwrite" begin
        mktempdir() do tempdir
            run(`$(joinpath(TEST_TEMPLATES, "create_git_test_repo.sh")) $(tempdir)`)
            generate(tempdir; user_replacements = (YEAR = year, ), template = template)
            for file in ["staged", "untracked", "in_repo_unstaged"]
                @test chomp(read(joinpath(tempdir, file), String)) == file
            end
            @test chomp(read(joinpath(tempdir, "comitted"), String)) == year
        end
    end

    @testset "forced overwrite" begin
        mktempdir() do tempdir
            run(`$(joinpath(TEST_TEMPLATES, "create_git_test_repo.sh")) $(tempdir)`)
            generate(tempdir; user_replacements = (YEAR = year, ), template = template,
                     overwrite_uncommitted = true)
            for file in ["staged", "untracked", "in_repo_unstaged", "comitted"]
                @test chomp(read(joinpath(tempdir, file), String)) == year
            end
        end
    end
end

@testset "unset options" begin
    # NOTE this should be the last test as it unsets options on CI
    if CI                       # only for CI
        setgitopt("user.name", nothing)
        @test_throws GitOptionNotFound fill_replacements(NamedTuple();
                                                         target_dir = "/tmp/FOO.jl")
    end
end
