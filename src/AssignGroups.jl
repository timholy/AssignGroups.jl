module AssignGroups

using JuMP
# using Pajarito
# using Hypatia
# using HiGHS
using Ipopt
using Juniper

export Student, assign!, unassign!, printstats

struct Student
    first_name::String
    last_name::String
    program::String
    assigned::Vector{Int}   # option assigned to each week
end
Student(first_name, last_name, program) = Student(first_name, last_name, program, Int[])

Base.:(==)(s1::Student, s2::Student) = s1.first_name == s2.first_name &&
                                       s1.last_name == s2.last_name &&
                                       s1.program == s2.program &&
                                       s1.assigned == s2.assigned

singlename(s::Student) = s.last_name * ", " * s.first_name

unassign!(students) = foreach(s -> empty!(s.assigned), students)

function assign!(students::AbstractVector{Student}, interests; penalty_sameprogram=5, penalty_samepartner=0.5, ipopt_options=["print_level"=>0])
    # Check the inputs
    axs = eachindex(students)
    first(axs) == 1 || throw(DimensionMismatch("`students` indices must start at 1"))
    noptions, nstudents, nweeks = Int[], length(axs), length(interests)
    for week in interests
        ndims(week) == 2 || throw(DimensionMismatch("Each week in `interests` must be a matrix, `week[istudent, jgroup]`"))
        axsw = axes(week)
        axs == axsw[1] || throw(DimensionMismatch("All weeks must have the same number of students"))
        first(axsw[2]) == 1 || throw(DimensionMismatch("Option indices must start at 1"))
        push!(noptions, size(week, 2))   # number of choices (groups) in each week
        all(iszero(week)) || all(>(0), week) || throw(DomainError("All entries in `interests` must be nonnegative (except pre-assigned weeks which may be all-zero)"))
    end
    coptions = [0; cumsum(noptions)]  # coptions[i]+1:coptions[i+1] is the range of column indices in A corresponding to week `i`
    totaloptions = coptions[end]

    # Define the solver
    ipopt = optimizer_with_attributes(Ipopt.Optimizer, ipopt_options...)
    optimizer = optimizer_with_attributes(Juniper.Optimizer, "nl_solver"=>ipopt)
    model = Model(optimizer)
    set_silent(model)

    # A[i, j] = 1 if student i is assigned to option j
    @variable(model, A[1:nstudents, 1:totaloptions], Bin)
    # # We'd like to use binary variables but I'm getting infeasibility errors; instead we approximate it with constraints
    # @variable(model, 0 <= A[1:nstudents, 1:totaloptions] <= 1) #, Bin)
    # @constraint(model, A .* (1 .- A) .<= 0.1/totaloptions)   # z*(1-z) == 0 implies z == 0 or z == 1

    # Each student gets assigned one option per week:
    for (i, s) in enumerate(students)
        s = students[i]
        for j = 1:nweeks
            if j > length(s.assigned) || s.assigned[j] > 0   # use -1 to indicate not participating in that week
                @constraint(model, 0.99 <= sum(A[i, coptions[j]+1:coptions[j+1]]) <= 1.01)
            end
        end
    end
    # If any of the weeks are pre-assigned, respect the choice:
    all_preassigned = true
    for (i, student) in enumerate(students)
        for (j, option) in enumerate(student.assigned)
            offset = coptions[j]
            for k = 1:noptions[j]
                if k == option
                    @constraint(model,  0.99 <= A[i, offset+k])
                    set_start_value(A[i, offset+k], 1)
                else
                    @constraint(model, A[i, offset+k] <= 0.01)
                    set_start_value(A[i, offset+k], 0)
                end
            end
        end
        all_preassigned &= length(student.assigned) == nweeks
    end
    if all_preassigned
        @warn "All students are already assigned to groups (use `unassign!` to reset)"
        return students
    end
    # Warm-start at an intermediate value (∝ 1/interest) for the remaining weeks:
    for (i, student) in enumerate(students)
        for j = length(student.assigned)+1:nweeks
            _interests = interests[j][i, :]
            w = sum(1 ./ _interests)
            isfinite(w) || throw(DomainError("Student $i has invalid preference scores in week $j (all must be > 0)"))
            offset = coptions[j]
            for k = 1:noptions[j]
                set_start_value(A[i, offset+k], 1 / (_interests[k] * w))
            end
        end
    end
    ## Build the objective
    # First we create a matrix S where S[i, j] = true/false depending on whether students i and j are in the same program
    S = falses(nstudents, nstudents)
    for i1 = 1:nstudents
        p1 = students[i1].program
        for i2 = i1+1:nstudents
            p2 = students[i2].program
            S[i1, i2] = S[i2, i1] = p1 == p2
        end
    end
    # The aggregate preference matrix
    P = hcat(interests...)
    # Now the objective
    @NLobjective(model, Min, sum(A[i, j] * P[i, j] for i = 1:nstudents, j = 1:totaloptions) +
                             penalty_sameprogram * sum(A[i1, j] * A[i2, j] * S[i1, i2] for i1 = 1:nstudents, i2 = i1+1:nstudents, j = 1:totaloptions) +
                             penalty_samepartner * sum(A[i1, j] * A[i2, j] for i1 = 1:nstudents, i2 = i1+1:nstudents, j = 1:totaloptions)^2)
    optimize!(model)
    # @show primal_status(model) dual_status(model) has_values(model) has_duals(model) objective_value(model)
    # Extract the assignments
    Aval = value.(A)
    for i = 1:nstudents
        s = students[i]
        for j = length(s.assigned)+1:nweeks
            offset = coptions[j]
            for k = 1:noptions[j]
                Aval[i, offset+k] > 0.5 && push!(s.assigned, k)
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
    nweeksnz = 0
    for (j, week) in enumerate(interests)
        all(iszero, week) && continue
        nweeksnz += 1
        for (i, s) in enumerate(students)
            pref += week[i, s.assigned[j]]
        end
    end
    pref /= nweeksnz * nstudents
    for (i1, s1) in enumerate(students)
        for i2 = i1+1:nstudents
            s2 = students[i2]
            prkey = (singlename(s1), singlename(s2))
            for j = 1:nweeks
                if s1.assigned[j] == s2.assigned[j] && s1.assigned[j] > 0
                    npairs[prkey] = get(npairs, prkey, 0) + 1
                end
            end
            if s1.program == s2.program
                prog = s1.program
                for j = 1:nweeks
                    if s1.assigned[j] == s2.assigned[j] && s1.assigned[j] > 0
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
    println(io, "Mean preference score: ", pref)
    println(io, "\nTwo or more students from the same program assigned to the same group (\"program collisions\"):")
    println(io, "  Total number of program collisions: ", length(nprog))
    println(io, "  Maximum number of collisions in a single group: ", maximum(values(nprog); init=0))
    progsum = Dict{String, Int}()
    for ((j, k, prog), v) in nprog
        progsum[prog] = get(progsum, prog, 0) + v
    end
    println(io, "  Number of times each program appears in a collision:")
    for pr in sort(collect(progsum); by=first)
        println(io, "   ", pr)
    end
    println(io, "\nTwo or more students sharing a group in more than one week (\"student collisions\"):")
    println(io, "  Total number of student collisions: ", length(filter(pr -> pr.second > 1, npairs)))
    println(io, "  Maximum number of collisions for a single pair: ", maximum(values(npairs); init=0))
end
printstats(students, interests) = printstats(stdout, students, interests)

function parse_inputs end

end
