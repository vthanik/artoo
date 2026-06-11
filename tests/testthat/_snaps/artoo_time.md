# print is stable

    Code
      print(artoo_time(c(0, 30600, NA)))
    Output
      <artoo_time[3]>
      [1] 00:00:00 08:30:00 <NA>    

# c.artoo_time rejects an incompatible part with caller attribution

    Code
      c(a, "x")
    Condition
      Error:
      ! Cannot combine <artoo_time> with a string.

# [<- aborts on a character RHS (no silent corruption)

    Code
      t[1] <- "noon"
    Condition
      Error:
      ! Cannot assign a string into a <artoo_time>.

# comparison with a character value aborts (review)

    Code
      t == "08:30:00"
    Condition
      Error:
      ! Cannot compare a <artoo_time> with a character value.
      i Build a <artoo_time> with `artoo_time()`, or compare on seconds.

