# .resolve_charset aborts on an unavailable charset

    Code
      artoo:::.resolve_charset("not-a-real-charset-zzz")
    Condition
      Error:
      ! Encoding "not-a-real-charset-zzz" is not available on this system.
      i The host `iconv` provides no spelling of it or a known alias.

# .to_target fast-paths UTF-8 and honours on_invalid policies

    Code
      artoo:::.to_target(x, "US-ASCII", "error")
    Condition
      Error:
      ! Cannot encode 1 value to "US-ASCII".
      x Offending value: "™".
      i Write to Dataset-JSON (UTF-8), or set `on_invalid`.

