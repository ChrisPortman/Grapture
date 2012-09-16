use strict;
use warnings;
use Test::More;


use Catalyst::Test 'grapture';
use grapture::Controller::static;

ok( request('/static')->is_success, 'Request should succeed' );
done_testing();
