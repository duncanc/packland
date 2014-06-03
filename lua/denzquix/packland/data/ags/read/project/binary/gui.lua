
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'
local versioning = require 'denzquix.packland.versioning'
local v = require 'denzquix.packland.data.ags.versioning.project'

-------------------------------------------------------------------------------

local reader_proto = {}

-------------------------------------------------------------------------------

local function list(length)
	local t = {byId={}}
	for i = 1, length do
		local id = i-1
		local el = {id = id}
		t[i] = el
		t.byId[id] = el
	end
	return t
end

-------------------------------------------------------------------------------

local gui_v = versioning.schema 'GUI Format'

local gv_0          = gui_v(0)
local gv2_1_4       = gui_v(100)
local gv2_2_2       = gui_v(101)
local gv2_3_0       = gui_v(102)
local gv_103        = gui_v(103)
local gv_104        = gui_v(104)
local gv2_6_0       = gui_v(105)
local gv_106        = gui_v(106)
local gv_107        = gui_v(107)
local gv_108        = gui_v(108)
local gv_109        = gui_v(109)
local gv2_7_0       = gui_v(110)
local gv2_7_2a      = gui_v(111)
local gv2_7_2b      = gui_v(112)
local gv2_7_2c      = gui_v(113)
local gv2_7_2d      = gui_v(114)
local gv2_7_2e      = gui_v(115)
local gv3_3_0       = gui_v(116)
local gv_current    = gv3_3_0
local gv_fwd_compat = gv2_7_2e

local GLF_SGINDEXVALID = 4
local GBUT_ALIGN_TOPMIDDLE    = 0
local GBUT_ALIGN_TOPLEFT      = 1
local GBUT_ALIGN_TOPRIGHT     = 2
local GBUT_ALIGN_MIDDLELEFT   = 3 
local GBUT_ALIGN_CENTRED      = 4
local GBUT_ALIGN_MIDDLERIGHT  = 5
local GBUT_ALIGN_BOTTOMLEFT   = 6
local GBUT_ALIGN_BOTTOMMIDDLE = 7
local GBUT_ALIGN_BOTTOMRIGHT  = 8
local GUIF_TRANSLATED = 0x80
local MAX_OBJS_ON_GUI = 30

local GUIF_NOCLICK = 1

local GOBJ_BUTTON    = 1
local GOBJ_LABEL     = 2
local GOBJ_INVENTORY = 3
local GOBJ_SLIDER    = 4
local GOBJ_TEXTBOX   = 5
local GOBJ_LISTBOX   = 6

local GUIF_DEFAULT    = 0x0001
local GUIF_DISABLED   = 0x0004
local GUIF_INVISIBLE  = 0x0010
local GUIF_CLIP       = 0x0020
local GUIF_NOCLICKS   = 0x0040
local GUIF_TRANSLATED = 0x0080
local GUIF_DELETED    = 0x8000

local IBACT_SETMODE   = 1
local IBACT_SCRIPT    = 2

local GALIGN_LEFT   = 0
local GALIGN_RIGHT  = 1
local GALIGN_CENTRE = 2

local GTF_NOBORDER  = 1

local GLF_NOBORDER     = 1
local GLF_NOARROWS     = 2
local GLF_SGINDEXVALID = 4

local POPUP_NONE = 0
local POPUP_MOUSEY = 1
local POPUP_SCRIPT = 2
local POPUP_NOAUTOREM = 3
local POPUP_NONEINITIALLYOFF = 4

