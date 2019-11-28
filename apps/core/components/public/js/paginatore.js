/* funzioni per paginatore v 1 */
/* il parametro scope limita il funzionamento ad un pezzo della pagina, serve per avere più paginatori nella pagina */
/* stesso paginatore presente in portal */

function previous(scope){
    if (scope === undefined) {
          scope = 'body';
    } 
    new_page = parseInt($(scope).find('#current_page').val())-1;
    /* if there is an item before the current active link run the function */
    if($(scope).find('.active_page').prev('.page_link').length==true){
        go_to_page(new_page, scope);
    }

};

function next(scope){
    if (scope === undefined) {
          scope = 'body';
    }
    new_page = parseInt($(scope).find('#current_page').val())+1;
    /*if there is an item after the current active link run the function */
    if($(scope).find('.active_page').next('.page_link').length==true){
        go_to_page(new_page, scope);
    }

};

function go_to_page(page_num, scope){
    if (scope === undefined) {
          scope = 'body';
    }

    /*get the number of items shown per page*/
    var show_per_page = parseInt($(scope).find('#show_per_page').val());

    /*get the element number where to start the slice from*/
    start_from = page_num * show_per_page;

    /*get the element number where to end the slice*/
    end_on = start_from + show_per_page;

    /*hide all children elements of pagination_content div, get specific items and show them*/
    $(scope).find('.pagination_content .paginated_element').hide().slice(start_from, end_on).show();

    /*get the page link that has longdesc attribute of the current page and add active_page class to it
    and remove that class from previously active page link*/
    $(scope).find('.page_link.active_page').removeClass('active_page');
    

    /*how much items per page to show */
    var show_per_page = parseInt($(scope).find("#items_per_page").val());
    /* numero di pagine nella navigation bar */
    var max_page_in_navbar = parseInt($(scope).find("#max_page_in_navbar").val());
    /*getting the amount of elements inside pagination_content div*/
    //var number_of_items = $(scope).find('.pagination_content').children().size();
    var number_of_items = parseInt($(scope).find('.pagination_content .paginated_element').size());
    /*calculate the number of pages we are going to have*/
    var number_of_pages = Math.ceil(number_of_items/show_per_page);


    /*update the current page input field*/
    $(scope).find('#current_page').val(page_num);

    if(number_of_pages>max_page_in_navbar){
        /* su la pag corrente è maggiore del numero di pagine - metà delle pagine mostrate nella navbar non traslo più le pagine*/
        if(page_num >= (number_of_pages-Math.floor(parseInt(max_page_in_navbar)/2)))
        {
            $(scope).find(".page_navigation").empty();
            var navigation_html = "<li class=\"previous_link\"><a href=\"javascript:previous('"+scope+"');\">Prev</a></li>";
            for (i=number_of_pages-max_page_in_navbar; i<number_of_pages; i++){

                navigation_html += "<li class=\"page_link\" longdesc=\"" + i +"\"><a href=\"javascript:go_to_page(" + i +", '" + scope + "')\" >"+ (i + 1) +"</a></li>";
            }
            navigation_html += "<li class=\"next_link\"><a href=\"javascript:next('"+scope+"');\">Next</a></li>";
            $(scope).find('.page_navigation').html(navigation_html);
        }
        else
        /* traslo le pagine */
        {
            var current_link = (page_num-Math.floor(max_page_in_navbar/2));
            if(current_link<1){
               current_link = 0; 
            }
            $(scope).find(".page_navigation").empty();
            var navigation_html = "<li class=\"previous_link\"><a href=\"javascript:previous('"+scope+"');\">Prev</a></li>";
            for (i=current_link; i<(current_link+max_page_in_navbar); i++){
                navigation_html += "<li class=\"page_link\" longdesc=\"" + i +"\"><a href=\"javascript:go_to_page(" + i +", '" + scope + "')\" >"+ (i + 1) +"</a></li>";
            }
            navigation_html += "<li class=\"page_link\" longdesc=\"...\"><a href=\"#\">...</a></li>";
            navigation_html += "<li class=\"next_link\"><a href=\"javascript:next('"+scope+"');\">Next</a></li>";
            $(scope).find('.page_navigation').html(navigation_html);
         }

    }

    $(scope).find(".page_link[longdesc='"+page_num+"']").addClass('active_page');

};

function init_paginatore(scope){
    if (scope === undefined) {
          scope = 'body';
    }

    /*how much items per page to show */
    var show_per_page = $(scope).find("#items_per_page").val();
    /* numero di pagine nella navigation bar */
    var max_page_in_navbar = $(scope).find("#max_page_in_navbar").val();
    /*getting the amount of elements inside pagination_content div*/
    //var number_of_items = $(scope).find('.pagination_content').children().size();
    var number_of_items = $(scope).find('.pagination_content .paginated_element').size();
    /*calculate the number of pages we are going to have*/
    var number_of_pages = Math.ceil(number_of_items/show_per_page);

    /*set the value of our hidden input fields*/
    $(scope).find('#current_page').val(0);
    $(scope).find('#show_per_page').val(show_per_page);

    /*
    what are we going to have in the navigation?
        - link to previous page
        - links to specific pages
        - link to next page
    */
    if(number_of_pages>0){

        var navigation_html = "<li class=\"previous_link\"><a href=\"javascript:previous('"+scope+"');\">Prev</a></li>";
        var current_link = 0;
        if(number_of_pages<max_page_in_navbar)
        {
            while(number_of_pages > current_link){
                navigation_html += "<li class=\"page_link\" longdesc=\"" + current_link +"\"><a href=\"javascript:go_to_page(" + current_link +", '" + scope + "')\" >"+ (current_link + 1) +"</a></li>";
                //navigation_html += '<li class="page_link" longdesc="' + current_link +'"><a href="javascript:go_to_page(' + current_link +', \"' + scope + '\")" >'+ (current_link + 1) +'</a></li></ul>';
                current_link++;
            }
        }
        else{
            while(current_link<max_page_in_navbar){
                navigation_html += "<li class=\"page_link\" longdesc=\"" + current_link +"\"><a href=\"javascript:go_to_page(" + current_link +", '" + scope + "')\" >"+ (current_link + 1) +"</a></li>";
                current_link++;
            }
            navigation_html += "<li class=\"page_link\" longdesc=\"...\"><a href=\"#\">...</a></li>";
        }
        navigation_html += "<li class=\"next_link\"><a href=\"javascript:next('"+scope+"');\">Next</a></li>";

        $(scope).find('.page_navigation').html(navigation_html);

        /*add active_page class to the first page link*/
        $(scope).find('.page_navigation .page_link:first').addClass('active_page');

        /*hide all the elements inside pagination_content div*/
        /*$(scope).find('.pagination_content').children().css('display', 'none');*/
        $(scope).find('.pagination_content .paginated_element').hide();

        /*and show the first n (show_per_page) elements*/
        /*$(scope).find('.pagination_content').children().slice(0, show_per_page).css('display', 'block');*/
        $(scope).find('.pagination_content .paginated_element').slice(0, show_per_page).show();

    }
}


