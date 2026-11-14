# Kill la Kill The Game - IF (0100A3F00C536000): the rewriter's patches of this game's own builds. dm/tools/patch_nso.py loads every profile's patches.py;
# MATCH_FRAME_STEP as described there ("Registered patches")
from nso_asm import ADRP, B, BL

# Render size. The game keeps its view sizes in a table of 0x30-byte entries; entry 0 is the 3D view, written only by one leaf function (1.0.0 main+0x7dab0, 0x54 bytes:
# setter(index w0, float size[2] at x1, alignment w2): +0x48 the size as given, +0x50 / +0x54 each side rounded up to the alignment). Its two callers (start-up, main+0x5be2c, and
# the console-mode change, main+0x5c960) both pass index 0 and alignment 8, with the size of the console mode (1920x1080 docked, 1280x720 handheld), the second one times the
# game's own scale (1.0, state +0x9178). The 2D layer and the HUD use the display size, not this entry, so they stay at full resolution.
# The stub runs the setter with the size times the host's render scale (state +0x10, DM_RENDER_SCALE, written by the loader), each side rounded to a multiple of 8 so the size as
# given and the aligned one stay equal, as for the game's own sizes (0.5 docked: 960x544, 67.5 eighths rounding to 68; 0.75: 1440x808; 1.5: 2880x1624; 2.0: 3840x2160).
# 1.0, NaN, nothing written, or another index: the original setter (the loader clamps the scale to 0.5..2.0). It writes x8-x11 as the setter does, and x16, x17, v16-v19 (free at a call: the setter is a leaf).
# Found by its fingerprint (the whole function, addresses masked), so a build with the same setter elsewhere in its main (another region of 1.0.0) gets it too.
def render_size(ctx):
    here, emit = ctx.here, ctx.emit
    setter = ctx.base
    table = ctx.address(setter)   # adrp x8 / add x8,#lo: the view size table
    ctx.site(setter, ADRP(8, setter, table).to_bytes(4, 'little').hex())   # the setter's adrp x8 (its page is the build's)
    start = here(); emit(ADRP(16, here(), ctx.state))
    for w in (0xbd401210,   # ldr s16,[x16,#0x10]       render scale
              0x1e2e1011,   # fmov s17,#1.0
              0x1e312200,   # fcmp s16,s17
              0x54000400,   # b.eq orig                 1.0: the game's size
              0x1e202208,   # fcmp s16,#0.0
              0x540003cd,   # b.le orig                 none written (or NaN)
              0x350003a0,   # cbnz w0,orig              not the 3D view
              0x2d404831,   # ldp s17,s18,[x1]          the size given
              0x1e300a31,   # fmul s17,s17,s16
              0x1e300a52,   # fmul s18,s18,s16
              0x1e281013,   # fmov s19,#0.125
              0x1e330a31,   # fmul s17,s17,s19
              0x1e330a52,   # fmul s18,s18,s19
              0x1e200230,   # fcvtns w16,s17            width / 8
              0x1e200251,   # fcvtns w17,s18            height / 8
              0x531d7210,   # lsl w16,w16,#3
              0x531d7231,   # lsl w17,w17,#3
              0x1e230211,   # ucvtf s17,w16
              0x1e230232):  # ucvtf s18,w17
        emit(w)
    emit(ADRP(8, here(), table)); emit(0x91000108 | (table & 0xfff) << 10)   # adrp x8,table; add x8,x8,#lo
    for w in (0x52800609,   # mov w9,#0x30
              0x9ba92008,   # umaddl x8,w0,w9,x8        the entry
              0x2d094911,   # stp s17,s18,[x8,#0x48]    the size as given
              0x5100044a,   # sub w10,w2,#1
              0x4b0203eb,   # neg w11,w2
              0x0b100149,   # add w9,w10,w16
              0x0a0b0129,   # and w9,w9,w11
              0x1e230120,   # ucvtf s0,w9
              0xbd005100,   # str s0,[x8,#0x50]         width aligned
              0x0b110149,   # add w9,w10,w17
              0x0a0b0129,   # and w9,w9,w11
              0x1e230120,   # ucvtf s0,w9
              0xbd005500,   # str s0,[x8,#0x54]         height aligned
              0xd65f03c0):  # ret
        emit(w)
    assert here() - start == 0x90, 'render size stub: orig must follow at +0x90 (the b.ge / b.le / cbnz offsets)'
    emit(ADRP(8, here(), table)); emit(B(here(), setter + 4))   # orig: the setter's adrp x8, then its add and the rest
    ctx.put(setter, [B(setter, start)], 'render size: the 3D view\'s size times the host\'s render scale (state +0x10; 1.0 = the game\'s 1920x1080 / 1280x720)')
    ctx.render_scale = 2   # the largest scale the stub takes (the loader keeps 0.5 to 2.0: 3840x2160 docked, 2560x1440 handheld)
    # The screen fade (1.0.0 main+0x16f750; menus, intro logos and movies fade through it) draws a rectangle from (0, 0) the size of entry 0's +0x40, the docked display size
    # (1920x1080, the getter at setter+0x80), which its drawing code (main+0x5b0c0) turns into clip space by the render size (entry 0's +0x48): above 1.0 it covered only the
    # top-left 1/scale of the frame (a darker box over the menus; 1.30: 1920x1080 of 2496x1408). It takes entry 0's +0x48 instead (the getter at setter+0xe0): the render size,
    # equal to the display size at 1.0 docked, and the handheld size in handheld mode (where the 1920x1080 rectangle also covered the whole 1280x720 frame)
    fade = ctx.others.get('fade')
    if fade is not None:
        getter_size = setter + 0xe0
        ctx.site(getter_size + 8, 'e9071c320820a99b00210191c0035fd6')   # mov w9,#0x30; umaddl x8,w0,w9,x8; add x0,x8,#0x48; ret
        ctx.site(fade + 0x70, 'e0031f2aff0700f9' + BL(fade + 0x78, setter + 0x80).to_bytes(4, 'little').hex())   # mov w0,wzr; str xzr,[sp,#8]; bl display size
        ctx.put(fade + 0x78, [BL(fade + 0x78, getter_size)], 'screen fade: the render size, not the display size (the fade covers the whole frame at any render scale)')


