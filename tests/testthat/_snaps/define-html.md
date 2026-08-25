# a missing bundled stylesheet is an install error, not a render error

    Code
      artoo:::.dx_render_html(path, TRUE, artoo:::.define_profile("2.1"))
    Condition
      Error:
      ! The Define-XML 2.1 stylesheet is missing from the artoo install.
      x Expected 'define2-1.xsl'.
      i Reinstall artoo; the stylesheets ship with the package.

