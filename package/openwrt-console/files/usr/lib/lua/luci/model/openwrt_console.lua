local fs = require "nixio.fs"
local sys = require "luci.sys"
local nixio = require "nixio"

local M = {}
local base = "/etc/openwrt-console/"
local path = base .. "init_system_openwrt_25.12.sh"
local flag = base .. "login-enabled"

local function result(ok, message)
	return { ok = ok, message = message }
end

local function atomic_write(target, content, syntax_check)
	local temp = target .. ".new." .. tostring(nixio.getpid())
	if not fs.writefile(temp, content) then
		return nil, "无法写入临时文件；原文件未改动。"
	end
	if not fs.chmod(temp, "0600") then
		fs.unlink(temp)
		return nil, "设置临时文件权限失败。"
	end
	-- Both target and temp paths are constants, never supplied by the browser.
	if syntax_check and sys.call("/bin/sh -n " .. temp .. " >/dev/null 2>&1") ~= 0 then
		fs.unlink(temp)
		return nil, "脚本未通过 sh -n 语法检查，未保存。"
	end
	return temp
end

local function commit(temp, target)
	if not fs.chmod(temp, "0644") or not fs.rename(temp, target) then
		fs.unlink(temp)
		return nil, "保存文件失败；原文件未替换。"
	end
	return true
end

function M.state()
	local content = fs.readfile(path)
	if content == nil then
		return result(false, "找不到菜单脚本，请重新安装完整软件包。")
	end
	return {
		ok = true, script = content, path = path,
		enabled = (fs.readfile(flag) or ""):match("^1%s*$") ~= nil
	}
end

function M.save(content, backup)
	if type(content) ~= "string" or #content == 0 or #content > 262144 then
		return result(false, "脚本必须非空且不超过 256 KiB。")
	end
	content = content:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
	if content:find("\000", 1, true) then
		return result(false, "脚本不能包含 NUL 字符。")
	end
	local temp, err = atomic_write(path, content, true)
	if not temp then return result(false, err) end
	if backup then
		local old = fs.readfile(path)
		local backup_temp, backup_err = atomic_write(path .. ".bak", old or "", false)
		if not backup_temp then
			fs.unlink(temp)
			return result(false, backup_err)
		end
		local saved, saved_err = commit(backup_temp, path .. ".bak")
		if not saved then
			fs.unlink(temp)
			return result(false, saved_err)
		end
	end
	local saved, saved_err = commit(temp, path)
	if not saved then return result(false, saved_err) end
	return result(true, backup and "已保存菜单脚本，并生成 .bak 备份。"
		or "已保存菜单脚本（未创建新备份）。")
end

function M.set_enabled(value)
	if value ~= "0" and value ~= "1" then return result(false, "开关值无效。") end
	if value == "1" and sys.call("/bin/sh -n " .. path .. " >/dev/null 2>&1") ~= 0 then
		return result(false, "菜单脚本语法检查失败，无法启用登录自启。")
	end
	local temp, err = atomic_write(flag, value .. "\n", false)
	if not temp then return result(false, err) end
	local saved, saved_err = commit(temp, flag)
	if not saved then return result(false, saved_err) end
	local response = result(true, value == "1"
		and "已开启：下次登录 SSH 自动显示菜单。"
		or "已关闭：下次登录 SSH 直接进入命令行。")
	response.enabled = value == "1"
	return response
end

return M
