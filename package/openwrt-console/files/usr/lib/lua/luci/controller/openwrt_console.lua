module("luci.controller.openwrt_console", package.seeall)

function index()
	local node = entry({"admin", "services", "openwrt_console", "action"}, post("action"))
	node.leaf = true
	node.sysauth = "root"
end

function action()
	local http = require "luci.http"
	local json = require "luci.jsonc"
	local ok, response = pcall(function()
		local model = require "luci.model.openwrt_console"
		local operation = http.formvalue("operation")
		if operation == "state" then
			return model.state()
		elseif operation == "save_script" then
			return model.save(http.formvalue("script"), http.formvalue("backup") == "1")
		elseif operation == "set_autostart" then
			return model.set_enabled(http.formvalue("enabled"))
		end
		return { ok = false, message = "不支持的操作。" }
	end)
	http.prepare_content("application/json")
	http.header("Cache-Control", "no-store")
	http.write(json.stringify(ok and response or {
		ok = false, message = "接口执行失败：" .. tostring(response)
	}))
end
