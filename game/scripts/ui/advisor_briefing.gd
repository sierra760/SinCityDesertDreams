# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

static func make(row: Dictionary, compact: bool, short: bool = false) -> VBoxContainer:
	var speaker: Dictionary = row.speaker
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UITheme.MARGIN)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", UITheme.MARGIN)
	var portrait := portrait_for(speaker, 72 if short else (96 if compact else 144))
	portrait.name = "AdvisorPortrait"
	heading.add_child(portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if short:
		identity.custom_minimum_size.x = 180
		identity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	identity.add_theme_constant_override("separation", 4)
	identity.add_child(wrapped(String(speaker.role), UITheme.FONT_HEADER if compact else UITheme.FONT_TITLE, UITheme.HEADER))
	identity.add_child(wrapped(String(speaker.name), UITheme.FONT_SMALL if compact else UITheme.FONT_BODY, UITheme.TEXT_PRIMARY))
	identity.add_child(wrapped(String(speaker.status), UITheme.FONT_SMALL if compact else UITheme.FONT_HEADER, mood_color(row.mood)))
	if not compact: identity.add_child(wrapped(String(speaker.scope), UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	heading.add_child(identity)
	body.add_child(heading)
	if compact and not short: body.add_child(wrapped(String(speaker.scope), UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	var quote := PanelContainer.new()
	var face := StyleBoxFlat.new()
	face.bg_color = UITheme.TITLE_BAR_DARK
	face.set_corner_radius_all(UITheme.CORNER)
	face.content_margin_left = UITheme.MARGIN
	face.content_margin_right = UITheme.MARGIN
	face.content_margin_top = UITheme.MARGIN
	face.content_margin_bottom = UITheme.MARGIN
	quote.add_theme_stylebox_override("panel", face)
	quote.add_child(wrapped("“%s”" % speaker.quip, UITheme.FONT_BODY, UITheme.TITLE_TEXT))
	quote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if short: heading.add_child(quote)
	else: body.add_child(quote)
	if row.issues.is_empty():
		var message := "No current recommendations for this department. Keep an eye on the next report."
		if row.mood == "neutral": message = "Some readings are still developing. Review the latest reports before making changes."
		elif row.attention: message = "The latest outcomes need attention. Review the department reports before choosing changes."
		body.add_child(wrapped(message, UITheme.FONT_BODY, UITheme.TEXT_PRIMARY))
	else:
		if not compact: body.add_child(wrapped("Recommendations", UITheme.FONT_HEADER, UITheme.HEADER))
		for issue: Dictionary in row.issues:
			var item := VBoxContainer.new()
			item.add_theme_constant_override("separation", 4)
			var urgent := bool(issue.get("urgent", false))
			item.add_child(wrapped(("Urgent · " if urgent else "") + String(issue.get("title", "")), UITheme.FONT_HEADER,
				UITheme.MONEY_NEGATIVE if urgent else UITheme.HEADER))
			item.add_child(wrapped(String(issue.get("text", "")), UITheme.FONT_BODY, UITheme.TEXT_PRIMARY))
			body.add_child(item)
			body.add_child(HSeparator.new())
	body.add_child(wrapped("Current city · latest readings" if compact else "Latest readings", UITheme.FONT_SMALL if compact else UITheme.FONT_HEADER, UITheme.HEADER))
	for fact: String in row.facts:
		body.add_child(wrapped(fact, UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	return body

static func portrait_for(speaker: Dictionary, edge: int) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.texture = load(String(speaker.portrait)) as Texture2D
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(edge,edge)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.accessibility_name = "%s, %s" % [speaker.name,speaker.status]
	return portrait

static func mood_color(mood: String) -> Color:
	if mood == "critical": return UITheme.MONEY_NEGATIVE
	if mood == "concerned": return UITheme.FOCUS
	if mood == "neutral": return UITheme.TEXT_MUTED
	return UITheme.MONEY_POSITIVE

static func wrapped(text: String, font_size: int, color: Color) -> Label:
	var label := UIFactory.make_label(text,font_size,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2.ZERO
	return label
