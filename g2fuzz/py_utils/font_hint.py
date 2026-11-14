"""ALFRED (G2F_FONT_HINT=1, 2026-11-13): a note on the real fontTools API, added to the prompts that ask the LLM to
write or extend a generator for a font format. Off (unset or 0): every prompt is unchanged.

Why: in A00's seed generation for freetype2_ftfuzzer (gpt-oss-20b, fontTools 4.65.0), all 122 generators that used
fontTools failed, 213 of the 254 failed runs with fontTools names that don't exist; the 40 generators that were kept
pack a few tables by hand with struct, and in the fuzzing runs their mutations fail on struct.error. The names in
HINT are the ones those logs show; the skeleton was run against fontTools 4.65.0. No dependencies, so the tests can
import it without the openai package.
"""
import os

FONT_FORMATS = ("ttf", "otf", "woff", "woff2")

HINT = """
Notes on writing font files in Python (the fontTools library, checked against version 4.65):
- Build the font with `fontTools.fontBuilder.FontBuilder`. Do not pack the tables by hand with `struct`, and do not fill an empty `TTFont()` table by table. This skeleton runs as it is:
```
import os
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.DefaultTable import DefaultTable

os.makedirs("./tmp", exist_ok=True)
fb = FontBuilder(unitsPerEm=1000, isTTF=True)   # it has no other arguments (no isBold, isItalic, isFixedPitch, isVariable)
fb.setupGlyphOrder([".notdef", "A"])            # first: every glyph name
fb.setupCharacterMap({0x41: "A"})               # the cmap table: code point -> glyph name
pen = TTGlyphPen(None)
pen.moveTo((100, 0)); pen.lineTo((300, 700)); pen.lineTo((500, 0)); pen.closePath()
fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "A": pen.glyph()})   # glyf, loca and maxp
fb.setupHorizontalMetrics({".notdef": (500, 0), "A": (600, 100)})       # hmtx: glyph name -> (advance, left side bearing)
fb.setupHorizontalHeader(ascent=800, descent=-200)                      # hhea
fb.setupNameTable({"familyName": "Test", "styleName": "Regular"})       # name
fb.setupOS2()
fb.setupPost()
font = fb.font                                   # the TTFont: change or add tables here, before saving
font["OS/2"].fsType = 8                          # a table's fields are attributes of font[tag]
font["name"].setName("more text", 5, 3, 1, 0x409)   # (string, nameID, platformID, platEncID, langID)
gasp = newTable("gasp"); gasp.version = 1; gasp.gaspRange = {8: 2, 65535: 15}; font["gasp"] = gasp
raw = DefaultTable("zzzz"); raw.data = b"\\x00\\x01\\x02\\x03"; font["zzzz"] = raw   # a table of any tag from raw bytes
fb.addOpenTypeFeatures("feature kern { pos A A -50; } kern;")           # GSUB/GPOS from feature-file text
fb.save("./tmp/font.ttf")                        # save takes only the path; for WOFF set font.flavor = "woff" or "woff2" first
```
- Table tags have exactly 4 characters: "OS/2", "cvt ", "CFF ".
- These do not exist, so do not use them: `FontBuilder` in `fontTools.varLib.builder` or `fontTools.feaLib.builder`; `FontBuilder.setupName`, `.setupHmtx`, `.addGlyph`; `TTFont.newTable`; `cmap.newSubtable`; `name.NameRecord`, `NameRecord(...)` with arguments; `CmapTable`, `CmapSubtableFormat4`, `GlyfTable`, `GlyphSet`, `HmtxTable`, `HeadTable`; modules such as `fontTools.ttLib.tables._cmap`, `._head`, `._glyf`, `._o_s_2`; `otTables.NameRecord`, `otTables.OS_2`.
"""


def font_hint(file_format):
    """HINT if G2F_FONT_HINT=1 and file_format is a font format, else ''."""
    if os.environ.get("G2F_FONT_HINT", "0") == "1" and str(file_format).lower() in FONT_FORMATS:
        return HINT
    return ""


def with_font_hint(prompt, file_format):
    """prompt, with the hint after it when font_hint() gives one; otherwise the same prompt."""
    return prompt + font_hint(file_format)
