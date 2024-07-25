module AssignGroupsDataFrames

using AssignGroups, DataFrames

function Immersion.parse_inputs(parser, df::DataFrame; studentcols=[1,2,3,4], preferencecols=maximum(studentcols)+1:size(df, 2))
    length(studentcols) == 4 || throw(ArgumentError("studentcols must have 4 elements"))
    students = Immersion.Student[]
    preferences = Real[]
    T = Union{}
    ngroups, nrows = length(preferencecols), 0
    for (i, row) in enumerate(eachrow(df))
        push!(students, Immersion.Student(row[studentcols]...))
        for j = preferencecols
            v = parser(row[j])
            T = promote_type(T, typeof(v))
            push!(preferences, v)
        end
        nrows = i
    end
    return students, Matrix{T}(reshape(preferences, ngroups, nrows)'), String.(collect(names(df)))[preferencecols]
end

function Partners.parse_inputs(df::DataFrame; preferencescore=-1)
    students = Partners.Student[]
    studentidx = Dict{String,Int}()
    preferences = Pair{Int,String}[]
    for (i, row) in enumerate(eachrow(df))
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
