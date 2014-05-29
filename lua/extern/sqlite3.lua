
local ffi = require 'ffi'

ffi.cdef [[

	typedef struct sqlite3 sqlite3;
	typedef struct sqlite3_stmt sqlite3_stmt;

	int sqlite3_open(const char* utf8_path, sqlite3** ret_db);
	int sqlite3_close(sqlite3*);

	int sqlite3_exec(
	  sqlite3*,
	  const char* sql,
	  int (*callback)(void*,int,char**,char**),
	  void* callback_userdata,
	  char** ret_errmsg
	);

	int64_t sqlite3_last_insert_rowid(sqlite3*);

	int sqlite3_prepare_v2(sqlite3*,
		const char* sql, int sql_len,
		sqlite3_stmt** ret_stmt, const char** ret_tail);

	void sqlite3_free(void*);

	const char* sqlite3_errmsg(sqlite3*);

	int sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int n, void(*)(void*));
	int sqlite3_bind_double(sqlite3_stmt*, int, double);
	int sqlite3_bind_int(sqlite3_stmt*, int, int);
	int sqlite3_bind_int64(sqlite3_stmt*, int, int64_t);
	int sqlite3_bind_null(sqlite3_stmt*, int);
	int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int n, void(*)(void*));
	int sqlite3_bind_zeroblob(sqlite3_stmt*, int, int n);

	int sqlite3_bind_parameter_index(sqlite3_stmt*, const char* name);

	int sqlite3_step(sqlite3_stmt*);
	int sqlite3_reset(sqlite3_stmt*);
	int sqlite3_finalize(sqlite3_stmt*);

	sqlite3* sqlite3_db_handle(sqlite3_stmt*);

	enum {
		SQLITE_OK = 0,
		SQLITE_ERROR = 1,
		SQLITE_INTERNAL = 2,
		SQLITE_PERM = 3,
		SQLITE_ABORT = 4,
		SQLITE_BUSY = 5,
		SQLITE_LOCKED = 6,
		SQLITE_NOMEM = 7,
		SQLITE_READONLY = 8,
		SQLITE_INTERRUPT = 9,
		SQLITE_IOERR = 10,
		SQLITE_CORRUPT = 11,
		SQLITE_NOTFOUND = 12,
		SQLITE_FULL = 13,
		SQLITE_CANTOPEN = 14,
		SQLITE_PROTOCOL = 15,
		SQLITE_EMPTY = 16,
		SQLITE_SCHEMA = 17,
		SQLITE_TOOBIG = 18,
		SQLITE_CONSTRAINT = 19,
		SQLITE_MISMATCH = 20,
		SQLITE_MISUSE = 21,
		SQLITE_NOLFS = 22,
		SQLITE_AUTH = 23,
		SQLITE_FORMAT = 24,
		SQLITE_RANGE = 25,
		SQLITE_NOTADB = 26,
		SQLITE_NOTICE = 27,
		SQLITE_WARNING = 28,
		SQLITE_ROW = 100,
		SQLITE_DONE = 101
	};

]]

local lib = ffi.load 'sqlite3'

ffi.metatype('sqlite3', {
	__index = {
		close = lib.sqlite3_close;
		exec = function(self, sql)
			if lib.SQLITE_OK == lib.sqlite3_exec(self, sql, nil, nil, nil) then
				return true
			end
			return false, self:errmsg()
		end;
		last_insert_rowid = lib.sqlite3_last_insert_rowid;
		prepare = function(self, sql)
			local ret_stmt = ffi.new('sqlite3_stmt*[1]')
			if lib.SQLITE_OK ~= lib.sqlite3_prepare_v2(self, sql, #sql, ret_stmt, nil) then
				return nil, self:errmsg()
			end
			return ret_stmt[0]
		end;
		errmsg = function(self)
			return ffi.string(lib.sqlite3_errmsg(self))
		end;
	};
})

local step_results = {
	[lib.SQLITE_ROW] = 'row';
	[lib.SQLITE_DONE] = 'done';
}

local cache = {}

ffi.metatype('sqlite3_stmt', {
	__index = {
		step = function(self)
			local result = step_results[ lib.sqlite3_step(self) ]
			if result then
				return result
			else
				return false, self:db_handle():errmsg()
			end
		end;
		reset = function(self)
			if lib.SQLITE_OK == lib.sqlite3_reset(self) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		finalize = function(self)
			if lib.SQLITE_OK == lib.sqlite3_finalize(self) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		db_handle = lib.sqlite3_db_handle;
		bind_parameter_index = lib.sqlite3_bind_parameter_index;
		bind_blob = function(self, n, blob)
			if blob ~= nil then
				cache[blob] = blob
			end
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_blob(self, n, blob, #(blob or ''), nil) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		bind_double = function(self, n, double)
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_double(self, n, double) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		bind_int = function(self, n, int)
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_int(self, n, int) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		bind_bool = function(self, n, bool)
			return self:bind_int(n, bool and 1 or 0)
		end;
		bind_int64 = function(self, n, int64)
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_int64(self, n, int64) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		bind_null = function(self, n)
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_null(self, n) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		bind_text = function(self, n, text)
			if text ~= nil then
				cache[text] = text
			end
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_text(self, n, text, #(text or ''), nil) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		bind_zeroblob = function(self, n, size)
			if type(n) == 'string' then
				n = self:bind_parameter_index(n)
			end
			if lib.SQLITE_OK == lib.sqlite3_bind_zeroblob(self, n, size) then
				return true
			end
			return false, self:db_handle():errmsg()
		end;
		clear_cache = function()
			cache = {}
		end;
	};
})

return lib
