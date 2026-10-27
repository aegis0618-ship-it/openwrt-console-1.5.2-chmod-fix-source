'use strict';
'require view';
'require ui';

function api(operation, values) {
	var data = new URLSearchParams();
	data.set('operation', operation);
	data.set('token', L.env.token || '');
	Object.keys(values || {}).forEach(function(key) {
		data.set(key, values[key]);
	});
	return fetch(L.url('admin', 'services', 'openwrt_console', 'action'), {
		method: 'POST',
		credentials: 'same-origin',
		cache: 'no-store',
		headers: {
			'Content-Type': 'application/x-www-form-urlencoded',
			'Accept': 'application/json'
		},
		body: data.toString()
	}).then(function(response) {
		return response.text().then(function(text) {
			if (response.redirected || /^\s*</.test(text) ||
			    /text\/html/i.test(response.headers.get('content-type') || ''))
				throw new Error('接口返回 HTML（HTTP ' + response.status +
					'）。请重新登录 LuCI；若仍出错，请检查 luci-compat 安装状态和 logread。');
			if (!response.ok)
				throw new Error('接口请求失败：HTTP ' + response.status);
			var result;
			try { result = JSON.parse(text); }
			catch (error) { throw new Error('接口未返回有效 JSON，请检查 logread。'); }
			if (!result || typeof result.ok !== 'boolean')
				throw new Error('接口响应格式不正确。');
			if (!result.ok)
				throw new Error(result.message || '操作失败。');
			return result;
		});
	});
}

function notify(message, error) {
	ui.addNotification(null, E('p', {}, [ message ]), error ? 'error' : 'info');
}

return view.extend({
	load: function() {
		return api('state');
	},

	render: function(state) {
		var editor = E('textarea', {
			'class': 'oc-editor', 'spellcheck': 'false',
			'aria-label': 'init_system_openwrt_25.12.sh'
		}, [ state.script ]);
		var backup = E('input', { 'type': 'checkbox', 'checked': 'checked' });
		var switchInput = E('input', {
			'type': 'checkbox', 'role': 'switch',
			'aria-label': 'SSH 登录自动显示菜单',
			'checked': state.enabled ? 'checked' : null,
			'aria-checked': state.enabled ? 'true' : 'false'
		});
		var switchText = E('strong', {}, [
			state.enabled ? '已开启 (Enabled)' : '已关闭 (Disabled)'
		]);
		var save = E('button', {
			'type': 'button', 'class': 'cbi-button cbi-button-positive',
			'click': function() {
				save.disabled = true;
				api('save_script', {
					script: editor.value, backup: backup.checked ? '1' : '0'
				}).then(function(result) {
					notify(result.message, false);
				}).catch(function(error) {
					notify(error.message, true);
				}).finally(function() { save.disabled = false; });
			}
		}, [ '保存菜单脚本 (Save)' ]);

		switchInput.addEventListener('change', function() {
			switchInput.disabled = true;
			api('set_autostart', { enabled: switchInput.checked ? '1' : '0' })
				.then(function(result) {
					state.enabled = result.enabled;
					notify(result.message, false);
				}).catch(function(error) {
					notify(error.message, true);
				}).finally(function() {
					switchInput.checked = state.enabled;
					switchInput.setAttribute('aria-checked', state.enabled ? 'true' : 'false');
					switchText.textContent = state.enabled ? '已开启 (Enabled)' : '已关闭 (Disabled)';
					switchInput.disabled = false;
				});
		});

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ 'OpenWrt 控制台' ]),
			E('p', {}, [ '网页编辑菜单脚本，登录 SSH 后显示菜单。修改脚本后请先保存，再重新登录 SSH。' ]),
			E('section', { 'class': 'cbi-section oc-section' }, [
				E('h3', {}, [ 'SSH 登录自动显示菜单 (SSH Login Autostart)' ]),
				E('label', { 'class': 'oc-switch-row' }, [
					E('span', { 'class': 'oc-switch' }, [
						switchInput, E('span', { 'class': 'oc-slider' })
					]),
					switchText
				]),
				E('p', {}, [ '开启后，下次 root 交互式终端登录时运行已保存的脚本；退出菜单后返回命令行。' ])
			]),
			E('section', { 'class': 'cbi-section oc-section' }, [
				E('h3', {}, [ '菜单脚本编辑 (Menu Script Editor)' ]),
				E('p', {}, [ E('code', {}, [ state.path ]) ]),
				editor,
				E('label', { 'class': 'oc-backup' }, [
					backup, ' 保存前创建 .bak 备份 (Backup before saving)'
				]),
				E('div', {}, [ save ]),
				E('p', {}, [ '保存时只检查 Shell 语法，不会执行菜单脚本。备份未勾选时，不创建或更新已有 .bak。' ])
			]),
			E('style', {}, [
				'.oc-section{padding:1.2rem}.oc-editor{display:block;width:100%;box-sizing:border-box;' +
				'min-height:32rem;font-family:monospace;line-height:1.5;tab-size:4;white-space:pre;overflow:auto}' +
				'.oc-backup{display:block;margin:1rem 0}.oc-switch-row{display:inline-flex;gap:.8rem;align-items:center;cursor:pointer}' +
				'.oc-switch{position:relative;display:inline-block;width:48px;height:26px}' +
				'.oc-switch input{opacity:0;width:1px;height:1px;position:absolute}' +
				'.oc-slider{position:absolute;inset:0;background:#999;border-radius:20px;transition:.2s}' +
				'.oc-slider:before{content:"";position:absolute;width:20px;height:20px;left:3px;top:3px;' +
				'background:#fff;border-radius:50%;transition:.2s}' +
				'.oc-switch input:checked+.oc-slider{background:#5268d7}' +
				'.oc-switch input:checked+.oc-slider:before{transform:translateX(22px)}' +
				'.oc-switch input:focus-visible+.oc-slider{outline:2px solid #5268d7;outline-offset:3px}' +
				'.oc-switch input:disabled+.oc-slider{opacity:.5}'
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