MATCH_FRAME_STEP = {'main': [
    {'name': 'render size from the host\'s render scale', 'size': 0x54,
     'fingerprints': ['e7b52048a0723e9e66f08ce80ec6f3db70c89a230f9b946c466892a69735ce88'],   # 1.0.0 (JP 0100A3F00C536000) main+0x7dab0
     'others': {'fade': {'size': 0xac, 'fingerprints': ['746a663af4becd3abcb537afcab6346b201e94f268ca4ff431575be0beee7c1c']}},   # 1.0.0 main+0x16f750, the screen fade
     'stub': render_size},
]}

BINDING = [
    {'what': 'render size: the 3D view\'s size times the host\'s render scale', 'now': 'game', 'goal': 'game', 'purpose': 'rendering',
     'why': "the game's own view-size setter, found by its fingerprint (addresses masked), so any build of the game with the same setter gets it",
     'checked': '1.0.0 JP main: one function of the fingerprint, its two callers pass index 0 and alignment 8 (2026-11-13)'},
    {'what': 'screen fade: sized by the render size, not the display size', 'now': 'game', 'goal': 'game', 'purpose': 'rendering',
     'why': "the game's fade rectangle (main+0x16f750) takes the display size and its drawing code divides by the render size: above render scale 1.0 it covered only the top-left 1/scale of the frame",
     'checked': '1.0.0 JP main: fade fingerprint unique; Mac at 1.30: intro logo fades and the title-to-menu fade cover the whole frame (2026-11-14)'},
]
