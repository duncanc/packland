
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

local reader_proto = {}

local SCOM_VERSION = 89

local registers = {'sp', 'mar', 'ax', 'bx', 'cx', 'op', 'dx'}

function reader_proto:script(script)
	assert(self:expectBlob 'SCOM', 'unsupported script format')
	local formatVersion = self:int32le()
	assert(formatVersion <= SCOM_VERSION, 'unsupported script version')

	local data_size     = self:int32le()
	local code_size     = self:int32le()
	local strings_size  = self:int32le()

	local data    = self:blob(data_size)
	local code    = self:blob(code_size * 4) -- int array
	local strings = self:blob(strings_size)

	local fixups = {}
	for i = 1, self:int32le() do
		local fixup = {}
		self:script_fixup(fixup)
		fixups[i] = fixup
	end
	for _, fixup in ipairs(fixups) do
		fixup.offset = self:int32le()
	end

	local imports = {}
	for offset = 0, self:int32le()-1 do
		local import = self:nullTerminated()
		if import ~= '' then
			imports[#imports+1] = {name=import, offset=offset}
		end
	end

	local exports = {}
	for i = 1, self:int32le() do
		local export = {}
		self:script_export(export)
		exports[i] = export
	end

	local sections = {}
	if formatVersion >= 83 then
		for i = 1, self:int32le() do
			local section = {}
			section.name = self:nullTerminated()
			section.offset = self:int32le()
			sections[i] = section
		end
	end

	assert(self:int32le() == bit.tobit(0xbeefcafe), 'missing end-of-script marker')

	if sections[1] and sections[1].offset == 0 then
		script.name = sections[1].name
	end

	script.data_length = #data

	script.funcs = {}

	script.vars = {}

	local imports_by_offset = {}
	for _, import in ipairs(imports) do
		imports_by_offset[import.offset] = import
	end

	local fixups_by_pos = {}
	for _, fixup in ipairs(fixups) do
		if fixup.context == 'code' then
			fixups_by_pos[fixup.offset] = fixup.type
		end
	end

	for i, export in ipairs(exports) do
		if export.type == 'data' then
			script.vars[#script.vars+1] = {name=export.name, offset=export.offset}
		elseif export.type == 'function' then
			local func = {}
			func.name = export.name
			func.arg_count = export.arg_count
			script.funcs[#script.funcs+1] = func

			do
				local code_reader = R.fromstring(code)
				code_reader:inject 'bindata'
				code_reader:inject(reader_proto)

				local instructions = {}
				local by_pos = {}
				local start_sites = {{pos=export.offset, start=true}}
				local pos_labels = {}
				local next_label = 1

				repeat
					local site = table.remove(start_sites, 1)
					if not by_pos[site.pos] then
						code_reader:pos('set', 4 * site.pos)
						while true do
							local pos = code_reader:pos() / 4
							local instr = {}
							if not code_reader:instruction(instr) then
								break
							end
							instructions[#instructions+1] = instr
							instr.pos = pos
							by_pos[pos] = instr
							for i, arg_type in ipairs(instr.def.args) do
								if arg_type == 'label' then
									local label = 'label' .. next_label
									next_label = next_label + 1
									pos_labels[instr[i]] = label
									start_sites[#start_sites+1] = {pos=instr[i]}
									instr[i] = string.format('%q', label)
								elseif arg_type == 'register' then
									instr[i] = assert(registers[instr [i] ], 'unknown register')
								elseif arg_type == 'value' then
									local fixup = fixups_by_pos[pos + i]
									if fixup == 'strings' then
										instr[i] = string.format('%q', strings:match('%Z*', instr[i]+1))
									elseif fixup == 'import' then
										local import = assert(imports_by_offset[instr[i]])
										instr[i] = string.format('import(%q, %d)', import.name, import.offset)
									end
								end
							end
							if instr.def.stop then
								break
							end
						end
					end
				until start_sites[1] == nil

				if instructions[1] and instructions[1].def.name == 'LINENUM' then
					func.line_number = instructions[1][1]
					table.remove(instructions, 1)
				end

				if instructions[1] and instructions[1].def.name == 'THISBASE' and instructions[1][1] == export.offset then
					table.remove(instructions, 1)
				end

				local buf = {}
				for _, instr in ipairs(instructions) do
					local label = pos_labels[instr.pos]
					if label then
						buf[#buf+1] = ''
						buf[#buf+1] = string.format('label(%q)', label)
						buf[#buf+1] = ''
					end
					buf[#buf+1] = instr.def.name .. '(' .. table.concat(instr, ', ') .. ')'
				end
				func.instructions = table.concat(buf, '\n')

			end

		end
	end
end

local instr_info = {}

local function instr(def)
	def.args = def.args or {}
	instr_info[def.code] = def
end

instr {name='NULL', code=0}
instr {name='ADD', code=1, args={'register', 'value'}}
instr {name='SUB', code=2, args={'register', 'value'}}
instr {name='REGTOREG', code=3, args={'register', 'register'}}
instr {name='WRITELIT'        , code=4, args={'value', 'value'}}
instr {name='RET'             , code=5, args={}, stop=true}
instr {name='LITTOREG'        , code=6, args={'register', 'value'}}
instr {name='MEMREAD'         , code=7, args={'register'}}
instr {name='MEMWRITE'        , code=8, args={'register'}}
instr {name='MULREG'          , code=9, args={'register', 'register'}}
instr {name='DIVREG'          , code=10, args={'register', 'register'}}
instr {name='ADDREG'          , code=11, args={'register', 'register'}}
instr {name='SUBREG'          , code=12, args={'register', 'register'}}
instr {name='BITAND'          , code=13, args={'register', 'register'}}
instr {name='BITOR'           , code=14, args={'register', 'register'}}
instr {name='ISEQUAL'         , code=15, args={'register', 'register'}}
instr {name='NOTEQUAL'        , code=16, args={'register', 'register'}}
instr {name='GREATER'         , code=17, args={'register', 'register'}}
instr {name='LESSTHAN'        , code=18, args={'register', 'register'}}
instr {name='GTE'             , code=19, args={'register', 'register'}}
instr {name='LTE'             , code=20, args={'register', 'register'}}
instr {name='AND'             , code=21, args={'register', 'register'}}
instr {name='OR'              , code=22, args={'register', 'register'}}
instr {name='CALL'            , code=23, args={'register'}}
instr {name='MEMREADB'        , code=24, args={'register'}}
instr {name='MEMREADW'        , code=25, args={'register'}}
instr {name='MEMWRITEB'       , code=26, args={'register'}}
instr {name='MEMWRITEW'       , code=27, args={'register'}}
instr {name='JZ'              , code=28, args={'label'}}
instr {name='PUSHREG'         , code=29, args={'register'}}
instr {name='POPREG'          , code=30, args={'register'}}
instr {name='JMP'             , code=31, args={'label'}, stop=true}
instr {name='MUL'             , code=32, args={'register', 'value'}}
instr {name='CALLEXT'         , code=33, args={'register'}}
instr {name='PUSHREAL'        , code=34, args={'register'}}
instr {name='SUBREALSTACK'    , code=35, args={'value'}}
instr {name='LINENUM'         , code=36, args={'value'}}
instr {name='CALLAS'          , code=37, args={'register'}}
instr {name='THISBASE'        , code=38, args={'value'}}
instr {name='NUMFUNCARGS'     , code=39, args={'value'}}
instr {name='MODREG'          , code=40, args={'register', 'register'}}
instr {name='XORREG'          , code=41, args={'register', 'register'}}
instr {name='NOTREG'          , code=42, args={'register'}}
instr {name='SHIFTLEFT'       , code=43, args={'register', 'register'}}
instr {name='SHIFTRIGHT'      , code=44, args={'register', 'register'}}
instr {name='CALLOBJ'         , code=45, args={'register'}}
instr {name='CHECKBOUNDS'     , code=46, args={'register', 'value'}}
instr {name='MEMWRITEPTR'     , code=47, args={'register'}}
instr {name='MEMREADPTR'      , code=48, args={'register'}}
instr {name='MEMZEROPTR'      , code=49, args={}}
instr {name='MEMINITPTR'      , code=50, args={'register'}}
instr {name='LOADSPOFFS'      , code=51, args={'value'}}
instr {name='CHECKNULL'       , code=52, args={}}
instr {name='FADD'            , code=53, args={'register', 'value'}}
instr {name='FSUB'            , code=54, args={'register', 'value'}}
instr {name='FMULREG'         , code=55, args={'register', 'register'}}
instr {name='FDIVREG'         , code=56, args={'register', 'register'}}
instr {name='FADDREG'         , code=57, args={'register', 'register'}}
instr {name='FSUBREG'         , code=58, args={'register', 'register'}}
instr {name='FGREATER'        , code=59, args={'register', 'register'}}
instr {name='FLESSTHAN'       , code=60, args={'register', 'register'}}
instr {name='FGTE'            , code=61, args={'register', 'register'}}
instr {name='FLTE'            , code=62, args={'register', 'register'}}
instr {name='ZEROMEMORY'      , code=63, args={'value'}}
instr {name='CREATESTRING'    , code=64, args={'register'}}
instr {name='STRINGSEQUAL'    , code=65, args={'register', 'register'}}
instr {name='STRINGSNOTEQ'    , code=66, args={'register', 'register'}}
instr {name='CHECKNULLREG'    , code=67, args={'register'}}
instr {name='LOOPCHECKOFF'    , code=68, args={}}
instr {name='MEMZEROPTRND'    , code=69, args={}}
instr {name='JNZ'             , code=70, args={'label'}}
instr {name='DYNAMICBOUNDS'   , code=71, args={'register'}}
instr {name='NEWARRAY'        , code=72, args={'register', 'value', 'value'}}

function reader_proto:instruction(instr)
	local instr_code = self:int32le()
	if instr_code == nil then
		return false
	end
	local instr_def = instr_info[instr_code]
	if instr_def == nil then
		error('unknown instruction: ' .. instr_code)
	end
	instr.def = instr_def
	for _, arg_type in ipairs(instr_def.args) do
		local arg_value = self:int32le()
		instr[#instr+1] = arg_value
	end

	for i, arg_type in ipairs(instr_def.args) do
		if arg_type == 'label' then
			instr[i] = self:pos()/4 + instr[i]
		end
	end
	return true
end

function reader_proto:script_export(export)
	local name = self:nullTerminated()
	local pre_arg, arg_count = name:match('^([^%$]+)%$(%d+)$')
	if pre_arg then
		export.name = pre_arg
		export.arg_count = tonumber(arg_count)
	else
		export.name = name
	end
	local address = self:int32le()
	local export_type = bit.rshift(address, 24)
	if export_type == 1 then
		export.type = 'function'
	elseif export_type == 2 then
		export.type = 'data'
	else
		export.type = tostring(export_type)
	end
	export.offset = bit.band(address, 0xffffff)
end

function reader_proto:script_fixup(fixup)
	fixup.type = self:uint8()
	if fixup.type == 1 then
		fixup.context = 'code'
		fixup.type = 'data'
	elseif fixup.type == 2 then
		fixup.context = 'code'
		fixup.type = 'code'
	elseif fixup.type == 3 then
		fixup.context = 'code'
		fixup.type = 'strings'
	elseif fixup.type == 4 then
		fixup.context = 'code'
		fixup.type = 'import'
	elseif fixup.type == 5 then
		fixup.context = 'data'
		fixup.type = 'data'
	elseif fixup.type == 6 then
		fixup.context = 'code'
		fixup.type = 'stack'
	else
		fixup.type = tostring(fixup.type)
	end
end

return reader_proto
