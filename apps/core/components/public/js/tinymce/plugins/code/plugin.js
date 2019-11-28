/**
 * plugin.js
 *
 * Released under LGPL License.
 * Copyright (c) 1999-2015 Ephox Corp. All rights reserved
 *
 * License: http://www.tinymce.com/license
 * Contributing: http://www.tinymce.com/contributing
 */

/*global tinymce:true */

tinymce.PluginManager.add('code', function(editor) {
	function showDialog() {

		var win = editor.windowManager.open({
			title: "Source code",
			body: {
				type: 'textbox',
				name: 'code',
				multiline: true,
				minWidth: editor.getParam("code_dialog_width", 600),
				minHeight: editor.getParam("code_dialog_height", Math.min(tinymce.DOM.getViewPort().h - 200, 500)),
				spellcheck: false,
				style: 'direction: ltr; text-align: left'
			},
			onSubmit: function(e) {
				
				// We get a lovely "Wrong document" error in IE 11 if we
				// don't move the focus to the editor before creating an undo
				// transation since it tries to make a bookmark for the current selection
				editor.focus();

				editor.undoManager.transact(function() {
					editor.setContent(e.data.code);
				});

				editor.selection.setCursorLocation();
				editor.nodeChanged();
			}
		});

		// Gecko has a major performance issue with textarea
		// contents so we need to set it when all reflows are done
		var options = {
		  "indent":"auto",
		  "indent-spaces":2,
		  "wrap":80,
		  "markup":true,
		  "output-xml":false,
		  "numeric-entities":true,
		  "quote-marks":true,
		  "quote-nbsp":false,
		  "show-body-only":false,
		  "quote-ampersand":false,
		  "break-before-br":true,
		  "uppercase-tags":false,
		  "uppercase-attributes":false,
		  "drop-font-tags":false,
		  "tidy-mark":true,
		  "output-html": true
		}
		var result = tidy_html5(editor.getContent({source_view: true}), options);
		var result_pulito = result.replace(/<form>/gi, "").replace(/<\/form>/gi,"");
		win.find('#code').value(result_pulito);
	}

	editor.addCommand("mceCodeEditor", showDialog);

	editor.addButton('code', {
		icon: 'code',
		tooltip: 'Source code',
		onclick: showDialog
	});

	editor.addMenuItem('code', {
		icon: 'code',
		text: 'Source code',
		context: 'tools',
		onclick: showDialog
	});
});