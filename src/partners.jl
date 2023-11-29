module Partners

using JuMP
using HiGHS
using Statistics

const OPTIMAL = MOI.OPTIMAL
export Student, assign, OPTIMAL

const PSA = Pair{String}

"""
    Student(first_name, last_name, score)

Construct a student. `score` should be some measure of performance. It is used as an optimization target, attempting
to minimize the differences in average `score` across groups.
"""
struct Student
    first_name::String
    last_name::String
    score::Float64
end

Base.:(==)(s1::Student, s2::Student) = s1.first_name == s2.first_name &&
                                       s1.last_name == s2.last_name

Base.show(io::IO, s::Student) = print(io, s.first_name, " ", s.last_name, " (", s.score, ")")

singlename(s::Student) = s.first_name * " " * s.last_name

"""
    groups, status = assign(students::AbstractVector{Student}, ngroups::Int, preferences::AbstractMatrix{<:Real};
                            silent::Bool=true, time_limit=10.0, attributes=()))

Assign `students` to `ngroups` groups, balancing the number of students/group, average "scores", and respecting partner `preferences`.
`preferences[i, j] < 0` if `students[i]` and `students[j]` have listed each other as desirable partners; the more negative (the larger the magnitude),
the more this preference will be valued compared to balancing average "scores."

`groups` is a vector-of-vectors, each containing the students assigned to a particular group.
`status = OPTIMAL` if optimization converged.

Keyword arguments:
- set `silent=false` to see incremental output during optimization
- `time_limit` is expressed in seconds; consider increasing this number if `status != OPTIMAL`
- `attributes` is a list of `"name" => val` pairs, see the [HiGHS options](https://ergo-code.github.io/HiGHS/dev/options/definitions/) for a complete list.
  `"mip_rel_gap"` may be particularly useful for controlling convergence.

See also: [`Student`](@ref), [`Partners.parse_inputs`](@ref) (after loading `CSV.jl`).
"""
function assign(students::AbstractVector{Student}, ngroups::Int, preferences::AbstractMatrix{<:Real};
                silent::Bool=true, time_limit=10.0, attributes::Union{Tuple{Vararg{PSA}}, AbstractVector{<:PSA}}=())
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
    silent && set_silent(model)
    set_attribute(model, "time_limit", float(time_limit))
    if attributes !== nothing
        for pr in attributes
            set_attribute(model, pr...)
        end
    end

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
        print(solution_summary(model))
        if termination_status(model) == MOI.TIME_LIMIT
            rtol = round(solution_summary(model).relative_gap; sigdigits=2)
            @info "Consider increasing `time_limit` (currently $time_limit) and/or `attributes=(\"mip_rel_gap\"=>rtol, ...)` where rtol > $rtol\n      or make `preferences` even more negative. Set `silent=true` to see progress."
        end
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
    return groups, termination_status(model)
end

"""
    students, preferences = parse_inputs(file::CSV.Rows; preferencescore=-1)

Extract a list of students from a CSV file. The CSV file should have the following format:

    First,Last,Score,Partners
    StudentA,Last,0.78,
    StudentB,Last,0.92,"StudentA Last,StudentK Last"
    StudentC,Last,0.85,
    ...

The header line is optional.  `Score` is a floating point number, and `Partners` is (optionally) a comma-separated list
of student names who are requested partners. The `preferencescore` is the score assigned to each requested pairing, i.e.,
`preferences[i, j] ∈ (0, preferencescore)`.

!!! warning
    You must load the `CSV` package for this method to be available.

See also: [`assign`](@ref).
"""
function parse_inputs end

end
