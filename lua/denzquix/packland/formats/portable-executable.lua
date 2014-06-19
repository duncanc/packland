
local R = require 'denzquix.packland.reader'
local format = {}

local reader_proto = {}

local resource_types = {
	[1] = 'RT_CURSOR';
	[2] = 'RT_BITMAP';
	[3] = 'RT_ICON';
	[4] = 'RT_MENU';
	[5] = 'RT_DIALOG';
	[6] = 'RT_STRING';
	[7] = 'RT_FONTDIR';
	[8] = 'RT_FONT';
	[9] = 'RT_ACCELERATOR';
	[10] = 'RT_RCDATA';
	[11] = 'RT_MESSAGETABLE';
	[12] = 'RT_GROUP_CURSOR';
	[13] = 'RT_GROUP_ICON';
	[16] = 'RT_VERSION';
	[17] = 'RT_DLGINCLUDE';
	[19] = 'RT_PLUGPLAY';
	[20] = 'RT_VXD';
	[21] = 'RT_ANICURSOR';
	[22] = 'RT_ANIICON';
	[23] = 'RT_HTML';
	[24] = 'RT_MANIFEST';
}

function format.todb(intype, inpath, db)
	local data = R.fromfile(inpath)

	data:inject 'bindata'
	data:inject(reader_proto)

	local dos_header = {}
	data:dos_header(dos_header)

	data:pos('set', dos_header.e_lfanew)

	local id = data:blob(2)
	data:pos('cur', -2)
	if id == 'NE' then
		local base_pos = data:pos()
		local ne_header = {}
		data:ne_header(ne_header)
		data:pos('set', base_pos + ne_header.resource_table_offset)
		local alignment_shift_count = data:int16le()
		while true do
			local type_id = data:uint16le()
			if type_id == 0x0000 then
				break
			elseif type_id >= 0x8000 then
				type_id = type_id - 0x8000
				type_id = resource_types[type_id] or type_id
				print('resource type ' .. type_id)
			else
				print('resource type @' .. (ne_header.resource_table_offset + type_id))
			end
			local resource_count = data:int16le()
			data:skip(4) -- reserved for runtime use
			for i = 1, resource_count do
				local offset = data:int16le() -- in alignment units from start of file
				local length = data:int16le()
				local flags = data:int16le() -- moveable, shareable, preloaded
				local resource_id = data:uint16le()
				if resource_id >= 0x8000 then
					resource_id = resource_id - 0x8000
				else
					resource_id = '@'..(ne_header.resource_table_offset + type_id)
				end
				data:skip(4) -- reserved for runtime use
				print('\toffset:'..offset..' length:'..length..' id:'..resource_id)
			end
		end
		local names = {}
		while true do
			local len = data:uint8()
			if len == 0 then
				break
			end
			names[#names+1] = data:blob(len)
		end
		print(data:pos())
	elseif id == 'PE' then
		local pe_header = {}
		data:pe_header(pe_header)
	else
		error 'executable header not found'
	end
end

function reader_proto:dos_header(header)
	assert(self:expectBlob 'MZ', 'executable header not found')
	local base = self:pos()
	header.lastsize = self:int16le()
	header.nblocks = self:int16le()
	header.nreloc = self:int16le()
	header.hdrsize = self:int16le()
	header.minalloc = self:int16le()
    header.maxalloc = self:int16le()
    self:skip(2) -- void* ss
    self:skip(2) -- void* sp
    header.checksum = self:int16le()
    self:skip(2) -- void* ip
    self:skip(2) -- void* cs
    header.relocpos = self:int16le()
    header.noverlay = self:int16le()
    self:skip(2 * 4) -- reserved short[4]
    header.oem_id = self:int16le()
    header.oem_info = self:int16le()
    self:skip(2 * 10) -- reserved short[10]
    header.e_lfanew = self:int32le()
end

function reader_proto:ne_header(header)
	local base = self:pos()
	assert(self:expectBlob 'NE', 'executable header not found')
	header.linker_version_major = self:uint8()
	header.linker_version_minor = self:uint8()
	header.entry_table_offset = self:int16le()
	header.entry_table_length = self:int16le()
	header.file_load_crc = self:int32le()
	header.program_flags = self:uint8()
	--[[
	 0-1 - DGroup type :
		   0 - none
		   1 - single shared
		   2 - multiple
		   3 - (null)
	   2 - Global initialization
	   3 - Protected mode only
	   4 - 8086 instructions
	   5 - 80286 instructions
	   6 - 80386 instructions
	   7 - 80x87 instructions
	--]]
	header.application_flags = self:uint8()
	--[[
	 0-2 - Application type
		   1 - Full screen (not aware of
			   Windows/P.M. API)
		   2 - Compatible with Windows/P.M. API
		   3 - Uses Windows/P.M. API
	   3 - OS/2 family application
	   4 - reserved?
	   5 - Errors in image/executable
	   6 - "non-conforming program" whatever
	   7 - DLL or driver (SS:SP info invalid, CS:IP
		   points at FAR init routine called with
		   AX=module handle which returns AX=0000h
		   on failure, AX nonzero on successful
		   initialization)
	--]]
	header.auto_data_segment_index = self:uint8()
	self:align(2, base)
	header.initial_local_heap_size = self:uint16le()
	header.initial_stack_size = self:uint16le()
	header.entry_point = self:int32le()
	--[[
	(CS:IP) CS is index into segment table
	--]]
	header.initial_stack_pointer = self:int32le()
	--[[
	(SS:SP) SS is index into segment table
	--]]
	header.segment_count = self:int16le()
	header.module_reference_count = self:int16le()
	header.nonresident_names_table_size = self:int16le() -- in bytes
	header.segment_table_offset = self:int16le()
	header.resource_table_offset = self:int16le()
	header.resident_names_table_offset = self:int16le()
	header.module_reference_table_offset = self:int16le()
	header.imported_names_table_offset = self:int16le()
	header.nonresident_names_table_offset = self:int32le() -- from start of file
	header.moveable_entry_point_count = self:int16le() -- in entry table
	header.file_alignment_size_shift_count = self:int16le() -- 0 is equivalent to 9 (default 512-byte pages)
	header.resource_table_entry_count = self:int16le()
	header.target_operating_system = self:uint8()
	--[[
	  0 - unknown
	  1 - OS/2
	  2 - Windows
	  3 - European MS-DOS 4.x
	  4 - Windows 386
	  5 - BOSS (Borland Operating System Services)
	--]]
	header.os_2_flags = self:uint8()
	--[[
	 0 - Long filename support
	 1 - 2.x protected mode
	 2 - 2.x proportional fonts
	 3 - Executable has gangload area
	--]]
	header.offset_to_return_thunks_or_start_of_gangload_area = self:int16le() -- whatever that means
	header.offset_to_segment_reference_thunks_or_length_of_gangload_area = self:int16le()
	header.minimum_code_swap_area_size = self:int16le()
	header.expected_windows_version_minor = self:uint8()
	header.expected_windows_version_major = self:uint8()
end

function reader_proto:pe_header(header)
	assert(self:expectBlob 'PE\0\0', 'executable header not found')
	header.coff = {}
	self:coff_header(header.coff)
	header.signature = self:int16le()
	header.is_32bit = header.signature == 267
	header.is_64bit = header.signature == 523
	header.linker_version_major = self:uint8()
	header.linker_version_minor = self:uint8()
	header.size_of_code = self:int32le()
	header.size_of_initialized_data = self:int32le()
	header.size_of_uninitialized_data = self:int32le()
	header.address_of_entry_point = self:int32le()
	header.base_of_code = self:int32le()
	header.base_of_data = self:int32le()
	header.image_base = self:int32le()
	header.section_alignment = self:int32le()
	header.file_alignment = self:int32le()	
	header.major_os_version = self:int16le()
	header.minor_os_version = self:int16le()
	header.major_image_version = self:int16le()
	header.minor_image_version = self:int16le()
	header.major_subsystem_version = self:int16le()
	header.minor_subsystem_version = self:int16le()
	self:skip(4) -- reserved int
	header.size_of_image = self:int32le()
	header.size_of_headers = self:int32le()
	header.checksum = self:int32le()
	header.subsystem = self:int16le()
	header.dll_characteristics = self:int16le()
	header.size_of_stack_reserve = self:int32le()
	header.size_of_stack_commit = self:int32le()
	header.size_of_heap_reserve = self:int32le()
	header.size_of_heap_commit = self:int32le()
	header.loader_flags = self:int32le()
	header.number_of_rva_and_sizes = self:int32le()
	header.data_directory = {}
	for i = 1, header.number_of_rva_and_sizes do
		local entry = {}
		header.data_directory[i] = entry
		entry.virtual_address = self:int32le()
		entry.size = self:int32le()
	end
end

local machine_names = {
	[0x14c] = 'Intel 386';
	[0x14d] = 'Intel i860';
	[0x162] = 'MIPS R3000';
	[0x166] = 'MIPS little endian (R4000)';
	[0x168] = 'MIPS R10000';
	[0x169] = 'MIPS little endian WCI v2';
	[0x183] = 'old Alpha AXP';
	[0x184] = 'Alpha AXP';
	[0x1a2] = 'Hitachi SH3';
	[0x1a3] = 'Hitachi SH3 DSP';
	[0x1a6] = 'Hitachi SH4';
	[0x1a8] = 'Hitachi SH5';
	[0x1c0] = 'ARM little endian';
	[0x1c2] = 'Thumb';
	[0x1d3] = 'Matsushita AM33';
	[0x1f0] = 'PowerPC little endian';
	[0x1f1] = 'PowerPC with floating point support';
	[0x200] = 'Intel IA64';
	[0x266] = 'MIPS16';
	[0x268] = 'Motorola 68000 series';
	[0x284] = 'Alpha AXP 64-bit';
	[0x366] = 'MIPS with FPU';
	[0x466] = 'MIPS16 with FPU';
	[0xebc] = 'EFI Byte Code';
	[0x8664] = 'AMD AMD64';
	[0x9041] = 'Mitsubishi M32R little endian';
	[0xc0ee] = 'clr pure MSIL';
}

function reader_proto:coff_header(header)
	header.machine = self:int16le()
	header.number_of_sections = self:int16le()
	header.time_date_stamp = self:int32le()
	header.pointer_to_symbol_table = self:int32le()
	header.number_of_symbols = self:int32le()
	header.size_of_optional_header = self:int16le()
	header.characteristics = self:int16le()
	header.is_executable = 0 ~= bit.band(2, header.characteristics)
	header.has_absolute_addresses = 0 ~= bit.band(0x200, header.characteristics)
	header.is_dll = 0 ~= bit.band(0x2000, header.characteristics)
end

return format
