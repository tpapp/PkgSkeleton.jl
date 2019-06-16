using PkgSkeleton, Test, Dates, UUIDs

# test internals
using PkgSkeleton: get_replacement_values, resolve_template_dir

####
#### Command line git should be installed for tests (so that they don't depend in LibGit2).
####

if !success(`git --help`)
    @info "Command line git should be installed."
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
        err("couldn't get git option $(opt)")
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
    d = Dict(get_replacement_values(; pkg_name = "FOO"))
    @test d["{UUID}"] isa UUID
    @test d["{GHUSER}"] == GHUSER
    @test d["{USERNAME}"] == USERNAME
    @test d["{USEREMAIL}"] == USEREMAIL
    @test d["{YEAR}"] == year(now())
end

@testset "template directories" begin
    default_template = abspath(joinpath(@__DIR__, "..", "templates", "default"))
    @test resolve_template_dir(:default) == default_template
    @test_throws ArgumentError resolve_template_dir(:nonexistent_builtin)
    @test resolve_template_dir(default_template) == default_template
    @test_throws ArgumentError resolve_template_dir(tempname()) # nonexistent
end
