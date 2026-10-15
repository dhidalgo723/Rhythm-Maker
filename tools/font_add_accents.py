"""Crea una copia de la fuente del juego con las letras que le faltan para el
espanol: vocales con tilde, ñ, ü y algunos signos (•, —, …).

La fuente original no se toca. La copia se guarda junto a ella con el sufijo
" Acentos" y es la que carga el juego (GuiTheme.FONT_PATH).

La fuente esta dibujada en una rejilla de pixeles: cada letra mide 7x7 bloques
de 1303/7 unidades. Los acentos se dibujan con bloques de ese mismo tamano,
encima de la letra y separados por una fila vacia.

Uso:  python tools/font_add_accents.py ["Fonts/After Burner Neue.ttf"]
Necesita fonttools (pip install fonttools).
"""
import sys
from pathlib import Path

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "Fonts/After Burner Neue.ttf")
DST = SRC.with_name(SRC.stem + " Acentos" + SRC.suffix)

CAP = 1303          # altura de las letras en unidades
U = CAP / 7         # un bloque de la rejilla

# Acentos como listas de bloques (columna, fila), con la columna 0..6 sobre una
# letra de 7 de ancho y las filas contadas desde la base (la letra ocupa 0..6;
# la 7 se deja vacia).
ACUTE = [(3, 8), (4, 8), (4, 9), (5, 9)]
TILDE = [(0, 8), (1, 9), (2, 9), (3, 8), (4, 8), (5, 9), (6, 9)]
DIAERESIS = [(1, 8), (2, 8), (1, 9), (2, 9), (4, 8), (5, 8), (4, 9), (5, 9)]

ACCENTED = {
    "á": ("a", ACUTE), "é": ("e", ACUTE), "í": ("i", ACUTE), "ó": ("o", ACUTE), "ú": ("u", ACUTE),
    "Á": ("A", ACUTE), "É": ("E", ACUTE), "Í": ("I", ACUTE), "Ó": ("O", ACUTE), "Ú": ("U", ACUTE),
    "ñ": ("n", TILDE), "Ñ": ("N", TILDE),
    "ü": ("u", DIAERESIS), "Ü": ("U", DIAERESIS),
}


def block_rect(pen, x0, y0, x1, y1):
    """Rectangulo en sentido horario (contorno relleno en TrueType)."""
    x0, y0, x1, y1 = (round(v) for v in (x0, y0, x1, y1))
    pen.moveTo((x0, y0))
    pen.lineTo((x0, y1))
    pen.lineTo((x1, y1))
    pen.lineTo((x1, y0))
    pen.closePath()


def draw_blocks(pen, blocks, dx):
    for col, row in blocks:
        block_rect(pen, dx + col * U, row * U, dx + (col + 1) * U, (row + 1) * U)


def add_glyph(font, char, glyph, advance):
    name = "uni%04X" % ord(char)
    glyph.recalcBounds(font["glyf"])
    order = font.getGlyphOrder()
    if name not in order:
        font.setGlyphOrder(order + [name])
    font["glyf"][name] = glyph
    font["hmtx"][name] = (advance, glyph.xMin if glyph.numberOfContours else 0)
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap[ord(char)] = name


def main():
    font = TTFont(SRC)
    glyf = font["glyf"]
    cmap = font.getBestCmap()

    for char, (base_char, blocks) in ACCENTED.items():
        base = cmap[ord(base_char)]
        base_glyph = glyf[base]
        base_glyph.recalcBounds(glyf)
        # Centrar el acento sobre la letra, ajustado a la rejilla.
        center = (base_glyph.xMin + base_glyph.xMax) / 2
        dx = round((center - 3.5 * U) / U) * U
        pen = TTGlyphPen(glyf)
        base_glyph.draw(pen, glyf)
        draw_blocks(pen, blocks, dx)
        add_glyph(font, char, pen.glyph(), font["hmtx"][base][0])

    gap = font["hmtx"][cmap[ord(".")]][0] - 3 * U   # separacion tras un signo

    # • : cuadrado de 3x3 a media altura.
    pen = TTGlyphPen(glyf)
    block_rect(pen, 0, 2 * U, 3 * U, 5 * U)
    add_glyph(font, "•", pen.glyph(), round(3 * U + gap))

    # — : guion de 7 de ancho a la altura del guion normal.
    pen = TTGlyphPen(glyf)
    block_rect(pen, 0, 2 * U, 7 * U, 4 * U)
    add_glyph(font, "—", pen.glyph(), round(7 * U + gap))

    # … : tres puntos como el punto normal (3x2).
    pen = TTGlyphPen(glyf)
    step = 3 * U + gap
    for i in range(3):
        block_rect(pen, i * step, 0, i * step + 3 * U, 2 * U)
    add_glyph(font, "…", pen.glyph(), round(3 * step))

    font.save(DST)
    print("Guardada %s con %d letras nuevas" % (DST, len(ACCENTED) + 3))


if __name__ == "__main__":
    main()
