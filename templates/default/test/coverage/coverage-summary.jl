####
#### Coverage summary, printed as "(percentage) covered".
####
#### Useful for CI environments that just want a summary (eg a Gitlab setup).

# NOTE: used by the Gitlab CI script, if you are not using that you can delete this file.

using Coverage
cd(joinpath(@__DIR__, "..", "..")) do
    covered_lines, total_lines = get_summary(process_folder())
    percentage = covered_lines / total_lines * 100
    println("($(percentage)%) covered")
end
