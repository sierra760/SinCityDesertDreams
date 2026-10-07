# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Full-screen credits for the real-world terrain data sources, read from the
## bundled notice file. Works offline: it needs no network, cache or browser.
class_name TerrainSourcesDialog
extends Control
signal closed
const NOTICE_PATH := "res://data/real_world_terrain_notices.txt"
var panel: PanelContainer
var notice_text: RichTextLabel
var done_button: Button

func _init() -> void:
 name="TerrainSourcesDialog"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 var shade := ColorRect.new()
 shade.color=Color(0,0,0,0.35)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 var chrome := UIFactory.make_window_chrome("Terrain data sources")
 panel=chrome.root
 panel.set_meta("preferred_size",Vector2(680,500))
 panel.set_anchors_preset(Control.PRESET_CENTER)
 panel.offset_left=-340; panel.offset_right=340
 panel.offset_top=-250; panel.offset_bottom=250
 add_child(panel)
 chrome.close_button.pressed.connect(close)
 var summary := UIFactory.make_label("Elevation: Mapzen / Joerd terrain providers\nWater: ESA WorldCover 2021 v200 · CC BY 4.0\nChooser map and place search: © OpenStreetMap contributors · ODbL")
 summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 chrome.body.add_child(summary)
 notice_text=RichTextLabel.new()
 notice_text.name="SourceNotice"
 notice_text.bbcode_enabled=false
 notice_text.selection_enabled=true
 notice_text.fit_content=true
 notice_text.scroll_active=false
 notice_text.focus_mode=Control.FOCUS_ALL
 notice_text.custom_minimum_size.y=100
 notice_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 notice_text.add_theme_color_override("default_color",UITheme.TEXT_PRIMARY)
 notice_text.text=FileAccess.get_file_as_string(NOTICE_PATH)
 chrome.body.add_child(notice_text)
 chrome.body_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 # Focus the viewport for keyboard scrolling, not the taller selectable text.
 chrome.body_scroll.focus_mode=Control.FOCUS_ALL
 chrome.body_scroll.follow_focus=false
 chrome.body_scroll.gui_input.connect(_scroll_key)
 done_button=UIFactory.make_button("Done")
 chrome.actions.add_child(done_button)
 done_button.pressed.connect(close)
 WindowDrag.enable(chrome.title_bar,panel)
 resized.connect(func() -> void: apply_layout(size.x<700))
 visible=false

func _scroll_key(event: InputEvent) -> void:
 var scroll: ScrollContainer=panel.get_meta("window_chrome").body_scroll
 if not scroll.has_focus() or not event is InputEventKey or not event.pressed: return
 if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
 var page := maxi(1,int(scroll.size.y)-32)
 match event.keycode:
  KEY_PAGEDOWN: scroll.scroll_vertical+=page
  KEY_PAGEUP: scroll.scroll_vertical-=page
  KEY_DOWN: scroll.scroll_vertical+=32
  KEY_UP: scroll.scroll_vertical-=32
  KEY_HOME: scroll.scroll_vertical=0
  KEY_END: scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
  _: return
 scroll.accept_event()

func open() -> void:
 visible=true
 (panel.get_meta("window_chrome").body_scroll as ScrollContainer).scroll_vertical=0
 UIFactory.contain_modal_focus(self,panel.get_meta("window_chrome").body_scroll)
 apply_layout(size.x<700)

func close() -> void:
 if not visible: return
 visible=false
 closed.emit()

func apply_layout(_compact: bool) -> void:
 panel._schedule_fit()
