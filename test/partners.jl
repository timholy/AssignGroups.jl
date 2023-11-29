module TestPartners

using AssignGroups.Partners
using Statistics
using Test
using CSV

@testset "Partners" begin
    students = [Student("Student"*s, "Last", p) for (s, p) in zip('A':'F', [1,2,3,1,2,3])]
    groups, status = assign(students, 2, zeros(6, 6); attributes=("mip_rel_gap" => 1e-3,))
    @test status == OPTIMAL
    for g in groups
        @test length(g) == 3
        @test mean([s.score for s in g]) ≈ 2
    end
    redirect_stdout(devnull) do
        @test_logs (:error, r"TIME_LIMIT") (:info, r"Consider") assign(students, 2, zeros(6, 6); time_limit=1e-6)
    end

    groups, status = assign(students, 3, zeros(6, 6))
    for g in groups
        @test length(g) == 2
        @test mean([s.score for s in g]) ≈ 2
    end
    # A strong preference overrides the score balancing
    prefs = zeros(6, 6)
    prefs[1, 4] = prefs[4, 1] = -1000
    groups, status = assign(students, 3, prefs)
    any14 = false
    for g in groups
        @test length(g) == 2
        any14 |= students[[1,4]] ⊆ g
    end
    @test any14
    prefs[1, 4] = prefs[4, 1] = -0.1
    groups, status = assign(students, 3, prefs)
    for g in groups
        @test length(g) == 2
        @test mean([s.score for s in g]) ≈ 2
    end

    students2, prefs2 = Partners.parse_inputs(CSV.Rows(joinpath(@__DIR__, "csvfiles", "partners.csv")); preferencescore=-0.1)
    @test students2 == students
    @test prefs2 == prefs
end

end
