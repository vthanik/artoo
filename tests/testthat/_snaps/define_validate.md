# an unknown version argument is refused

    Code
      validate_define(minimal(), version = "3.0")
    Condition
      Error in `validate_define()`:
      ! `version` must be one of "2.0" and "2.1".
      x You supplied "3.0".

# a document with no CDISC def namespace is refused with guidance

    Code
      validate_define(other)
    Condition
      Error in `validate_define()`:
      ! '<tmp>/not-define.xml' is not a Define-XML document.
      x It declares no CDISC def namespace.
      i Pass `version` to validate it as Define-XML anyway.

# a Define-XML v1.0 document is refused by name

    Code
      validate_define(v1)
    Condition
      Error in `validate_define()`:
      ! '<tmp>/define-v1.xml' is a Define-XML v1.0 document.
      x artoo validates Define-XML 2.0 and 2.1.
      i Re-export the define from a 2.x-capable tool.

# an incomplete schema install is reported as an install fault

    Code
      validate_define(minimal())
    Condition
      Error in `validate_define()`:
      ! The Define-XML schema tree is incomplete in this artoo install.
      x Missing 1 file, including '2.1.0/core/xlink.xsd'.
      i Reinstall artoo. This is not a problem with your document.

