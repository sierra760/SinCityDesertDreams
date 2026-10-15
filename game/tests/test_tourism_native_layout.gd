# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
func before_each() -> void:
 host=Fixture.make_host(self,"tourism-native-layout")
func after_each() -> void:
 host.free()
 await process_frame
func test_small_phone_tourism_legend_fits_actual_plot() -> void:
 root.size=Vector2i(320,568)
 host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,320,548),0)
 var graphs := host.open_window("graphs") as GraphsWindow
 await Fixture.settle(self,8)
 var canvas := graphs._canvas
 check(canvas.has_method("legend_text"),"drawn legend has a bounded compact label")
 if not canvas.has_method("legend_text"): return
 var available := canvas.plot_rect().size.x-26.0
 for key in [&"tourists",&"tourist_occupancy",&"taxes_occupancy",&"taxes_gaming"]:
  var label := String(canvas.call("legend_text",key,GraphsWindow.SERIES_LABELS[key]))
  check(canvas.get_theme_default_font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,UITheme.FONT_SMALL).x<=available,"legend text fits plot: "+label)
  check(not label.is_empty())
  if key==&"tourist_occupancy": check(label.contains("%"))
  if key in [&"taxes_occupancy",&"taxes_gaming"]: check(label.contains("$") and label.contains("tax"))
  check_eq(graphs._series_boxes[key].text,GraphsWindow.SERIES_LABELS[key],"picker retains full explicit label")
func test_small_phone_endpoint_values_do_not_overlap() -> void:
 root.size=Vector2i(320,568)
 host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,320,548),0)
 var graphs := host.open_window("graphs") as GraphsWindow
 await Fixture.settle(self,8)
 var canvas := graphs._canvas
 var rows: Array[Dictionary] = []
 var names := [&"tourists",&"tourist_occupancy",&"taxes_occupancy",&"taxes_gaming"]
 for i in names.size():
  rows.append({"name":names[i],"label":GraphsWindow.SERIES_LABELS[names[i]],"values":PackedInt32Array([0,[111,18,8,6][i]]),"color":GraphsWindow.PALETTE[i]})
 canvas.set_series(rows,12)
 await Fixture.settle(self,3)
 check(canvas.has_method("endpoint_labels"),"endpoint labels expose the actual fitted draw rectangles")
 if not canvas.has_method("endpoint_labels"): return
 for values in [[111,18,8,6],[0,0,0,0]]:
  for i in rows.size(): rows[i].values=PackedInt32Array([[0,0,0,0][i] if values[0] else 100,values[i]])
  canvas.set_series(rows,12)
  var labels: Array = canvas.call("endpoint_labels")
  check_eq(labels.size(),4)
  for i in labels.size():
   var label: Dictionary=labels[i]
   var bounds: Rect2=label.rect
   check(Rect2(Vector2.ZERO,canvas.size).grow(.5).encloses(bounds),"complete endpoint label fits canvas")
   check_eq(label.text,canvas.value_text(label.name,values[names.find(label.name)]),"dollar/percent values retained")
   check(canvas.get_theme_default_font().get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,UITheme.FONT_SMALL).x<=bounds.size.x,"full value width fits")
   for j in range(i): check(not bounds.intersects(labels[j].rect),"endpoint labels never overlap")
func test_landscape_inspector_reveals_tourism_rows_and_preserves_controls() -> void:
 root.size=Vector2i(844,390)
 host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(47,0,750,369),0)
 var a:=Vector2i(40,40)
 host.sim.city.stamp_building(a.x,a.y,Buildings.id_of(&"arcology_boddy"))
 host.sim.tourism().reconcile_now()
 host.open_query(a)
 await Fixture.settle(self,12)
 var panel:=host.query_panel
 check_ge(panel.body_scroll.size.y,80,"landscape body can show multiple unwrapped tourism rows")
 for label in panel.rows.find_children("*","Label",true,false):
  if label.text in ["Completed gaming base","Completed lodging base","Tourists"]:
   panel.body_scroll.ensure_control_visible(label)
   await Fixture.settle(self,3)
   check(panel.body_scroll.get_global_rect().grow(.5).encloses(label.get_global_rect()),"entire tourism label can be revealed")
 for button in [panel.rename_button,panel.demolish_button,panel.close_button]:
  check_ge(button.size.y,44)
  check(host.display_layout.logical_rect().grow(.5).encloses(button.get_global_rect()))
 check(panel.get_global_rect().end.y<=host.status_bar.get_global_rect().position.y,"inspector leaves adjacent population/tourists face clear")
 root.size=Vector2i(390,844)
 host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763),0)
 await Fixture.settle(self,10)
 check(panel.rename_button.get_global_rect().position.y>panel.body_scroll.get_global_rect().position.y,"portrait restores footer actions")

