use strict;
use warnings;
use Test::More;


use Catalyst::Test 'grapture';
use grapture::Controller::Rest;

ok( request('/rest')->is_success, 'Request should succeed' );
done_testing();
