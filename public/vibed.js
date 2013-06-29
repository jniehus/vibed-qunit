// set up globals params object that all tests can access

var parameters = null;

$.extend({
    // jQuery method extension to capture any parameters that were passed in via the URL
    // from: http://jquery-howto.blogspot.com/2009/09/get-url-parameters-values-with-jquery.html
    getUrlVars: function() {
        var vars = {}, hash;
        var hashes = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
        for(var i = 0; i < hashes.length; i++) {
            hash = hashes[i].split('=');
            vars[decodeURIComponent(hash[0])] = decodeURIComponent(hash[1]);
        }
        return vars;
    },

    getUrlVar: function(name) {
        return $.getUrlVars()[name];
    }
});

$(document).ready(function() {
    /** VIBE SETUP **/
    parameters = $.getUrlVars();

    // generic method to post requests to vibe
    function postRequest (req) {
        req["browser"] = parameters["browser"];
        return $.ajax({
            type: 'POST',
            url: '/process_req',
            data: JSON.stringify(req),
            contentType: 'application/json',
            dataType: 'text'
        });
    }

    // routine to get information about what happened in the event of an error/failure in a test case
    function parseQunitTestAssertions(details) {
        var testli = $('.test-name:contains(' + details['name'] + ')').parent().parent('li');
        var assertions = [];

        testli.find('ol').children('.fail').each(function(index) {
            var assertion = {};
            if ($(this).find('.test-message').length  != 0) { assertion['message']  = $(this).find('.test-message').text();  }
            if ($(this).find('.test-expected').length != 0) { assertion['expected'] = $(this).find('.test-expected').text(); }
            if ($(this).find('.test-actual').length   != 0) { assertion['result']   = $(this).find('.test-actual').text();   }

            // excessive details i dont find usefull
            //if ($(this).find('.test-diff').length   != 0) { assertion['diff']   = $(this).find('.test-diff').text();   }
            //if ($(this).find('.test-source').length != 0) { assertion['source'] = $(this).find('.test-source').text(); }
            assertions.push(assertion);
        });
        return assertions;
    }

    // ajax request to vibe to log results of a specific QUnit test case
    function testResults(details) {
        details['action'] = "testresults"
        if (details['failed'] > 0) {
            details['assertions'] = parseQunitTestAssertions(details)
        }
        postRequest(details).done(function() {
            /* do nothing for now */
        });
    }

    // ajax request to vibe to log results of QUnit suite
    function suiteResults(details) {
        details['action'] = "suiteresults"
        setTimeout(function() {
            postRequest(details).done(function(data) {
                setTimeout(function() {
                    postRequest({action:'qunitdone'});
                }, 500);
            });
        }, 500);
    }

    // call this function after each test is done
    QUnit.testDone( testResults );

    // call this function when QUnit is done
    QUnit.done( suiteResults );
});