# an unknown version is refused by name

    Code
      artoo:::.define_profile("1.0")
    Condition
      Error:
      ! `version` must be "2.0" or "2.1".
      x You supplied "1.0".

# a value outside a closed vocabulary is refused

    Code
      artoo:::.dx_enum("Sideways", p$enum$origin_type, "def:Origin Type")
    Condition
      Error:
      ! def:Origin Type "Sideways" is not allowed in this Define-XML version.
      i Allowed: "Assigned", "Collected", "Derived", "Not Available", "Other", "Predecessor", and "Protocol".

