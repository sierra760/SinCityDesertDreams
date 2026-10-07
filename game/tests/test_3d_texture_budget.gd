# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const TEXTURES: Array[String] = [
	"res://assets/desert-dreams-3d/textures/desert-sand.png",
	"res://assets/desert-dreams-3d/textures/desert-rock.png",
	"res://assets/desert-dreams-3d/textures/road-grain.png",
]

func test_3d_surface_textures_use_compression_and_full_mipmaps() -> void:
	for path: String in TEXTURES:
		var config := ConfigFile.new()
		check_eq(config.load(path+".import"),OK,path+" import settings load")
		check_eq(config.get_value("params","compress/mode"),2,path+" uses GPU compression")
		check_eq(config.get_value("params","compress/high_quality"),true,path+" retains high quality")
		check_eq(config.get_value("params","mipmaps/generate"),true,path+" has distant sampling mipmaps")
		check_eq(config.get_value("params","process/size_limit"),0,path+" keeps authored resolution")
		check_eq(config.get_value("params","process/normal_map_invert_y"),false,path+" preserves authored orientation")
		check_eq(config.get_value("params","compress/normal_map"),0,path+" is an albedo texture, not a normal map")

func test_imported_surface_textures_retain_resolution_with_bounded_storage() -> void:
	var compressed_bytes := 0
	var raw_bytes := 0
	for path: String in TEXTURES:
		var texture := load(path) as Texture2D
		check(texture != null,path+" loads")
		if texture == null: continue
		var authored := Image.load_from_file(ProjectSettings.globalize_path(path))
		var image := texture.get_image()
		check(image != null and not image.is_empty(),path+" imported image available")
		if image == null or image.is_empty(): continue
		check_eq(Vector2i(texture.get_width(),texture.get_height()),authored.get_size(),path+" preserves source dimensions")
		var blocks := Vector2i(ceili(authored.get_width()/4.0)*4,ceili(authored.get_height()/4.0)*4)
		check_eq(image.get_size(),blocks,path+" storage uses exact 4x4 block alignment")
		check(image.has_mipmaps(),path+" imports actual mip levels")
		check(image.is_compressed(),path+" remains GPU compressed")
		compressed_bytes += image.get_data_size()
		raw_bytes += authored.get_width()*authored.get_height()*3
	check_lt(compressed_bytes,raw_bytes*.55,"six 3D textures consume less than 55% of unmipmapped RGB storage")