function reader_proto:gui_section(gui)
	assert(self:int32le() == bit.tobit(0xcafebeef), 'bad gui signature')

	local v = self:int32le()
	if v < 100 then
		self.gv = gv_0
		gui.interfaces = list(v)
	else
		self.gv = gui_v( v )
		assert(self.gv <= gv_current, 'future GUI version!!')
		gui.interfaces = list(self:int32le())
	end

	for _, interface in ipairs(gui.interfaces) do
		self:gui_interface(interface)
	end

	gui.buttons = list(self:int32le())
	for _, button in ipairs(gui.buttons) do
		self:gui_button(button)
	end

	gui.labels = list(self:int32le())
	for _, label in ipairs(gui.labels) do
		self:gui_label(label)
	end

	gui.inventory_windows = list(self:int32le())
	for _, inventory_window in ipairs(gui.inventory_windows) do
		self:gui_inventory_window(inventory_window)
	end

	if self.gv < gv2_1_4 then
		return
	end

	gui.sliders = list(self:int32le())
	for _, slider in ipairs(gui.sliders) do
		self:gui_slider(slider)
	end

	if self.gv < gv2_2_2 then
		return
	end

	gui.text_boxes = list(self:int32le())
	for _, text_box in ipairs(gui.text_boxes) do
		self:gui_text_box(text_box)
	end

	if self.gv < gv2_3_0 then
		return
	end

	gui.list_boxes = list(self:int32le())
	for _, list_box in ipairs(gui.list_boxes) do
		self:gui_list_box(list_box)
	end
end

local control_type_names = {
	[GOBJ_BUTTON] = 'button';
	[GOBJ_LABEL] = 'label';
	[GOBJ_INVENTORY] = 'inventory_window';
	[GOBJ_SLIDER] = 'slider';
	[GOBJ_TEXTBOX] = 'text_box';
	[GOBJ_LISTBOX] = 'list_box';
}

function reader_proto:gui_interface(interface)
	interface.vtext = self:nullTerminated(4) -- compatibility?
	interface.script_name = self:nullTerminated(16)
	interface.on_click = self:nullTerminated(20)
	if interface.on_click == '' then
		interface.on_click = nil
	end
	interface.x = self:int32le()
	interface.y = self:int32le()
	interface.width = self:int32le()
	interface.height = self:int32le()
	interface.height = math.max(interface.height, 2)
	interface.focus = self:int32le()
	local control_count = self:int32le()

	interface.popup = self:int32le()
	interface.popup_mouse_y = self:int32le()
	if interface.popup ~= POPUP_MOUSEY then
		interface.popup_mouse_y = nil
	end
	interface.is_always_shown = interface.popup == POPUP_NOAUTOREM
	interface.is_initially_shown = (interface.popup == POPUP_NONE) or interface.is_always_shown
	interface.pauses_game_while_shown = interface.popup == POPUP_SCRIPT

	interface.background_color = self:int32le()
	interface.background_sprite = self:int32le()
	interface.border_color = self:int32le()
	interface.mouseover = self:int32le()
	interface.mousewasx = self:int32le()
	interface.mousewasy = self:int32le()
	interface.mousedownon = self:int32le()
	interface.highlightobj = self:int32le()
	interface.flags = self:int32le()
	interface.is_clickable = 0 == bit.band(GUIF_NOCLICK, interface.flags)
	interface.transparency = self:int32le()
	interface.z_order = self:int32le()
	self:int32le() -- gui_id: overwritten

	self:skip(6 * 4) -- reserved int[6]

	interface.on = self:int32le()
	self:skip(MAX_OBJS_ON_GUI * 4) -- unused

	interface.controls = {}
	for i = 1, control_count do
		local v = self:int32le()
		local control_type = bit.rshift(v, 16)
		local control_id = bit.band(0xffff, v)
		local type_name = control_type_names[control_type]
		if type_name == nil then
			error('unknown control type ID: ' .. control_type)
		end
		interface.controls[i] = {type=type_name, id=control_id}
	end
	self:skip((MAX_OBJS_ON_GUI - control_count) * 4)

	if self.gv < gv_103 then
		interface.script_name = 'GUI'..interface.id
	end
	if self.gv < gv2_6_0 then
		interface.z_order = interface.id
	end
	if self.v <= v.v2_7_2 and interface.script_name:sub(1,1) ~= 'g' then
		-- Fix names for 2.x: "GUI" -> "gGui"
		interface.script_name = 'g' .. interface.script_name:sub(1,1) .. interface.script_name:sub(2):lower()
	end
end

