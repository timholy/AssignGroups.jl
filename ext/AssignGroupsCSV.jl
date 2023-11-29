module AssignGroupsCSV

using AssignGroups, CSV

function Immersion.parse_inputs(parser, file::CSV.Rows)
    students = Immersion.Student[]
    preferences = Real[]
    T = Bool
    ngroups, nrows = nothing, 0
    for (i, row) in enumerate(file)
        push!(students, Immersion.Student(row[1], row[2], row[3]))
        for j = 4:length(row)
            v = parser(row[j])
            T = promote_type(T, typeof(v))
            push!(preferences, v)
        end
        if i == 1
            ngroups = length(preferences)
        else
            @assert length(row) - 3 == ngroups
        end
        nrows = i
    end
    return students, Matrix{T}(reshape(preferences, ngroups, nrows)'), String.(collect(keys(first(file)))[4:end])
end

function Partners.parse_inputs(file::CSV.Rows; preferencescore=-1)
    students = Partners.Student[]
    studentidx = Dict{String,Int}()
    preferences = Pair{Int,String}[]
    for (i, row) in enumerate(file)
        s = Partners.Student(row[1], row[2], parse(Float64, row[3]))
        push!(students, s)
        studentidx[Partners.singlename(s)] = i
        if !ismissing(row[4])
            push!(preferences, i => row[4])
        end
    end
    prefmtrx = zeros(typeof(preferencescore), length(students), length(students))
    for (i, prefs) in preferences
        for name in split(prefs, ",")
            j = studentidx[strip(name)]
            prefmtrx[i, j] = prefmtrx[j, i] = preferencescore
        end
    end
    return students, prefmtrx
end

end
