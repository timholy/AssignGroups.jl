module AssignGroupsCSV

using AssignGroups, CSV

function AssignGroups.parse_inputs(parser, file::CSV.Rows)
    students = Student[]
    preferences = Real[]
    T = Bool
    ngroups, nrows = nothing, 0
    for (i, row) in enumerate(file)
        push!(students, Student(row[1], row[2], row[3]))
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

end