function reader_proto:gui_control(control)
	control.flags = self:int32le()
	control.is_enabled = 0 == bit.band(GUIF_DISABLED, control.flags)
	control.is_visible = 0 == bit.band(GUIF_INVISIBLE, control.flags)
	control.is_clickable = 0 == bit.band(GUIF_NOCLICKS, control.flags)
	control.is_translated = 0 ~= bit.band(GUIF_TRANSLATED, control.flags)
	control.ignore = 0 ~= bit.band(GUIF_DELETED, control.flags)

	control.x = self:int32le()
	control.y = self:int32le()
	control.width = self:int32le()
	control.height = self:int32le()
	control.z_order = self:int32le()
	control.activated = self:int32le()

	if self.gv < gv_106 then
		return
	end

	control.script_name = self:nullTerminated()

	if self.gv < gv_108 then
		return
	end

	control.event_handlers = {}
	self:event_handlers(control.event_handlers)
end

local button_vertical_align = {
	[GBUT_ALIGN_TOPLEFT]   = 'top';
	[GBUT_ALIGN_TOPMIDDLE] = 'top';
	[GBUT_ALIGN_TOPRIGHT]  = 'top';

	[GBUT_ALIGN_MIDDLELEFT]  = 'middle';
	[GBUT_ALIGN_CENTRED]     = 'middle';
	[GBUT_ALIGN_MIDDLERIGHT] = 'middle';

	[GBUT_ALIGN_BOTTOMLEFT]   = 'bottom';
	[GBUT_ALIGN_BOTTOMMIDDLE] = 'bottom';
	[GBUT_ALIGN_BOTTOMRIGHT]  = 'bottom';
}

local button_horizontal_align = {
	[GBUT_ALIGN_TOPLEFT]    = 'left';
	[GBUT_ALIGN_MIDDLELEFT] = 'left';
	[GBUT_ALIGN_BOTTOMLEFT] = 'left';

	[GBUT_ALIGN_TOPMIDDLE]    = 'middle';
	[GBUT_ALIGN_CENTRED]      = 'middle';
	[GBUT_ALIGN_BOTTOMMIDDLE] = 'middle';

	[GBUT_ALIGN_TOPRIGHT]    = 'right';
	[GBUT_ALIGN_MIDDLERIGHT] = 'right';
	[GBUT_ALIGN_BOTTOMRIGHT] = 'right';
}

function reader_proto:gui_button(button)
	self:gui_control(button)

	if button.event_handlers then
		button.on_click = button.event_handlers[0]
	end

	button.is_default = 0 ~= bit.band(GUIF_DEFAULT, button.flags)
	button.clips_background = 0 ~= bit.band(GUIF_CLIP, button.flags)
	button.is_translated = true

	button.normal_sprite = self:int32le()
	button.mouseover_sprite = self:int32le()
	button.pushed_sprite = self:int32le()
	if button.normal_sprite <= 0 then
		button.normal_sprite = nil
	end
	if button.mouseover_sprite <= 0 then
		button.mouseover_sprite = nil
	end
	if button.pushed_sprite <= 0 then
		button.pushed_sprite = nil
	end

	self:int32le() -- usepic: just copies sprite
	button.is_pushed = self:int32le()
	button.is_over = self:int32le()

	button.font = self:int32le()
	button.text_color = self:int32le()
	if button.text_color == 0 then
		button.text_color = 16
	end
	button.left_click = self:int32le()
	button.right_click = self:int32le()
	button.left_click_data = self:int32le()
	button.right_click_data = self:int32le()
	button.text = self:nullTerminated(50)

	if button.left_click == IBACT_SETMODE then
		button.set_cursor_mode = button.left_click_data
		button.on_click = nil
	elseif button.left_click ~= IBACT_SCRIPT then
		button.is_clickable = false
		button.on_click = nil
	end

	if self.gv < gv2_7_2a then
		button.horizontal_align = 'middle'
		button.vertical_align = 'top'
		return
	end

	local alignment = self:int32le()
	button.horizontal_align = button_horizontal_align[alignment]
	button.vertical_align = button_vertical_align[alignment]

	self:skip(4) -- reserved int[1]
end

