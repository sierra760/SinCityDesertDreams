# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fix_mirrored_textures import read_glb
from split_model_palms import triangle_count

ROOT = Path(__file__).resolve().parents[2]

class MayorHouseModelTests(unittest.TestCase):
    def test_ground_level_slots_are_authored_and_model_stays_in_budget(self):
        doc, binary = read_glb((ROOT/'game/assets/desert-dreams-3d/243-blender.glb').read_bytes())
        self.assertLessEqual((ROOT/'game/assets/desert-dreams-3d/243-blender.glb').stat().st_size,337928)
        names = {node.get('name'): node for node in doc['nodes']}
        for name in ['MayorWalkStart','MayorParking_car','MayorParking_police','MayorParking_fire_engine','MayorHelipad'] + [f'MayorTree_{i:02d}' for i in range(6)]:
            self.assertIn(name, names, 'ground-level motor court markers must be authored')
            self.assertAlmostEqual(names[name]['translation'][1], .21, places=3)
        self.assertLessEqual(triangle_count(doc, binary), 4874)
        self.assertEqual(len(doc['materials']),19)
        self.assertEqual(len(doc.get('images',[])),2)
        self.assertTrue(all('uri' in image for image in doc['images']))


class MayorNightFinishTests(unittest.TestCase):
    def test_cream_stone_and_painted_lines_are_not_named_as_neon(self):
        doc, _ = read_glb((ROOT/'game/assets/desert-dreams-3d/243-blender.glb').read_bytes())
        self.assertNotIn('warm_light', {m['name'] for m in doc['materials']}, 'stone and paint must stay dark under the shared night roles')

class MayorClearanceTests(unittest.TestCase):
    def test_measured_vehicle_and_rotor_envelopes_clear_the_real_house_collision(self):
        import numpy as np
        from split_model_palms import parts_of
        doc, binary = read_glb((ROOT/'game/assets/desert-dreams-3d/243-blender.glb').read_bytes())
        obstacles=[p for p in parts_of(doc,binary) if p['collision'] and p['hi'][1]>.5]
        # Literal measured envelopes, independent of the layout builder.
        slots=[((2.2,4.8),(2.041,1.509,4.752)),((6.6,4.8),(2.139,1.734,4.955)),
               ((11.4,4.8),(2.679,3.179,8.206)),((-7.5,6),(8,100,8.77))]
        for (x,z),(w,h,d) in slots:
            lo=np.array([x-w/2,.21,z-d/2]);hi=lo+np.array([w,h,d])
            self.assertGreater(lo[0],-14.8);self.assertLess(hi[0],14.8)
            self.assertGreater(lo[2],-.7);self.assertLess(hi[2],16)
            for p in obstacles:
                self.assertFalse(np.all(hi>p['lo']) and np.all(lo<p['hi']),
                                 f'vehicle/takeoff prism intersects house: {(x,z)} {p["material"]}')

if __name__ == '__main__': unittest.main()
