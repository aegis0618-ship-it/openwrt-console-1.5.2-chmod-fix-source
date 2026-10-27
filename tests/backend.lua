-- Isolated persistence tests: never touch host /etc or execute menu contents.
local files = {}
local path = "/etc/openwrt-console/init_system_openwrt_25.12.sh"
local flag = "/etc/openwrt-console/login-enabled"
local writes = 0
local fail_rename = false
files[path] = "#!/bin/sh\necho old\n"
files[flag] = "0\n"
package.preload["nixio.fs"] = function()
	return {
		readfile = function(p) return files[p] end,
		writefile = function(p, content)
			writes = writes + 1
			files[p] = content
			return #content
		end,
		chmod = function() return true end,
		unlink = function(p) files[p] = nil; return true end,
		rename = function(a, b)
			if fail_rename then return nil end
			files[b], files[a] = files[a], nil
			return true
		end
	}
end
package.preload["nixio"] = function() return { getpid = function() return 123 end } end
package.preload["luci.sys"] = function()
	return {
		call = function(command)
			assert(command:match("^/bin/sh %-n "), "Only syntax checks may run")
			local target = command:match("^/bin/sh %-n ([^ ]+)")
			assert(files[target], "Syntax check target missing")
			return files[target]:find("SYNTAX_ERROR", 1, true) and 2 or 0
		end
	}
end
local model = dofile("package/openwrt-console/files/usr/lib/lua/luci/model/openwrt_console.lua")
assert(model.state().enabled == false)
assert(model.set_enabled("1").ok)
assert(model.state().enabled == true)
assert(files[flag] == "1\n")
assert(model.set_enabled("0").ok and not model.state().enabled)
assert(not model.set_enabled("unexpected").ok)

local original = files[path]
assert(model.save("#!/bin/sh\necho new\n", true).ok)
assert(files[path .. ".bak"] == original)
local backup = files[path .. ".bak"]
assert(model.save("#!/bin/sh\necho newest\n", false).ok)
assert(files[path .. ".bak"] == backup, "Unchecked backup must not update .bak")

local before = files[path]
assert(not model.save("SYNTAX_ERROR", true).ok)
assert(files[path] == before and files[path .. ".bak"] == backup)
assert(not model.save("", false).ok)
assert(not model.save("abc\000def", false).ok)
assert(not model.save(string.rep("a", 262145), false).ok)
assert(model.save("\239\187\191#!/bin/sh\r\nexit 0\r\n", false).ok)
assert(files[path] == "#!/bin/sh\nexit 0\n")

fail_rename = true
before = files[path]
assert(not model.save("#!/bin/sh\necho failed\n", false).ok)
assert(files[path] == before, "Failed replacement must preserve original")
fail_rename = false
local count = writes
assert(model.state().ok and writes == count, "Reading state must not write files")
print("PASS backend: login switch, optional backup, atomic replacement, syntax-failure guard, normalization")
