
local reader_proto = {}

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

-- interactions v1 (1997)

-- interactions v2 (1999)

-- interactions v3 (2002)

function reader_proto:interactions_v3(interactions)
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
			self:v3_interaction_commands(event.commands)
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

local v3_command_info = {
	[0] = {'DoNothing'};
	[1] = {'RunScript', 'int'};
	[2] = {'Game_AddScore', 'int'};
	[3] = {'Game_AddScoreOnFirstExecution', 'int'};
	[4] = {'Game_DisplayMessage', 'int'};
	[5] = {'Game_PlayMusic', 'int'};
	[6] = {'Game_StopMusic'};
	[7] = {'Game_PlaySoundEffect', 'int'};
	[8] = {'Game_PlayFlicAnimation', 'int'};
	[9] = {'Game_RunDialog', 'int'};
	[10] = {'Game_EnableDialogOption', 'int', 'int'};
	[11] = {'Game_DisableDialogOption', 'int', 'int'};
	[12] = {'Player_GoToRoom', 'int', 'int', stop=true};
	[13] = {'Player_GiveInventory', 'int'};
	[14] = {'Object_Move', 'int', 'int', 'int', 'int'}; -- 4th: speed
	[15] = {'Object_Hide', 'int'};
	[16] = {'Object_Show', 'int'};
	[17] = {'Object_SetView', 'int', 'int'};
	[18] = {'Object_Animate', 'int', 'int', 'int'};
	[19] = {'Character_Move', 'int', 'int', 'int', 'int'};
	[20] = {'If_InventoryItemWasUsed', 'int', children=true};
	[21] = {'If_PlayerHasInventoryItem', 'int', children=true};
	[22] = {'If_CharacterIsMoving', 'int', children=true};
	[23] = {'If_VariableHasValue', 'int', children=true};
	[24] = {'Character_StopWalking', 'int'};
	[25] = {'Player_GoToRoomAtXY', 'int', 'int', 'int', stop=true};
	[26] = {'NPC_ChangeRoom', 'int', 'int'};
	[27] = {'Character_SetView', 'int', 'int'};
	[28] = {'Character_ReleaseView', 'int'};
	[29] = {'Character_FollowCharacter', 'int', 'int'};
	[30] = {'Character_StopFollowing', 'int'};
	[31] = {'Game_DisableHotspot', 'int'};
	[32] = {'Game_EnableHotspot', 'int'};
	[33] = {'Game_SetVariableValue', 'int', 'int'};
	[34] = {'Character_RunAnimationLoop', 'int', 'int', 'int'};
	[35] = {'Character_QuickAnimation', 'int', 'int', 'int', 'int'};
	[36] = {'Character_SetIdleAnimation', 'int', 'int', 'int'};
	[37] = {'Character_DisableIdleAnimation', 'int'};
	[38] = {'Player_LoseInventory', 'int'};
	[39] = {'Game_ShowGUI', 'int'};
	[40] = {'Game_HideGUI', 'int'};
	[41] = {'Stop', stop=true};
	[42] = {'Character_FaceLocation', 'int', 'int', 'int'};
	[43] = {'Wait', 'int'};
	[44] = {'Character_SetView', 'int', 'int'};
	[45] = {'If_PlayerIsCharacter', 'int', children=true};
	[46] = {'If_CursorModeIs', 'int', children=true};
	[47] = {'If_VisitedRoom', 'int', children=true};
}

local v3_type_names = {
	[1] = 'int';
	[2] = 'var';
	[3] = 'boolean';
	[4] = 'character';
}

function reader_proto:v3_interaction_commands(commands)
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

			arg.type = v3_type_names[arg.type] or tostring(arg.type)
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
			self:v3_interaction_commands(command.children)
		end
	end
end

function reader_proto:append_interaction_command(buf, command, indent)
	indent = indent or ''
	local info = v3_command_info[command.type]
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

function reader_proto:v3_local_var(local_var)
	local_var.name = self:nullTerminated(23)
	local_var.type = self:uint8()
	local_var.type = v3_type_names[local_var.type] or tostring(local_var.type)
	local_var.value = self:int32le()
end

return reader_proto
