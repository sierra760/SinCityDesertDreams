# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

from tools.model_art.contracts import validate_model

def model():
    return dict(kind='pedestrian', tier='near', triangles=13000, materials=12,
                units='meters', meters_per_tile=16, source_forward='+Y', source_up='+Z',
                godot_forward='-Z', godot_up='+Y', origin='feet',
                size_m=[.6,1.8,.6], envelope_m=[.7,1.9,.7],
                motion={'wheel_radius_m': .44, 'wheel_axis': 'X'})

def test_valid_model():
    assert validate_model(model()) == []

def test_wrong_scale_caps_and_envelope():
    for key, value in [('meters_per_tile', 1), ('triangles',13001), ('materials',13),
                       ('units','tiles'), ('size_m',[1,2,1])]:
        entry=model();entry[key]=value
        assert validate_model(entry), key

def test_nan_and_unknown_motion_axes():
    for motion in [{'wheel_radius_m':float('nan')}, {'wheel_axis':'Q'}]:
        entry=model();entry['motion']=motion
        assert validate_model(entry)

def test_middle_far_budgets():
    for tier, cap in [('middle',3500),('far',1500)]:
        entry=model();entry.update(tier=tier,triangles=cap,materials=6)
        assert validate_model(entry)==[]
        entry['triangles']+=1
        assert validate_model(entry)

def test_road_and_large_caps():
    for kind, origin, caps in [('car','contact',(16000,6000,2000)),
                                ('ship','waterline',(24000,8000,3000))]:
        for tier, cap in zip(('near','middle','far'),caps):
            entry=model();entry.update(kind=kind,origin=origin,tier=tier,triangles=cap,materials=6)
            assert validate_model(entry)==[]
            entry['triangles']=cap+1
            assert validate_model(entry)

def test_nested_motion_and_conversion_axes():
    entry=model();entry['motion']={'rotors':[{'axis':'Q','radians_per_second':float('nan')}]}
    assert validate_model(entry)
    entry=model();entry['source_forward']='-Z'
    assert validate_model(entry)
