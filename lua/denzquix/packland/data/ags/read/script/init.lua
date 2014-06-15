
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

	local funcs_by_offset = {}
	for _, export in ipairs(exports) do
		if export.type == 'function' then
			funcs_by_offset[export.offset] = export
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
				local next_loop = 1

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
									local label_pos = instr[i]
									local label
									if label_pos <= pos then
										label = 'loop' .. next_loop
										next_loop = next_loop + 1
									else
										label = 'label' .. next_label
										next_label = next_label + 1
									end
									pos_labels[label_pos] = label
									start_sites[#start_sites+1] = {pos=instr[i]}
									instr[i] = string.format('jump_label(%q)', label)
								elseif arg_type == 'register' then
									local register = registers[instr[i]]
									if register then
										instr[i] = string.format('register(%q)', register)
									else
										instr[i] = string.format('register(%d)', instr[i])
									end
								elseif arg_type == 'value' then
									local fixup = fixups_by_pos[pos + i]
									if fixup == 'strings' then
										instr[i] = string.format('%q', strings:match('%Z*', instr[i]+1))
									elseif fixup == 'import' then
										local import = assert(imports_by_offset[instr[i]])
										instr[i] = string.format('import(%q)', import.name)
									elseif fixup == 'code' then
										local func = assert(funcs_by_offset[instr[i]])
										instr[i] = string.format('exported_func(%q)', func.name)
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
						buf[#buf+1] = string.format('Mark_Label(jump_label(%q))', label)
					end
					buf[#buf+1] = instr.def.name .. '(' .. table.concat(instr, ', ') .. ')'
				end
				func.instructions = table.concat(buf, '\n')

			end

		end
	end
end

local instr_info = {}

local instr_meta = {}

local function instr(def)
	if type(def) == 'number' then
		def = {code=def}
	elseif type(def) == 'string' then
		def = {name=def}
	end
	def.args = def.args or {}
	if def.code then
		instr_info[def.code] = def
	end
	return setmetatable(def, instr_meta)
end

function instr_meta:__call(v)
	if type(v) == 'number' then
		self.code = v
		instr_info[v] = self
	elseif type(v) == 'string' then
		self.name = v
	else
		for k,v in pairs(v) do
			self[k] = v
		end
	end
	return self
end

instr 'NULL'          (00)
instr 'ADD'           (01) {args={'register', 'value'}}
instr 'SUB'           (02) {args={'register', 'value'}}
instr 'REGTOREG'      (03) {args={'register', 'register'}}
instr 'WRITELIT'      (04) {args={'value', 'value'}}
instr 'RET'           (05) {stop=true}
instr 'LITTOREG'      (06) {args={'register', 'value'}}
instr 'MEMREAD'       (07) {args={'register'}}
instr 'MEMWRITE'      (08) {args={'register'}}
instr 'MULREG'        (09) {args={'register', 'register'}}
instr 'DIVREG'        (10) {args={'register', 'register'}}
instr 'ADDREG'        (11) {args={'register', 'register'}}
instr 'SUBREG'        (12) {args={'register', 'register'}}
instr 'BITAND'        (13) {args={'register', 'register'}}
instr 'BITOR'         (14) {args={'register', 'register'}}
instr 'ISEQUAL'       (15) {args={'register', 'register'}}
instr 'NOTEQUAL'      (16) {args={'register', 'register'}}
instr 'GREATER'       (17) {args={'register', 'register'}}
instr 'LESSTHAN'      (18) {args={'register', 'register'}}
instr 'GTE'           (19) {args={'register', 'register'}}
instr 'LTE'           (20) {args={'register', 'register'}}
instr 'AND'           (21) {args={'register', 'register'}}
instr 'OR'            (22) {args={'register', 'register'}}
instr 'CALL'          (23) {args={'register'}}
instr 'MEMREADB'      (24) {args={'register'}}
instr 'MEMREADW'      (25) {args={'register'}}
instr 'MEMWRITEB'     (26) {args={'register'}}
instr 'MEMWRITEW'     (27) {args={'register'}}
instr 'JZ'            (28) {args={'label'}}
instr 'PUSHREG'       (29) {args={'register'}}
instr 'POPREG'        (30) {args={'register'}}
instr 'JMP'           (31) {args={'label'}} {stop=true}
instr 'MUL'           (32) {args={'register', 'value'}}
instr 'CALLEXT'       (33) {args={'register'}}
instr 'PUSHREAL'      (34) {args={'register'}}
instr 'SUBREALSTACK'  (35) {args={'value'}}
instr 'LINENUM'       (36) {args={'value'}}
instr 'CALLAS'        (37) {args={'register'}}
instr 'THISBASE'      (38) {args={'value'}}
instr 'NUMFUNCARGS'   (39) {args={'value'}}
instr 'MODREG'        (40) {args={'register', 'register'}}
instr 'XORREG'        (41) {args={'register', 'register'}}
instr 'NOTREG'        (42) {args={'register'}}
instr 'SHIFTLEFT'     (43) {args={'register', 'register'}}
instr 'SHIFTRIGHT'    (44) {args={'register', 'register'}}
instr 'CALLOBJ'       (45) {args={'register'}}
instr 'CHECKBOUNDS'   (46) {args={'register', 'value'}}
instr 'MEMWRITEPTR'   (47) {args={'register'}}
instr 'MEMREADPTR'    (48) {args={'register'}}
instr 'MEMZEROPTR'    (49)
instr 'MEMINITPTR'    (50) {args={'register'}}
instr 'LOADSPOFFS'    (51) {args={'value'}}
instr 'CHECKNULL'     (52)
instr 'FADD'          (53) {args={'register', 'value'}}
instr 'FSUB'          (54) {args={'register', 'value'}}
instr 'FMULREG'       (55) {args={'register', 'register'}}
instr 'FDIVREG'       (56) {args={'register', 'register'}}
instr 'FADDREG'       (57) {args={'register', 'register'}}
instr 'FSUBREG'       (58) {args={'register', 'register'}}
instr 'FGREATER'      (59) {args={'register', 'register'}}
instr 'FLESSTHAN'     (60) {args={'register', 'register'}}
instr 'FGTE'          (61) {args={'register', 'register'}}
instr 'FLTE'          (62) {args={'register', 'register'}}
instr 'ZEROMEMORY'    (63) {args={'value'}}
instr 'CREATESTRING'  (64) {args={'register'}}
instr 'STRINGSEQUAL'  (65) {args={'register', 'register'}}
instr 'STRINGSNOTEQ'  (66) {args={'register', 'register'}}
instr 'CHECKNULLREG'  (67) {args={'register'}}
instr 'LOOPCHECKOFF'  (68)
instr 'MEMZEROPTRND'  (69)
instr 'JNZ'           (70) {args={'label'}}
instr 'DYNAMICBOUNDS' (71) {args={'register'}}
instr 'NEWARRAY'      (72) {args={'register', 'value', 'value'}}

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
