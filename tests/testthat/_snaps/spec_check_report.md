# .format_check renders the sectioned report

    Code
      cat(vport:::.format_check(fixed_check()), sep = "\n")
    Output
      vport Spec Check
      ================
      
      Spec Summary
      ------------
      Study: CDISCPILOT01
      Scope: ADSL
      Datasets: 1    Variables: 48
      Methods referenced: 5    Comments referenced: 3
      
      Findings Summary
      ----------------
        error    1
        warning  1
        note     1
      
      Errors
      ------
      [variable_method_resolves] Variable ADSL.AGEGR1 references undefined method 'MT.MISSING'.  (ADSL.AGEGR1)
      
      Warnings
      --------
      [method_description_present] method_id 'MT.X' has a blank description that spans lines.  (MT.X)
      
      Notes
      -----
      [variable_label_present] Variable ADSL.SEX has no label.  (ADSL.SEX)
      

