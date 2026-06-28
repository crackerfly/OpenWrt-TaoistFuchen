'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require rpc';
'require poll';

var LOG_PATH = '/tmp/fakehttp.log';

/* Ask procd whether a given service has a running instance. */
var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

function serviceRunning(name) {
	return L.resolveDefault(callServiceList(name), {}).then(function (res) {
		try {
			var inst = res[name].instances;
			for (var k in inst)
				if (inst[k] && inst[k].running)
					return true;
		} catch (e) {}
		return false;
	});
}

/* List real network interfaces from /sys/class/net (skip loopback). */
function listInterfaces() {
	return L.resolveDefault(fs.list('/sys/class/net'), []).then(function (entries) {
		var names = [];
		(entries || []).forEach(function (e) {
			if (e && e.name && e.name !== 'lo')
				names.push(e.name);
		});
		names.sort();
		return names;
	});
}

/* Best-effort: find the WAN egress device from the default route. */
function detectWanDevice() {
	return L.resolveDefault(fs.read('/proc/net/route'), '').then(function (txt) {
		var lines = String(txt || '').split(/\n/);
		for (var i = 1; i < lines.length; i++) {
			var f = lines[i].split(/\s+/);
			if (f.length >= 2 && f[1] === '00000000' && f[0])
				return f[0];
		}
		return '';
	});
}

/* Keep only the last N lines of a blob of text. */
function tailText(txt, maxLines) {
	txt = String(txt || '').replace(/\s+$/, '');
	if (!txt) return '';
	var lines = txt.split(/\n/);
	if (maxLines && lines.length > maxLines)
		lines = lines.slice(lines.length - maxLines);
	return lines.join('\n');
}

/* Re-read the log file and push it into the textarea. */
function refreshLog() {
	return L.resolveDefault(fs.read(LOG_PATH), '').then(function (txt) {
		var el = document.getElementById('fakehttp-logview');
		if (!el) return;
		var t = tailText(txt, 200);
		if (t) {
			el.value = t;
			el.scrollTop = el.scrollHeight;
		} else {
			el.value = _('(No log yet. Enable the service, click Save & Apply, then wait a moment.)');
		}
	});
}

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('fakehttp'),
			listInterfaces(),
			detectWanDevice(),
			serviceRunning('fakehttp')
		]);
	},

	render: function (data) {
		var ifaces  = data[1] || [];
		var wandev  = data[2] || '';
		var running = data[3] || false;

		var m, s, o;

		m = new form.Map('fakehttp', _('FakeHTTP'),
			_('FakeHTTP disguises your outgoing TCP connections as ordinary HTTP traffic so that Deep Packet Inspection (DPI) systems have a harder time fingerprinting them. It only acts during the TCP handshake — it is not a tunnel or a proxy, and it does not change where your traffic goes, only how it looks on the wire. You normally only need to run it on one side of a connection.'));

		s = m.section(form.NamedSection, 'main', 'fakehttp', _('Settings'));
		s.addremove = false;
		s.anonymous = true;

		o = s.option(form.DummyValue, '_status', _('Service status'));
		o.cfgvalue = function () {
			return running ? _('Running') : _('Stopped');
		};

		o = s.option(form.Flag, 'enabled', _('Enable'),
			_('Turn FakeHTTP on. After enabling, choose the interface below and click Save & Apply.'));
		o.rmempty = false;

		o = s.option(form.Value, 'interface', _('Network interface'),
			_('Pick the interface that faces the Internet — the one your traffic leaves through. For PPPoE dial-up this is usually %s; otherwise choose your WAN device. You can select one from the list or type a name.').format('<code>pppoe-wan</code>'));
		ifaces.forEach(function (n) { o.value(n); });
		if (wandev)
			o.default = wandev;
		o.rmempty = false;
		o.validate = function (section_id, value) {
			var en = this.map.lookupOption('enabled', section_id);
			var enabled = (en && en[0]) ? en[0].formvalue(section_id) : '0';
			if (enabled === '1' && (!value || !value.trim()))
				return _('Please choose the Internet-facing interface before applying.');
			return true;
		};

		o = s.option(form.Value, 'hostname', _('Obfuscation hostname'),
			_('The website name your TCP connections will be disguised as. Any ordinary-looking domain works; the default is fine for most people.'));
		o.default = 'www.speedtest.net';
		o.rmempty = false;
		o.validate = function (section_id, value) {
			if (!value || !value.trim())
				return _('Please enter a hostname.');
			if (!/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(value))
				return _('Enter a bare hostname such as www.speedtest.net (no http://, no slashes).');
			return true;
		};

		o = s.option(form.Value, 'boot_delay', _('Boot start delay (seconds)'),
			_('How many seconds to wait after the router boots before this service starts, so a slow WAN (e.g. PPPoE dial-up) can come online first. Range 0–120; default 30. The delay applies only at boot — toggling Enable above starts the service right away.'));
		o.default = '30';
		o.placeholder = '30';
		o.rmempty = false;
		o.validate = function (section_id, value) {
			if (value === null || String(value).trim() === '')
				return _('Please enter the delay in seconds (0–120).');
			if (!/^\d+$/.test(String(value).trim()))
				return _('Enter a whole number of seconds (0–120).');
			var n = parseInt(value, 10);
			if (n < 0 || n > 120)
				return _('The delay must be between 0 and 120 seconds.');
			return true;
		};

		return m.render().then(function (mapNode) {
			var logView = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Run log')),
				E('div', { 'class': 'cbi-section-descr' },
					_('Live output from FakeHTTP. The log is stored in RAM at %s and is trimmed automatically (every 30 minutes, and on reboot) so it can never fill up storage. It refreshes every few seconds.').format('<code>' + LOG_PATH + '</code>')),
				E('textarea', {
					'id': 'fakehttp-logview',
					'readonly': 'readonly',
					'wrap': 'off',
					'style': 'width:100%;height:320px;font-family:monospace;font-size:12px;resize:vertical;'
				}, [ _('Loading…') ]),
				E('div', { 'style': 'margin-top:8px;' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-remove',
						'click': function (ev) {
							ev.target.blur();
							return L.resolveDefault(fs.write(LOG_PATH, ''), null).then(refreshLog);
						}
					}, [ _('Clear log') ])
				])
			]);

			poll.add(refreshLog, 5);
			refreshLog();

			return E('div', {}, [ mapNode, logView ]);
		});
	}
});
