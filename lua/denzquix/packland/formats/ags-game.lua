
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'
local versioning = require 'denzquix.packland.versioning'
require 'denzquix.packland.data.ags.read'

-------------------------------------------------------------------------------

local format = {}

local reader_proto = {}

-------------------------------------------------------------------------------

local SCOM_VERSION = 89

local MAX_INV = 301
local MAXLIPSYNCFRAMES = 20

local SPF_640x400         = 0x01
local SPF_HICOLOR         = 0x02
local SPF_DYNAMICALLOC    = 0x04
local SPF_TRUECOLOR       = 0x08
local SPF_ALPHACHANNEL    = 0x10
local SPF_HADALPHACHANNEL = 0x80

local CHF_MANUALSCALING   = 0x00001
local CHF_FIXVIEW         = 0x00002   -- between SetCharView and ReleaseCharView
local CHF_NOINTERACT      = 0x00004
local CHF_NODIAGONAL      = 0x00008
local CHF_ALWAYSIDLE      = 0x00010
local CHF_NOLIGHTING      = 0x00020
local CHF_NOTURNING       = 0x00040
local CHF_NOWALKBEHINDS   = 0x00080
local CHF_FLIPSPRITE      = 0x00100   -- ?? Is this used??
local CHF_NOBLOCKING      = 0x00200
local CHF_SCALEMOVESPEED  = 0x00400
local CHF_NOBLINKANDTHINK = 0x00800
local CHF_SCALEVOLUME     = 0x01000
local CHF_HASTINT         = 0x02000   -- engine only
local CHF_BEHINDSHEPHERD  = 0x04000   -- engine only
local CHF_AWAITINGMOVE    = 0x08000   -- engine only
local CHF_MOVENOTWALK     = 0x10000   -- engine only - do not do walk anim
local CHF_ANTIGLIDE       = 0x20000


local MCF_ANIMMOVE = 1
local MCF_DISABLED = 2
local MCF_STANDARD = 4
local MCF_HOTSPOT  = 8  -- only animate when over hotspot

local LOOPFLAG_RUNNEXTLOOP = 1

local VFLG_FLIPSPRITE = 1

local format_v = versioning.schema 'game file format'
local v_LotD = format_v(9) -- Lunchtime of the Damned
local v2_3_0 = format_v(12)
local v2_4_0 = v2_3_0
local v2_5_0 = format_v(18)
local v2_5_1 = format_v(19)
local v2_5_2 = v2_5_1
local v2_5_3 = format_v(20)
local v2_5_4 = format_v(21)
local v2_5_5 = format_v(22)
local v2_5_6 = format_v(24)
local v2_6_0 = format_v(25)
local v2_6_1 = format_v(26)
local v2_6_2 = format_v(27)
local v2_7_0 = format_v(31)
local v2_7_2 = format_v(32)
local v3_0_0 = format_v(35)
local v3_0_1 = format_v(36)
local v3_1_0 = format_v(37)
local v3_1_1 = format_v(39)
local v3_1_2 = format_v(40)
local v3_2_0 = format_v(41)
local v3_2_1 = format_v(42)
local v3_3_0 = format_v(43)
local v_current = v3_3_0

-------------------------------------------------------------------------------

-- TODO: remove game-wide anti-glide

