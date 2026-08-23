# a document with no MetaDataVersion is refused

    Code
      define_lint(other)
    Condition
      Error in `define_lint()`:
      ! '<tmp>/no-mdv.xml' is not a Define-XML document.
      x It has no MetaDataVersion element.

# the printed reports name what they actually checked

    Code
      print(validate_define(minimal()))
    Output
      artoo Define-XML Schema Check
      =============================
      
      Summary
      -------
      Document: define-minimal.xml
      Define-XML version: 2.1
      Schema valid: yes
      
      No findings.
      

---

    Code
      print(define_lint(minimal()))
    Output
      artoo Define-XML Reference Check
      ================================
      
      Summary
      -------
      Document: define-minimal.xml
      Definitions: 9    References: 8
      
      No findings.
      