function reader_proto:gui_label(label)
	self:gui_control(label)
	label.is_translated = true
	if self.gv >= gv2_7_2c then
		label.text = self:nullTerminated( self:int32le() )
	else
		label.text = self:nullTerminated( 200 )
	end
	label.font = self:int32le()
	label.text_color = self:int32le()
	if label.text_color == 0 then
		label.text_color = 16
	end
	local alignment = self:int32le()
	if alignment == GALIGN_LEFT then
		label.horizontal_align = 'left'
	elseif alignment == GALIGN_CENTRE then
		label.horizontal_align = 'middle'
	elseif alignment == GALIGN_RIGHT then
		label.horizontal_align = 'right'
	end
	label.vertical_align = 'top'
end

function reader_proto:gui_inventory_window(inventory_window)
	self:gui_control(inventory_window)
	if self.gv < gv_109 then
		inventory_window.item_width = 40
		inventory_window.item_height = 22
		inventory_window.top_index = 0
		return
	end
	inventory_window.for_character = self:int32le()
	if inventory_window.for_character == -1 then
		inventory_window.for_character = nil
	end
	inventory_window.item_width = self:int32le()
	inventory_window.item_height = self:int32le()
	if self.v >= v.v2_7_0 then
		inventory_window.item_width = math.min(inventory_window.width, inventory_window.item_width)
		inventory_window.item_height = math.min(inventory_window.height, inventory_window.item_height)
	end
	inventory_window.top_index = self:int32le()
end

function reader_proto:gui_slider(slider)
	self:gui_control(slider)
	slider.min_value = self:int32le()
	slider.max_value = self:int32le()
	slider.default_value = self:int32le()
	self:skip(4) -- runtime: mouse-pressed
	if self.gv < gv_104 then
		slider.handle_offset = 0
		return
	end
	slider.handle_sprite = self:int32le()
	if slider.handle_sprite <= 0 then
		slider.handle_sprite = nil
	end
	slider.handle_offset = self:int32le()
	slider.background_sprite = self:int32le()
	if slider.background_sprite <= 0 then
		slider.background_sprite = nil
	end
end

function reader_proto:gui_text_box(text_box)
	self:gui_control(text_box)
	text_box.default_text = self:nullTerminated(200)
	text_box.font = self:int32le()
	text_box.text_color = self:int32le()
	if text_box.text_color == 0 then
		text_box.text_color = 16
	end
	text_box.exflags = self:int32le()
	text_box.has_border = 0 == bit.band(GTF_NOBORDER, text_box.exflags)
end

function reader_proto:gui_list_box(list_box)
	self:gui_control(list_box)
	local num_items = self:int32le()
	list_box.selected_text_color = self:int32le()
	list_box.top_item = self:int32le()
	list_box.mouse_x = self:int32le()
	list_box.mouse_y = self:int32le()
	list_box.row_height = self:int32le()
	list_box.num_items_fit = self:int32le()
	list_box.font = self:int32le()
	list_box.text_color = self:int32le()
	if list_box.text_color == 0 then
		list_box.text_color = 16
	end
	list_box.background_color = self:int32le()
	list_box.exflags = self:int32le()
	list_box.has_border = 0 == bit.band(GLF_NOBORDER, list_box.exflags)
	list_box.has_arrows = 0 == bit.band(GLF_NOARROWS, list_box.exflags)
	if self.gv >= gv2_7_2b then
		local alignment = self:int32le()
		if alignment == GALIGN_LEFT then
			list_box.horizontal_align = 'left'
		elseif alignment == GALIGN_CENTRE then
			list_box.horizontal_align = 'middle'
		elseif alignment == GALIGN_RIGHT then
			list_box.horizontal_align = 'right'
		end
		self:skip(4) -- reserved int[1]
	else
		list_box.horizontal_align = 'left'
	end
	if self.gv >= gv_107 then
		list_box.selected_background_color = self:int32le()
	else
		list_box.selected_background_color = list_box.text_color
	end
	list_box.items = {}
	for i = 0, num_items-1 do
		list_box.items[i] = {name=self:nullterminated(), saveGame=-1}
	end
	if self.gv >= gv2_7_2d and 0 ~= bit.band(list_box.exflags, GLF_SGINDEXVALID) then
		for i = 0, numItems-1 do
			list_box.items[i].save_game = self:int16le()
		end
	end
end

return reader_proto
