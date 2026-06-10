# print is stable

    Code
      print(vport_time(c(0, 30600, NA)))
    Output
      <vport_time[3]>
      [1] 00:00:00 08:30:00 <NA>    

# c.vport_time rejects an incompatible part with caller attribution

    Code
      c(a, "x")
    Condition
      Error:
      ! Cannot combine <vport_time> with a string.

# [<- aborts on a character RHS (no silent corruption)

    Code
      t[1] <- "noon"
    Condition
      Error:
      ! Cannot assign a string into a <vport_time>.

# comparison with a character value aborts (review)

    Code
      t == "08:30:00"
    Condition
      Error:
      ! Cannot compare a <vport_time> with a character value.
      i Build a <vport_time> with `vport_time()`, or compare on seconds.