function format.dbinit(db)
	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS game (
			dbid INTEGER PRIMARY KEY,
			title TEXT,
			engine_version TEXT,

			debug_mode,
			score_sound,
			walk_in_look_mode,
			dialog_gui,
			text_window_gui,
			dialog_gap,
			no_skip_text,
			hide_gui_on_disabled,
			always_show_text_as_speech,
			speech_type,
			pixel_perfect,
			no_walk_mode,
			force_letterbox,
			fixed_inv_cursor,
			no_lose_inventory,
			no_scale_fonts,
			split_resources,
			rotate_chars,
			fade_type,
			handle_inventory_clicks,
			use_mouse_wheel,
			dialog_numbered,
			dialog_upwards,
			crossfade_music,
			antialias_fonts,
			thought_gui,
			turn_to_face,
			text_left_to_right,
			duplicate_inventory,
			save_screenshot,
			portrait_side,
			strict_scripting,
			left_to_right_eval,
			compress_sprites,
			strict_strings,
			gui_alpha_mode,
			run_game_during_dialog,
			native_coordinates,
			global_talk_anim_speed,
			sprite_alpha,
			no_mod_music,
			lipsync_text,
			palette_uses BLOB,
			palette BLOB,
			player_character_idx INTEGER,
			total_score INTEGER,
			color_depth INTEGER,
			target_win,
			dialog_bullet,
			hotdot,
			hotdotouter,
			uniqueid,
			default_resolution,
			default_lipsync_frame,
			invhotdotsprite,

			guid,
			save_extension,
			save_folder,

			global_script INTEGER,
			dialog_script INTEGER,

			sound_on_score INTEGER
		);

		CREATE TABLE IF NOT EXISTS font (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			size INTEGER NOT NULL,

			-- outline: NULL, other font dbid (NOT idx), or 'auto'
			outline,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS sprite (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,

			-- 'low' (320x200, 320x240) or 'high' (640x400, ...)
			resolution,

			has_alpha_channel,
			bits_per_pixel INTEGER,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS inventory_item (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			script_name TEXT,
			name TEXT,
			sprite INTEGER,
			cursor_sprite INTEGER,
			handle_x INTEGER,
			handle_y INTEGER,
			-- TODO: start with?

			on_look_at TEXT,
			on_interact TEXT,
			on_other_click TEXT,
			on_use_inventory TEXT,
			on_talk_to TEXT,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS cursor (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			name TEXT,
			sprite INTEGER,
			handle_x INTEGER,
			handle_y INTEGER,
			view INTEGER,
			animate_when_moving INTEGER,
			animate_over_hotspot INTEGER,
			process_click INTEGER,
			enabled INTEGER,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS character (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,

			script_name TEXT,
			name TEXT,
			speech_color INTEGER,
			room INTEGER,
			x INTEGER,
			y INTEGER,
			scale_volume,
			blink_view INTEGER,
			idle_view INTEGER,
			normal_view INTEGER,
			speech_anim_delay INTEGER,
			speech_view INTEGER,
			think_view INTEGER,
			ignore_lighting,
			ignore_scaling,
			clickable,
			scale_speed,
			anim_delay INTEGER,
			diagonal_loops,
			link_move_to_anim,
			walk_speed_x INTEGER,
			walk_speed_y INTEGER,
			solid,
			turn_before_walking,

			on_look_at TEXT,
			on_interact TEXT,
			on_any_click TEXT,
			on_use_inventory TEXT,
			on_talk_to TEXT,
			on_pick_up TEXT,
			on_user_mode_1 TEXT,
			on_user_mode_2 TEXT,
		
			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS parser_word (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			word TEXT NOT NULL,
			code INTEGER,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS script (
			dbid INTEGER PRIMARY KEY,

			version INTEGER,
			compiled BLOB,
			data BLOB
		);

		CREATE TABLE IF NOT EXISTS script_string (
			script_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			string TEXT,

			FOREIGN KEY (script_dbid) REFERENCES script(dbid)
		);

		CREATE TABLE IF NOT EXISTS script_fixup (
			script_dbid INTEGER NOT NULL,
			type INTEGER NOT NULL,
			value INTEGER NOT NULL,

			FOREIGN KEY (script_dbid) REFERENCES script(dbid)
		);

		CREATE TABLE IF NOT EXISTS script_import (
			script_dbid INTEGER NOT NULL,
			name TEXT,
			address INTEGER,

			FOREIGN KEY (script_dbid) REFERENCES script(dbid)
		);

		CREATE TABLE IF NOT EXISTS script_export (
			script_dbid INTEGER NOT NULL,
			name TEXT,
			address INTEGER,

			FOREIGN KEY (script_dbid) REFERENCES script(dbid)
		);

		CREATE TABLE IF NOT EXISTS script_section (
			script_dbid INTEGER NOT NULL,
			name TEXT,
			offset INTEGER,
			
			FOREIGN KEY (script_dbid) REFERENCES script(dbid)
		);

		CREATE TABLE IF NOT EXISTS game_module_script (
			game_dbid INTEGER NOT NULL,
			script_dbid INTEGER NOT NULL,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid),
			FOREIGN KEY (script_dbid) REFERENCES script(dbid)
		);

	    CREATE TABLE IF NOT EXISTS anim_view (
	    	dbid INTEGER PRIMARY KEY,
	    	game_dbid INTEGER NOT NULL,
	    	idx INTEGER NOT NULL,
	    	script_name TEXT,

	    	FOREIGN KEY (game_dbid) REFERENCES game(dbid)
	    );

	    CREATE TABLE IF NOT EXISTS anim_loop (
	    	dbid INTEGER PRIMARY KEY,
	    	view_dbid INTEGER NOT NULL,
	    	idx INTEGER NOT NULL,

	    	run_next INTEGER,

	    	FOREIGN KEY (view_dbid) REFERENCES anim_view(dbid)	
	    );

	    CREATE TABLE IF NOT EXISTS anim_frame (
	    	dbid INTEGER PRIMARY KEY,
	    	loop_dbid INTEGER NOT NULL,
	    	idx INTEGER NOT NULL,

	    	x_offset INTEGER,
	    	y_offset INTEGER,
	    	speed INTEGER,

	    	flipped INTEGER,

	    	FOREIGN KEY (loop_dbid) REFERENCES anim_loop(dbid)
	    );

		CREATE TABLE IF NOT EXISTS lipsync_letter (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			letter TEXT NOT NULL,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS message (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			message_content TEXT NOT NULL,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS dialog (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			script_name TEXT,

			show_parser,

			entry_point,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS dialog_option (
			dbid INTEGER PRIMARY KEY,
			dialog_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,

			text TEXT,
			enabled,
			say,

			entry_point,

			FOREIGN KEY (dialog_dbid) REFERENCES dialog(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_interface (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			script_name TEXT,
			-- layout
			x INTEGER,
			y INTEGER,
			width INTEGER,
			height INTEGER,
			z_order INTEGER,
			-- appearance
			background_color INTEGER,
			background_sprite INTEGER,
			border_color INTEGER,
			clickable, -- boolean
			initially_shown,
			always_shown,
			pause_while_shown,
			popup_mouse_y INTEGER NULL,
			transparency INTEGER,
			-- event handlers
			on_click TEXT,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_control (
			dbid INTEGER PRIMARY KEY,
			interface_dbid INTEGER NOT NULL,

			script_name TEXT,

			x INTEGER, y INTEGER, width INTEGER, height INTEGER, z_order INTEGER,

			enabled,
			visible,
			clickable,
			translated,

			FOREIGN KEY (interface_dbid) REFERENCES gui_interface(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_button (
			dbid INTEGER PRIMARY KEY,
			control_dbid INTEGER NOT NULL,

			text, text_color, font,
			horizontal_align, vertical_align,
			normal_sprite, mouseover_sprite, pushed_sprite,

			is_default,
			clip,

			on_click, set_cursor_mode,

			FOREIGN KEY (control_dbid) REFERENCES gui_control(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_label (
			dbid INTEGER PRIMARY KEY,
			control_dbid INTEGER NOT NULL,

			text, text_color, font,
			horizontal_align, vertical_align,

			FOREIGN KEY (control_dbid) REFERENCES gui_control(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_inventory_window (
			dbid INTEGER PRIMARY KEY,
			control_dbid INTEGER NOT NULL,

			item_width INTEGER,
			item_height INTEGER,
			for_character INTEGER,

			FOREIGN KEY (control_dbid) REFERENCES gui_control(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_slider (
			dbid INTEGER PRIMARY KEY,
			control_dbid INTEGER NOT NULL,

			min_value INTEGER,
			max_value INTEGER,
			default_value INTEGER,

			handle_sprite, handle_offset,
			background_sprite,

			FOREIGN KEY (control_dbid) REFERENCES gui_control(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_text_box (
			dbid INTEGER PRIMARY KEY,
			control_dbid INTEGER NOT NULL,

			default_text,
			font, text_color,
			use_border,

			FOREIGN KEY (control_dbid) REFERENCES gui_control(dbid)
		);

		CREATE TABLE IF NOT EXISTS gui_list_box (
			dbid INTEGER PRIMARY KEY,
			control_dbid INTEGER NOT NULL,

			font, text_color, selected_text_color,
			use_border,
			use_arrows,
			horizontal_align,

			background_color, selected_background_color,

			FOREIGN KEY (control_dbid) REFERENCES gui_control(dbid)
		);

		CREATE TABLE IF NOT EXISTS plugin (
			game_dbid INTEGER NOT NULL,
			name TEXT,
			editor_only INTEGER,
			data BLOB,
			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS property_schema (
			game_dbid INTEGER NOT NULL,
			name TEXT,
			description TEXT,
			value_type TEXT,
			default_value,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS room (
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			name TEXT,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS character_property (
			character_dbid INTEGER NOT NULL,
			name TEXT NOT NULL,
			value,

			FOREIGN KEY (character_dbid) REFERENCES character(dbid)
		);

		CREATE TABLE IF NOT EXISTS inventory_item_property (
			item_dbid INTEGER NOT NULL,
			name TEXT NOT NULL,
			value,

			FOREIGN KEY (item_dbid) REFERENCES inventory_item(dbid)
		);

		CREATE TABLE IF NOT EXISTS audio_type (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,

			reserved_channels INTEGER,
			reduce_volume_for_speech INTEGER,
			crossfade_speed INTEGER,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid)
		);

		CREATE TABLE IF NOT EXISTS audio_clip (
			dbid INTEGER PRIMARY KEY,
			game_dbid INTEGER NOT NULL,
			type_dbid INTEGER NULL,
			idx INTEGER NOT NULL,

			script_name TEXT,
			file_name TEXT,
			file_type TEXT,

			default_repeat,
			default_priority INTEGER,
			default_volume INTEGER,

			FOREIGN KEY (game_dbid) REFERENCES game(dbid),
			FOREIGN KEY (type_dbid) REFERENCES audio_type(dbid)
		);

	]])
end

function format.todb(intype, inpath, db)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')
	local reader = assert(R.fromfile(inpath))
	reader:inject('bindata')
	reader:inject(reader_proto)

	local game = {}
	reader:game(game)

	format.dbinit(db)

	local exec_add_game = assert( db:prepare [[

		INSERT INTO game (
			title, engine_version,
			debug_mode,
			score_sound,
			walk_in_look_mode,
			dialog_gui,
			text_window_gui,
			dialog_gap,
			no_skip_text,
			hide_gui_on_disabled,
			always_show_text_as_speech,
			speech_type,
			pixel_perfect,
			no_walk_mode,
			force_letterbox,
			fixed_inv_cursor,
			no_lose_inventory,
			no_scale_fonts,
			split_resources,
			rotate_chars,
			fade_type,
			handle_inventory_clicks,
			use_mouse_wheel,
			dialog_numbered,
			dialog_upwards,
			crossfade_music,
			antialias_fonts,
			thought_gui,
			turn_to_face,
			text_left_to_right,
			duplicate_inventory,
			save_screenshot,
			portrait_side,
			strict_scripting,
			left_to_right_eval,
			compress_sprites,
			strict_strings,
			gui_alpha_mode,
			run_game_during_dialog,
			native_coordinates,
			global_talk_anim_speed,
			sprite_alpha,
			no_mod_music,
			lipsync_text,
			palette_uses,
			palette,
			player_character_idx,
			total_score,
			color_depth,
			target_win,
			dialog_bullet,
			hotdot,
			hotdotouter,
			uniqueid,
			default_resolution,
			default_lipsync_frame,
			invhotdotsprite,

			guid,
			save_extension,
			save_folder
		)
		VALUES (
			:title, :engine_version,
			:debug_mode,
			:score_sound,
			:walk_in_look_mode,
			:dialog_gui,
			:text_window_gui,
			:dialog_gap,
			:no_skip_text,
			:hide_gui_on_disabled,
			:always_show_text_as_speech,
			:speech_type,
			:pixel_perfect,
			:no_walk_mode,
			:force_letterbox,
			:fixed_inv_cursor,
			:no_lose_inventory,
			:no_scale_fonts,
			:split_resources,
			:rotate_chars,
			:fade_type,
			:handle_inventory_clicks,
			:use_mouse_wheel,
			:dialog_numbered,
			:dialog_upwards,
			:crossfade_music,
			:antialias_fonts,
			:thought_gui,
			:turn_to_face,
			:text_left_to_right,
			:duplicate_inventory,
			:save_screenshot,
			:portrait_side,
			:strict_scripting,
			:left_to_right_eval,
			:compress_sprites,
			:strict_strings,
			:gui_alpha_mode,
			:run_game_during_dialog,
			:native_coordinates,
			:global_talk_anim_speed,
			:sprite_alpha,
			:no_mod_music,
			:lipsync_text,
			:palette_uses,
			:palette,
			:player_character_idx,
			:total_score,
			:color_depth,
			:target_win,
			:dialog_bullet,
			:hotdot,
			:hotdotouter,
			:uniqueid,
			:default_resolution,
			:default_lipsync_frame,
			:invhotdotsprite,

			:guid,
			:save_extension,
			:save_folder
		)

	]] )

	assert( exec_add_game:bind_text(':title', game.title) )
	assert( exec_add_game:bind_text(':engine_version', game.engine_version) )
	assert( exec_add_game:bind_int(':debug_mode', game.debug_mode) )
	assert( exec_add_game:bind_int(':score_sound', game.score_sound) )
	assert( exec_add_game:bind_int(':walk_in_look_mode', game.walk_in_look_mode) )
	assert( exec_add_game:bind_int(':dialog_gui', game.dialog_gui) )
	assert( exec_add_game:bind_int(':text_window_gui', game.text_window_gui) )
	assert( exec_add_game:bind_int(':dialog_gap', game.dialog_gap) )
	assert( exec_add_game:bind_int(':no_skip_text', game.no_skip_text) )
	assert( exec_add_game:bind_int(':hide_gui_on_disabled', game.hide_gui_on_disabled) )
	assert( exec_add_game:bind_int(':always_show_text_as_speech', game.always_show_text_as_speech) )
	assert( exec_add_game:bind_int(':speech_type', game.speech_type) )
	assert( exec_add_game:bind_int(':pixel_perfect', game.pixel_perfect) )
	assert( exec_add_game:bind_int(':no_walk_mode', game.no_walk_mode) )
	assert( exec_add_game:bind_int(':force_letterbox', game.force_letterbox) )
	assert( exec_add_game:bind_int(':fixed_inv_cursor', game.fixed_inv_cursor) )
	assert( exec_add_game:bind_int(':no_lose_inventory', game.no_lose_inventory) )
	assert( exec_add_game:bind_int(':no_scale_fonts', game.no_scale_fonts) )
	assert( exec_add_game:bind_int(':split_resources', game.split_resources) )
	assert( exec_add_game:bind_int(':rotate_chars', game.rotate_chars) )
	assert( exec_add_game:bind_int(':fade_type', game.fade_type) )
	assert( exec_add_game:bind_int(':handle_inventory_clicks', game.handle_inventory_clicks) )
	assert( exec_add_game:bind_int(':use_mouse_wheel', game.use_mouse_wheel) )
	assert( exec_add_game:bind_int(':dialog_numbered', game.dialog_numbered) )
	assert( exec_add_game:bind_int(':dialog_upwards', game.dialog_upwards) )
	assert( exec_add_game:bind_int(':crossfade_music', game.crossfade_music) )
	assert( exec_add_game:bind_int(':antialias_fonts', game.antialias_fonts) )
	assert( exec_add_game:bind_int(':thought_gui', game.thought_gui) )
	assert( exec_add_game:bind_int(':turn_to_face', game.turn_to_face) )
	assert( exec_add_game:bind_int(':text_left_to_right', game.text_left_to_right) )
	assert( exec_add_game:bind_int(':duplicate_inventory', game.duplicate_inventory) )
	assert( exec_add_game:bind_int(':save_screenshot', game.save_screenshot) )
	assert( exec_add_game:bind_int(':portrait_side', game.portrait_side) )
	assert( exec_add_game:bind_int(':strict_scripting', game.strict_scripting) )
	assert( exec_add_game:bind_int(':left_to_right_eval', game.left_to_right_eval) )
	assert( exec_add_game:bind_int(':compress_sprites', game.compress_sprites) )
	assert( exec_add_game:bind_int(':strict_strings', game.strict_strings) )
	assert( exec_add_game:bind_int(':gui_alpha_mode', game.gui_alpha_mode) )
	assert( exec_add_game:bind_int(':run_game_during_dialog', game.run_game_during_dialog) )
	assert( exec_add_game:bind_int(':native_coordinates', game.native_coordinates) )
	assert( exec_add_game:bind_int(':global_talk_anim_speed', game.global_talk_anim_speed) )
	assert( exec_add_game:bind_int(':sprite_alpha', game.sprite_alpha) )
	assert( exec_add_game:bind_int(':no_mod_music', game.no_mod_music) )
	assert( exec_add_game:bind_int(':lipsync_text', game.lipsync.text) )
	assert( exec_add_game:bind_blob(':palette_uses', game.palette_uses) )
	assert( exec_add_game:bind_blob(':palette', game.palette) )
	assert( exec_add_game:bind_int(':player_character_idx', game.characters.player.id) )
	assert( exec_add_game:bind_int(':total_score', game.total_score) )
	assert( exec_add_game:bind_int(':color_depth', game.color_depth) )
	assert( exec_add_game:bind_int(':target_win', game.target_win) )
	assert( exec_add_game:bind_int(':dialog_bullet', game.dialog_bullet) )
	assert( exec_add_game:bind_int(':hotdot', game.hotdot) )
	assert( exec_add_game:bind_int(':hotdotouter', game.hotdotouter) )
	assert( exec_add_game:bind_int(':uniqueid', game.uniqueid) )
	assert( exec_add_game:bind_int(':default_resolution', game.default_resolution) )
	assert( exec_add_game:bind_int(':default_lipsync_frame', game.lipsync.default_frame) )
	assert( exec_add_game:bind_int(':invhotdotsprite', game.invhotdotsprite) )

	assert( exec_add_game:bind_text(':guid', game.guid) )
	assert( exec_add_game:bind_text(':save_extension', game.save_extension) )
	assert( exec_add_game:bind_text(':save_folder', game.save_folder) )

	assert( assert( exec_add_game:step() ) == 'done' )
	assert( exec_add_game:finalize() )

	local game_dbid = db:last_insert_rowid()

	do
		local exec_add_font = assert(db:prepare [[

			INSERT INTO font (game_dbid, idx, size, outline)
			VALUES (:game_dbid, :idx, :size, :outline)

		]])
		assert( exec_add_font:bind_int64(':game_dbid', game_dbid) )
		for _, font in ipairs(game.fonts) do
			assert( exec_add_font:bind_int(':idx', font.id) )
			assert( exec_add_font:bind_int(':size', font.size) )
			if font.outline == nil then
				assert( exec_add_font:bind_null(':outline') )
			elseif font.outline == 'auto' then
				assert( exec_add_font:bind_text(':outline', 'auto') )
			else
				assert( exec_add_font:bind_int(':outline', font.outline) )
			end
			assert( assert( exec_add_font:step() ) == 'done' )
			assert( exec_add_font:reset() )
		end
		exec_add_font:finalize()
	end

	do
		local exec_add_sprite = assert(db:prepare [[

			INSERT INTO sprite (game_dbid, idx, resolution, has_alpha_channel, bits_per_pixel)
			VALUES (:game_dbid, :idx, :resolution, :has_alpha_channel, :bits_per_pixel)

		]])
		assert( exec_add_sprite:bind_int64(':game_dbid', game_dbid) )
		for _, sprite in ipairs(game.sprites) do
			assert( exec_add_sprite:bind_int(':idx', sprite.id) )
			assert( exec_add_sprite:bind_text(':resolution', sprite.resolution) )
			assert( exec_add_sprite:bind_int(':has_alpha_channel', sprite.alpha and 1 or 0) )
			assert( exec_add_sprite:bind_int(':bits_per_pixel', sprite.bits_per_pixel) )

			assert( assert( exec_add_sprite:step() ) == 'done' )
			assert( exec_add_sprite:reset() )
		end
		exec_add_sprite:finalize()
	end

	do
		local exec_add_inventory_item = assert(db:prepare [[

			INSERT INTO inventory_item (
				game_dbid, idx, script_name, name, sprite, cursor_sprite, handle_x, handle_y,
				on_interact, on_look_at, on_other_click, on_talk_to, on_use_inventory)
			VALUES (
				:game_dbid, :idx, :script_name, :name, :sprite, :cursor_sprite, :handle_x, :handle_y,
				:on_interact, :on_look_at, :on_other_click, :on_talk_to, :on_use_inventory)

		]])
		assert( exec_add_inventory_item:bind_int64(':game_dbid', game_dbid) )
		for _, item in ipairs(game.inventory) do
			if not item.ignore then
				assert( exec_add_inventory_item:bind_int(':idx', item.id) )
				assert( exec_add_inventory_item:bind_text(':script_name', item.script_name) )
				assert( exec_add_inventory_item:bind_text(':name', item.name) )
				assert( exec_add_inventory_item:bind_int(':sprite', item.sprite) )
				assert( exec_add_inventory_item:bind_int(':cursor_sprite', item.sprite) )
				assert( exec_add_inventory_item:bind_int(':handle_x', item.handle_x) )
				assert( exec_add_inventory_item:bind_int(':handle_y', item.handle_y) )

				assert( exec_add_inventory_item:bind_text(':on_interact', item.on_interact) )
				assert( exec_add_inventory_item:bind_text(':on_look_at', item.on_look_at) )
				assert( exec_add_inventory_item:bind_text(':on_other_click', item.on_other_click) )
				assert( exec_add_inventory_item:bind_text(':on_talk_to', item.on_talk_to) )
				assert( exec_add_inventory_item:bind_text(':on_use_inventory', item.on_use_inventory) )

				assert( assert( exec_add_inventory_item:step() ) == 'done' )
				assert( exec_add_inventory_item:reset() )
			end
		end
		assert( exec_add_inventory_item:finalize() )
 	end

	do
		local exec_add_cursor = assert(db:prepare [[

			INSERT INTO cursor (
				game_dbid, idx, name, enabled, sprite,
				handle_x, handle_y, view, process_click,
				animate_when_moving, animate_over_hotspot)
			VALUES (
				:game_dbid, :idx, :name, :enabled, :sprite,
				:handle_x, :handle_y, :view, :process_click,
				:animate_when_moving, :animate_over_hotspot)

		]])

		assert( exec_add_cursor:bind_int64(':game_dbid', game_dbid) )

		for _, cursor in ipairs(game.cursors) do
			assert( exec_add_cursor:bind_int(':idx', cursor.id) )
			assert( exec_add_cursor:bind_text(':name', cursor.name) )
			assert( exec_add_cursor:bind_bool(':enabled', cursor.enabled) )
			assert( exec_add_cursor:bind_int(':sprite', cursor.sprite) )
			assert( exec_add_cursor:bind_int(':handle_x', cursor.handle_x) )
			assert( exec_add_cursor:bind_int(':handle_y', cursor.handle_y) )
			if cursor.view == nil then
				assert( exec_add_cursor:bind_null(':view') )
			else
				assert( exec_add_cursor:bind_int(':view', cursor.view) )
			end
			assert( exec_add_cursor:bind_bool(':process_click', cursor.process_click) )
			assert( exec_add_cursor:bind_bool(':animate_when_moving', cursor.animate_when_moving) )
			assert( exec_add_cursor:bind_bool(':animate_over_hotspot', cursor.animate_over_hotspot) )

			assert( assert( exec_add_cursor:step() ) == 'done' )
			assert( exec_add_cursor:reset() )
		end

		assert( exec_add_cursor:finalize() )
	end

	do
		local exec_add_character = assert(db:prepare [[

			INSERT INTO character (
				game_dbid, idx,

				scale_volume, blink_view, idle_view, normal_view, speech_anim_delay,
				speech_color, speech_view, think_view, ignore_lighting, ignore_scaling,
				clickable, name, script_name, room, x, y, scale_speed, anim_delay,
				diagonal_loops, link_move_to_anim, walk_speed_x, walk_speed_y, solid,
				turn_before_walking,

				on_any_click, on_interact, on_look_at, on_pick_up, on_talk_to,
				on_use_inventory, on_user_mode_1, on_user_mode_2
			)
			VALUES (
				:game_dbid, :idx,

				:scale_volume, :blink_view, :idle_view, :normal_view, :speech_anim_delay,
				:speech_color, :speech_view, :think_view, :ignore_lighting, :ignore_scaling,
				:clickable, :name, :script_name, :room, :x, :y, :scale_speed, :anim_delay,
				:diagonal_loops, :link_move_to_anim, :walk_speed_x, :walk_speed_y, :solid,
				:turn_before_walking,

				:on_any_click, :on_interact, :on_look_at, :on_pick_up, :on_talk_to,
				:on_use_inventory, :on_user_mode_1, :on_user_mode_2
			)

		]])
		assert( exec_add_character:bind_int64(':game_dbid', game_dbid) )
		for _, character in ipairs(game.characters) do
			assert( exec_add_character:bind_int(':idx', character.id) )

			assert( exec_add_character:bind_bool(':scale_volume', character.scale_volume) )
			if character.blink_view == nil then
				assert( exec_add_character:bind_null(':blink_view') )
			else
				assert( exec_add_character:bind_int(':blink_view', character.blink_view) )
			end
			if character.idle_view == nil then
				assert( exec_add_character:bind_null(':idle_view') )
			else
				assert( exec_add_character:bind_int(':idle_view', character.idle_view) )
			end
			if character.normal_view == nil then
				assert( exec_add_character:bind_null(':normal_view') )
			else
				assert( exec_add_character:bind_int(':normal_view', character.normal_view) )
			end
			assert( exec_add_character:bind_int(':speech_anim_delay', character.speech_anim_delay) )
			assert( exec_add_character:bind_int(':speech_color', character.speech_color) )
			if character.speech_view == nil then
				assert( exec_add_character:bind_null(':speech_view') )
			else
				assert( exec_add_character:bind_int(':speech_view', character.speech_view) )
			end
			if character.think_view == nil then
				assert( exec_add_character:bind_null(':think_view') )
			else
				assert( exec_add_character:bind_int(':think_view', character.think_view) )
			end
			assert( exec_add_character:bind_bool(':ignore_lighting', character.ignore_lighting) )
			assert( exec_add_character:bind_bool(':ignore_scaling', character.ignore_scaling) )
			assert( exec_add_character:bind_bool(':clickable', character.clickable) )
			assert( exec_add_character:bind_text(':name', character.name) )
			assert( exec_add_character:bind_text(':script_name', character.script_name) )
			if character.room == nil then
				assert( exec_add_character:bind_null(':room') )
			else
				assert( exec_add_character:bind_int(':room', character.room) )
			end
			assert( exec_add_character:bind_int(':x', character.x) )
			assert( exec_add_character:bind_int(':y', character.y) )
			assert( exec_add_character:bind_bool(':scale_speed', character.scale_speed) )
			assert( exec_add_character:bind_int(':anim_delay', character.anim_delay) )
			assert( exec_add_character:bind_bool(':diagonal_loops', character.diagonal_loops) )
			assert( exec_add_character:bind_bool(':link_move_to_anim', character.link_move_to_anim) )
			assert( exec_add_character:bind_int(':walk_speed_x', character.walk_speed_x) )
			assert( exec_add_character:bind_int(':walk_speed_y', character.walk_speed_y) )
			assert( exec_add_character:bind_bool(':solid', character.solid) )
			assert( exec_add_character:bind_bool(':turn_before_walking', character.turn_before_walking) )

			assert( exec_add_character:bind_text(':on_any_click', character.on_any_click) )
			assert( exec_add_character:bind_text(':on_interact', character.on_interact) )
			assert( exec_add_character:bind_text(':on_look_at', character.on_look_at) )
			assert( exec_add_character:bind_text(':on_pick_up', character.on_pick_up) )
			assert( exec_add_character:bind_text(':on_talk_to', character.on_talk_to) )
			assert( exec_add_character:bind_text(':on_use_inventory', character.on_use_inventory) )
			assert( exec_add_character:bind_text(':on_user_mode_1', character.on_user_mode_1) )
			assert( exec_add_character:bind_text(':on_user_mode_2', character.on_user_mode_2) )

			assert( assert( exec_add_character:step() ) == 'done' )
			assert( exec_add_character:reset() )
		end
		assert( exec_add_character:finalize() )
	end

	if game.dictionary and next(game.dictionary) then
		local exec_add_word = assert(db:prepare [[

			INSERT INTO parser_word (game_dbid, word, code)
			VALUES (:game_dbid, :word, :code)

		]])
		assert( exec_add_word:bind_int64(':game_dbid', game_dbid) )

		for word, code in pairs(game.dictionary) do
			assert( exec_add_word:bind_text(':word', word) )
			assert( exec_add_word:bind_int(':code', code) )

			assert( assert( exec_add_word:step() ) == 'done' )
			assert( exec_add_word:reset() )
		end

		assert( exec_add_word:finalize() )
	end

	do
		local exec_add_script = assert(db:prepare [[

			INSERT INTO script (version, compiled, data)
			VALUES (:version, :compiled, :data)

		]])

		local exec_add_script_string = assert(db:prepare [[

			INSERT INTO script_string (script_dbid, idx, string)
			VALUES (:script_dbid, :idx, :string)

		]])

		local exec_add_script_import = assert(db:prepare [[

			INSERT INTO script_import (script_dbid, name, address)
			VALUES (:script_dbid, :name, :address)

		]])

		local exec_add_script_export = assert(db:prepare [[

			INSERT INTO script_export (script_dbid, name, address)
			VALUES (:script_dbid, :name, :address)

		]])

		local exec_add_script_fixup = assert(db:prepare [[

			INSERT INTO script_fixup (script_dbid, type, value)
			VALUES (:script_dbid, :type, :value)

		]])

		local exec_add_script_section = assert(db:prepare [[

			INSERT INTO script_section (script_dbid, name, offset)
			VALUES (:script_dbid, :name, :offset)

		]])

		local function add_script(script)
			if script == nil then
				return nil
			end
			assert( exec_add_script:bind_int(':version', script.version) )
			assert( exec_add_script:bind_blob(':compiled', script.code) )
			assert( exec_add_script:bind_blob(':data', script.data) )
			assert( assert( exec_add_script:step() ) == 'done' )
			assert( exec_add_script:reset() )

			local script_dbid = db:last_insert_rowid()

			assert( exec_add_script_string:bind_int64(':script_dbid', script_dbid) )
			for id, str in pairs(script.strings) do
				assert( exec_add_script_string:bind_int(':idx', id) )
				assert( exec_add_script_string:bind_text(':string', str) )
				assert( assert( exec_add_script_string:step() ) == 'done' )
				assert( exec_add_script_string:reset() )
			end

			assert( exec_add_script_import:bind_int64(':script_dbid', script_dbid) )
			for address, name in pairs(script.imports) do
				assert( exec_add_script_import:bind_int(':address', address) )
				assert( exec_add_script_import:bind_text(':name', name) )
				assert( assert( exec_add_script_import:step() ) == 'done' )
				assert( exec_add_script_import:reset() )
			end

			assert( exec_add_script_export:bind_int64(':script_dbid', script_dbid) )
			for name, address in pairs(script.exports) do
				assert( exec_add_script_export:bind_text(':name', name) )
				assert( exec_add_script_export:bind_int(':address', address) )
				assert( assert( exec_add_script_export:step() ) == 'done' )
				assert( exec_add_script_export:reset() )
			end

			assert( exec_add_script_fixup:bind_int64(':script_dbid', script_dbid) )
			for _, fixup in ipairs(script.fixups) do
				assert( exec_add_script_fixup:bind_int(':type', fixup.type) )
				assert( exec_add_script_fixup:bind_int(':value', fixup.value) )
				assert( assert( exec_add_script_fixup:step() ) == 'done' )
				assert( exec_add_script_fixup:reset() )
			end

			assert( exec_add_script_section:bind_int64(':script_dbid', script_dbid) )
			for _, section in ipairs(script.sections or {}) do
				assert( exec_add_script_section:bind_text(':name', section.name) )
				assert( exec_add_script_section:bind_int(':offset', section.offset) )
				assert( assert( exec_add_script_section:step() ) == 'done' )
				assert( exec_add_script_section:reset() )
			end

			return script_dbid
		end

		do
			local global_script_dbid = add_script(game.global_script)
			local dialog_script_dbid = add_script(game.dialog_script)

			local exec_set_global_script = assert(db:prepare [[

				UPDATE game 
				SET global_script = :global_script_dbid, dialog_script = :dialog_script_dbid
				WHERE dbid = :game_dbid

			]])
			assert( exec_set_global_script:bind_int64(':global_script_dbid', global_script_dbid) )
			if dialog_script_dbid == nil then
				assert( exec_set_global_script:bind_null(':dialog_script_dbid') )
			else
				assert( exec_set_global_script:bind_int64(':dialog_script_dbid', dialog_script_dbid) )
			end
			assert( exec_set_global_script:bind_int64(':game_dbid', game_dbid) )

			assert( assert( exec_set_global_script:step() ) == 'done' )
			assert( exec_set_global_script:finalize() )
		end

		if game.module_scripts then
			local exec_add_module_script = assert(db:prepare [[

				INSERT INTO game_module_script (game_dbid, script_dbid) VALUES (:game_dbid, :script_dbid)

			]])
			assert( exec_add_module_script:bind_int64(':game_dbid', game_dbid) )
			for i, module_script in ipairs(game.module_scripts) do
				local module_script_dbid = add_script(module_script)
				assert( exec_add_module_script:bind_int64(':script_dbid', module_script_dbid) )
				assert( assert( exec_add_module_script:step() ) == 'done' )
				assert( exec_add_module_script:reset() )
			end
			assert( exec_add_module_script:finalize() )
		end

		assert( exec_add_script:finalize() )
		assert( exec_add_script_string:finalize() )
		assert( exec_add_script_import:finalize() )
		assert( exec_add_script_export:finalize() )
		assert( exec_add_script_fixup:finalize() )
		assert( exec_add_script_section:finalize() )
	end

	do
		local exec_add_view = assert(db:prepare [[

			INSERT INTO anim_view (game_dbid, idx, script_name) VALUES (:game_dbid, :idx, :script_name)

		]])

		local exec_add_loop = assert(db:prepare [[

			INSERT INTO anim_loop (view_dbid, idx, run_next) VALUES (:view_dbid, :idx, :run_next)

		]])

		local exec_add_frame = assert(db:prepare [[

			INSERT INTO anim_frame (loop_dbid, idx, x_offset, y_offset, speed, flipped)
			VALUES (:loop_dbid, :idx, :x_offset, :y_offset, :speed, :flipped)

		]])

		assert( exec_add_view:bind_int64(':game_dbid', game_dbid) )

		for _, view in ipairs(game.views) do
			assert( exec_add_view:bind_int(':idx', view.id) )
			assert( exec_add_view:bind_text(':script_name', view.script_name) )
			assert( assert( exec_add_view:step() ) == 'done' )
			assert( exec_add_view:reset() )
			local view_dbid = db:last_insert_rowid()

			assert( exec_add_loop:bind_int64(':view_dbid', view_dbid) )

			for _, loop in ipairs(view.loops) do
				assert( exec_add_loop:bind_int(':idx', loop.id) )
				assert( exec_add_loop:bind_bool(':run_next', loop.run_next) )
				assert( assert(exec_add_loop:step() ) == 'done' )
				assert( exec_add_loop:reset() )
				local loop_dbid = db:last_insert_rowid()

				assert( exec_add_frame:bind_int64(':loop_dbid', loop_dbid) )

				for _, frame in ipairs(loop.frames) do
					assert( exec_add_frame:bind_int(':idx', frame.id) )
					assert( exec_add_frame:bind_int(':x_offset', frame.x_offset) )
					assert( exec_add_frame:bind_int(':y_offset', frame.y_offset) )
					assert( exec_add_frame:bind_int(':speed', frame.speed) )
					assert( exec_add_frame:bind_bool(':flipped', frame.flipped) )
					assert( assert( exec_add_frame:step() ) == 'done' )
					assert( exec_add_frame:reset() )
				end
			end
		end

		assert( exec_add_view:finalize() )
		assert( exec_add_loop:finalize() )
		assert( exec_add_frame:finalize() )
	end

	do
		local exec_add_lipsync = assert(db:prepare [[

			INSERT INTO lipsync_letter (game_dbid, idx, letter)
			VALUES (:game_dbid, :idx, :letter)

		]])
		assert( exec_add_lipsync:bind_int64(':game_dbid', game_dbid) )

		for letter, frame_number in pairs(game.lipsync.letter_frames) do
			assert( exec_add_lipsync:bind_int(':idx', frame_number) )
			assert( exec_add_lipsync:bind_text(':letter', letter) )
			assert( assert( exec_add_lipsync:step() ) == 'done' )
			assert( exec_add_lipsync:reset() )
		end

		assert( exec_add_lipsync:finalize() )
	end

	do
		local exec_add_message = assert(db:prepare [[

			INSERT INTO message (game_dbid, idx, message_content)
			VALUES (:game_dbid, :idx, :message_content)

		]])
		assert( exec_add_message:bind_int64(':game_dbid', game_dbid) )

		for message_number, message_content in pairs(game.messages) do
			assert( exec_add_message:bind_int(':idx', message_number) )
			assert( exec_add_message:bind_text(':message_content', message_content) )
			assert( assert( exec_add_message:step() ) == 'done' )
			assert( exec_add_message:reset() )
		end

		assert( exec_add_message:finalize() )
	end

	do
		local exec_add_dialog = assert(db:prepare [[

			INSERT INTO dialog (game_dbid, idx, script_name, show_parser, entry_point)
			VALUES (:game_dbid, :idx, :script_name, :show_parser, :entry_point)

		]])

		local exec_add_option = assert(db:prepare [[

			INSERT INTO dialog_option (dialog_dbid, idx, text, enabled, say, entry_point)
			VALUES (:dialog_dbid, :idx, :text, :enabled, :say, :entry_point)

		]])

		assert( exec_add_dialog:bind_int64(':game_dbid', game_dbid) )

		for _, dialog in ipairs(game.dialogs) do
			assert( exec_add_dialog:bind_int(':idx', dialog.id) )
			assert( exec_add_dialog:bind_text(':script_name', dialog.script_name) )
			assert( exec_add_dialog:bind_bool(':show_parser', dialog.show_parser) )
			assert( exec_add_dialog:bind_int(':entry_point', dialog.entry_point) )
			assert( assert( exec_add_dialog:step() ) == 'done' )
			assert( exec_add_dialog:reset() )

			local dialog_dbid = db:last_insert_rowid()

			exec_add_option:bind_int64(':dialog_dbid', dialog_dbid)

			for _, option in ipairs(dialog.options) do
				assert( exec_add_option:bind_int(':idx', option.id) )
				assert( exec_add_option:bind_text(':text', option.text) )
				assert( exec_add_option:bind_bool(':enabled', option.enabled) )
				assert( exec_add_option:bind_bool(':say', option.say) )
				assert( exec_add_option:bind_int(':entry_point', option.entry_point) )
				assert( assert( exec_add_option:step() ) == 'done' )
				assert( exec_add_option:reset() )
			end
		end

		assert( exec_add_dialog:finalize() )
		assert( exec_add_option:finalize() )
	end

	do
		local exec_add_interface = assert(db:prepare [[

			INSERT INTO gui_interface (
				game_dbid, idx, script_name,
				x, y, width, height, z_order,
				background_color, background_sprite, border_color, transparency,
				clickable, initially_shown, always_shown, pause_while_shown, popup_mouse_y,
				on_click
			)
			VALUES (
				:game_dbid, :idx, :script_name,
				:x, :y, :width, :height, :z_order,
				:background_color, :background_sprite, :border_color, :transparency,
				:clickable, :initially_shown, :always_shown, :pause_while_shown, :popup_mouse_y,
				:on_click
			)

		]])

		assert( exec_add_interface:bind_int64(':game_dbid', game_dbid) )

		local exec_add_control = assert(db:prepare [[

			INSERT INTO gui_control (
				interface_dbid, script_name,
				x, y, width, height, z_order,
				enabled, visible, clickable, translated
			)
			VALUES (
				:interface_dbid, :script_name,
				:x, :y, :width, :height, :z_order,
				:enabled, :visible, :clickable, :translated
			)

		]])

		local exec_add_button = assert(db:prepare [[

			INSERT INTO gui_button (
				control_dbid,
				text, text_color, font, horizontal_align, vertical_align,
				normal_sprite, mouseover_sprite, pushed_sprite,
				is_default, clip,
				on_click, set_cursor_mode
			) VALUES (
				:control_dbid,
				:text, :text_color, :font, :horizontal_align, :vertical_align,
				:normal_sprite, :mouseover_sprite, :pushed_sprite,
				:is_default, :clip,
				:on_click, :set_cursor_mode
			)

		]])

		local exec_add_label = assert(db:prepare [[

			INSERT INTO gui_label (
				control_dbid,
				text, text_color, font,
				horizontal_align, vertical_align
			)
			VALUES (
				:control_dbid,
				:text, :text_color, :font,
				:horizontal_align, :vertical_align
			)

		]])

		local exec_add_inventory_window = assert(db:prepare [[

			INSERT INTO gui_inventory_window (control_dbid, item_width, item_height, for_character)
			VALUES (:control_dbid, :item_width, :item_height, :for_character)

		]])

		local exec_add_slider = assert(db:prepare [[

			INSERT INTO gui_slider (
				control_dbid,
				min_value, max_value, default_value,
				handle_sprite, handle_offset, background_sprite
			)
			VALUES (
				:control_dbid,
				:min_value, :max_value, :default_value,
				:handle_sprite, :handle_offset, :background_sprite
			)

		]])

		local exec_add_text_box = assert(db:prepare [[

			INSERT INTO gui_text_box (control_dbid, default_text, font, text_color, use_border)
			VALUES (:control_dbid, :default_text, :font, :text_color, :use_border)

		]])

		local exec_add_list_box = assert(db:prepare [[

			INSERT INTO gui_list_box (
				control_dbid,
				font, text_color, selected_text_color,
				use_border,
				use_arrows,
				horizontal_align,
				background_color, selected_background_color
			)
			VALUES (
				:control_dbid,
				:font, :text_color, :selected_text_color,
				:use_border,
				:use_arrows,
				:horizontal_align,
				:background_color, :selected_background_color
			)

		]])


		for _, interface in ipairs(game.gui.interfaces) do
			assert( exec_add_interface:bind_int(':idx', interface.id) )
			assert( exec_add_interface:bind_text(':script_name', interface.script_name) )
			assert( exec_add_interface:bind_int(':x', interface.x) )
			assert( exec_add_interface:bind_int(':y', interface.y) )
			assert( exec_add_interface:bind_int(':width', interface.width) )
			assert( exec_add_interface:bind_int(':height', interface.height) )
			assert( exec_add_interface:bind_int(':z_order', interface.z_order) )
			assert( exec_add_interface:bind_int(':background_color', interface.background_color) )
			assert( exec_add_interface:bind_int(':background_sprite', interface.background_sprite) )
			assert( exec_add_interface:bind_int(':border_color', interface.border_color) )
			assert( exec_add_interface:bind_int(':transparency', interface.transparency) )
			assert( exec_add_interface:bind_bool(':clickable', interface.clickable) )
			assert( exec_add_interface:bind_bool(':initially_shown', interface.initially_shown) )
			assert( exec_add_interface:bind_bool(':always_shown', interface.always_shown) )
			assert( exec_add_interface:bind_bool(':pause_while_shown', interface.pause_while_shown) )
			if interface.popup_mouse_y == nil then
				assert( exec_add_interface:bind_null(':popup_mouse_y') )
			else
				assert( exec_add_interface:bind_int(':popup_mouse_y', interface.popup_mouse_y) )
			end
			assert( exec_add_interface:bind_text(':on_click', interface.on_click) )
			assert( assert( exec_add_interface:step() ) == 'done' )
			assert( exec_add_interface:reset() )

			local interface_dbid = db:last_insert_rowid()

			assert( exec_add_control:bind_int64(':interface_dbid', interface_dbid) )

			for _, control in ipairs(interface.controls) do
				local control_type = control.type
				control = game.gui[control_type:gsub('x$', 'xe')..'s'].byId[control.id]

				assert( exec_add_control:bind_text(':script_name', control.script_name) )
				assert( exec_add_control:bind_int(':x', control.x) )
				assert( exec_add_control:bind_int(':y', control.y) )
				assert( exec_add_control:bind_int(':width', control.width) )
				assert( exec_add_control:bind_int(':height', control.height) )
				assert( exec_add_control:bind_int(':z_order', control.z_order) )
				assert( exec_add_control:bind_bool(':enabled', control.enabled) )
				assert( exec_add_control:bind_bool(':visible', control.visible) )
				assert( exec_add_control:bind_bool(':clickable', control.clickable) )
				assert( exec_add_control:bind_bool(':translated', control.translated) )
				assert( assert( exec_add_control:step() ) == 'done' )
				assert( exec_add_control:reset() )

				local control_dbid = db:last_insert_rowid()

				if control_type == 'button' then
					assert( exec_add_button:bind_int64(':control_dbid', control_dbid) )
					assert( exec_add_button:bind_text(':text', control.text) )
					assert( exec_add_button:bind_int(':text_color', control.text_color) )
					assert( exec_add_button:bind_int(':font', control.font) )
					assert( exec_add_button:bind_text(':horizontal_align', control.horizontal_align) )
					assert( exec_add_button:bind_text(':vertical_align', control.vertical_align) )
					if control.normal_sprite == nil then
						assert( exec_add_button:bind_null(':normal_sprite') )
					else
						assert( exec_add_button:bind_int(':normal_sprite', control.normal_sprite) )
					end
					if control.mouseover_sprite == nil then
						assert( exec_add_button:bind_null(':mouseover_sprite') )
					else
						assert( exec_add_button:bind_int(':mouseover_sprite', control.mouseover_sprite) )
					end
					if control.pushed_sprite == nil then
						assert( exec_add_button:bind_null(':pushed_sprite') )
					else
						assert( exec_add_button:bind_int(':pushed_sprite', control.pushed_sprite) )
					end
					assert( exec_add_button:bind_bool(':is_default', control.is_default) )
					assert( exec_add_button:bind_bool(':clip', control.clip) )
					assert( exec_add_button:bind_text(':on_click', control.on_click) )
					if control.set_cursor_mode == nil then
						assert( exec_add_button:bind_null(':set_cursor_mode') )
					else
						assert( exec_add_button:bind_int(':set_cursor_mode', control.set_cursor_mode) )
					end
					assert( assert( exec_add_button:step() ) == 'done' )
					assert( exec_add_button:reset() )
				elseif control_type == 'label' then
					assert( exec_add_label:bind_int64(':control_dbid', control_dbid) )
					assert( exec_add_label:bind_text(':text', control.text) )
					assert( exec_add_label:bind_int(':text_color', control.text_color) )
					assert( exec_add_label:bind_int(':font', control.font) )
					assert( exec_add_label:bind_text(':horizontal_align', control.horizontal_align) )
					assert( exec_add_label:bind_text(':vertical_align', control.vertical_align) )
					assert( assert( exec_add_label:step() ) == 'done' )
					assert( exec_add_label:reset() )
				elseif control_type == 'inventory_window' then
					assert( exec_add_inventory_window:bind_int64(':control_dbid', control_dbid) )
					assert( exec_add_inventory_window:bind_int(':item_width', control.item_width) )
					assert( exec_add_inventory_window:bind_int(':item_height', control.item_height) )
					-- TODO: use db rowid instead of runtime id
					if control.for_character == nil then
						assert( exec_add_inventory_window:bind_null(':for_character') )
					else
						assert( exec_add_inventory_window:bind_int(':for_character', control.for_character) )
					end
					assert( assert( exec_add_inventory_window:step() ) == 'done' )
					assert( exec_add_inventory_window:reset() )
				elseif control_type == 'slider' then
					assert( exec_add_slider:bind_int64(':control_dbid', control_dbid) )
					assert( exec_add_slider:bind_int(':min_value', control.min_value) )
					assert( exec_add_slider:bind_int(':max_value', control.max_value) )
					assert( exec_add_slider:bind_int(':default_value', control.default_value) )
					if control.handle_sprite == nil then
						assert( exec_add_slider:bind_null(':handle_sprite') )
					else
						assert( exec_add_slider:bind_int(':handle_sprite', control.handle_sprite) )
					end
					assert( exec_add_slider:bind_int(':handle_offset', control.handle_offset) )
					if control.background_sprite == nil then
						assert( exec_add_slider:bind_null(':background_sprite') )
					else
						assert( exec_add_slider:bind_int(':background_sprite', control.background_color) )
					end
					assert( assert(exec_add_slider:step() ) == 'done' )
					assert( exec_add_slider:reset() )
				elseif control_type == 'text_box' then
					assert( exec_add_text_box:bind_int64(':control_dbid', control_dbid) )
					assert( exec_add_text_box:bind_text(':default_text', control.default_text) )
					assert( exec_add_text_box:bind_int(':font', control.font) )
					assert( exec_add_text_box:bind_int(':text_color', control.text_color) )
					assert( exec_add_text_box:bind_bool(':use_border', control.use_border) )
					assert( assert( exec_add_text_box:step() ) == 'done' )
					assert( exec_add_text_box:reset() )
				elseif control_type == 'list_box' then
					assert( exec_add_list_box:bind_int64(':control_dbid', control_dbid) )
					assert( exec_add_list_box:bind_int(':font', control.font) )
					assert( exec_add_list_box:bind_int(':text_color', control.text_color) )
					assert( exec_add_list_box:bind_int(':background_color', control.background_color) )
					assert( exec_add_list_box:bind_int(':selected_text_color', control.selected_text_color) )
					assert( exec_add_list_box:bind_int(':selected_background_color', control.selected_background_color) )
					assert( exec_add_list_box:bind_bool(':use_border', control.use_border) )
					assert( exec_add_list_box:bind_bool(':use_arrows', control.use_arrows) )
					assert( exec_add_list_box:bind_text(':horizontal_align', control.horizontal_align) )
					assert( assert( exec_add_list_box:step() ) == 'done' )
					assert( exec_add_list_box:reset() )
				end
			end
		end

		exec_add_interface:finalize()
		exec_add_control:finalize()
		exec_add_button:finalize()
		exec_add_label:finalize()
		exec_add_inventory_window:finalize()
		exec_add_slider:finalize()
	end

	if game.plugins and game.plugins[1] then
		local exec_add_plugin = assert(db:prepare [[

			INSERT INTO plugin (game_dbid, name, editor_only, data)
			VALUES (:game_dbid, :name, :editor_only, :data)

		]])

		assert( exec_add_plugin:bind_int64(':game_dbid', game_dbid) )

		for _, plugin in ipairs(game.plugins) do
			assert( exec_add_plugin:bind_text(':name', plugin.name) )
			assert( exec_add_plugin:bind_bool(':editor_only', plugin.editor_only) )
			assert( exec_add_plugin:bind_blob(':data', plugin.data) )

			assert( assert( exec_add_plugin:step() ) == 'done' )
			assert( exec_add_plugin:reset() )
		end

		assert( exec_add_plugin:finalize() )
	end

	if game.property_schema then
		local exec_add_schema = assert(db:prepare [[

			INSERT INTO property_schema (game_dbid, name, description, value_type, default_value)
			VALUES (:game_dbid, :name, :description, :value_type, :default_value)

		]])

		assert( exec_add_schema:bind_int64(':game_dbid', game_dbid) )

		for _, property in ipairs(game.property_schema) do
			assert( exec_add_schema:bind_text(':name', property.name) )
			assert( exec_add_schema:bind_text(':description', property.description) )
			assert( exec_add_schema:bind_text(':value_type', property.value_type) )
			assert( exec_add_schema:bind_text(':default_value', property.default_value) )

			assert( assert( exec_add_schema:step() ) == 'done' )
			assert( exec_add_schema:reset() )
		end

		assert( exec_add_schema:finalize() )
		exec_add_schema = nil

		local exec_add_charprop = assert(db:prepare [[

			INSERT INTO character_property (character_dbid, name, value)
			SELECT dbid, :name, :value
			FROM character
			WHERE idx = :character_idx AND game_dbid = :game_dbid

		]])

		assert( exec_add_charprop:bind_int64(':game_dbid', game_dbid) )

		for _, character in ipairs(game.characters) do
			assert( exec_add_charprop:bind_int(':character_idx', character.id) )
			for name, value in pairs(character.properties) do
				assert( exec_add_charprop:bind_text(':name', name) )
				assert( exec_add_charprop:bind_text(':value', value) )
				assert( assert( exec_add_charprop:step() ) == 'done' )
				assert( exec_add_charprop:reset() )
			end
		end

		assert( exec_add_charprop:finalize() )
		exec_add_charprop = nil

		local exec_add_itemprop = assert(db:prepare [[

			INSERT INTO inventory_item_property (item_dbid, name, value)
			SELECT dbid, :name, :value
			FROM inventory_item
			WHERE idx = :item_idx AND game_dbid = :game_dbid

		]])

		assert( exec_add_itemprop:bind_int64(':game_dbid', game_dbid) )

		for _, item in ipairs(game.inventory) do
			assert( exec_add_itemprop:bind_int(':item_idx', item.id) )
			for name, value in pairs(item.properties) do
				assert( exec_add_itemprop:bind_text(':name', name) )
				assert( exec_add_itemprop:bind_text(':value', value) )
				assert( assert( exec_add_itemprop:step() ) == 'done' )
				assert( exec_add_itemprop:reset() )
			end
		end

		assert( exec_add_itemprop:finalize() )
	end

	if game.audio then
		local exec_add_audio_type = assert(db:prepare [[

			INSERT INTO audio_type (
				game_dbid, idx, reserved_channels, reduce_volume_for_speech, crossfade_speed
			)
			VALUES (
				:game_dbid, :idx, :reserved_channels, :reduce_volume_for_speech, :crossfade_speed
			)

		]])

		assert( exec_add_audio_type:bind_int64(':game_dbid', game_dbid) )

		local audio_type_rtid_to_dbid = {}

		for _, t in ipairs(game.audio.types) do
			assert( exec_add_audio_type:bind_int(':idx', t.id) )
			assert( exec_add_audio_type:bind_int(':reserved_channels', t.reserved_channels) )
			assert( exec_add_audio_type:bind_int(':reduce_volume_for_speech', t.reduce_volume_for_speech) )
			assert( exec_add_audio_type:bind_int(':crossfade_speed', t.crossfade_speed) )
			assert( assert( exec_add_audio_type:step() ) == 'done' )
			assert( exec_add_audio_type:reset() )

			audio_type_rtid_to_dbid[t.id] = db:last_insert_rowid()
		end

		assert( exec_add_audio_type:finalize() )
		exec_add_audio_type = nil

		local exec_add_audio_clip = assert(db:prepare [[

			INSERT INTO audio_clip (
				game_dbid, idx, type_dbid, script_name, file_name, file_type,
				default_repeat, default_priority, default_volume
			)
			VALUES (
				:game_dbid, :idx, :type_dbid, :script_name, :file_name, :file_type,
				:default_repeat, :default_priority, :default_volume
			)

		]])

		assert( exec_add_audio_clip:bind_int64(':game_dbid', game_dbid) )

		for _, clip in ipairs(game.audio.clips) do
			assert( exec_add_audio_clip:bind_int(':idx', clip.id) )
			assert( exec_add_audio_clip:bind_int64(':type_dbid', audio_type_rtid_to_dbid[clip.type]) )
			assert( exec_add_audio_clip:bind_text(':script_name', clip.script_name) )
			assert( exec_add_audio_clip:bind_text(':file_name', clip.file_name) )
			assert( exec_add_audio_clip:bind_text(':file_type', clip.file_type) )
			assert( exec_add_audio_clip:bind_int(':default_repeat', clip.default_repeat) )
			assert( exec_add_audio_clip:bind_int(':default_priority', clip.default_priority) )
			assert( exec_add_audio_clip:bind_int(':default_volume', clip.default_volume) )
			assert( assert( exec_add_audio_clip:step() ) == 'done' )
			assert( exec_add_audio_clip:reset() )

			if clip == game.audio.sound_on_score then
				local clip_dbid = db:last_insert_rowid()
				local exec_set_score_sound = assert(db:prepare [[

					UPDATE game SET sound_on_score = :clip_dbid
					WHERE dbid = :game_dbid

				]])
				assert( exec_set_score_sound:bind_int64(':clip_dbid', clip_dbid) )
				assert( exec_set_score_sound:bind_int64(':game_dbid', game_dbid) )
				assert( assert( exec_set_score_sound:step() ) == 'done' )
				assert( exec_set_score_sound:finalize() )
			end
		end

		assert( exec_add_audio_clip:finalize() )
	end

	if game.rooms then
		local exec_add_room = assert(db:prepare [[

			INSERT INTO room (game_dbid, idx, name)
			VALUES (:game_dbid, :idx, :name)

		]])

		assert( exec_add_room:bind_int64(':game_dbid', game_dbid) )

		for _, room in ipairs(game.rooms) do
			assert( exec_add_room:bind_int(':idx', room.id) )
			assert( exec_add_room:bind_text(':name', room.name) )

			assert( assert( exec_add_room:step() ) == 'done' )
			assert( exec_add_room:reset() )
		end

		assert( exec_add_room:finalize() )
	end
end

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

local function update_list_ids(list)
	list.byId = {}
	for _, item in ipairs(list) do
		list.byId[item.id] = item
	end
end

function reader_proto:game(game)
	assert(self:expectBlob 'Adventure Creator Game File v2', 'missing/invalid file signature')
	self.v = format_v( self:int32le() )

	-- TODO: somehow determine exactly when the engine version string was added
	--
	-- all I know is it was some time after the version used in
	-- "Lunchtime of the Damned"
	if self.v > v_LotD then
		game.engine_version = self:blob( self:int32le() )
	end

	do
		local base = self:pos()
		game.title = self:nullTerminated(50)
		self:align(4, base)
		local options_start = self:pos()
		game.debug_mode                 = self:bool32()
		game.score_sound                = self:int32le()
		game.walk_in_look_mode          = self:bool32()
		game.dialog_gui                 = self:int32le()
		game.anti_glide                 = self:bool32()
		game.text_window_gui            = self:int32le()
		game.dialog_gap                 = self:int32le()
		game.no_skip_text               = self:int32le()
		game.hide_gui_on_disabled       = self:bool32()
		game.always_show_text_as_speech = self:int32le()
		game.speech_type                = self:int32le()
		game.pixel_perfect              = self:bool32()
		game.no_walk_mode               = self:bool32()
		game.force_letterbox            = self:bool32()
		game.fixed_inv_cursor           = self:bool32()
		game.no_lose_inventory          = self:bool32()
		game.no_scale_fonts             = self:bool32()
		game.split_resources            = self:int32le() -- unused?
		game.rotate_chars               = self:int32le()
		game.fade_type                  = self:int32le()
		game.handle_inventory_clicks    = self:bool32()
		game.use_mouse_wheel            = self:bool32()
		game.dialog_numbered            = self:bool32()
		game.dialog_upwards             = self:bool32()
		game.crossfade_music            = self:bool32()
		game.antialias_fonts            = self:bool32()
		game.thought_gui                = self:int32le()
		game.turn_to_face               = self:bool32()
		game.text_left_to_right         = self:bool32()
		game.duplicate_inventory        = self:bool32()
		game.save_screenshot            = self:bool32()
		game.portrait_side              = self:int32le()
		game.strict_scripting           = self:bool32()
		game.left_to_right_eval         = self:bool32()
		game.compress_sprites           = self:bool32()
		game.strict_strings             = self:bool32()
		game.gui_alpha_mode             = self:int32le() -- 3 modes!
		game.run_game_during_dialog     = self:bool32()
		game.native_coordinates         = self:bool32()
		game.global_talk_anim_speed     = self:int32le()
		game.sprite_alpha               = self:int32le()

		self:pos('set', options_start + (98 * 4))
		game.no_mod_music = self:bool32()
		game.lipsync = {}
		game.lipsync.text = self:bool32()

		game.palette_uses = self:blob(256)
		game.palette      = self:blob(256 * 4)

		game.views      = list( self:int32le() )

		game.characters = list( self:int32le() )

		game.characters.player = game.characters.byId[ self:int32le() ]

		game.total_score = self:int32le()

		game.inventory = list( self:int16le() )

		self:align(4, base)

		game.dialogs = list( self:int32le() )

		game.numdlgmessage = self:int32le() -- ?

		game.fonts = list( self:int32le() )

		game.color_depth = self:int32le()

		game.target_win = self:int32le()

		game.dialog_bullet = self:int32le()

		game.hotdot = self:int16le()
		game.hotdotouter = self:int16le()

		game.uniqueid = self:int32le()

		local numgui = self:int32le() -- overwritten rather than referred to, later

		game.cursors = list( self:int32le() )
		game.default_resolution = self:int32le()
		game.lipsync.default_frame = self:int32le()
		game.invhotdotsprite = self:int32le()

		self:skip(4 * 17)

		game.messages = {}
		for i = 0, 499 do
			game.messages[i] = self:bool32()
		end

		if self:bool32() then
			game.dictionary = {}
		end
		self:skip(4 * 2) -- global script & chars
		game.load_compiled_script = self:bool32()
	end
	if self.v > v2_7_2 then
		game.guid = self:nullTerminated(40)
		game.save_extension = self:nullTerminated(20)
		game.save_folder = self:nullTerminated(50)
	end
	for _, font in ipairs(game.fonts) do
		font.flags = self:uint8()
		font.size = bit.band(font.flags, 0x3F)
		if font.size == 0 then
			font.size = 8
		end
	end
	for _, font in ipairs(game.fonts) do
		font.outline = self:int8()
		if font.outline == -10 then
			font.outline = 'auto'
		elseif font.outline < 0 then
			font.outline = nil
		end
	end
	if self.v < v2_5_6 then
		game.sprites = list( 6000 )
	else
		game.sprites = list( self:int32le() )
	end
	for _, sprite in ipairs(game.sprites) do
		sprite.flags = self:uint8()
		if bit.band(sprite.flags, SPF_640x400) == 0 then
			sprite.resolution = 'low'
		else
			sprite.resolution = 'high'
		end
		if bit.band(sprite.flags, bit.bor(SPF_ALPHACHANNEL, SPF_HADALPHACHANNEL)) ~= 0 then
			sprite.alpha = true
		end
		if bit.band(sprite.flags, SPF_TRUECOLOR) then
			sprite.bits_per_pixel = 32
		elseif bit.band(sprite.flags, SPF_HICOLOR) then
			sprite.bits_per_pixel = 16
		else
			sprite.bits_per_pixel = 8
		end
	end
	for _, item in ipairs(game.inventory) do
		if item.id == 0 then
			item.ignore = true
		end
		self:inventoryItem(item)
	end
	for _, cursor in ipairs(game.cursors) do
		self:cursor(cursor)
	end
	if self.v > v2_7_2 then
		for _, character in ipairs(game.characters) do
			character.event_handlers = {}
			self:event_handlers(character.event_handlers)

			character.on_look_at = character.event_handlers[0]
			character.on_interact = character.event_handlers[1]
			character.on_any_click = character.event_handlers[2]
			character.on_use_inventory = character.event_handlers[3]
			character.on_talk_to = character.event_handlers[4]
			character.on_pick_up = character.event_handlers[5]
			character.on_user_mode_1 = character.event_handlers[6]
			character.on_user_mode_2 = character.event_handlers[7]
		end
		for _, item in ipairs(game.inventory) do
			if not item.ignore then
				item.event_handlers = {}
				self:event_handlers(item.event_handlers)

				item.on_look_at       = item.event_handlers[0]
				item.on_interact      = item.event_handlers[1]
				item.on_other_click   = item.event_handlers[2]
				item.on_use_inventory = item.event_handlers[3]
				item.on_talk_to       = item.event_handlers[4]
			end
		end
	else
		for _, character in ipairs(game.characters) do
			character.interactions = {}
			self:interactions(character.interactions)
		end

		for _, item in ipairs(game.inventory) do
			item.interactions = {}
			self:interactions(item.interactions)
		end

		game.interaction_vars = list( self:int32le() )
		for _, interaction_var in ipairs(game.interaction_vars) do
			self:interaction_var(interaction_var)
		end
	end
	if game.dictionary then
		for i = 1, self:int32le() do
			local word = self:masked_blob( "Avis Durgan", self:int32le() )
			local id = self:int16le()
			game.dictionary[word] = id
		end
	end
	game.global_script = {}
	self:script( game.global_script )

    if self.v > v3_1_0 then
    	game.dialog_script = {}
    	self:script( game.dialog_script )
    end

    if self.v >= v2_7_0 then
    	game.module_scripts = {}
    	for i = 1, self:int32le() do
    		game.module_scripts[i] = {}
    		self:script( game.module_scripts[i] )
    	end
    end

    if self.v > v2_7_2 then
    	for _, view in ipairs(game.views) do
    		view.loops = list( self:int16le() )
    		for _, loop in ipairs(view.loops) do
    			loop.frames = list( self:int16le() )
    			loop.flags = self:int32le()
    			loop.run_next = 0 ~= bit.band(LOOPFLAG_RUNNEXTLOOP, loop.flags)
    			for _, frame in ipairs(loop.frames) do
					local base = self:pos()
    				self:anim_frame(frame, base)
    			end
    		end
    	end
    else
    	for _, view in ipairs(game.views) do
    		view.loops = list( 16 )
    		for _, loop in ipairs(view.loops) do
    			loop.frames = list( 20 )
    		end

    		local base = self:pos()

    		local used_loops = self:int16le()
    		for _, loop in ipairs(view.loops) do
    			loop.used_frames = self:int16le()
    		end
    		self:align(4, base)
    		for _, loop in ipairs(view.loops) do
    			loop.flags = self:int32le()
    			loop.run_next = 0 ~= bit.band(LOOPFLAG_RUNNEXTLOOP, loop.flags)
    		end
    		for _, loop in ipairs(view.loops) do
    			for _, frame in ipairs(loop.frames) do
    				self:anim_frame(frame, base)
    			end
    			for i = loop.used_frames+1, #loop.frames do
    				local id = loop.frames[i]
    				loop.frames[i] = nil
    				loop.frames.byId[id] = nil
    			end
    		end

    		for i = used_loops+1, #view.loops do
    			local id = view.loops[i].id
    			view.loops[i] = nil
    			view.loops.byId[id] = nil
    		end
    	end
    end

    if self.v <= v2_5_1 then
    	-- unknown data....?
    	self:skip(self:int32le() * 0x204)
    end

    for _, character in ipairs(game.characters) do
    	self:character(character, game)
    end

	-- lipsync frames
	if self.v >= v2_5_4 then
		game.lipsync.letter_frames = {}
		for frame_number = 0, MAXLIPSYNCFRAMES-1 do
			local letters = self:nullTerminated(50)
			for letter in letters:gmatch('[^/]+') do
				game.lipsync.letter_frames[letter] = frame_number
			end
		end
	end

	-- messages
	for i = 0, 499 do
		if game.messages[i] then
			local message
			if self.v >= v2_6_1 then
				local length = self:int32le()
				message = self:masked_blob('Avis Durgan', length)
			else
				message = self:nullTerminated()
			end
			game.messages[i] = message
		else
			game.messages[i] = nil
		end
	end

	-- dialogs
	do
		for _, dialog in ipairs(game.dialogs) do
			self:dialog(dialog)
		end

		if self.v <= v3_1_0 then
			for _, dialog in ipairs(game.dialogs) do
				dialog.old_script = self:blob(dialog.code_size)
				self:skip( self:int32le() ) -- encrypted text script?
			end
			if self.v > v2_6_0 then
				game.speech_lines = {}
				local next_id = 0
				while true do
					local line_len = self:int32le()
					if line_len == bit.tobit(0xcafebeef) then
						-- gui magic
						self:pos('cur', -4)
						break
					end
					error 'TODO'
					speech_lines[next_id] = self:masked_blob('Avis Durgan', line_len)
					next_id = next_id + 1
				end
			else
				error 'TODO'
			end
		end
	end

	-- gui
	do
		self:inject 'ags:project.binary.gui'
		game.gui = {}
		self:gui_section(game.gui)
	end

	-- plugins
	if self.v >= v2_6_0 then
		assert(self:int32le() == 1, 'unsupported plugin data version')
		game.plugins = list( self:int32le() )
		for _, plugin in ipairs(game.plugins) do
			plugin.name = self:nullTerminated()
			plugin.editor_only = (plugin.name:sub(-1) == '!')
			plugin.data = self:blob( self:int32le() )
		end
	end

	-- custom properties & script names for other things
	if self.v >= v2_6_0 then
		game.property_schema = {}
		self:property_schema(game.property_schema)

		for _, character in ipairs(game.characters) do
			character.properties = {}
			self:properties(character.properties)
		end

		for _, item in ipairs(game.inventory) do
			item.properties = {}
			self:properties(item.properties)
		end

		for _, view in ipairs(game.views) do
			view.script_name = self:nullTerminated()
			if view.script_name == '' then
				view.script_name = nil
			end
		end

		for _, item in ipairs(game.inventory) do
			item.script_name = self:nullTerminated()
		end

		for _, dialog in ipairs(game.dialogs) do
			dialog.script_name = self:nullTerminated()
		end
	end

	-- audio
	if self.v >= v3_2_0 then
		game.audio = {}
		self:audio_section(game.audio)
	end

	-- room names (debug only)
	if self.v >= v3_0_1 and game.debug_mode then
		game.rooms = {}
		for i = 1, self:int32le() do
			local id = self:int32le()
			local name = self:nullTerminated()
			game.rooms[i] = {id=id, name=name}
		end
	end
end

function reader_proto:anim_frame(frame, base)
	frame.sprite = self:int32le()
	frame.x_offset = self:int16le()
	frame.y_offset = self:int16le()
	frame.speed = self:int16le()
	self:align(4, base)
	frame.flags = self:int32le()
	frame.flipped = 0 ~= bit.band(VFLG_FLIPSPRITE, frame.flags)
	frame.sound = self:int32le()
	self:skip(4 * 2) -- reserved int[2]
end

function reader_proto:interactions(interactions)
	if self:int32le() ~= 1 then
		interactions.ignore = true
		return
	end
	interactions.events = list( self:int32le() )
	for _, event in ipairs(interactions.events) do
		event.type = self:int32le()
	end
	for _, event in ipairs(interactions.events) do
		if self:bool32() then
			event.commands = {}
		end
	end
	for _, event in ipairs(interactions.events) do
		if event.commands then
			self:interaction_commands(event.commands)
			local buf = {}
			for i, command in ipairs(event.commands) do
				if i > 0 then
					buf[#buf+1] = '\n'
				end
				self:append_interaction_command(buf, command, '')
			end
			-- TODO: store this
			event.converted_script = table.concat(buf)
		end
	end
end

local val_type_names = {
	[1] = 'int';
	[2] = 'var';
	[3] = 'boolean';
	[4] = 'character';
}

local command_type_info = {
	[0] = {'no-op'};
	[1] = {'run-script', 'int'};
	[2] = {'add-score-once', 'int'};
	[3] = {'give-score', 'int'};
	[4] = {'display-message', 'int'};
	[5] = {'play-music', 'int'};
	[6] = {'stop-music'};
	[7] = {'play-sound', 'int'};
	[8] = {'play-flic', 'int'};
	[9] = {'run-dialog', 'int'};
	[10] = {'enable-dialog-option', 'int', 'int'};
	[11] = {'disable-dialog-option', 'int', 'int'};
	[12] = {'go-to-room', 'int', 'int', stop=true};
	[13] = {'add-inventory', 'int'};
	[14] = {'move-object', 'int', 'int', 'int', 'int'}; -- 4th: speed
	[15] = {'object-off', 'int'};
	[16] = {'object-on', 'int'};
	[17] = {'set-object-view', 'int', 'int'};
	[18] = {'animate-object', 'int', 'int', 'int'};
	[19] = {'move-character', 'int', 'int', 'int', 'int'};
	[20] = {'if-active-inv', 'int', children=true};
	[21] = {'if-carrying-inv', 'int', children=true};
	[22] = {'if-character-moving', 'int', children=true};
	[23] = {'if-equal', 'int', children=true};
	[24] = {'stop-moving', 'int'};
	[25] = {'go-to-room-at', 'int', 'int', 'int', stop=true};
	[26] = {'npc-to-room', 'int', 'int'};
	[27] = {'set-character-view', 'int', 'int'};
	[28] = {'release-character-view', 'int'};
	[29] = {'follow-character', 'int', 'int'};
	[30] = {'stop-following', 'int'};
	[31] = {'disable-hotspot', 'int'};
	[32] = {'enable-hotspot', 'int'};
	[33] = {'set-variable-value', 'int', 'int'};
	[34] = {'run-animation', 'int', 'int', 'int'};
	[35] = {'quick-animation', 'int', 'int', 'int', 'int'};
	[36] = {'set-idle-animation', 'int', 'int', 'int'};
	[37] = {'disable-idle-animation', 'int'};
	[38] = {'lose-inventory', 'int'};
	[39] = {'show-gui', 'int'};
	[40] = {'hide-gui', 'int'};
	[41] = {'stop-running-commands', stop=true};
	[42] = {'face-location', 'int', 'int', 'int'};
	[43] = {'wait', 'int'};
	[44] = {'change-character-view', 'int', 'int'};
	[45] = {'if-player-is', 'int', children=true};
	[46] = {'if-cursor-mode', 'int', children=true};
	[47] = {'if-visited-room', 'int', children=true};
}

function reader_proto:interaction_commands(commands)
	local count = self:int32le()
	commands.times_run = self:int32le()

	commands.byId = {}
	for i = 1, count do
		local command = {}

		self:skip(4) -- vtbl ptr
		command.type = self:int32le()

		command.args = list(5)
		for _, arg in ipairs(command.args) do
			local base = self:pos()
			arg.type = self:uint8()
			self:align(4, base)
			arg.val = self:int32le()
			arg.extra = self:int32le()

			arg.type = val_type_names[arg.type] or tostring(arg.type)
		end

		if self:bool32() then
			command.children = {}
		end
		self:skip(4) -- parent ptr

		commands[i] = command
		commands.byId[i-1] = command
	end

	for _, command in ipairs(commands) do
		if command.children then
			self:interaction_commands(command.children)
		end
	end
end

function reader_proto:append_interaction_command(buf, command, indent)
	indent = indent or ''
	local info = command_type_info[command.type]
	buf[#buf+1] = indent .. info[1]
	for i = 2, #info do
		if i > 2 then
			buf[#buf+1] = ', '
		else
			buf[#buf+1] = ' '
		end
		buf[#buf+1] = tostring(command.args[i-1].val)
	end
	if info.children then
		buf[#buf+1] = '\n' .. indent .. '{'
		local sub_indent = indent  .. '\t'
		for _, child in ipairs(command.children or {}) do
			self:append_interaction_command(buf, child, sub_indent)
		end
		buf[#buf+1] = '\n' .. indent .. '}'
	end
end

function reader_proto:interaction_var(interaction_var)
	interaction_var.name = self:nullTerminated(23)
	interaction_var.type = self:int8()
	interaction_var.value = self:int32le()
end

function reader_proto:audio_section(audio)
	audio.types = list( self:int32le() )
	for _, t in ipairs(audio.types) do
		self:audio_type(t)
	end
	update_list_ids(audio.types)

	audio.clips = list( self:int32le() )
	for _, clip in ipairs(audio.clips) do
		self:audio_clip(clip)
	end
	update_list_ids(audio.clips)

	audio.sound_on_score = audio.clips.byId[ self:int32le() ]
end

function reader_proto:audio_type(t)
	t.id                       = self:int32le()
	t.reserved_channels        = self:int32le()
	t.reduce_volume_for_speech = self:int32le()
	t.crossfade_speed          = self:int32le()
	self:skip(4) -- reserved int[1]
end

local file_type_names = {
	[1] = 'ogg';
	[2] = 'mp3';
	[3] = 'wav';
	[4] = 'voc';
	[5] = 'midi';
	[6] = 'mod';
}

function reader_proto:audio_clip(clip)
	local base = self:pos()

	--clip.id               = self:int32le()
	self:skip(4)
	clip.script_name      = self:nullTerminated(30)
	clip.file_name        = self:nullTerminated(15)
	clip.bundling_type    = self:uint8()
	clip.type             = self:uint8()
	clip.file_type        = self:uint8()

	clip.file_type = file_type_names[clip.file_type] or tostring(clip.file_type)

	clip.default_repeat   = self:uint8()	
	self:align(2, base)
	clip.default_priority = self:int16le()
	clip.default_volume   = self:int16le()
	self:align(4, base)
	self:skip(4) -- reserved int[1]
end

local PROP_TYPE_BOOL   = 1
local PROP_TYPE_INT    = 2
local PROP_TYPE_STRING = 3

function reader_proto:property_schema(schema)
	assert(self:int32le() == 1, 'unsupported property system version')
	for i = 1, self:int32le() do
		local property = {}
		property.name = self:nullTerminated()
		property.description = self:nullTerminated()
		property.default_value = self:nullTerminated()
		local type_code = self:int32le()
		if type_code == PROP_TYPE_BOOL then
			property.value_type = 'boolean'
		elseif type_code == PROP_TYPE_STRING then
			property.value_type = 'string'
		elseif type_code == PROP_TYPE_INT then
			property.value_type = 'integer'
		else
			property.value_type = tostring(type_code)
		end
		schema[i] = property
	end
end

function reader_proto:properties(properties)
	assert(self:int32le() == 1, 'unsupported property system version')
	for i = 1, self:int32le() do
		local name = self:nullTerminated()
		local value = self:nullTerminated()
		properties[name] = value
	end
end

local DFLG_ON = 1  -- currently enabled
local DFLG_OFFPERM = 2  -- off forever (can't be trurned on)
local DFLG_NOREPEAT = 4  -- character doesn't repeat it when clicked
local DFLG_HASBEENCHOSEN = 8  -- dialog option is 'read'

local DTFLG_SHOWPARSER = 1
local MAXTOPICOPTIONS = 30

function reader_proto:dialog(dialog)
	dialog.options = list(MAXTOPICOPTIONS)
	for _, option in ipairs(dialog.options) do
		option.text = self:nullTerminated(150)
	end
	for _, option in ipairs(dialog.options) do
		option.flags = self:int32le()
		option.enabled = 0 ~= bit.band(DFLG_ON, option.flags)
		option.say = 0 == bit.band(DFLG_NOREPEAT, option.flags)
	end
	self:skip(4) -- optionscripts pointer
	for _, option in ipairs(dialog.options) do
		option.entry_point = self:int16le()
	end
	dialog.entry_point = self:int16le()
	dialog.code_size = self:int16le()
	local used_count = self:int32le()
	for i = used_count + 1, #dialog.options do
		local id = dialog.options[i].id
		dialog.options.byId[id] = nil
		dialog.options[i] = nil
	end
	dialog.flags = self:int32le()
	dialog.show_parser = 0 ~= bit.band(DTFLG_SHOWPARSER, dialog.flags)
end

function reader_proto:character(character, game)
	local base = self:pos()

	character.normal_view       = self:int32le()
	character.speech_view       = self:int32le()
	character.view              = self:int32le()
	character.room              = self:int32le()
	character.prev_room         = self:int32le()
	character.x                 = self:int32le()
	character.y                 = self:int32le()
	character.anim_delay        = self:int32le()

	character.flags             = self:int32le()

	-- NOTE: some of these are flipped (not equal to zero)
	character.ignore_scaling      = 0 ~= bit.band(CHF_MANUALSCALING, character.flags)
	character.clickable           = 0 == bit.band(CHF_NOINTERACT, character.flags)
	character.diagonal_loops      = 0 ~= bit.band(CHF_NODIAGONAL, character.flags)
	character.ignore_lighting     = 0 ~= bit.band(CHF_NOLIGHTING, character.flags)
	character.turn_before_walking = 0 == bit.band(CHF_NOTURNING, character.flags)
	character.ignore_walkbehinds  = 0 == bit.band(CHF_NOWALKBEHINDS, character.flags)
	character.solid               = 0 ~= bit.band(CHF_NOBLOCKING, character.flags)
	character.scale_speed         = 0 ~= bit.band(CHF_SCALEMOVESPEED, character.flags)
	character.blink_while_think   = 0 == bit.band(CHF_NOBLINKANDTHINK, character.flags)
	character.scale_volume        = 0 ~= bit.band(CHF_SCALEVOLUME, character.flags)
	character.link_move_to_anim   = 0 ~= bit.band(CHF_ANTIGLIDE, character.flags)

	character.following         = self:int16le()
	character.followinfo        = self:int16le()

	character.idle_view         = self:int32le()

	character.idle_time         = self:int16le()
	character.idle_left         = self:int16le()
	character.transparency      = self:int16le()
	character.baseline          = self:int16le()

	character.active_inv        = self:int32le()
	character.speech_color      = self:int32le()
	character.think_view        = self:int32le()

	character.blink_view        = self:int16le()
	character.blink_interval    = self:int16le()
	character.blink_timer       = self:int16le()
	character.blink_frame       = self:int16le()
	character.walk_speed_y      = self:int16le()
	character.pic_yoffs         = self:int16le()

	character.z                 = self:int32le()

	character.walk_anim_delay   = self:int32le()

	character.speech_anim_delay = self:int16le()
	self:skip(2)                -- reserved short[1]
	character.blocking_width    = self:int16le()
	character.blocking_height   = self:int16le()

	character.index_id          = self:int32le()

	character.pic_xoffs         = self:int16le()
	character.walk_wait_counter = self:int16le()
	character.loop              = self:int16le()
	character.frame             = self:int16le()
	character.walking           = self:int16le()
	character.animating         = self:int16le()
	character.walk_speed_x      = self:int16le()
	character.animspeed         = self:int16le()

	character.inventory = {}
	for inventory_id = 0, MAX_INV-1 do
		for i = 1, self:int16le() do
			character.inventory[#character.inventory+1] = game.inventory.byId[inventory_id]
		end
	end

	character.act_x             = self:int16le()
	character.act_y             = self:int16le()
	character.name              = self:nullTerminated(40)
	character.script_name       = self:nullTerminated(20)
	character.on                = self:bool8()

	self:align(2, base)

	if character.room < 0 then
		character.room = nil
	end

	if character.normal_view < 0 then
		character.normal_view = nil
	end

	if character.speech_view < 0 then
		character.speech_view = nil
	end

	if character.think_view < 0 then
		character.think_view = nil
	end

	if character.idle_view < 0 then
		character.idle_view = nil
	end

	if character.blink_view < 0 then
		character.blink_view = nil
	end

	if character.walk_speed_y == 0 then
		character.walk_speed_y = character.walk_speed_x
	end

    if self.v <= v2_7_2 then
    	-- e.g. EGO -> cEgo
		character.script_name = 'c' .. character.script_name:sub(1,1)
									.. character.script_name:sub(2):lower()
    end

    if self.v <= v3_1_0 and game.anti_glide then
		character.link_move_to_anim = true
    end

    if self.v < v2_5_4 then
    	character.solid = false
    end
end

function reader_proto:script(script)
	assert(self:expectBlob 'SCOM', 'bad script')
	local formatVersion = self:int32le()
	assert(formatVersion <= SCOM_VERSION, 'bad script')

	script.version = formatVersion

	local data_size     = self:int32le()
	local code_size     = self:int32le()
	local strings_size  = self:int32le()

	if data_size > 0 then
		script.data = self:blob(data_size)
	end

	-- code is an array of ints
	script.code = self:blob(4 * code_size)

	script.strings = {}
	local id = 0
	for str in self:blob(strings_size):gmatch('(%Z*)%z') do
		script.strings[id] = str
		id = id + 1
	end

	local fixup_count = self:int32le()
	if fixup_count > 0 then
		script.fixups = list(fixup_count)
		for _, fixup in ipairs(script.fixups) do
			fixup.type = self:uint8()
		end
		for _, fixup in ipairs(script.fixups) do
			fixup.value = self:int32le()
		end
	end

	script.imports = {}
	for i = 1, self:int32le() do
		local import = self:nullTerminated()
		if #import > 0 then
			local id = i-1
			script.imports[id] = import
		end
	end

	script.exports = {}
	for i = 1, self:int32le() do
		local name = self:nullTerminated()
		local address = self:int32le()
		script.exports[name] = address
	end

	if formatVersion >= 83 then
		script.sections = {}
		for i = 1, self:int32le() do
			local section = {}
			section.name = self:nullTerminated()
			section.offset = self:int32le()
			script.sections[i] = section
		end
	end

	assert(self:int32le() == bit.tobit(0xbeefcafe), 'missing end-of-script marker')
end


function reader_proto:masked_blob(mask, n)
	local buf = {}
	for i = 1, n do
		local b = self:uint8()
		local mb = mask:byte(((i-1) % #mask) + 1)
		buf[i] = string.char(bit.band(0xFF, b - mb))
	end
	return table.concat(buf)
end

function reader_proto:cursor(cursor)
	local base = self:pos()
	cursor.sprite = self:int32le()
	cursor.handle_x = self:int16le()
	cursor.handle_y = self:int16le()
	cursor.view = self:int16le()
	if cursor.view < 0 or (cursor.view == 0 and self.v < v2_7_2) then
		cursor.view = nil
	end
	self:align(2, base)
	cursor.name = self:nullTerminated(10)
	cursor.flags = self:uint8()
	cursor.animate_when_moving = 0 ~= bit.band(MCF_ANIMMOVE, cursor.flags)
	cursor.animate_over_hotspot = 0 ~= bit.band(MCF_HOTSPOT, cursor.flags)
	cursor.process_click = 0 ~= bit.band(MCF_STANDARD, cursor.flags)
	cursor.enabled = 0 == bit.band(MCF_DISABLED, cursor.flags)
	self:align(4, base)
end

function reader_proto:event_handlers(handlers)
	for i = 0, self:int32le() - 1 do
		local handler = self:nullTerminated()
		if handler ~= '' then
			handlers[i] = handler
		end
	end
end

function reader_proto:inventoryItem(item)
	local base = self:pos()
	item.name = self:nullTerminated(25)
	self:align(4, base)
	item.sprite = self:int32le()
	item.cursor_sprite = self:int32le()
	item.handle_x = self:int32le()
	item.handle_y = self:int32le()
	self:skip(5 * 4) -- reserved int[5]
	item.flags = self:uint8()
	if bit.band(1, item.flags) then
		item.startWith = true
	end
	self:align(4, base)
end

-------------------------------------------------------------------------------

return format
