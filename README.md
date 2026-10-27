# OpenWrt 控制台 1.5.2 — chmod 兼容修复

这是完整的 GitHub Actions 构建仓库源码。目标是使用 `opkg` 的 Kwrt
25.12 x86/64，产物为 `openwrt-console_1.5.2-1_all.ipk`。

## 你要的效果

1. LuCI → 服务 → OpenWrt 控制台。
2. 编辑 `init_system_openwrt_25.12.sh`，点击保存。
3. 保留滑动开关“SSH 登录自动显示菜单”：开启后，下次 root 交互式 SSH 登录自动运行菜单。
4. 菜单选择退出后，返回 SSH 命令行。
5. 开关关闭后，下次 SSH 登录直接进入命令行。
6. 保存前备份为可勾选项，默认勾选；不勾选时不会创建或更新 `.bak`。

软件包已包含用户提供的原始菜单脚本（只统一为 UTF-8 无 BOM、LF 换行）。
网页和 SSH 均使用同一文件：

```
/etc/openwrt-console/init_system_openwrt_25.12.sh
```

脚本和开关标记列为 conffiles，包升级时由 opkg 保护本地修改。
保存只运行 `sh -n` 语法检查，不执行脚本。首次安装默认关闭自启。
1.5.1 移除了菜单项对 app ACL 名称的显示依赖；LuCI 页面的写操作仍通过
root 认证的 Lua 控制器处理。

## GitHub Actions 云编译

1. 新建 GitHub 仓库，把本目录下全部内容上传到仓库根目录（不是再套一层目录）。
2. 必须包含隐藏目录 `.github`。根目录应该有：

```
.github/workflows/build-ipk.yml
package/openwrt-console/Makefile
package/openwrt-console/files/...
tests/
tools/
README.md
```

3. 打开 Actions → Build OpenWrt Console IPK → Run workflow。
4. 等待成功后，打开该次运行，下载带有 `kwrt-x86_64-linux-6.12.112` 名称的 Artifact。
5. 解压得到 `.ipk` 和 `SHA256SUMS`。

工作流直接从 `kiddin9/Kwrt` 克隆指定分支、标签或提交，并在 Kwrt 源码树中构建；
不再使用 OpenWrt 23.05.5 SDK，也不会下载或安装固件。构建前会检查源码是否
包含所填的内核版本。

设备建议填写：

```text
kwrt_ref: 25.12
expected_kernel: 6.12.112
```

如果固件由某个具体 Kwrt 提交构建，应将 `kwrt_ref` 填成该提交 SHA。
IPK 不会刷写内核；精确兼容取决于 Kwrt 提交、LuCI 版本、feeds 和软件源。

## 安装和使用

把 IPK 上传到 `/tmp`，在设备 SSH 中执行：

```sh
opkg install /tmp/openwrt-console_1.5.2-1_all.ipk
rm -f /tmp/luci-indexcache
```

如果缺少 `luci-compat`，使用设备自身的 Kwrt 软件源安装，避免混装官方系统组件：

```sh
opkg update
opkg install luci-compat
```

重新登录 LuCI，并按 Ctrl+F5 刷新。进入“服务 → OpenWrt 控制台”，保存脚本，
打开“SSH 登录自动显示菜单”，断开并重新连接 SSH。无需重启 rpcd/uhttpd。

安装不会修改 procd.sh，不会自动执行菜单，不会清空 banner。
交互式 scp/sftp 以外的非交互会话不显示菜单；判断依据为交互 shell 和终端检测。

如果已安装 1.5.0 但“服务”菜单没有入口，可先临时修复菜单 JSON：

```sh
cp -p /usr/share/luci/menu.d/luci-app-openwrt-console.json \
  /usr/share/luci/menu.d/luci-app-openwrt-console.json.bak
cat > /usr/share/luci/menu.d/luci-app-openwrt-console.json <<'EOF'
{
  "admin/services/openwrt_console": {
    "title": "OpenWrt 控制台",
    "order": 90,
    "action": {
      "type": "view",
      "path": "openwrt_console"
    }
  }
}
EOF
rm -f /tmp/luci-indexcache*
```

退出 LuCI 后重新登录，并在浏览器中强制刷新（Ctrl+F5）。可直接测试页面：

```text
/cgi-bin/luci/admin/services/openwrt_console
```

不要为刷新菜单重启 `uhttpd`。你看到的 `procd.sh: line 144: shift` 是独立的
Kwrt 系统服务问题，不是插件安装脚本触发的；重启失败也不代表 LuCI 菜单缓存未清理。

若菜单 JSON 已修复且清缓存、重新登录后仍未显示，测试直达页面：

```text
/cgi-bin/luci/admin/services/openwrt_console
```

若直达页面正常而侧栏仍没有入口，通常是 LuCI 浏览器缓存；强制刷新或退出再登录。
若直达页面返回 404，请检查：

```sh
cat /usr/share/luci/menu.d/luci-app-openwrt-console.json
ls -l /www/luci-static/resources/view/openwrt_console.js
logread | grep -iE 'luci|openwrt_console' | tail -n 80
```

SSH 登录自启是另一个独立开关。`ps | grep openwrt-console` 没有进程是正常的：
控制台菜单不是后台守护进程，只有自启开关开启并且 root 建立交互式 SSH 登录时才运行。
可用 `cat /etc/openwrt-console/login-enabled` 查看开关（`1` 为开启，`0` 为关闭）。

## 旧版本迁移

升级时仅删除旧 1.3.x 写入 `/etc/rc.local` 中的 `OPENWRT_CONSOLE_STARTUP`
标记区块，迁移前保存 `/etc/rc.local.before-console-1.4.bak`。其他内容不删除。
旧的 `startup.sh` 不会自动覆盖本版菜单脚本，请按需手动复制修改。

如果以前把 `/root/init_system.sh` 自动运行块写入 `/etc/profile`，
请备份 profile 后移除该旧块，避免显示两次菜单：

```sh
cp -p /etc/profile /etc/profile.before-console-1.4.bak
sed -i '/^# >>> OPENWRT_CUSTOM_CONSOLE_BEGIN$/,/^# <<< OPENWRT_CUSTOM_CONSOLE_END$/d' /etc/profile
```

## 紧急关闭、手动运行

当前会话中关闭下次登录自启：

```sh
printf '0\n' > /etc/openwrt-console/login-enabled
```

菜单正常退出可回命令行；若菜单异常，可从电脑建立非交互 SSH 关闭开关：

```sh
ssh root@路由器IP "printf '0\n' > /etc/openwrt-console/login-enabled"
```

手动运行：

```sh
openwrt-console
```

## 已知边界

- 继承的菜单含修改网络、恢复出厂、重启等功能，请阅读确认提示。
- root 以外账户不自动启动菜单，后端接口仅允许 root。
- 编辑脚本需要 luci-compat 的 Lua runtime；缺少依赖、登录过期或接口异常时，
  前端给出错误，不把 HTML 登录页强行当成 JSON。
- 本地前端测试与云端编译检查不能替代 Kwrt 实机验证。此仓库尚未在你的 GitHub 上运行。
