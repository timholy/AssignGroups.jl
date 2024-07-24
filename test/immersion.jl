module TestImmersion

using AssignGroups.Immersion
using CSV, DataFrames
using Test

@testset "Immersion" begin
    students = [Student("Student"*s, "Last", "Program"*p) for (s, p) in zip('A':'F', "123123")]
    # Easy case (perfect solution available): one week, students from same program have disjoint preferences
    preferences = (
        [1 4;
         1 4;
         1 4;
         4 1;
         4 1;
         4 1],
    )
    assign!(students, preferences)
    for (i, s) in enumerate(students)
        @test only(s.assigned) == 1 + (i > 3)
    end
    pref, maximbalance, npairs, nprog = Immersion.analyze(students, preferences)
    @test pref == 1
    @test npairs[("Last, StudentA", "Last, StudentB")] == 1
    @test npairs[("Last, StudentA", "Last, StudentC")] == 1
    @test npairs[("Last, StudentB", "Last, StudentC")] == 1
    @test npairs[("Last, StudentD", "Last, StudentE")] == 1
    @test npairs[("Last, StudentD", "Last, StudentF")] == 1
    @test npairs[("Last, StudentE", "Last, StudentF")] == 1
    @test get(npairs, ("Last, StudentA", "Last, StudentD"), 0) == 0
    @test isempty(nprog)
    str = sprint(printstats, students, preferences)
    @test occursin(r"Mean preference score: 1.0", str)
    @test occursin(r"Two or more students from the same program assigned to the same group", str)
    @test occursin(r"Total number of program collisions: 0", str)
    @test occursin(r"Total number of student collisions: 0", str)
    # Easy case (perfect solution available): two weeks, students from same program have disjoint preferences
    preferences = (
        [1 4;
         1 4;
         1 4;
         4 1;
         4 1;
         4 1],
        [1 4 4;
         4 1 4;
         4 4 1;
         4 1 4;
         4 4 1;
         1 4 4],
    )
    unassign!(students)
    assign!(students, preferences)
    for (i, s) in enumerate(students)
        @test s.assigned == [1 + (i > 3), i < 4 ? i : mod1(i+1, 3)]
    end
    pref, maximbalance, npairs, nprog = Immersion.analyze(students, preferences)
    @test pref == 1
    @test npairs[("Last, StudentA", "Last, StudentB")] == 1
    @test npairs[("Last, StudentA", "Last, StudentC")] == 1
    @test npairs[("Last, StudentB", "Last, StudentC")] == 1
    @test npairs[("Last, StudentD", "Last, StudentE")] == 1
    @test npairs[("Last, StudentD", "Last, StudentF")] == 1
    @test npairs[("Last, StudentE", "Last, StudentF")] == 1
    @test npairs[("Last, StudentA", "Last, StudentF")] == 1
    @test npairs[("Last, StudentB", "Last, StudentD")] == 1
    @test npairs[("Last, StudentC", "Last, StudentE")] == 1
    @test get(npairs, ("Last, StudentA", "Last, StudentD"), 0) == 0
    @test isempty(nprog)
    # Can we get the same assignment by manually specifying the first week assignment?
    students0 = deepcopy(students)
    for student in students
        pop!(student.assigned)
    end
    preferences_fake = (zeros(Int, 6, 2), preferences[2])
    assign!(students, preferences_fake)
    @test students == students0
    # Do we get a warning if all students are pre-assigned?
    @test_logs (:warn, "All students are already assigned to groups (use `unassign!` to reset)") assign!(students, preferences)
    # Case with conflict: three groups, one week, students from the same program have the same top choice but differ in their second choice
    preferences = (
        [1 3 4;
         4 1 3;
         3 4 1;
         1 4 2;
         2 1 4;
         4 2 1],
    )
    unassign!(students)
    assign!(students, preferences)
    for (i, s) in enumerate(students)
        @test only(s.assigned) == (i < 4 ? i : mod1(i-1, 3))
    end
    pref, maximbalance, npairs, nprog = Immersion.analyze(students, preferences)
    @test pref == 1.5
    @test isempty(nprog)
    # If we eliminate the same-program penalty, each student gets the top choice
    unassign!(students)
    assign!(students, preferences; penalty_sameprogram=0)
    for (i, s) in enumerate(students)
        @test only(s.assigned) == (i < 4 ? i : mod1(i, 3))
    end
    pref, maximbalance, npairs, nprog = Immersion.analyze(students, preferences)
    @test pref == 1
    @test nprog[(1, 1, "Program1")] == 1  # during week 1, group 1 has two students from Program1
    @test nprog[(1, 2, "Program2")] == 1  # during week 1, group 2 has two students from Program2
    @test nprog[(1, 3, "Program3")] == 1  # during week 1, group 3 has two students from Program3
    # Case with conflict: two weeks, students from different programs have the same top choice but differ in their second choice
    preferences = (
        [1 4;
         1 4;
         1 4;
         4 1;
         4 1;
         4 1],
        [1 3 4;
         1 2 4;
         1 4 3;
         1 3 4;
         1 2 4;
         1 4 3],
    )
    unassign!(students)
    assign!(students, preferences; penalty_sameprogram=0)
    for (i, s) in enumerate(students)
        @test s.assigned == [1 + (i > 3), mod1(i, 3)]
    end
    pref, maximbalance, npairs, nprog = Immersion.analyze(students, preferences)
    @test pref == 1.5
    @test nprog[(2, 1, "Program1")] == 1  # during week 2, group 1 has two students from Program1
    @test nprog[(2, 2, "Program2")] == 1
    @test nprog[(2, 3, "Program3")] == 1
    @test maximum(values(npairs)) == 1

    unassign!(students)
    assign!(students, preferences; penalty_samepartner=0)
    pref, maximbalance, npairs, nprog = Immersion.analyze(students, preferences)
    @test pref == (6 + (3 + 1 + 1 + 1 + 2 + 3)) / 12
    @test isempty(nprog)
    @test any(==(2), values(npairs))

    # Test the extensions
    students1, preferences1, groups1 = Immersion.parse_inputs(x -> parse(Int, x), CSV.Rows(joinpath(@__DIR__, "csvfiles", "immersion1.csv")))
    @test length(students1) == 6
    @test size(preferences1) == (6, 2)
    @test groups1 == ["TopicA", "TopicB"]
    students1, preferences1, groups1 = Immersion.parse_inputs(x -> parse(Int, x), DataFrame(CSV.Rows(joinpath(@__DIR__, "csvfiles", "immersion1.csv"))))
    @test length(students1) == 6
    @test size(preferences1) == (6, 2)
    @test groups1 == ["TopicA", "TopicB"]
end

end
