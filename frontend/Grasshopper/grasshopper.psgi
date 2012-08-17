use strict;
use warnings;
use lib 'lib/';

use Grasshopper;

my $app = Grasshopper->apply_default_middlewares(Grasshopper->psgi_app);
$app;

