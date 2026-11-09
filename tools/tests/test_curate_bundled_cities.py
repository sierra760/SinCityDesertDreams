# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
"""Offline curation contracts: continuous roads, authored names and intact lots."""
import base64
import copy
import zlib
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import curate_bundled_cities as curator


def link(a, b):
    a, b = sorted((a, b), key=lambda p: (p[1], p[0]))
    return f"{a[0]},{a[1]},open>{b[0]},{b[1]},open"


class StreetCurationTests(unittest.TestCase):
    def test_crossing_keeps_straight_streets_and_bends_continue(self):
        west, east = link((1, 2), (2, 2)), link((2, 2), (3, 2))
        north, south = link((2, 1), (2, 2)), link((2, 2), (2, 3))
        bend = link((3, 2), (3, 3))
        groups = curator.street_groups([west, east, north, south, bend])
        self.assertCountEqual([set(g) for g in groups], [{west, east, bend}, {north, south}])

    def test_border_changes_names_only_at_the_dam_line(self):
        links = [link((x, 3), (x + 1, 3)) for x in range(64, 70)]
        groups = curator.street_groups(links, border_x=67)
        self.assertCountEqual([set(g) for g in groups], [set(links[:3]), set(links[3:])])

    def test_tunnel_and_surface_channels_do_not_merge(self):
        surface = ['1,2,open>2,2,open', '2,2,open>3,2,open']
        bore = ['1,2,bore>2,2,bore', '2,2,bore>3,2,bore']
        self.assertCountEqual([set(g) for g in curator.street_groups(surface + bore)], [set(surface), set(bore)])

    def test_authored_names_are_preserved_and_extend_to_unnamed_connections(self):
        links = [link((x, 4), (x + 1, 4)) for x in range(1, 6)]
        metadata = {'schema': 1, 'next_street_id': 3, 'streets': {'1': 'Adaven Road', '2': 'School Canyon Road'},
                    'links': {links[0]: 1, links[-1]: 2}, 'station_auto': {}}
        result = curator.name_streets(links, metadata, {'roots': ['Sagebrush', 'Juniper'], 'primary': []})
        self.assertEqual(result['links'][links[0]], 1)
        self.assertEqual(result['links'][links[-1]], 2)
        self.assertEqual(result['streets'], metadata['streets'])
        self.assertEqual(set(result['links']), set(links))
        self.assertEqual(result['links'][links[1]], 1)
        self.assertEqual(result['links'][links[-2]], 2)

    def test_new_whole_street_is_one_identity_and_second_pass_is_identical(self):
        links = [link((x, 4), (x + 1, 4)) for x in range(1, 6)]
        empty = {'schema': 1, 'next_street_id': 1, 'streets': {}, 'links': {}, 'station_auto': {}}
        theme = {'roots': ['Sagebrush', 'Juniper'], 'primary': ['Basin Boulevard']}
        result = curator.name_streets(links, empty, theme)
        self.assertEqual(len(set(result['links'].values())), 1)
        self.assertEqual(set(result['streets'].values()), {'Basin Boulevard'})
        self.assertEqual(curator.name_streets(list(reversed(links)), result, theme), result)
        self.assertEqual(empty['links'], {}, 'caller input remains intact')

    def test_sonoran_and_arizona_streets_use_their_own_name_banks(self):
        links = [link((x, 4), (x + 1, 4)) for x in range(65, 69)]
        empty = {'schema': 1, 'next_street_id': 1, 'streets': {}, 'links': {}, 'station_auto': {}}
        theme = {'border_x': 67, 'sonora': {'primary': ['Avenida Sonora'], 'roots': ['Mezquite']},
                 'arizona': {'primary': ['Santa Cruz Road'], 'roots': ['Mesquite']}}
        result = curator.name_streets(links, empty, theme)
        self.assertEqual(result['streets'][str(result['links'][links[0]])], 'Avenida Sonora')
        self.assertEqual(result['streets'][str(result['links'][links[-1]])], 'Santa Cruz Road')

    def test_planned_grid_numbers_and_letters_follow_geographic_order(self):
        west = [link((10,y),(10,y+1)) for y in range(1,4)]
        east = [link((30,y),(30,y+1)) for y in range(1,10)]
        north = [link((x,40),(x+1,40)) for x in range(1,4)]
        south = [link((x,60),(x+1,60)) for x in range(1,10)]
        empty = {'schema':1,'next_street_id':1,'streets':{},'links':{},'station_auto':{}}
        result = curator.name_streets(west+east+north+south, empty, {'grid':True,'roots':['Sonoma'],'primary':[]})
        names = [result['streets'][str(result['links'][keys[0]])] for keys in [west,east,north,south]]
        self.assertEqual(names, ['1st Street','2nd Street','A Street','B Street'])

    def test_new_street_types_do_not_reuse_a_base_name(self):
        horizontal = [link((1,1),(2,1))]
        vertical = [link((10,1),(10,2))]
        empty = {'schema':1,'next_street_id':1,'streets':{},'links':{},'station_auto':{}}
        result = curator.name_streets(horizontal+vertical, empty, {'primary':[], 'roots':['Aliso','Doheny']})
        self.assertEqual({n.rsplit(' ',1)[0] for n in result['streets'].values()}, {'Aliso','Doheny'})

    def test_existing_suffix_duplicates_keep_main_identity_and_reuse_no_other_roots(self):
        main = [link((x,1),(x+1,1)) for x in range(1,5)]
        minor = [link((10,1),(10,2))]
        third = [link((20,1),(20,2))]
        metadata = {'schema':1,'next_street_id':4,'streets':{'1':'Aliso Drive','2':'Aliso Avenue','3':'Doheny Street'},
                    'links':{**{k:1 for k in main}, minor[0]:2, third[0]:3},'station_auto':{}}
        theme = {'primary':[], 'roots':['Aliso','Doheny','Toyon']}
        result = curator.name_streets(main+minor+third, metadata, theme)
        self.assertEqual(result['streets'], {'1':'Aliso Drive','2':'Toyon Avenue','3':'Doheny Street'})
        self.assertEqual(result['links'], metadata['links'])
        self.assertEqual(curator.name_streets(main+minor+third,result,theme), result)
        self.assertEqual(metadata['streets']['2'], 'Aliso Avenue', 'input is not mutated')

    def test_spanish_prefixes_and_english_suffixes_share_one_root_registry(self):
        west = [link((65,1),(66,1))]
        east = [link((70,1),(71,1))]
        metadata = {'schema':1,'next_street_id':3,'streets':{'1':'Avenida Nogales','2':'Nogales Street'},
                    'links':{west[0]:1,east[0]:2},'station_auto':{}}
        theme = {'border_x':67,'sonora':{'primary':['Avenida Nogales'],'spanish':True,'roots':['Nogales','Ímuris']},
                 'arizona':{'primary':[],'roots':['Nogales','Tubac']}}
        result = curator.name_streets(west+east,metadata,theme)
        self.assertEqual(result['streets'], {'1':'Avenida Nogales','2':'Tubac Street'})

    def test_base_names_ignore_accents_abbreviations_and_prefix_articles(self):
        variants = ['Calle Constitución','Avenida de la Constitución','Constitucion Rd.', 'Constitución Boulevard']
        for name in variants:
            self.assertEqual(curator.name_root(name), 'constitucion')



