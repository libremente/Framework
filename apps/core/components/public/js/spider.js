function $W(path){
    // var path_parts = path.split('/');
    // var wdgt;
    // for (var i=0; i < path_parts.length; i++){
    //     wdgt = $('.widget.id-'+path_parts[i]);
    // }
    if (Spider.widgets[path]) return Spider.widgets[path];
    var wdgt_id = path.replace(/\//g, '-');
    var wdgt = $('#'+wdgt_id);
    if (wdgt.length == 0) return null;
    return Spider.Widget.initFromEl(wdgt);
}


Spider = function(){};
if (window.SPIDER_BASE_URL) Spider.baseUrl = window.SPIDER_BASE_URL;
else Spider.baseUrl = "";

Spider.widgets = {};

Widgets = function(){};

Spider.Widget = Class.extend({
    
    init: function(container, path, config){
        this.el = container;
        this.path = path;
		var pathParts = path.split('/');
		this.widgetId = pathParts[pathParts.length - 1];
        this.fullId = pathParts.join('_');
        this.backend = new Spider.WidgetBackend(this);
		this.readyFunctions = [];
		config = $.extend({}, config);
		this.config = config;
		this.model = config.model;
        Spider.widgets[path] = this;
		this.events = [];
		this.onWidgetCallbacks = {};
		this.widgets = {};
		this.findWidgets();		
		this.startup();
		this.ready();
		this.applyReady();
		this.plugins = [];
		if (this.includePlugins){
		    for (var i=0; i<this.includePlugins.length; i++){
    			this.plugin(this.includePlugins[i]);
    		}
		} 
    },
    
    remote: function(){
        var args = Array.prototype.slice.call(arguments); 
        var method = args.shift();
		var options = {};
		if ($.isFunction(args[args.length-1])){
			options.callback = args.pop();
		}
        return this.backend.send(method, args, options);
    },

	onReady: function(callback){
		this.readyFunctions.push(callback);
		callback.apply(this);
	},
	
	applyReady: function(){
		for (var i=0; i<this.readyFunctions.length; i++){
			this.readyFunctions[i].apply(this);
		}
	},
	
	reload: function(params, callback){
		if (!callback && $.isFunction(params)){
			callback = params;
			params = {};
		}
        if ($.browser.msie){
            if (!params) params = {};
            params['_t'] = (new Date).valueOf();
        }
		$C.loadWidget(this.path, params, callback);
	},
	
	isLoaded: function(){
		return !this.el.is(':empty');
	},
	
	startup: function(){},
	ready: function(){},
	update: function(){},
	afterReplace: function(){},
	
	replaceHTML: function(html){
		var el = $(html);
		this.el.html(el.html());
		this.findWidgets();
		this.update();
		this.ready();
		Spider.newHTML(this.el);
		this.applyReady();
		this.afterReplace();
	},
	
	replaceEl: function(el){
		this.el = el;
		this.findWidgets();		
		this.update();
		this.ready();
		this.applyReady();
		this.afterReplace();
	},
	
	findWidgets: function(){
		var self = this;
		$('.widget', this.el).filter(function(index){
			if ($(this).parents('.widget').get(0) == self.el.get(0)) return true;
			return false;
		}).each(function(){
			var $this = $(this);
			var w = $this.spiderWidget();
			if (!self.widgets[w.widgetId]) self.addWidget(w.widgetId, w);
			else self.widgets[w.widgetId].replaceEl($this);
		});
	},
	
	addWidget: function(id, w){
		this.widgets[id] = w;
		if (this.onWidgetCallbacks[id]){
			for (var i=0; i<this.onWidgetCallbacks[id].length; i++){
				this.onWidgetCallbacks[id][i].call(this, w);
			}
		}
	},
	
	paramName: function(key){
		var pathParts = this.path.split('/');
		var param = "_w";
		for (var i=0; i<pathParts.length; i++){
			param += "["+pathParts[i]+"]";
		}
        var matches = key.match(/(.+)(\[.*\])/);
		if (matches){
			param += "["+matches[1]+"]"+matches[2];
		}
		else param += "["+key+"]";
		return param;
	},
	
	
	ajaxifyAll: function(options){
		var els = $('form:not(.ajaxified), a:not(.ajaxified)', this.el);
		if (!options) options = {};
		if (options.filter) els = els.filter(options.filter);
		if (options.not) els = els.not(options.not);
		this.ajaxify(els, options);
	},
	
	findWidgetsAjaxifiable: function(options){
		var selfEl = this.el.get(0);
		return $('form:not(.ajaxified), a:not(.ajaxified)', this.el).filter(function(index){
			var p = $(this).parent();
			while (p){
				if (p.is('.widget')){
					if (p.get(0) == selfEl) return true;
					return false;
				}
				p = p.parent();
			}
			return false;
		});
	},
	
	
	ajaxify: function(el, options){
		var w = this;
		if (!el || !el.eq){
			options = el;
			el = this.findWidgetsAjaxifiable();
		}
		if (!options) options = {};
		el.each(function(){
			var $this = $(this);
			if (this.tagName == 'FORM'){
				w.ajaxifyForm($(this), options);
			}
			else if (this.tagName == 'A'){
				w.ajaxifyLink($(this), options);
			}
		});

	},
	
	ajaxifyForm: function(form, options){
		var isForm = form.get(0).tagName == 'FORM';
		if (!options) options = {};
		$('input[type=submit]', form).addClass('ajaxified').bind('click.ajaxify', function(e){
			var $this = $(this);
			var w = $this.parentWidget();
			e.preventDefault();
			w.setLoading();
			var submitName = $this.attr('name');
			var submitValue = $this.val();
			var formOptions = {
				dataType: 'html',
				semantic: !isForm,
				beforeSubmit: function(data, form, options){
					data.push({name: submitName, value: submitValue});
					data.push({name: '_wt', value: w.path});
					if (options.before) options.before();
				},
				success: function(res){
				    w.trigger('ajaxifyResponse', form);
					w.replaceHTML(res);
					w.removeLoading();
					if (options.onLoad) options.onLoad(form);
					w.trigger('ajaxifyLoad', form);
				}
			};
            if (!isForm) formOptions.type = 'POST';
			form.ajaxSubmit(formOptions);
		});
	},
	
	ajaxifyLink: function(a, options){
		var w = this;
		if (!options) options = {};
		a.addClass('ajaxified').bind('click.ajaxify', function(e){
			if (options.before){
				var res = options.before.apply(w);
				if (res === false) return false ;
			}
			e.preventDefault();
			var a = $(e.target);
			var href = $(this).attr('href');
			if (!href) return true;
			var url = w.urlToAction(href);
			if (options.before) options.before();
			w.setLoading();
			$.ajax({
				url: url,
				type: 'GET',
				dataType: 'html',
				success: function(res){
                    w.trigger('ajaxifyResponse', a);
					w.replaceHTML(res);
					w.removeLoading();
					if (options.onLoad) options.onLoad(a);
					w.trigger('ajaxifyLoad', a);
				}
			});
			return true;
		});
	},
	
	urlToAction: function(url){
	    var parts = url.split('?');
		url = parts[0]; //+'.json';
		url += '?';
		if (parts[1]) url += parts[1]+'&';
		url += '_wt='+this.path;
		return url;
	},
	
	setLoading: function(){
		if (this.el.is(':empty') || this.el.children().hasClass('empty-placeholder')){
			this.el.addClass('loading-empty');
		}
		else{
			this.el.addClass('loading');
		}
	},
	
	removeLoading: function(){
		this.el.removeClass('loading').removeClass('loading-empty');
	},
	
	acceptDataObject: function(model, acceptOptions, droppableOptions){
        if (!model.push) model = [model];
        var cls = "";
        for (var i=0; i<model.length; i++){
            if (cls) cls += ', ';
            cls += '.model-'+Spider.modelToCSS(model[i])+' .dataobject';
        }
		droppableOptions = $.extend({
			accept: cls,
			hoverClass: 'drophover',
			tolerance: 'pointer'
		}, droppableOptions);
		acceptOptions = $.extend({
			el: this.el
		}, acceptOptions);
		if (acceptOptions.el != this.el){
			this.onReady(function(){ 
				$(acceptOptions.el, this.el).droppable(droppableOptions); 
			});
		}
		else this.el.droppable(droppableOptions);
	},
	
	getClassInfo: function(prefix){
		var info = [];
		var cl = this.el.attr('class');
		var cl_parts = cl.split(' ');
		for (var i=0; i < cl_parts.length; i++){
			if (cl_parts[i].substr(0, prefix.length) == prefix){
				info.push(cl_parts[i].substr(prefix.length+1));
			}
		}
		return info;
	},
	
	plugin: function(pClass, prop){
		if (prop) pClass = pClass.extend(prop);
		this.plugins[pClass] = new pClass(this);
		var plugin = this.plugins[pClass];
		for (var name in pClass.prototype){
			if (name.substring(0, 1) == '_') continue;
			if (typeof pClass.prototype[name] == "function" && !this[name]){
				this[name] = function(name){
					return function(){
						return plugin[name].apply(this, arguments);
					};
				}(name);
			}
		}
	},
	
	widget: function(id){
		return this.widgets[id];
	},
	
	onWidget: function(id, callback){
        var idParts = id.split('/', 2);
        if (idParts[1]){
            return this.onWidget(idParts[0], function(w){
                w.onWidget(idParts[1], callback);
            });
        }
        if (this.widgets[id]) callback.call(this, this.widgets[id]);
        else{
            if (!this.onWidgetCallbacks[id]) this.onWidgetCallbacks[id] = [];
    		this.onWidgetCallbacks[id].push(callback);
        }
        return true;
	},
	
	removeOnWidget: function(id, callback){
	    for (var i=0; i < this.onWidgetCallbacks[id].length; i++){
	        if (this.onWidgetCallbacks[id][i] == callback){
                this.onWidgetCallbacks[id].splice(i, 1);
                return;
	        }
	    }
	},
	
	parentWidget: function(){
        var pathParts = this.path.split('/');
        return $W(pathParts.slice(0, pathParts.length -1).join('/'));
	}
	
	
    
});

Spider.Widget.initFromEl = function(el){
	if (!el || !el.attr('id')) return null;
    var path = Spider.Widget.pathFromId(el.attr('id'));
	if (Spider.widgets[path]){
		var widget = Spider.widgets[path];
		if (el.get(0) != widget.el.get(0)) widget.replaceEl(el);
		return widget;
	} 
    var cl = el.attr('class');
    var cl_parts = cl.split(' ');
    var w_cl = null;
	var config = {};
	var i;
    for (i=0; i < cl_parts.length; i++){
        if (cl_parts[i].substr(0, 5) == 'wdgt-'){
            w_cl = cl_parts[i].substr(5);
        }
		else if (cl_parts[i].substr(0, 6) == 'model-'){
			config.model = cl_parts[i].substr(6);
		}
    }
    if (w_cl){
        var w_cl_parts = w_cl.split('-');
        var target = Widgets;
        for (i=0; i < w_cl_parts.length; i++){
            target = target[w_cl_parts[i]];
            if (!target) break;
        }
    }
    var func = null;
    if (target) func = target;
    else func = Spider.Widget;
    var obj = new func(el, path, config);
    return obj;
};

Spider.Widget.pathFromId = function(id){
	return id.replace(/-/g, '/');
};



Spider.WidgetBackend = Class.extend({

	init: function(widget){
		this.widget = widget;
		this.baseUrl = document.location.href.split('#')[0];
		this.urlParts = this.baseUrl.split('?');
		this.wUrl = this.urlParts[0]+'?';
		if (this.urlParts[1]) this.wUrl += this.urlParts[1]+'&';
		this.wUrl += '_wt='+this.widget.path;
	},

	urlForMethod: function(method){
		return this.wUrl + '&_we='+method;
	},

    // Note: args must be plain values (no arrays or objects). If you need to pass
    // an array or an object, you should encode it to a string (and decode it in the controller)
	send: function(method, args, options){
		if (!options) options = {};
		var defaults = {
			type: 'POST',
			dataType: 'json'
		};
		options = $.extend(defaults, options);
		if (!options.format) options.format = options.dataType;
		var url = this.baseUrl;
		var data = {};
		if ($.isPlainObject(args[0])) data = args[0];
		else data = {'_wp': args};
		$.extend(data, {
			'_wt': this.widget.path,
			'_we': method,
			'_wf': options.format
		});
		var callback = this.widget[method+'_response'];
		if (!callback) callback = options.callback;
		if (!callback) callback = function(){};
		delete(options.callback);
		options.success = callback;
		options.data = data;
		options.url = url;
		$.ajax(options);
	}

});

Spider.widgetClasses = {};

Spider.defineWidget = function(name, parent, w){
	if (!w){
		w = parent;
		parent = null;
	}
    var parts = name.split('.');
    var curr = Widgets;
    for (var i=0; i<parts.length-1; i++){
        if (!curr[parts[i]]) curr[parts[i]] = function(){};
        curr = curr[parts[i]];
    }
    var last = parts[parts.length-1];
    var widget;
    if (curr[last]){
        widget = curr[last].extend(w);
    } 
    else{
        if (parent) parent = Spider.widgetClasses[parent];
    	else parent = Spider.Widget;
    	widget = parent.extend(w);
    }
	curr[last] = widget;
	Spider.widgetClasses[name] = widget;
	if (w.autoInit){
		var initSelector = null;
		if (w.autoInit === true){
			initSelector = '.wdgt-'+parts.join('-');
		}
		else{
			initSelector = w.autoInit;
		}
		Spider.onHTML(function(){
			$(initSelector, this).each(function(){
				Spider.Widget.initFromEl($(this));
			});
		});
	}
	return widget;
};

Spider.Controller = Class.extend({
    
    init: function(){
        var loc = $('link[rel=index]').attr('href');
        if (loc){
            if (loc.substr(loc.length - 5) == 'index') loc = loc.substr(0, loc.length - 5);
            url = loc;
        }
        else{
            var loc = ''+document.location;
    		var slashPos = loc.lastIndexOf('/');
    		url = loc.substr(0, slashPos);
        }
		this.setUrl(url);
        this.currentAction = loc.substr(slashPos+1);
        
    },

	setUrl: function(url){
		this.url = url;
		this.publicUrl = this.url+'/public'; // FIXME
		this.homeUrl = this.url+'/_h';
	},
    
	remote: function(method, params, callback, options){
		var args = Array.prototype.slice.call(arguments); 
		if ($.isFunction(params)){
		    options = callback;
		    callback = params;
		    params = null;
		}
		if (!callback) callback = function(){};
		var url = this.url+'/'+method;
		if( options == null || options['dataType'] == null || options['dataType'] == 'json'){
			url = url+'.json';
		}
		var defaults = {
			url: url,
			type: 'POST',
			success: callback,
			data: params,
			dataType: 'json'
		};
		options = $.extend(defaults, options);
		$.ajax(options);
	},
	
	loadWidget: function(path, params, callback){
		var widget = $W(path);
		var href = document.location.href;
		var urlParts = href.split('?');
		var docParts = urlParts[0].split('#');
		var url = docParts[0]+'?_wt='+path;
		if (urlParts[1]) url += "&"+urlParts[1];
		if (params){
			for (var key in params){
				url += '&'+this.paramToQuery(params[key], widget.paramName(key));
			}
		}
		widget.setLoading();
		$.ajax({
			url: url,
			type: 'GET',
			dataType: 'html',
			success: function(res){
				widget.replaceHTML(res);
				widget.removeLoading();
				//widget.el.effect('highlight', {}, 700);
				if (callback) callback.apply(widget);
			}
		});
	},
	
	paramToQuery: function(value, prefix){
        return Spider.paramToQuery(value, prefix);
	}
    
});

$C = new Spider.Controller();

$(document).ready(function(){
	$('a.ajax').click(function(e){
		e.preventDefault();
		var a = $(e.target);
		var url = $(this).attr('href');
		var parts = url.split('?');
		url = parts[0]+'.json';
		if (parts[1]) url += '?'+parts[1];
		$.ajax({
			url: url,
			type: 'GET',
			dataType: 'json',
			success: function(res){
				a.trigger('autoAjaxSuccess', res);
			}
		});
		return false;
	});
});

$.fn.spiderWidget = function(){
	if (!this.attr('id')) return null;
	var path = Spider.Widget.pathFromId(this.attr('id'));
	if (Spider.widgets[path]) return Spider.widgets[path];
	return Spider.Widget.initFromEl(this);
};

$.fn.parentWidget = function(){
	var par = this;
	while (par && par.length > 0 && !par.is('.widget')){
		par = par.parent();
	}
	if (!par) return null;
	return par.spiderWidget();
};

$.fn.getDataObjectKey = function(){
	var doParent = null;
	var par = this;
	while (par && par.length > 0 && !par.is('.dataobject')){
		par = par.parent();
	}
	if (!par) return null;
	return $('>.dataobject-key', par).text();
};

$.fn.getDataModel = function(){
	var par = this;
	while (par && par.length > 0 && !par.is('.model')){
		par = par.parent();
	}
	if (!par) return null;
	var cl = par.attr('class');
	if (!cl) return null;
    var cl_parts = cl.split(' ');
    for (var i=0; i < cl_parts.length; i++){
		if (cl_parts[i].substr(0, 6) == 'model-'){
			return cl_parts[i].substr(6).replace(/-/g, '::');
		}
    }
    return null;
};

Spider.htmlFunctions = [];
Spider.onHTML = function(callback){
	Spider.htmlFunctions.push(callback);
	$(document).ready(function(){
		callback.call($(this.body));
	});
};

Spider.newHTML = function(el){
	for (var i=0; i<Spider.htmlFunctions.length; i++){
		Spider.htmlFunctions[i].call(el);
	}
};

Spider.modelToCSS = function(name){
	return name.split('::').join('-');
};

Spider.paramToQuery = function(value, prefix){
	var res = null;
	if (!prefix) prefix = '';
	if (!value){
		return '=null';
	}
	else if (value.push){ // array
		for (var i=0; i < value.length; i++){
			if (!res) res = "";
			else res += '&';
			res += this.paramToQuery(value[i], prefix+'[]');
		}
		return res;
	}
	else if (typeof (value) == 'object'){
		for (var name in value){
			if (!res) res = "";
			else res += '&';
			res += this.paramToQuery(value[name], prefix+'['+name+']');
		}
		return res;
	}
	else{
		return prefix+"="+value;
	}
};

jQuery.parseISODate = function(iso){
    var d = new Date();
    var r = /(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}):(\d{2}))?/.exec(iso);
    if (r){
        d.setFullYear(r[1], r[2]-1, r[3]);
        if (!r[4]) r[4] = 0; if (!r[5]) r[5] = 0; if (!r[6]) r[6] = 0;
        d.setHours(r[4], r[5], r[6], 0);
        return d;
    }
    else return null;
};

