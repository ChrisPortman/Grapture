use strict;
use warnings;

use Grasshopper;

my $app = Grasshopper->apply_default_middlewares(Grasshopper->psgi_app);
$app;