class ResortCurationTests(unittest.TestCase):
    def fixture(self, count):
        buildings = bytearray(16384)
        facilities, rewards, lots = {}, {}, []
        for n in range(count):
            x, y = 1 + (n % 6)*6, 1 + (n // 6)*6
            for dy in range(4):
                for dx in range(4): buildings[(y+dy)*128+x+dx] = 254
            anchor = f'{x},{y}'
            facilities[anchor] = {'key':'arcology_orbit','capacity':65000,'built_day':100,'condition':5,'residents':0}
            rewards[anchor] = {'capacity':65000,'built_year':2000,'condition':5}
            lots.append({'anchor':[x,y],'code':254,'key':'arcology_orbit','size':[4,4]})
        doc = {'version':1,'city':{'layers':{'building':base64.b64encode(zlib.compress(buildings)).decode()},
                   'facilities':facilities}, 'snapshot':{'systems':{'rewards':{'arcologies':rewards}}}}
        return doc, lots

    def test_replacements_keep_footprints_and_sync_facilities_and_snapshot(self):
        doc, lots = self.fixture(4)
        changes, curated = curator.diversify_resorts(doc, lots)
        self.assertEqual(len(changes), 3)
        self.assertEqual(len({row['code'] for row in curated}), 4)
        self.assertEqual(curated[0]['code'], 254, 'first original resort retained')
        codes = struct.unpack('<16384H', zlib.decompress(base64.b64decode(doc['city']['layers']['building'])))
        self.assertEqual(sum(c != 0 for c in codes), 64, 'same four occupied lots')
        for row in curated:
            x,y = row['anchor']; key = f'{x},{y}'
            self.assertEqual({codes[(y+dy)*128+x+dx] for dy in range(4) for dx in range(4)}, {row['code']})
            self.assertEqual(doc['city']['facilities'][key]['key'], row['key'])
            self.assertEqual(doc['city']['facilities'][key]['condition'], 5)
            self.assertEqual(doc['city']['facilities'][key]['capacity'], doc['snapshot']['systems']['rewards']['arcologies'][key]['capacity'])

    def test_thirteen_lots_exhaust_ten_designs_before_repeating(self):
        doc, lots = self.fixture(13)
        changes, curated = curator.diversify_resorts(doc, lots)
        self.assertEqual(len(changes), 11)
        self.assertEqual(len({row['code'] for row in curated}), 10)
        self.assertEqual(sum(row['code'] == 254 for row in curated), 2)
        self.assertLessEqual(max(sum(row['code'] == code for row in curated) for code in {r['code'] for r in curated}), 2)
        self.assertEqual(curator.diversify_resorts(doc, curated)[0], [], 'second pass stable')


if __name__ == '__main__':
    unittest.main()
