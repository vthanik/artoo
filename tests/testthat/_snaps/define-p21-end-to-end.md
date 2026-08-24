# the structural digest of each workbook's output is stable

    Code
      cat(name, version, "\n")
    Output
      adam 2.0 
    Code
      str(define_digest(out), max.level = 2)
    Output
      List of 2
       $ elements:List of 38
        ..$ Alias                 : int 44
        ..$ AnalysisDataset       : int 2
        ..$ AnalysisDatasets      : int 1
        ..$ AnalysisResult        : int 1
        ..$ AnalysisResultDisplays: int 1
        ..$ AnalysisVariable      : int 2
        ..$ CheckValue            : int 3
        ..$ CodeList              : int 20
        ..$ CodeListItem          : int 25
        ..$ CodeListRef           : int 54
        ..$ CommentDef            : int 11
        ..$ Decode                : int 25
        ..$ Description           : int 165
        ..$ DocumentRef           : int 6
        ..$ Documentation         : int 1
        ..$ EnumeratedItem        : int 43
        ..$ GlobalVariables       : int 1
        ..$ ItemDef               : int 104
        ..$ ItemGroupDef          : int 2
        ..$ ItemRef               : int 104
        ..$ MetaDataVersion       : int 1
        ..$ MethodDef             : int 45
        ..$ ODM                   : int 1
        ..$ Origin                : int 104
        ..$ PDFPageRef            : int 1
        ..$ ProgrammingCode       : int 1
        ..$ ProtocolName          : int 1
        ..$ RangeCheck            : int 3
        ..$ ResultDisplay         : int 1
        ..$ Study                 : int 1
        ..$ StudyDescription      : int 1
        ..$ StudyName             : int 1
        ..$ SupplementalDoc       : int 1
        ..$ TranslatedText        : int 190
        ..$ WhereClauseDef        : int 2
        ..$ WhereClauseRef        : int 2
        ..$ leaf                  : int 8
        ..$ title                 : int 8
       $ lint    :List of 2
        ..$ define_orphan_comment: int 3
        ..$ define_orphan_leaf   : int 3

---

    Code
      cat(name, version, "\n")
    Output
      adam 2.1 
    Code
      str(define_digest(out), max.level = 2)
    Output
      List of 2
       $ elements:List of 42
        ..$ Alias                 : int 44
        ..$ AnalysisDataset       : int 2
        ..$ AnalysisDatasets      : int 1
        ..$ AnalysisResult        : int 1
        ..$ AnalysisResultDisplays: int 1
        ..$ AnalysisVariable      : int 2
        ..$ CheckValue            : int 3
        ..$ Class                 : int 2
        ..$ CodeList              : int 20
        ..$ CodeListItem          : int 25
        ..$ CodeListRef           : int 54
        ..$ CommentDef            : int 11
        ..$ Decode                : int 25
        ..$ Description           : int 165
        ..$ DocumentRef           : int 6
        ..$ Documentation         : int 1
        ..$ EnumeratedItem        : int 43
        ..$ GlobalVariables       : int 1
        ..$ ItemDef               : int 104
        ..$ ItemGroupDef          : int 2
        ..$ ItemRef               : int 104
        ..$ MetaDataVersion       : int 1
        ..$ MethodDef             : int 45
        ..$ ODM                   : int 1
        ..$ Origin                : int 104
        ..$ PDFPageRef            : int 1
        ..$ ProgrammingCode       : int 1
        ..$ ProtocolName          : int 1
        ..$ RangeCheck            : int 3
        ..$ ResultDisplay         : int 1
        ..$ Standard              : int 4
        ..$ Standards             : int 1
        ..$ Study                 : int 1
        ..$ StudyDescription      : int 1
        ..$ StudyName             : int 1
        ..$ SubClass              : int 1
        ..$ SupplementalDoc       : int 1
        ..$ TranslatedText        : int 190
        ..$ WhereClauseDef        : int 2
        ..$ WhereClauseRef        : int 2
        ..$ leaf                  : int 8
        ..$ title                 : int 8
       $ lint    :List of 2
        ..$ define_orphan_leaf    : int 3
        ..$ define_orphan_standard: int 4

