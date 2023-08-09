module AssignGroups

using JuMP
using HiGHS

export Student, assign!, unassign!, printstats

struct Student
    first_name::String
    last_name::String
    program::String
    assigned::Vector{Int}   # option assigned to each week
end
Student(first_name, last_name, program) = Student(string(first_name), string(last_name), string(program), Int[])

Base.:(==)(s1::Student, s2::Student) = s1.first_name == s2.first_name &&
                                       s1.last_name == s2.last_name &&
                                       s1.program == s2.program &&
                                       s1.assigned == s2.assigned

function Base.show(io::IO, s::Student)
    print(io, s.first_name, " ", s.last_name, " (", s.program, ")")
    if !isempty(s.assigned)
        print(io, ": ", s.assigned)
    end
end

singlename(s::Student) = s.last_name * ", " * s.first_name

unassign!(students) = foreach(s -> empty!(s.assigned), students)

function assign!(students::AbstractVector{Student}, preferences; penalty_sameprogram=1, penalty_samepartner=1, penalty_sizeimbalance=1)
    # Check the inputs
    axs = eachindex(students)
    first(axs) == 1 || throw(DimensionMismatch("`students` indices must start at 1"))
    noptions, nstudents, nweeks = Int[], length(axs), length(preferences)
    for week in preferences
        ndims(week) == 2 || throw(DimensionMismatch("Each week in `preferences` must be a matrix, `week[istudent, jgroup]`"))
        axsw = axes(week)
        axs == axsw[1] || throw(DimensionMismatch("All weeks must have the same number of students"))
        first(axsw[2]) == 1 || throw(DimensionMismatch("Option indices must start at 1"))
        push!(noptions, size(week, 2))   # number of choices (groups) in each week
    end
    coptions = [0; cumsum(noptions)]  # coptions[i]+1:coptions[i+1] is the range of column indices in A corresponding to week `i`
    totaloptions = coptions[end]
    # nperweek = vcat((fill(noptions[k], noptions[k]) for k in 1:nweeks)...)
    P = hcat(preferences...)  # all preferences in one matrix

    # For efficiency, pre-partition the students into programs
    program_to_students = Dict{String,Vector{Int}}()
    for (i, s) in enumerate(students)
        push!(get!(Vector{Int}, program_to_students, s.program), i)
    end
    programs = collect(keys(program_to_students))

    # Define the solver
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    # Define the variables (which include calculation intermediates)
    @variables(model, begin
        # A[i, j] = 1 if student i is assigned to option j
        A[1:nstudents, 1:totaloptions], Bin
        groupsize[1:totaloptions]
        mingroupsize[1:nweeks]
        maxgroupsize[1:nweeks]
        # same_program_penalty[program, j] = z if z+1 students from the same program are assigned to option j
        same_program_penalty[programs, 1:totaloptions] >= 0
        # same_pairing[i1, i2, j] = 1 if students i1 and i2 are assigned to option j
        same_pairing[i=1:nstudents, (i+1):nstudents, 1:totaloptions], Bin
        # repeat_pairing_penalty[i1, i2] = z if students i1 and i2 are paired z+1 times
        repeat_pairing_penalty[i=1:nstudents, (i+1):nstudents] >= 0
    end)

    # Each student gets assigned one option per week. If any are pre-assigned, respect that choice.
    all_preassigned = true
    for (i, s) in enumerate(students)
        s = students[i]
        # encode pre-assignments
        for (j, option) in enumerate(s.assigned)
            offset = coptions[j]
            for k = 1:noptions[j]
                if k == option
                    @constraint(model,  A[i, offset+k] == 1)
                else
                    @constraint(model,  A[i, offset+k] == 0)
                end
            end
        end
        all_preassigned &= length(s.assigned) == nweeks
        # for the remaining weeks, enforce that each student is assigned exactly one option
        for j = length(s.assigned)+1:nweeks
            @constraint(model, sum(A[i, coptions[j]+1:coptions[j+1]]) == 1)
        end
    end
    if all_preassigned
        @warn "All students are already assigned to groups (use `unassign!` to reset)"
        return students
    end

    # Define the objective
    @objective(
        model,
        Min,
        # Optimize student preferences (lower preference score is better)
        sum(P[i, j] * A[i, j] for i in 1:nstudents, j in 1:totaloptions) +
        # Penalties
        penalty_sizeimbalance * sum(maxgroupsize - mingroupsize) +
        penalty_sameprogram * sum(same_program_penalty) +
        penalty_samepartner * sum(repeat_pairing_penalty),
    )

    # Constraints (which calculate intermediate variables too)
    @constraints(model, begin
        # Compute the minimum and maximum group size for each week
        [j=1:totaloptions], groupsize[j] == sum(A[:, j])
        [k=1:nweeks, j=coptions[k]+1:coptions[k+1]], mingroupsize[k] <= groupsize[j]
        [k=1:nweeks, j=coptions[k]+1:coptions[k+1]], maxgroupsize[k] >= groupsize[j]
        # Penalize if more than two students from program p are in the same group
        [j=1:totaloptions, p=programs], sum(A[i, j] for i in program_to_students[p]) - same_program_penalty[p, j] <= 1
        # Compute if two students are in the same group
        [i1=1:nstudents, i2=(i1+1):nstudents, j=1:totaloptions],
            A[i1, j] + A[i2, j] <= 1 + same_pairing[i1, i2, j]
        # Repeat pairing penalty
        [i1=1:nstudents, i2=(i1+1):nstudents],
            sum(same_pairing[i1, i2, j] for j in 1:totaloptions) <= 1 + repeat_pairing_penalty[i1, i2]
    end)

    # Solve the model
    optimize!(model)
    if termination_status(model) != MOI.OPTIMAL
        @error "Solver terminated with status $(termination_status(model))"
    end

    # @show value.(same_pairing) value.(repeat_pairing_penalty) value.(same_program_penalty)

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

function analyze(students, preferences)
    # Statistics on the assignments:
    # - mean preference score
    # - maximum group imbalance
    # - how many times students from the same program are assigned the same group
    # - how many times students appear in the same group
    exdiff((min, max)) = max - min

    pref = 0
    nstudents, nweeks = length(students), length(preferences)
    npairs = Dict{Tuple{String,String}, Int}()    # (student1, student2) => count
    nprog = Dict{Tuple{Int,Int,String}, Int}()    # (week, groupid, program) => count
    npergroup = [zeros(Int, size(week, 2)) for week in preferences]
    nstudentsperweek = zeros(Int, nweeks)
    for (j, week) in enumerate(preferences)
        npg = npergroup[j]
        computepref = !all(iszero, week)
        for (i, s) in enumerate(students)
            option = s.assigned[j]
            option > 0 || continue
            if computepref
                nstudentsperweek[j] += 1
                pref += week[i, option]
            end
            npg[option] += 1
        end
    end
    pref /= sum(nstudentsperweek)
    maximbalance = maximum([exdiff(extrema(npg)) for npg in npergroup])
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
    return pref, maximbalance, npairs, nprog
end

function printstats(io::IO, students, preferences)
    pref, maximbalance, npairs, nprog = analyze(students, preferences)
    println(io, "Mean preference score: ", pref)
    println(io, "Maximum imbalance in group size: ", maximbalance)
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
printstats(students, preferences) = printstats(stdout, students, preferences)

function parse_inputs end

end
