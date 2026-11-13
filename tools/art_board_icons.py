#!/usr/bin/env python3
"""Quest board main-story notice icons, native 16x16 pixels (stdlib only).

Run: python3 tools/art_board_icons.py
Writes 16x16 RGBA PNGs under assets/ui/board/:
  - story_torben.png       (HAMMERSCHLÄGE IM NORDEN)
  - story_spiegelhexe.png  (GRÜNES LICHT IM SÜDEN)
  - story_mornath.png      (SCHREI ÜBER DEN SÄULEN)
  - story_lake_witch.png   (AM WESTSEE BRENNT KEIN LICHT)
  - story_seal.png         (fallback sealed scroll)
"""
from gen_art import CLEAR, ROOT, hexc, outline_pass, write_png
from art_bush import check_icon

OUTLINE = hexc("1b1a2e")


def _from_grid(name: str, rows: list[str], pal: dict[str, tuple[int, int, int, int]]):
    assert len(rows) == 16 and all(len(r) == 16 for r in rows), f"{name}: must be 16x16"
    px = [[pal[ch] if ch != "." else CLEAR for ch in row] for row in rows]
    check_icon(name, px)
    return outline_pass(px, OUTLINE)


def icon_torben():
    """Diagonal smith's hammer striking iron ore/anvil corner with warm ember burst."""
    pal = {
        "I": hexc("dce4f7"),  # iron top-left specular
        "i": hexc("8b95b5"),  # iron lit face
        "s": hexc("535875"),  # iron mid-shadow
        "d": hexc("2c2a42"),  # iron deep cool shadow
        "W": hexc("b88962"),  # ashwood handle highlight
        "w": hexc("7d5646"),  # ashwood handle mid
        "u": hexc("493044"),  # ashwood handle shadow
        "E": hexc("fff2b8"),  # ember white-gold core
        "e": hexc("f4b448"),  # ember gold
        "o": hexc("d9682a"),  # ember orange
        "r": hexc("8f341e"),  # ember cinder
    }
    rows = [
        "................",
        "......IIi.......",
        ".....IIiss......",
        ".....Iissd......",
        "....iissd.......",
        ".....dWW........",
        "......wWu.......",
        "....e..wWu......",
        "...oEoo.wWud....",
        "....rEEiissd....",
        "....oEIssssdd...",
        "...iiIissssddd..",
        "..iisssdddddd...",
        "..ssdddddddd....",
        "...ddddddd......",
        "................",
    ]
    return _from_grid("story_torben", rows, pal)


def icon_spiegelhexe():
    """Crooked slate witch tower with perched raven silhouette and witch-green lantern window."""
    pal = {
        "S": hexc("a49ec4"),  # slate top-left edge
        "s": hexc("6d6691"),  # slate lit wall
        "m": hexc("433c63"),  # slate mid
        "d": hexc("26213d"),  # slate deep shadow
        "R": hexc("5e5587"),  # roof/raven highlight
        "r": hexc("3a3359"),  # roof/raven mid
        "k": hexc("221d38"),  # roof/raven deep
        "G": hexc("eaffc4"),  # witch-green core
        "g": hexc("a8ff6a"),  # witch-green glow
        "f": hexc("45a356"),  # witch-green bounce
        "v": hexc("1f5239"),  # green spill shadow
    }
    rows = [
        "................",
        ".......R........",
        "......RRr.......",
        "......Rrk.......",
        ".....RRrkk......",
        "....RRrkkk.Rk...",
        "...RRrrkkkkrrk..",
        "....SSmmdddrr...",
        ".....Sfgmdd.....",
        ".....SfGGd......",
        ".....mfggd......",
        ".....mvffd......",
        "....Ssmmmdd.....",
        "....ssmmmdd.....",
        "....mmddddd.....",
        "................",
    ]
    return _from_grid("story_spiegelhexe", rows, pal)