---

    Code
      cat(name, version, "\n")
    Output
      sdtm 2.0 
    Code
      str(define_digest(out), max.level = 2)
    Output
      List of 2
       $ elements:List of 33
        ..$ Alias           : int 108
        ..$ CheckValue      : int 41
        ..$ CodeList        : int 21
        ..$ CodeListItem    : int 57
        ..$ CodeListRef     : int 27
        ..$ CommentDef      : int 21
        ..$ Decode          : int 57
        ..$ Description     : int 127
        ..$ DocumentRef     : int 32
        ..$ EnumeratedItem  : int 46
        ..$ FormalExpression: int 2
        ..$ GlobalVariables : int 1
        ..$ ItemDef         : int 87
        ..$ ItemGroupDef    : int 4
        ..$ ItemRef         : int 87
        ..$ MetaDataVersion : int 1
        ..$ MethodDef       : int 15
        ..$ ODM             : int 1
        ..$ Origin          : int 72
        ..$ PDFPageRef      : int 29
        ..$ ProtocolName    : int 1
        ..$ RangeCheck      : int 39
        ..$ Study           : int 1
        ..$ StudyDescription: int 1
        ..$ StudyName       : int 1
        ..$ SupplementalDoc : int 1
        ..$ TranslatedText  : int 184
        ..$ ValueListDef    : int 6
        ..$ ValueListRef    : int 6
        ..$ WhereClauseDef  : int 35
        ..$ WhereClauseRef  : int 35
        ..$ leaf            : int 12
        ..$ title           : int 12
       $ lint    :List of 3
        ..$ define_missing_origin: int 2
        ..$ define_orphan_comment: int 9
        ..$ define_orphan_leaf   : int 9

---

    Code
      cat(name, version, "\n")
    Output
      sdtm 2.1 
    Code
      str(define_digest(out), max.level = 2)
    Output
      List of 2
       $ elements:List of 36
        ..$ Alias           : int 108
        ..$ CheckValue      : int 41
        ..$ Class           : int 4
        ..$ CodeList        : int 21
        ..$ CodeListItem    : int 57
        ..$ CodeListRef     : int 27
        ..$ CommentDef      : int 21
        ..$ Decode          : int 57
        ..$ Description     : int 127
        ..$ DocumentRef     : int 32
        ..$ EnumeratedItem  : int 46
        ..$ FormalExpression: int 2
        ..$ GlobalVariables : int 1
        ..$ ItemDef         : int 87
        ..$ ItemGroupDef    : int 4
        ..$ ItemRef         : int 87
        ..$ MetaDataVersion : int 1
        ..$ MethodDef       : int 15
        ..$ ODM             : int 1
        ..$ Origin          : int 72
        ..$ PDFPageRef      : int 29
        ..$ ProtocolName    : int 1
        ..$ RangeCheck      : int 39
        ..$ Standard        : int 6
        ..$ Standards       : int 1
        ..$ Study           : int 1
        ..$ StudyDescription: int 1
        ..$ StudyName       : int 1
        ..$ SupplementalDoc : int 1
        ..$ TranslatedText  : int 184
        ..$ ValueListDef    : int 6
        ..$ ValueListRef    : int 6
        ..$ WhereClauseDef  : int 35
        ..$ WhereClauseRef  : int 35
        ..$ leaf            : int 12
        ..$ title           : int 12
       $ lint    :List of 4
        ..$ define_orphan_comment : int 1
        ..$ define_missing_origin : int 2
        ..$ define_orphan_standard: int 6
        ..$ define_orphan_leaf    : int 9

# an incomplete workbook is written, and every gap is named

    Code
      spec <- write_spec(spec, out, version = "2.1", created = FROZEN_P21)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "codelists$name", "codelists$nci_code", and "comments$description".
      i A conformance report will raise 6 findings; fill them in the source spec.

# a variable named by two datasets is refused, not guessed

    Code
      write_spec(spec, out, created = FROZEN_P21)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "variables$label", "variables$origin", "variables$length", "values$label", "values$origin", and "values$length".
      i A conformance report will raise 12 findings; fill them in the source spec.
      Warning:
      The `def:Standards` block was not written.
      x The spec names "SDTMIG 3.4" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! Where clause "WC.1" does not say which "USUBJID" it means.
      x 2 datasets define it: "VS" and "LB".
      i Point the where-clause row's `dataset` at one of them.

# a display described two ways is refused (#p7-review-1)

    Code
      read_spec(book)
    Condition
      Error:
      ! Analysis display "RD.T1" is described two ways.
      x Its rows disagree on name: "Table 1" and "Table 1 (draft)".
      i One display is one row; a merged id cell may not span differing values.

# a document with no location is refused, not blamed on artoo (#p7-review-3)

    Code
      write_spec(spec, out, created = FROZEN_P21)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "variables$label", "variables$origin", "variables$length", and "documents$href".
      i A conformance report will raise 9 findings; fill them in the source spec.
      Error in `.dx_archive_leaf()`:
      ! Document "LF.dm" has no location.
      x `def:leaf/@xlink:href` is required by Define-XML.
      i Set `href` on the documents table.

