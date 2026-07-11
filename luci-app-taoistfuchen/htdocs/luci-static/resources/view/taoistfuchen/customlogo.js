'use strict';
'require view';
'require form';
'require uci';
'require request';
'require rpc';
'require ui';

var DEFAULT_LOGO = '/etc/taoistfuchen/assets/default-logo.svg';
var ASSET_PREFIX = '/etc/taoistfuchen/assets/';
var MAX_UPLOAD_SIZE = 512 * 1024;
var UPLOAD_URL = (L.env.cgi_base || '/cgi-bin') + '/taoistfuchen-upload';

function basename(path) {
	var parts = String(path || '').split(/[\\/]/);
	return parts[parts.length - 1] || '';
}

function extension(path) {
	var name = basename(path);
	var pos = name.lastIndexOf('.');
	return pos >= 0 ? name.substring(pos + 1).toLowerCase() : '';
}

function safeFilename(name, extensions) {
	return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name) &&
		name.length <= 96 && extensions.indexOf(extension(name)) >= 0;
}

var SecureUploadValue = form.Value.extend({
	__init__: function(map, section, option, title, description, settings) {
		this.super('__init__', [map, section, option, title, description]);
		this.uploadKind = settings.kind;
		this.extensions = settings.extensions;
		this.accept = settings.accept;
		this.stagingPath = settings.stagingPath;
		this.builtinPath = settings.builtinPath;
	},

	renderWidget: function(section_id, option_index, cfgvalue) {
		var current = cfgvalue || this.default || '';
		var readonly = (this.readonly != null) ? this.readonly : this.map.readonly;
		var valueWidget = new ui.Textfield(current, {
			id: this.cbid(section_id),
			optional: true,
			readonly: true,
			validate: this.getValidator(section_id),
			disabled: readonly
		});
		var valueNode = valueWidget.render();
		var fileInput = E('input', {
			'type': 'file',
			'accept': this.accept,
			'disabled': readonly ? '' : null,
			'style': 'display:none'
		});
		var status = E('span', {
			'class': 'upload-status',
			'aria-live': 'polite',
			'style': 'margin-inline-start:.75em'
		});
		var uploadButton = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-action',
			'disabled': readonly ? '' : null,
			'click': function(ev) {
				ev.preventDefault();
				fileInput.click();
			}
		}, _('Upload file…'));
		var builtinButton = this.builtinPath ? E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'disabled': readonly ? '' : null,
			'style': 'margin-inline-start:.5em',
			'click': function(ev) {
				ev.preventDefault();
				valueWidget.setValue(this.builtinPath);
				valueNode.querySelector('input').dispatchEvent(new Event('change', { bubbles: true }));
				status.textContent = _('Built-in asset selected.');
			}.bind(this)
		}, _('Use built-in asset')) : null;

		fileInput.addEventListener('change', function() {
			var file = fileInput.files && fileInput.files[0];
			var name = file ? basename(file.name) : '';

			if (!file)
				return;

			if (!safeFilename(name, this.extensions)) {
				ui.addNotification(null, E('p',
					_('Unsupported file name or type. Allowed extensions: %s.')
						.format(this.extensions.join(', '))));
				fileInput.value = '';
				return;
			}

			if (file.size < 1 || file.size > MAX_UPLOAD_SIZE) {
				ui.addNotification(null, E('p',
					_('The file must be between 1 byte and 512 KiB.')));
				fileInput.value = '';
				return;
			}

			var data = new FormData();
			data.append('sessionid', rpc.getSessionID());
			data.append('filename', this.stagingPath);
			data.append('filedata', file);
			status.textContent = _('Uploading…');
			uploadButton.disabled = true;
			if (builtinButton)
				builtinButton.disabled = true;

			request.post('%s?kind=%s&name=%s'.format(
				UPLOAD_URL, encodeURIComponent(this.uploadKind), encodeURIComponent(name)), data, {
				timeout: 0,
				progress: function(pev) {
					if (pev.total)
						status.textContent = _('Uploading… %s%%')
							.format(Math.floor((pev.loaded / pev.total) * 100));
				}
			}).then(function(res) {
				var reply = res.json();

				if (!reply || reply.ok !== true || !reply.path)
					throw new Error(reply && reply.error ? reply.error : _('Upload failed.'));

				valueWidget.setValue(reply.path);
				valueNode.querySelector('input').dispatchEvent(new Event('change', { bubbles: true }));
				status.textContent = _('Upload complete. Click “Save & Apply” to activate it.');
			}).catch(function(err) {
				status.textContent = _('Upload failed.');
				ui.addNotification(null, E('p',
					_('Upload failed: %s').format(err.message || err)));
			}).finally(function() {
				uploadButton.disabled = readonly;
				if (builtinButton)
					builtinButton.disabled = readonly;
				fileInput.value = '';
			});
		}.bind(this));

		return E('div', { 'class': 'cbi-value-field' }, [
			valueNode,
			E('div', { 'style': 'margin-top:.5em' }, [
				fileInput,
				uploadButton,
				builtinButton,
				status
			])
		]);
	},

	validate: function(section_id, value) {
		var name;

		if (!value || (this.builtinPath && value === this.builtinPath))
			return true;

		if (String(value).indexOf(ASSET_PREFIX) !== 0)
			return _('Select the built-in logo or upload a file from this page.');

		name = basename(value);
		if (value !== ASSET_PREFIX + name || !safeFilename(name, this.extensions))
			return _('The selected asset path is invalid.');

		return true;
	}
});

return view.extend({
	load: function() {
		return uci.load('taoistfuchen');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('taoistfuchen', _('Custom Logo'),
			_('Use the trusted built-in SVG or upload a PNG logo and a PNG/ICO browser icon. User-supplied SVG files are intentionally blocked for security.'));

		s = m.section(form.NamedSection, 'main', 'taoistfuchen', _('Basic Settings'));
		s.addremove = false;
		s.anonymous = true;

		o = s.option(form.Flag, 'enable', _('Enable Custom Logo'));
		o.rmempty = false;

		o = s.option(SecureUploadValue, 'logo', _('Navigation Bar Logo'),
			_('Default: the built-in SVG supplied with this package. Custom files must be PNG and no larger than 512 KiB.'), {
				kind: 'logo',
				extensions: ['png'],
				accept: '.png,image/png',
				stagingPath: '/var/run/taoistfuchen-upload/pending-logo',
				builtinPath: DEFAULT_LOGO
			});
	o.default = DEFAULT_LOGO;
	o.rmempty = true;
	o.retain = true;
	o.depends('enable', '1');

		o = s.option(SecureUploadValue, 'favicon', _('Web Icon (Favicon)'),
			_('Default: the built-in SVG. Custom files must be PNG or ICO and no larger than 512 KiB.'), {
				kind: 'favicon',
				extensions: ['png', 'ico'],
				accept: '.png,.ico,image/png,image/x-icon',
				stagingPath: '/var/run/taoistfuchen-upload/pending-favicon',
				builtinPath: DEFAULT_LOGO
			});
	o.default = DEFAULT_LOGO;
	o.rmempty = true;
	o.retain = true;
	o.depends('enable', '1');

		return m.render();
	}
});
