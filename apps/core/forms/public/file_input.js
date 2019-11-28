Spider.defineWidget('Spider.Forms.FileInput', 'Spider.Forms.Input', {
	
	autoInit: true,
	
	ready: function(){
		var self = this;
		var fileLink = $('.file-link', this.el.parent());
		if (fileLink.size() == 1){
			var changeLabel = $('.change-label', this.el.parent()).text();
			var changeDiv = $('.change', this.el.parent());
			changeDiv.hide();
			clearCheckBox = $('.clear input:checkbox', this.el.parent());
			fileInput = $('.change input', this.el.parent());
			
			var link = $('<a href="#" class="js-change-link"/>');
			link.text(changeLabel+'...').insertAfter(fileLink).click(function(e){
					e.preventDefault();
					if (clearCheckBox.is(':checked')){
						link.removeClass('open');
						fileLink.removeClass('deleted');
						clearCheckBox.attr('checked', false);
						changeDiv.hide();
					}
					else{
						fileLink.addClass('deleted');
						clearCheckBox.attr('checked', true);
						link.addClass('open');
						changeDiv.show();
					}
			});
		}
		
	}    
});