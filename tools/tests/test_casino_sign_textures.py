# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Recognisable names and mascot details must survive the switch to night."""
import numpy as np
from PIL import Image

from tools.prepare_casino_sign_textures import light_map, ROOT


def emitted(code):
    art=Image.open(ROOT/f'game/assets/desert-dreams-3d/{code}-blender_{code}-color.png').convert('RGBA')
    return np.asarray(art)/255,np.asarray(light_map(art,code)).max(axis=2)/255


def test_silver_lights_filled_letters_in_both_words():
    art,light=emitted(252)
    r,g,b=art[:,:,:3].transpose(2,0,1)
    for x0,x1 in [(235,327),(340,378),(389,483),(480,580),(583,678),(691,784)]:
        # Filled silver enamel in each SILVER letter, rather than its edge only.
        region=(r[220:285,x0:x1]>.48)&(r[220:285,x0:x1]>g[220:285,x0:x1]*1.05)&(b[220:285,x0:x1]>.30)
        assert region.sum()>20
        assert (light[220:285,x0:x1][region]>.50).mean()>.80
    for x0,x1 in [(148,215),(225,316),(327,414),(423,508),(513,592),(604,630),(639,729),(740,841)]:
        region=(g[360:430,x0:x1]>r[360:430,x0:x1]*1.35)&(g[360:430,x0:x1]>b[360:430,x0:x1]*1.05)
        assert region.sum()>20
        assert (light[360:430,x0:x1][region]>.50).mean()>.90
    assert light[347,442]<.05 # pale inset beside the C, not a lit rectangle


def test_alibi_lights_every_letter_and_hyphen_on_the_upper_ribbon():
    art,light=emitted(257)
    r,g,b=art[:,:,:3].transpose(2,0,1)
    for x0,x1,y0,y1 in [(310,360,150,216),(364,394,140,205),(398,455,130,196),(460,494,150,168),(500,560,125,180),(561,612,120,177),(615,663,122,176),(666,721,123,177),(723,783,127,181)]:
        region=(r[y0:y1,x0:x1]>g[y0:y1,x0:x1]*1.5)&(g[y0:y1,x0:x1]<.28)
        assert region.sum()>10
        assert (light[y0:y1,x0:x1][region]>.50).mean()>.85
    assert light[137,480]<.05 # mint ribbon above the hyphen
    assert light[192,560]<.05 # ribbon below the lettering
    assert light[275,185]<.1 # burgundy cabinet remains dark


def test_woolier_sheep_outline_eyes_nose_and_smile_emit_without_flooding_wool():
    _,light=emitted(263)
    # Landmarks on the animal silhouette, both eyes, nose and smiling mouth.
    for x,y in [(342,178),(405,82),(555,29),(647,75),(649,187),
                (544,80),(594,74),(578,105),(580,121)]:
        assert light[y-3:y+4,x-3:x+4].max()>.5,(x,y)
    assert light[130,430]<.05 # unlit wool within the body
    assert light[130,275]<.05 # enamel outside the sheep


def test_runtime_textures_contain_the_authored_name_and_mascot_lighting():
    for code in (252,257,263):
        art=Image.open(ROOT/f'game/assets/desert-dreams-3d/{code}-blender_{code}-color.png').convert('RGBA')
        shipped=Image.open(ROOT/f'game/assets/desert-dreams-3d/{code}-blender_{code}-light.png').convert('RGB')
        np.testing.assert_array_equal(np.asarray(shipped),np.asarray(light_map(art,code)))


def test_sheep_right_ear_follows_the_painted_droop_without_an_extra_loop():
    _,light=emitted(263)
    assert light[70:78,646:653].max()>.5 # outer tip in the original art
    assert light[66:72,616:627].max()>.5 # short inner fold
    assert light[69:79,657:666].max()<.05 # no oversized ear beyond the painting
    assert light[78:80,618:625].max()<.05 # no second closed ear loop
