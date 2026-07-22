# .resolve_charset aborts on an unavailable charset

    Code
      artoo:::.resolve_charset("not-a-real-charset-zzz")
    Condition
      Error:
      ! Encoding "not-a-real-charset-zzz" is not available on this system.
      i The host `iconv` provides no spelling of it or a known alias.

# .to_target passes valid UTF-8 through and honours on_invalid policies

    Code
      artoo:::.to_target(x, "US-ASCII", "error")
    Condition
      Error:
      ! Cannot encode 1 value to "US-ASCII".
      x Offending value: "™".
      i Write to Dataset-JSON (UTF-8), or set `on_invalid`.

# .to_target validates a UTF-8 target (invalid bytes hit on_invalid)

    Code
      artoo:::.to_target(bad, "UTF-8", "error")
    Condition
      Error:
      ! Cannot encode 1 value as UTF-8.
      x Invalid bytes (hex-escaped): "c<e9>".
      i Re-read the source with the correct `encoding`, or set `on_invalid`.

# .to_target translit still aborts on a character with no ASCII fold

    Code
      artoo:::.to_target(x, "US-ASCII", "translit")
    Condition
      Error:
      ! Cannot encode 1 value to "US-ASCII" even after punctuation folding.
      x Offending value: "Öztürk".
      i Only smart punctuation has an ASCII fold; use `on_invalid = "fold"` to also strip accents, or write to Dataset-JSON (UTF-8).

# .to_target fold aborts on a character with no standard ASCII fold

    Code
      artoo:::.to_target(x, "US-ASCII", "fold")
    Condition
      Error:
      ! Cannot encode 1 value to "US-ASCII" even after ASCII folding.
      x Offending value: "costs €100".
      i The character has no standards-backed ASCII fold (ICU Latin-ASCII leaves it unmapped); write to Dataset-JSON (UTF-8), or set `on_invalid`.

