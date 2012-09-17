use strict;
use warnings;
use lib 'lib/';

use Grapture;

my $app = Grapture->apply_default_middlewares(Grapture->psgi_app);
$app;