func test_budget_tourism_compact_comparison_disclosure_and_large_values_fit() -> void:
 for profile in [Vector2i(390,844),Vector2i(320,568),Vector2i(844,390),Vector2i(768,1024),Vector2i(1024,768),Vector2i(1280,800)]:
  root.size=profile
  host.display_layout.refresh_with_mobile_metrics(profile,1,Rect2i(Vector2i.ZERO,profile),0)
  var budget:=host.open_window("budget") as BudgetWindow
  await Fixture.settle(self,10)
  var section:=budget.find_child("TourismSection",true,false) as Control
  var details:=budget.find_child("TourismDetails",true,false) as Button
  var body:=budget.find_child("TourismDetailBody",true,false) as Control
  var scroll:=UIFactory.report_scroll(section)
  check(not body.visible,"newly opened details are collapsed")
  var collapsed:=section.size.y
  scroll.scroll_vertical+=int(section.get_global_rect().position.y-scroll.get_global_rect().position.y)
  await Fixture.settle(self,3)
  if profile==Vector2i(390,844):
   var estimate:=budget.find_child("TourismTaxEstimate",true,false) as Control
   check(scroll.get_global_rect().grow(.5).encloses(estimate.get_global_rect()),"phone shows rates/comparison/city tax estimate together from section heading")
  for expanded in [false,true]:
   details.button_pressed=expanded
   host.sim.stats.tourist_guests=123456789
   host.sim.stats.tourist_day_visitors=987654321
   budget.refresh()
   await Fixture.settle(self,8)
   check_eq(body.visible,expanded,"refresh retains disclosure")
   check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1,"no horizontal scrolling: "+str(profile))
   check_ge(details.size.y,44)
   for key in [&"occupancy",&"gaming"]:
    var field:=budget._tax_spinners[key] as TouchNumberField
    for control in [field._minus,field._plus,field.get_line_edit()]: check_ge(control.size.y,44)
   if expanded: check_gt(section.size.y,collapsed,"only explicit disclosure adds explanation height")
  details.button_pressed=false
  host.window_manager.close_all()

func test_budget_tourism_refresh_preserves_typing_focus_and_scroll() -> void:
 root.size=Vector2i(390,844)
 host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763),0)
 var budget:=host.open_window("budget") as BudgetWindow
 await Fixture.settle(self,10)
 var details:=budget.find_child("TourismDetails",true,false) as Button
 var field:=budget._tax_spinners[&"gaming"] as TouchNumberField
 var edit:=field.get_line_edit()
 var scroll:=UIFactory.report_scroll(edit)
 scroll.ensure_control_visible(edit)
 await Fixture.settle(self,4)
 edit.grab_focus()
 edit.text="1"
 edit.text_changed.emit("1")
 var before:=host.sim.snapshot().duplicate(true)
 var offset:=scroll.scroll_vertical
 budget.refresh()
 await Fixture.settle(self,4)
 check_eq(edit.text,"1","refresh preserves unfinished tourism rate")
 check_eq(root.gui_get_focus_owner(),edit,"refresh never steals typing focus")
 check_eq(scroll.scroll_vertical,offset,"refresh does not jump")
 check_eq(host.sim.snapshot(),before,"refresh does not commit partial rate")
 edit.text="7"
 edit.text_changed.emit("7")
 field.apply()
 details.grab_focus()
 details.button_pressed=true
 budget.refresh()
 await Fixture.settle(self,4)
 check_eq(root.gui_get_focus_owner(),details,"keyboard disclosure retains focus")
 check_eq(host.sim.snapshot(),before,"disclosure remains simulation-pure")
