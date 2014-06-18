
local lfs = require 'lfs'
local ffi = require 'ffi'
local D = require 'extern.sqlite3'

-------------------------------------------------------------------------------

local app = {}

local function lineargs(...)
	local p = {}
	for i = 1, select('#', ...) do
		local arg = select(i, ...)
		arg = arg:match('^%-(.+)$')
		if arg then
			local k,v = arg:match('^([^=]+)=(.*)$')
			if k then
				p[k] = v
			else
				p[arg] = true
			end
		end
	end
	return p
end

function app.extract(inpath, extraction, outpath)
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(inpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	local select_file = assert(db:prepare [[

		SELECT contents FROM file WHERE name LIKE :name

	]])

	assert( select_file:bind_text(':name', extraction) )

	local result = assert(select_file:step())
	if result == 'done' then
		error('extractable not found: ' .. extraction)
	end
	assert(result == 'row')
	local data = select_file:column_blob(0)
	assert(select_file:finalize())

	if data ~= nil then
		local f = assert(io.open(outpath, 'wb'))
		f:write(data)
		f:close()
	end
end

function app.todb(format, inpath, outpath, ...)
	if not format and inpath and outpath then
		return app.info()
	end
	local format = require('denzquix.packland.formats.' .. format)
	local args = lineargs(...)
	local intype = lfs.attributes(inpath, 'mode')
	if intype == nil then
		error('nothing to open at: ' .. inpath)
	end
	local outtype = lfs.attributes(outpath, 'mode')
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(outpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	assert( db:exec [[ BEGIN EXCLUSIVE TRANSACTION ]] )

	format.todb(intype, inpath, db, args)

	assert( db:exec [[ COMMIT ]] )
	
	db:close()
end

function app.togif(format, inpath, outpath)
	local format = require('denzquix.packland.formats.' .. format)
	if not format.togif then
		error('format does not support gif output')
	end

	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(inpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	format.togif(db, outpath)

	db:close()
end

function app.info()
	print ''
	print 'options:'
	print '  luajit packland.lua todb ags-assets audio.vox audiovox.db'
	print '  luajit packland.lua extract assetpack.db asset.dat extractedasset.dat'
	print '  luajit packland.lua todb ags-room-chunks room2.crm room2.db'
	print '  luajit packland.lua todb ags-sprites acsprset.spr sprites.db'
end

-------------------------------------------------------------------------------

local params = {...}

local action = params[1] or 'info'
if app[action] then
	app[action](select(2, ...))
else
	io.stderr:write('unknown action: ' .. params[1] .. '\n')
end
