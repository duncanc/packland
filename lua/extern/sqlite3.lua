
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
			local ret_errmsg = ffi.new 'char*[1]'
			if lib.SQLITE_OK ~= lib.sqlite3_exec(self, sql, nil, nil, ret_errmsg) then
				local msg = ffi.string(ret_errmsg[0])
				lib.sqlite3_free(ret_errmsg[0])
				error(msg, 2)
			end
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
		bind_blob = function(self, n, blob)
			cache[blob] = blob
			lib.sqlite3_bind_blob(self, n, blob, #blob, nil)
		end;
		bind_double = lib.sqlite3_bind_double;
		bind_int = lib.sqlite3_bind_int;
		bind_int64 = lib.sqlite3_bind_int64;
		bind_null = lib.sqlite3_bind_null;
		bind_text = function(self, n, text)
			cache[text] = text
			lib.sqlite3_bind_text(self, n, text, #text, nil)
		end;
		bind_zeroblob = lib.sqlite3_bind_zeroblob;
		clear_cache = function()
			cache = {}
		end;
	};
})

return lib
