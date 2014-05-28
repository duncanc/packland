
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
end

function app.todb(format, inpath, outpath, ...)
	if not format and inpath and outpath then
		return app.info()
	end
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
	local format = require('denzquix.packland.formats.' .. format)
	format.todb(intype, inpath, db, args)
	db:close()
end

function app.info()
	print ''
	print 'options:'
	print '  luajit packland.lua todb ags-assets audio.vox audiovox.db'
end

-------------------------------------------------------------------------------

local params = {...}

local action = params[1] or 'info'
if app[action] then
	app[action](select(2, ...))
else
	io.stderr:write('unknown action: ' .. params[1] .. '\n')
end
