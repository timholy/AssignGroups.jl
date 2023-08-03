# AssignGroups

This packages "optimizes" (according to chosen criteria) assignment of students to collaborative groups.

It was designed for Washington University in St. Louis' umbrella biomedical sciences program, the
Division of Biological and Biomedical Science (DBBS). DBBS currently consists of 12 programs, admits approximately
120 students/year, and begins with "Scientific Immersion" in which students get assigned to a group in week1 and week2.

The optimization criteria are as follows:
- each student supplies a preference score (lower is better) for each of the groups in each week
- penalize assigning students from the same program to the same group during the same week
- penalize having students paired in more than one group.

Here's a quick demo, setting up 6 students from 3 different programs; week 1 has just two groups, while week 2 has 3 groups.
The student preferences are captured in the variable `interests` below.

```julia
julia> using AssignGroups

julia> students = [Student("Student"*s, "Program"*p) for (s, p) in zip('A':'F', "123123")]
6-element Vector{Student}:
 Student("StudentA", "Program1", Int64[])
 Student("StudentB", "Program2", Int64[])
 Student("StudentC", "Program3", Int64[])
 Student("StudentD", "Program1", Int64[])
 Student("StudentE", "Program2", Int64[])
 Student("StudentF", "Program3", Int64[])

julia> interests = (# Easy case (perfect solution available): two weeks, students have disjoint interests
    [1 4;    # Week 1: student A scores group 1 as a 1 and group 2 as a 4
     1 4;    # students B&C give the same scores as A
     1 4;
     4 1;    # Students D-F have the opposing preference to students A-C
     4 1;
     4 1],
    [1 4 4; # Week 2: now there are 3 groups (no relation to the previous week, the groups get novel assignments)
     4 1 4; # Students who shared interests during week 1 are non-overlapping
     4 4 1;
     4 1 4; # And students in the same program are also not overlapping
     4 4 1;
     1 4 4],
);

julia> assign!(students, interests)

******************************************************************************
This program contains Ipopt, a library for large-scale nonlinear optimization.
 Ipopt is released as open source code under the Eclipse Public License (EPL).
         For more information visit https://github.com/coin-or/Ipopt
******************************************************************************

6-element Vector{Student}:
 Student("StudentA", "Program1", [1, 1])
 Student("StudentB", "Program2", [1, 2])
 Student("StudentC", "Program3", [1, 3])
 Student("StudentD", "Program1", [2, 2])
 Student("StudentE", "Program2", [2, 3])
 Student("StudentF", "Program3", [2, 1])
```

The output here means that:
- during week 1, students A-C were assigned group1 and students D-F were assigned group2
- during week 2, students A-C were assigned groups 1-3 respectively; StudentD got assigned group2,
  StudentE got assigned group3, and StudentF got assigned group1.

In other words,
- each student got their top preference in each week
- there were no cases where two students were assigned to the same group in both weeks
- there were no cases where two students from the same program got assigned to the same group

This is the "perfect case," but you cannot count on that always being achievable.

To get an overall sense of the solution, you can use

```
julia> printstats(students, interests)
Mean preference score: 1.0
Two or more students from the same program assigned to the same group ("program collisions"):
  Total number of program collisions: 0
  Maximum number of collisions in a single group: 0
  Number of times each program appears in a collision: Dict{String, Int64}()
Two or more students sharing a group in more than one week ("student collisions"):
  Total number of student collisions: 0
  Maximum number of collisions for a single pair: 1
```

The `printstats` call is intended to help you tune the fitting parameters to avoid undesirable outcomes:

```julia
assign!(students, interests; penalty_sameprogram=5, penalty_samepartner=10)
```

Increase:

- `penalty_sameprogram` if you get too many "program collisions"
- `penalty_samepartner` if you get too many "student collisions"

Note that these can be in conflict with each other, you may not be able to avoid all collisions.
Likewise, the more you penalize collisions, the less well you respect student `interests`.

Finally, you can manually perform early assignments and compute the remainder; if `student.assigned` is not empty upon calling `assign!`, the existing choices are retained. Use `unassign!(students)` to wipe out all existing assignments.
