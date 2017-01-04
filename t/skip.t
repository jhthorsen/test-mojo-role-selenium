use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;
use Mojo::Util 'monkey_patch';

my $t = Test::Mojo::WithRoles->new;
my @skip;

$ENV{TEST_SELENIUM} = '0';
monkey_patch 'Test::More', plan => sub { @skip = @_ };
$t->skip_all_or_setup;
like "@skip", qr{skip_all TEST_SELENIUM}, 'TEST_SELENIUM=0';

$ENV{TEST_SELENIUM} = '1';
monkey_patch ref($t), driver => sub { die 'can haz driver' };
$t->skip_all_or_setup;
like "@skip", qr{can haz driver}, 'TEST_SELENIUM=1';

monkey_patch ref($t), driver => sub {1};
@skip = ();
$t->skip_all_or_setup;
is "@skip", "", "not skipped";
ok !$ENV{MOJO_SELENIUM_BASE_URL}, 'MOJO_SELENIUM_BASE_URL undef';

$ENV{TEST_SELENIUM} = 'http://mojolicious.org';
$t->skip_all_or_setup;
is $ENV{MOJO_SELENIUM_BASE_URL}, 'http://mojolicious.org', 'MOJO_SELENIUM_BASE_URL set';

done_testing;
