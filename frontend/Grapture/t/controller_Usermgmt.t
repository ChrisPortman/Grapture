use strict;
use warnings;
use Test::More;


use Catalyst::Test 'grapture';
use grapture::Controller::Usermgmt;

ok( request('/usermgmt')->is_success, 'Request should succeed' );
done_testing();
