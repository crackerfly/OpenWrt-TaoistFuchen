'use strict';
'require view';
'require form';
'require uci';
'require fs';

var UPLOAD_DIR = '/etc/taoistfuchen/';
var MAX_FAVICON_SIZE = 512 * 1024;
var MAX_LOGO_SIZE = 1024 * 1024;

function getBasename(path) {
	var parts = String(path || '').split('/');
	return parts[parts.length - 1] || '';
}

function getExtension(path) {
	var name = getBasename(path);
	var pos = name.lastIndexOf('.');
	return pos >= 0 ? name.substr(pos + 1).toLowerCase() : '';
}

function validateUpload(allowedExts, maxSize) {
	return function(section_id, value) {
		var name, ext;

		if (!value)
			return true;

		value = String(value);
		name = getBasename(value);
		ext = getExtension(value);

		if (value.indexOf(UPLOAD_DIR) !== 0)
			return _('Only files under /etc/taoistfuchen are allowed. Please upload the file from this page.');

		if (value.indexOf('/../') >= 0 || value.match(/\/\.\.?$/))
			return _('Invalid file path.');

		if (!/^[A-Za-z0-9._-]+$/.test(name))
			return _('File name can only contain letters, numbers, dots, underscores and hyphens.');

		if (allowedExts.indexOf(ext) < 0)
			return _('Unsupported file type. Supported types: %s.').format(allowedExts.join(', '));

		return fs.stat(value).then(function(stat) {
			if (!stat || stat.type !== 'file')
				return _('The selected file does not exist. Please upload it again.');

			if (stat.size && stat.size > maxSize)
				return _('The selected file is too large. Maximum size: %s KB.').format(Math.floor(maxSize / 1024));

			return true;
		}).catch(function() {
			return _('The selected file does not exist. Please upload it again.');
		});
	};
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('taoistfuchen')
		]);
	},

	render: function() {
		var m, s, o;

		m = new form.Map('taoistfuchen', _('Custom Logo'),
			_('Upload and replace the OpenWrt Web UI favicon and navigation bar logo. Files are stored under /etc/taoistfuchen.'));

		s = m.section(form.NamedSection, 'main', 'taoistfuchen', _('Basic Settings'));
		s.addremove = false;
		s.anonymous = true;

		o = s.option(form.Flag, 'enable', _('Enable Custom Logo'));
		o.rmempty = false;

		o = s.option(form.FileUpload, 'favicon', _('Web Icon (Favicon)'),
			_('Allowed types: ICO, PNG, SVG. Maximum size: 512 KB. For the most compatible /favicon.ico replacement, use ICO.'));
		o.root_directory = '/etc/taoistfuchen';
		o.optional = true;
		o.rmempty = true;
		o.depends('enable', '1');
		o.validate = validateUpload(['ico', 'png', 'svg'], MAX_FAVICON_SIZE);

		o = s.option(form.FileUpload, 'logo', _('Navigation Bar Logo'),
			_('Allowed types: PNG, SVG. Maximum size: 1024 KB. SVG is recommended for sharp display.'));
		o.root_directory = '/etc/taoistfuchen';
		o.optional = true;
		o.rmempty = true;
		o.depends('enable', '1');
		o.validate = validateUpload(['png', 'svg'], MAX_LOGO_SIZE);

		return m.render();
	}
});
