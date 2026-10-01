# Token contrast (WCAG 2.x)

Computed from the hex values in `Design/Tokens.swift` by the same formulas as `KohaiColor.contrast(against:)`.
Backdrops are STAND-INS for the system material: `materialNominal` (typical dark material) and
`materialLifted` (worst case: bright wallpaper lifting the material). The real material is dynamic, so
the manual pass at min/max Liquid Glass transparency in the final report is still required.

Text must be >= 4.5:1. Seal fills are non-text graphics (>= 3:1); the glyph on a seal is text (>= 4.5:1).

| Palette | Token | Foreground | Against | Background | Ratio | Required | Pass |
|---|---|---|---|---|---|---|---|
| dark | text.primary | #F1EEE7 | materialNominal | #262628 | 13.04:1 | 4.5:1 | yes |
| dark | text.secondary | #CBC7BD | materialNominal | #262628 | 8.95:1 | 4.5:1 | yes |
| dark | text.tertiary | #B9B5AB | materialNominal | #262628 | 7.38:1 | 4.5:1 | yes |
| dark | seal.needsInput (non-text) | #EE6048 | materialNominal | #262628 | 4.60:1 | 3.0:1 | yes |
| dark | seal.done (non-text) | #A19E97 | materialNominal | #262628 | 5.65:1 | 3.0:1 | yes |
| dark | text.primary | #F1EEE7 | materialLifted | #3C3C3E | 9.50:1 | 4.5:1 | yes |
| dark | text.secondary | #CBC7BD | materialLifted | #3C3C3E | 6.52:1 | 4.5:1 | yes |
| dark | text.tertiary | #B9B5AB | materialLifted | #3C3C3E | 5.38:1 | 4.5:1 | yes |
| dark | seal.needsInput (non-text) | #EE6048 | materialLifted | #3C3C3E | 3.36:1 | 3.0:1 | yes |
| dark | seal.done (non-text) | #A19E97 | materialLifted | #3C3C3E | 4.12:1 | 3.0:1 | yes |
| dark | onSeal glyph on seal.needsInput | #1A1613 | seal.needsInput | #EE6048 | 5.48:1 | 4.5:1 | yes |
| dark | onSeal glyph on seal.done | #1A1613 | seal.done | #A19E97 | 6.72:1 | 4.5:1 | yes |
| darkIncreasedContrast | text.primary | #FAF8F3 | materialNominal | #262628 | 14.23:1 | 4.5:1 | yes |
| darkIncreasedContrast | text.secondary | #E4E0D7 | materialNominal | #262628 | 11.47:1 | 4.5:1 | yes |
| darkIncreasedContrast | text.tertiary | #D2CEC4 | materialNominal | #262628 | 9.61:1 | 4.5:1 | yes |
| darkIncreasedContrast | seal.needsInput (non-text) | #F2705A | materialNominal | #262628 | 5.21:1 | 3.0:1 | yes |
| darkIncreasedContrast | seal.done (non-text) | #B4B1AA | materialNominal | #262628 | 7.06:1 | 3.0:1 | yes |
| darkIncreasedContrast | text.primary | #FAF8F3 | materialLifted | #3C3C3E | 10.37:1 | 4.5:1 | yes |
| darkIncreasedContrast | text.secondary | #E4E0D7 | materialLifted | #3C3C3E | 8.36:1 | 4.5:1 | yes |
| darkIncreasedContrast | text.tertiary | #D2CEC4 | materialLifted | #3C3C3E | 7.01:1 | 4.5:1 | yes |
| darkIncreasedContrast | seal.needsInput (non-text) | #F2705A | materialLifted | #3C3C3E | 3.79:1 | 3.0:1 | yes |
| darkIncreasedContrast | seal.done (non-text) | #B4B1AA | materialLifted | #3C3C3E | 5.14:1 | 3.0:1 | yes |
| darkIncreasedContrast | onSeal glyph on seal.needsInput | #1A1613 | seal.needsInput | #F2705A | 6.20:1 | 4.5:1 | yes |
| darkIncreasedContrast | onSeal glyph on seal.done | #1A1613 | seal.done | #B4B1AA | 8.40:1 | 4.5:1 | yes |
