module Partners

using JuMP
using HiGHS
using Statistics

export Student, assign, printstats

struct Student
    first_name::String
    last_name::String
    score::Float64
end

Base.:(==)(s1::Student, s2::Student) = s1.first_name == s2.first_name &&
                                       s1.last_name == s2.last_name

Base.show(io::IO, s::Student) = print(io, s.first_name, " ", s.last_name, " (", s.score, ")")

singlename(s::Student) = s.first_name * " " * s.last_name

function assign(students::AbstractVector{Student}, ngroups::Int, preferences::AbstractMatrix{<:Real})
    # Check the inputs
    axs = eachindex(students)
    first(axs) == 1 || throw(DimensionMismatch("`students` indices must start at 1"))
    nstudents = length(axs)
    axes(preferences) == (axs, axs) || throw(DimensionMismatch("Dimensions of `preferences` must match `students`"))
    scores = [s.score for s in students]
    meanscore = mean(scores)
    minsize, maxsize = floor(Int, nstudents/ngroups), ceil(Int, nstudents/ngroups)

    # Define the solver
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    # Define the variables (which include calculation intermediates)
    @variables(model, begin
        # A[i, j] = 1 if student i is assigned to group j
        A[1:nstudents, 1:ngroups], Bin
        minsize <= groupsize[1:ngroups] <= maxsize, Int
        groupdeviation[1:ngroups]
        t
        # paired[i1, i2, j] = 1 if students i1 and i2 are in group j
        paired[i=1:nstudents, (i+1):nstudents, 1:ngroups], Bin
    end)

    # Each student gets assigned to exactly one group
    @constraints(model, begin
        [i=1:nstudents], sum(A[i, j] for j in 1:ngroups) == 1
    end)
    # Compute the group sizes
    @constraints(model, begin
        [j=1:ngroups], groupsize[j] == sum(A[i, j] for i in 1:nstudents)
    end)
    # Compute the group score deviations
    @constraints(model, begin
        [j=1:ngroups], groupdeviation[j] == sum(scores[i] * A[i, j] for i in 1:nstudents) - groupsize[j] * meanscore
    end)
    # Computing pairing
    @constraints(model, begin
        [i1=1:nstudents, i2=(i1+1):nstudents, j=1:ngroups], paired[i1, i2, j] <= (A[i1, j] + A[i2, j]) / 2
    end)
    # Objective term: minimize the groupdeviation
    @constraint(model, [t; groupdeviation] in MOI.NormOneCone(1 + ngroups))

    # Define the objective
    @objective(
        model,
        Min,
        t + sum(paired[i1, i2, j] * preferences[i1, i2] for i1 in 1:nstudents, i2 in (i1+1):nstudents, j in 1:ngroups)
    )

    # Solve the model
    optimize!(model)
    if termination_status(model) != MOI.OPTIMAL
        @error "Solver terminated with status $(termination_status(model))"
    end

    # @show value.(A) value.(groupsize) value.(groupdeviation) # value.(paired)

    # Extract the assignments
    Aval = value.(A)
    groups = [Student[] for j in 1:ngroups]
    for i = 1:nstudents
        s = students[i]
        for j = 1:ngroups
            Aval[i, j] > 0.5 && push!(groups[j], s)
        end
    end
    return groups
end

function parse_inputs end

end
