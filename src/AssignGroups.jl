module AssignGroups

using JuMP
# using Pajarito
# using Hypatia
# using HiGHS
using Ipopt
using Juniper

export Student, assign!, unassign!, printstats

struct Student
    name::String
    program::String
    assigned::Vector{Int}   # option assigned to each week
end
Student(name, program) = Student(name, program, [])

unassign!(students) = foreach(s -> empty!(s.assigned), students)

function assign!(students, interests; penalty_sameprogram=5, penalty_samepartner=10)
    nstudents, nweeks = length(students), length(interests)
    noptions = Int[]
    for week in interests
        nstudents == size(week, 1) || throw(DimensionMismatch("All weeks must have the same number of students"))
        push!(noptions, size(week, 2))
    end
    coptions = [0; cumsum(noptions)]

    # Define the solver
    ipopt = optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0)
    optimizer = optimizer_with_attributes(Juniper.Optimizer, "nl_solver"=>ipopt)
    model = Model(optimizer)
    set_silent(model)
    set_attribute(model, "time_limit", 60)

    # A[i, j] = 1 if student i is assigned to option j
    @variable(model, A[1:nstudents, 1:sum(noptions)], Bin)
    # Each student gets assigned one option per week:
    for i = 1:nstudents
        for j = 1:nweeks
            @constraint(model, sum(A[i, coptions[j]+1:coptions[j+1]]) == 1)
        end
    end
    ## Build the objective
    terms = [] # Union{JuMP.AffExpr, JuMP.QuadExpr}[]
    # Penalize assigning students to options they are less interested in
    for i = 1:nstudents
        for j = 1:nweeks
            week = interests[j]
            for k = 1:noptions[j]
                push!(terms, @expression(model, week[i, k] * A[i, coptions[j]+k]))
            end
        end
    end
    # Penalize assigning students from the same program to the same option
    for i1 = 1:nstudents
        p1 = students[i1].program
        for i2 = i1+1:nstudents
            p2 = students[i2].program
            p1 == p2 || continue
            for j = 1:nweeks
                for k = 1:noptions[j]
                    push!(terms, @expression(model, penalty_sameprogram * A[i1, coptions[j]+k] * A[i2, coptions[j]+k]))
                end
            end
        end
    end
    # Proxy for repeatedly sharing the same group in multiple weeks: penalize the correlation
    for i1 = 1:nstudents
        for i2 = i1+1:nstudents
            push!(terms, @expression(model, penalty_samepartner * (A[i1, :]' * A[i2, :])))
        end
    end
    @objective(model, Min, sum(terms))
    optimize!(model)
    Aval = value.(A)
    # Extract the assignments
    for i = 1:nstudents
        s = students[i]
        empty!(s.assigned)
        for j = 1:nweeks
            for k = 1:noptions[j]
                Aval[i, coptions[j]+k] > 0.5 && push!(s.assigned, k)
            end
        end
    end
    return students
end

function analyze(students, interests)
    # Statistics on the assignments:
    # - how many times students from the same program are assigned the same group
    # - how many times students appear in the same group
    # - mean preference score
    pref = 0
    nstudents, nweeks = length(students), length(interests)
    npairs = Dict{Tuple{String,String}, Int}()    # (student1, student2) => count
    nprog = Dict{Tuple{Int,Int,String}, Int}()    # (week, groupid, program) => count
    for (i1, s1) in enumerate(students)
        pref += sum(interests[j][i1, s1.assigned[j]] for j = 1:nweeks)
        for i2 = i1+1:nstudents
            s2 = students[i2]
            prkey = (s1.name, s2.name)
            for j = 1:nweeks
                if s1.assigned[j] == s2.assigned[j]
                    npairs[prkey] = get(npairs, prkey, 0) + 1
                end
            end
            if s1.program == s2.program
                prog = s1.program
                for j = 1:nweeks
                    if s1.assigned[j] == s2.assigned[j]
                        k = s1.assigned[j]
                        nprog[(j, k, prog)] = get(nprog, (j, k, prog), 0) + 1
                    end
                end
            end
        end
    end
    return pref, npairs, nprog
end

function printstats(io::IO, students, interests)
    pref, npairs, nprog = analyze(students, interests)
    nstudents, nweeks = length(students), length(interests)
    println(io, "Mean preference score: ", pref / nstudents / nweeks)
    println(io, "Two or more students from the same program assigned to the same group (\"program collisions\"):")
    println(io, "  Total number of program collisions: ", length(nprog))
    println(io, "  Maximum number of collisions in a single group: ", maximum(values(nprog); init=0))
    progsum = Dict{String, Int}()
    for ((j, k, prog), v) in nprog
        progsum[prog] = get(progsum, prog, 0) + v
    end
    print(io, "  Number of times each program appears in a collision: ")
    show(io, MIME("text/plain"), progsum)
    println(io)
    println(io, "Two or more students sharing a group in more than one week (\"student collisions\"):")
    println(io, "  Total number of student collisions: ", length(filter(pr -> pr.second > 1, npairs)))
    println(io, "  Maximum number of collisions for a single pair: ", maximum(values(npairs); init=0))
end
printstats(students, interests) = printstats(stdout, students, interests)

end
