/**
 * QUnit command line
**/

$(window).load(function () {
    /** VIBE **/
    var vibe = 'http://localhost:23432';

    // generic method to post requests to vibe
    function postRequest (req) {
        // this will tag each request with a specific
        // browser. This should help with parallelization
        req["browser"] = $.browser;
        return $.ajax({
            type: 'POST',
            url: vibe + '/process_req',
            data: JSON.stringify(req),
            contentType: 'application/json',
            dataType: 'text'
        });
    }

    function doWorkVibe(data) {
        data['action'] = 'dowork';
        return postRequest(data);
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
        postRequest(details).done(function() { /* do nothing for now */ });
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


    /** SETUP **/
    // call this function after each test is done
    QUnit.testDone(testResults);

    // call this function when QUnit is done
    QUnit.done(suiteResults);


    /** NOW ACTUAL TESTS **/
    //---
    module( "Module 1" );
    test( "hello test", 1, function() {
        ok( 1 == "1", "Passed!" );
    });

    asyncTest( "Hey vibe, go do some work", 5, function() {
        doWorkVibe({data:42}).done(function(vibeResponse) {
            equal( vibeResponse, 'done', 'Vibe should do something');
            equal( "e^(tau/2*i) + 1", 0, "eulers identity: 0, 1, i, tau/2, AND e ALL in one formula!?" );
            equal( (2+2), 4, "2+2 == 4");
            ok( 1 == 2, "fail :(");
            equal(2, 4, "2 == 4");
            start();
        });
    });

    //---
    module( "Module 2");
    test( "world test", 1, function() {
        ok ( true == true, "Passed!");
    });

    asyncTest( "Timeout test", 1, function() {
        setTimeout(function() {
            ok(true, "waiting...");
            start();
        }, 30); // set to 30000 to mimic a hang
    });
});

// END