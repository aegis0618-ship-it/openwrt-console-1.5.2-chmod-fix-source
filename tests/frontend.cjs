const fs = require('fs');
const assert = require('assert/strict');
const source = fs.readFileSync('package/openwrt-console/files/www/luci-static/resources/view/openwrt_console.js', 'utf8');
let sent, reply = { ok: true, script: '#!/bin/sh\necho "中文 <menu>"\n',
	path: '/etc/openwrt-console/init_system_openwrt_25.12.sh', enabled: false };
let html = false;
function E(tag, attrs, children) {
	attrs = attrs || {};
	return {
		tag, attrs, children: children || [], checked: !!attrs.checked,
		value: tag === 'textarea' ? children.join('') : '',
		listeners: {}, disabled: false,
		addEventListener(name, fn) { this.listeners[name] = fn; },
		setAttribute(name, value) { this.attrs[name] = value; }
	};
}
const view = new Function('L', 'view', 'ui', 'E', source)(
	{ env: { token: 'csrf-test' }, url: (...args) => '/cgi-bin/luci/' + args.join('/') },
	{ extend: x => x }, { addNotification() {} }, E
);
global.fetch = async (url, options) => {
	assert.equal(url, '/cgi-bin/luci/admin/services/openwrt_console/action');
	sent = new URLSearchParams(options.body);
	return {
		status: 200, ok: true, redirected: false,
		headers: { get: () => html ? 'text/html' : 'application/json' },
		text: async () => html ? '<!--]]>--><html>login</html>' : JSON.stringify(reply)
	};
};
function flatten(node) {
	if (!node || typeof node !== 'object') return [];
	return [ node, ...node.children.flatMap(flatten) ];
}
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
	const state = await view.load();
	assert.equal(sent.get('token'), 'csrf-test');
	const nodes = flatten(view.render(state));
	const editor = nodes.find(n => n.tag === 'textarea');
	const backup = nodes.find(n => n.tag === 'input' && n.attrs.role !== 'switch');
	const toggle = nodes.find(n => n.attrs.role === 'switch');
	const save = nodes.find(n => n.tag === 'button');
	assert.equal(editor.value, state.script);
	assert.equal(backup.checked, true);
	backup.checked = false;
	editor.value = '#!/bin/sh\necho edited\n';
	reply = { ok: true, message: 'saved' };
	save.attrs.click();
	await flush();
	assert.equal(sent.get('operation'), 'save_script');
	assert.equal(sent.get('script'), editor.value);
	assert.equal(sent.get('backup'), '0');
	assert.equal(save.disabled, false);
	backup.checked = true;
	save.attrs.click(); await flush();
	assert.equal(sent.get('backup'), '1');
	reply = { ok: true, enabled: true };
	toggle.checked = true;
	toggle.listeners.change(); await flush();
	assert.equal(sent.get('enabled'), '1');
	assert.equal(toggle.checked, true);
	reply = { ok: false, message: 'disk full' };
	toggle.checked = false;
	toggle.listeners.change(); await flush();
	assert.equal(toggle.checked, true, 'Failed switch update must restore server state');
	html = true;
	await assert.rejects(view.load(), /HTML/);
	html = false;
	reply = { ok: false, message: 'backend error' };
	await assert.rejects(view.load(), /backend error/);
	console.log('PASS frontend: editor contents, optional backup, SSH toggle, rollback, JSON/HTML errors, CSRF');
})().catch(error => { console.error(error); process.exitCode = 1; });