// Same as toISOString, but without time, and ignoring timezone
Date.prototype.toISODate = (function(){
    function t(i){return i<10?"0"+i:i;};
    return function(){
        return "".concat(
            this.getFullYear(), "-",
            t(this.getMonth() + 1), "-",
            t(this.getDate())
        );
    };
})();


if (!Date.prototype.toISOString){
    Date.prototype.toISOString = (function(){
        function t(i){return i<10?"0"+i:i;};
        function h(i){return i.length<2?"00"+i:i.length<3?"0"+i:3<i.length?Math.round(i/Math.pow(10,i.length-3)):i;};
        return function(){
            return "".concat(
                this.getUTCFullYear(), "-",
                t(this.getUTCMonth() + 1), "-",
                t(this.getUTCDate()), "T",
                t(this.getUTCHours()), ":",
                t(this.getUTCMinutes()), ":",
                t(this.getUTCSeconds()), ".",
                h("" + this.getUTCMilliseconds()), "Z"
            );
        };
    })();
}    


Spider.EventTarget = {
    bind: function(eventName, callback){
        if (!this.events) this.events = {};
		var handleObj = {
			callback: callback
		};
		if ( eventName.indexOf(".") > -1 ) {
			var namespaces = eventName.split(".");
			eventName = namespaces.shift();
			handleObj.namespace = namespaces.slice(0).sort().join(".");
		}
		if (!this.events[eventName]) this.events[eventName] = [];
		this.events[eventName].push(handleObj);
	},
	
	on: function(eventName, callback){ return this.bind(eventName, callback); },
	
	trigger: function(eventName){
	    if (!this.events) this.events = {};
		if ( eventName.indexOf(".") > -1 ) {
			var namespaces = eventName.split(".");
			eventName = namespaces.shift();
			namespace = namespaces.slice(0).sort().join(".");
		}
		if (!this.events[eventName]) return;
		var args = Array.prototype.slice.call(arguments, 1); 
		for (var i=0; i < this.events[eventName].length; i++){
			this.events[eventName][i].callback.apply(this, args);
		}
	},
	
	unbind: function(eventName){
	    if (!this.events) this.events = {};
		var namespace = null;
		if ( eventName.indexOf(".") > -1 ) {
			var namespaces = eventName.split(".");
			eventName = namespaces.shift();
			namespace = namespaces.slice(0).sort().join(".");
		}
		if (namespace){
			for (var i=0; i<this.events[eventName].length; i++){
				if (this.events[eventName][i].namespace == namespace){
					this.events[eventName].splice(i);
				}
			}
		}
		else this.events[eventName] = [];
	}
};

$.extend(Spider.Widget.prototype, Spider.EventTarget);

var translations = {};

function _(s){
    var str = s;
    var tr = translations[s];
    if (tr) str = tr;
    for (var i=1; i<arguments.length; i++){
        str = str.replace('%s', arguments[i]);
    }
    return str;
}

if(!window.console) {
  window.console = new function() {
    this.log = function(str) {};
    this.dir = function(str) {};
  };
}

function basename(path){
    return path.replace(/\\/g, '/').replace(/.*\//, '');
}

function dirname(path){
    return path.replace(/\\/g, '/').replace(/\/[^\/]*$/, '');
}

if(!String.prototype.trim) {
  String.prototype.trim=function(){return this.replace(/^\s+|\s+$/g, '');};
}

/* funzione per alzare il menu laterale se piu' alto di min-height */
if($("#spider-admin #container #sidebar #menu").length > 0){
	var h_menu_sidebar_admin = $("#spider-admin #container #sidebar #menu").height();
	if(h_menu_sidebar_admin > parseInt($("#spider-admin #container").css("min-height"))){
		$("#spider-admin #container").css("min-height",(h_menu_sidebar_admin+30).toString() +"px");
	}
}
