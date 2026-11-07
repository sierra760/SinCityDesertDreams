# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Signs are added without silently rebuilding the rest of the resort."""
import json
from io import BytesIO

import numpy as np
import pytest
from PIL import Image

from tools import casino_sign_models as signs
from tools.fix_mirrored_textures import read_glb, write_glb
from tools.split_model_palms import accessor_array
from tools.split_model_palms import world_transforms, parts_of


def fixture(name='building', material='wall', collision=False):
    positions = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], np.float32)
    indices = np.array([0, 1, 2], np.uint16)
    binary = bytearray(positions.tobytes() + indices.tobytes())
    doc = {'asset': {'version': '2.0'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
           'nodes': [{'name': name + ('-colonly' if collision else ''), 'mesh': 0}],
           'meshes': [{'primitives': [{'attributes': {'POSITION': 0}, 'indices': 1, 'material': 0}]}],
           'materials': [{'name': material}], 'bufferViews': [
               {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
               {'buffer': 0, 'byteOffset': 36, 'byteLength': 6}],
           'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3',
                          'min': [0, 0, 0], 'max': [1, 1, 0]},
                         {'bufferView': 1, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'}],
           'buffers': [{'byteLength': len(binary)}]}
    return write_glb(doc, binary)


def test_append_remaps_nodes_materials_accessors_and_preserves_base_bytes():
    base, binary = read_glb(fixture())
    output = signs.append_glb(fixture(), fixture('CasinoLogo', 'sign_logo_face'))
    doc, buf = read_glb(output)
    assert len(doc['nodes']) == 2 and len(doc['meshes']) == 2
    assert doc['meshes'][1]['primitives'][0]['material'] == 1
    assert doc['scenes'][0]['nodes'] == [0, 1]
    assert bytes(buf[:len(binary)]) == bytes(binary)
    for n in range(2):
        p = doc['meshes'][n]['primitives'][0]
        np.testing.assert_array_equal(accessor_array(doc, buf, p['attributes']['POSITION']),
                                      accessor_array(base, binary, 0))


def test_composition_removes_only_explicit_old_name_and_keeps_collision():
    base = signs.append_glb(fixture('Original name', 'lamp'), fixture('Shell', collision=True))
    spec = {'code': 251, 'old_mesh': 'Original name', 'old_triangles': 1}
    out, summary = signs.compose(base, fixture('CasinoLogo', 'sign_logo_face'), spec)
    doc, _ = read_glb(out)
    assert not any(n.get('name') == 'Original name' for n in doc['nodes'])
    assert any(n.get('name') == 'Shell-colonly' for n in doc['nodes'])
    assert summary['removed_triangles'] == 1
    assert summary['collision_sha256'] == signs.collision_hash(base) == signs.collision_hash(out)
    with pytest.raises(ValueError, match='already'):
        signs.compose(out, fixture('CasinoLogo', 'sign_logo_face'), spec)


def test_wrong_old_letter_count_refuses_to_modify_the_model():
    with pytest.raises(ValueError, match='expected'):
        signs.compose(fixture('Original name'), fixture('CasinoLogo'),
                      {'code': 251, 'old_mesh': 'Original name', 'old_triangles': 2})


def test_embedded_color_and_light_textures_are_remapped_without_touching_base_images():
    base,binary=read_glb(fixture())
    base['images']=[{'uri':'existing.png'}]
    base['textures']=[{'source':0,'sampler':0}]
    base['samplers']=[{'wrapS':10497,'wrapT':10497}]
    logo,buf=read_glb(fixture('CasinoLogo','sign_logo_letters'))
    image=BytesIO();Image.new('RGB',(1,1),'red').save(image,format='PNG');png=image.getvalue()
    while len(buf)%4:buf.append(0)
    logo['bufferViews'].append({'buffer':0,'byteOffset':len(buf),'byteLength':len(png)})
    buf.extend(png)
    logo['images']=[{'bufferView':2,'mimeType':'image/png'}]
    logo['samplers']=[{'wrapS':33071,'wrapT':33071}]
    logo['textures']=[{'source':0,'sampler':0}]
    logo['materials'][0].update(pbrMetallicRoughness={'baseColorTexture':{'index':0}},emissiveTexture={'index':0})
    output,raw=read_glb(signs.append_glb(write_glb(base,binary),write_glb(logo,buf)))
    assert output['images'][0]=={'uri':'existing.png'}
    assert output['textures'][1]=={'source':1,'sampler':1}
    material=output['materials'][1]
    assert material['pbrMetallicRoughness']['baseColorTexture']['index']==1
    assert material['emissiveTexture']['index']==1
    view=output['bufferViews'][output['images'][1]['bufferView']]
    assert raw[view['byteOffset']:view['byteOffset']+view['byteLength']]==png


def test_manifest_covers_fourteen_distinct_names_and_shapes():
    rows = signs.specifications()
    assert set(rows) == {251, 252, 253, 254, *range(256, 266)}
    assert len({r['name'] for r in rows.values()}) == 14
    assert len({r['shape'] for r in rows.values()}) == 14
    for row in rows.values():
        assert ''.join(row['lines']).replace('-', '').replace(' ', '').lower() == row['name'].replace('-', '').replace(' ', '').lower()


def test_finished_assets_preserve_collision_and_stay_inside_the_existing_budget():
    record = json.loads(signs.RECORD.read_text())
    assert len(record['models']) == 14
    for code, row in record['models'].items():
        data = (signs.ASSETS / f'{code}-blender.glb').read_bytes()
        doc, _ = read_glb(data)
        assert row['output_sha256'] == signs.sha(data)
        assert signs.collision_hash(data) == row['collision_sha256']
        assert row['triangles'] <= 40000
        assert row['sign_surfaces'] <= 8
        assert row['sign_triangles'] < 2500
        assert len(doc['images']) >= 2
        for channel in ('color','light'):
            texture=signs.ASSETS/f'{code}-blender_{code}-{channel}.png'
            assert Image.open(texture).size==(1024,512)
            settings=texture.with_suffix('.png.import').read_text()
            assert 'compress/mode=2' in settings and 'mipmaps/generate=true' in settings
            image=next(i for i in doc['images'] if i.get('name')==f'{code}-{channel}')
            view=doc['bufferViews'][image['bufferView']]
            _,binary=read_glb(data)
            embedded=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
            assert signs.sha(embedded)==signs.sha(texture.read_bytes())
        assert len([n for n in doc['nodes'] if n.get('name', '').startswith('CasinoLogo')]) > 0
        assert row['original_triangles'] - row['removed_triangles'] + row['sign_triangles'] == row['triangles']


def test_canopies_do_not_cross_the_six_freestanding_sign_cabinets():
    for code in range(256,262):
        spec=signs.specifications()[code]
        doc,buf=read_glb((signs.ASSETS/f'{code}-blender.glb').read_bytes())
        transforms=world_transforms(doc)
        cx,cy,cz=spec['center'];w,h=spec['width'],spec['height']
        for i,node in enumerate(doc['nodes']):
            if i not in transforms or 'mesh' not in node or node.get('name','').startswith('CasinoLogo') or node.get('name','').endswith('colonly'):continue
            for primitive in doc['meshes'][node['mesh']]['primitives']:
                a=accessor_array(doc,buf,primitive['attributes']['POSITION'])
                p=(np.c_[a,np.ones(len(a))]@transforms[i].T)[:,:3]
                triangles=accessor_array(doc,buf,primitive['indices']).ravel().reshape(-1,3)
                for triangle in p[triangles]:
                    lo,hi=triangle.min(0),triangle.max(0)
                    if hi[2]<=cz-.23:continue
                    intersects=lo[0]<cx+w*.50 and hi[0]>cx-w*.50 and lo[1]<cy+h*.50 and hi[1]>cy-h*.50
                    assert not intersects,f'{code}: {node.get("name")} crosses the sign cabinet'


def test_both_posts_reach_the_actual_irregular_cabinet_backing():
    for code,spec in signs.specifications().items():
        if spec.get('mount')!='posts':continue
        doc,buf=read_glb((signs.ASSETS/f'{code}-blender.glb').read_bytes())
        doc['scenes']=[{'nodes':[i for i,n in enumerate(doc['nodes']) if n.get('name','').startswith('CasinoLogo')]}]
        posts=[p for p in parts_of(doc,buf) if p['material']=='sign_logo_case']
        assert len(posts)==2
        image=Image.open(signs.ASSETS/f'{code}-blender_{code}-color.png').convert('RGBA')
        alpha=np.asarray(image)[:,:,3]
        for post in posts:
            x=(post['lo'][0]+post['hi'][0])/2
            u=(x-spec['center'][0])/spec['width']+.5
            column=min(alpha.shape[1]-1,max(0,round(u*(alpha.shape[1]-1))))
            pixels=np.flatnonzero(alpha[:,column]>160)
            assert len(pixels)>0
            bottom=spec['center'][1]+(.5-(pixels[-1]+.5)/alpha.shape[0])*spec['height']
            assert post['hi'][1]>=bottom+.035,f'{code}: post at {x:.2f} stops before the cabinet'
            assert post['lo'][1]<=spec['base']+.01