def icon_mornath():
    """Broken highland pillars beneath a riven dark-violet & gold sky-wing blade."""
    pal = {
        "P": hexc("d8d3eb"),  # pillar highlight
        "p": hexc("9b95b5"),  # pillar lit
        "m": hexc("625d7d"),  # pillar mid
        "d": hexc("35314d"),  # pillar shadow
        "V": hexc("e0c4ff"),  # wing edge light
        "v": hexc("9b5cff"),  # wing mid violet
        "u": hexc("5e359c"),  # wing deep violet
        "k": hexc("2e1b4f"),  # wing shadow
        "G": hexc("ffd98a"),  # gold crest light
        "g": hexc("c9983e"),  # gold crest mid
        "b": hexc("7a5622"),  # bronze shadow
    }
    rows = [
        "................",
        "...........VVv..",
        "..Vvv.....Vvvuk.",
        "..vVvu...Vvuuk..",
        "...vuuk.Vvuuk...",
        "....kGbGGgbu....",
        ".....Pppukb.....",
        "....Ppmd.k......",
        "....Pmdd..Pp....",
        "....Pmdd..Ppm...",
        "....Pmdd..pmd...",
        "....pmdd..mdd...",
        "...Ppmdd..mdd...",
        "..PPpmmmddmmdd..",
        "..ppmmmmdddddd..",
        "................",
    ]
    return _from_grid("story_mornath", rows, pal)


def icon_lake_witch():
    """Mossy standing ward-stone with carved ring above dark lake ripples and faint teal rune."""
    pal = {
        "S": hexc("a6b7d4"),  # stone top-left highlight
        "s": hexc("6e7b9c"),  # stone lit
        "m": hexc("444b69"),  # stone mid
        "d": hexc("25263f"),  # stone shadow
        "T": hexc("d6fff6"),  # teal rune glint
        "t": hexc("6ee8dc"),  # teal rune glow
        "c": hexc("2b8a8e"),  # teal dark ring
        "n": hexc("1c4754"),  # deep teal shadow
        "W": hexc("4c7da1"),  # water ripple light
        "w": hexc("2b496e"),  # water mid
        "b": hexc("1b2942"),  # deep water
    }
    rows = [
        "................",
        "......SSss......",
        ".....SSsmmd.....",
        ".....Ssmmdd.....",
        ".....Sctcmd.....",
        "....SctTTcmd....",
        "....Sctddcmd....",
        ".....sctcmd.....",
        ".....smccdd.....",
        ".....smmmdd.....",
        ".....smmmdd.....",
        "....Wsmmmddw....",
        "..WWwwcttcwwbb..",
        "...Wwwwwwwwbbb..",
        "....bbbbbbbbb...",
        "................",
    ]
    return _from_grid("story_lake_witch", rows, pal)


def icon_seal():
    """Rolled parchment notice stamped with a gold-rimmed crimson wax seal."""
    pal = {
        "P": hexc("f7edd9"),  # parchment bright
        "p": hexc("dfd0b8"),  # parchment mid
        "a": hexc("a8927e"),  # parchment shade
        "u": hexc("6e5a5c"),  # parchment deep shadow
        "R": hexc("d96277"),  # wax seal highlight
        "r": hexc("9e3550"),  # wax seal mid
        "k": hexc("5e1f38"),  # wax seal shadow
        "G": hexc("ffd98a"),  # gold cord highlight
        "g": hexc("d9b25f"),  # gold cord mid
        "b": hexc("8c6628"),  # gold cord shadow
    }
    rows = [
        "................",
        "....PPPPppa.....",
        "...Pppppppau....",
        "....ppppaaau....",
        "....PPPPppau....",
        "....Pppppppa....",
        "....PppgGbpa....",
        "....ppRRrgba....",
        "....ppRrkgba....",
        "....aakrkppa....",
        "....aappppaa....",
        "....aaapaaau....",
        "...PPPppaaau....",
        "...pppaaaauu....",
        "....uuuuuuu.....",
        "................",
    ]
    return _from_grid("story_seal", rows, pal)


def main() -> None:
    out_dir = ROOT / "ui" / "board"
    icons = {
        "story_torben.png": icon_torben,
        "story_spiegelhexe.png": icon_spiegelhexe,
        "story_mornath.png": icon_mornath,
        "story_lake_witch.png": icon_lake_witch,
        "story_seal.png": icon_seal,
    }
    for filename, fn in icons.items():
        write_png(out_dir / filename, 16, 16, fn())
    print(f"wrote {len(icons)} story board icons to {out_dir}")


if __name__ == "__main__":
    main()
