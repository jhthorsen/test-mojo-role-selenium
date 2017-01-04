use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;
use Mojo::Util 'monkey_patch';

my $t = Test::Mojo::WithRoles->new;
my @skip;

$ENV{MOJO_SELENIUM_DRIVER} = mock_driver();
$ENV{TEST_SELENIUM}        = '0';

monkey_patch 'Test::More', plan => sub { @skip = @_ };
$t->skip_all_or_setup;
like "@skip", qr{skip_all TEST_SELENIUM}, 'TEST_SELENIUM=0';

$ENV{TEST_SELENIUM} = '1';
monkey_patch 'Test::Mojo::Role::Selenium::MockDriver', new => sub { die 'can haz driver' };
$t->skip_all_or_setup;
like "@skip", qr{can haz driver}, 'TEST_SELENIUM=1';

@skip = ();
monkey_patch 'Test::Mojo::Role::Selenium::MockDriver',
  new => sub { bless {}, 'Test::Mojo::Role::Selenium::MockDriver' };
$t->skip_all_or_setup;
is "@skip", "", "not skipped";
ok !$ENV{MOJO_SELENIUM_BASE_URL}, 'MOJO_SELENIUM_BASE_URL undef';

$ENV{TEST_SELENIUM} = 'http://mojolicious.org';
$t->skip_all_or_setup;
is $ENV{MOJO_SELENIUM_BASE_URL}, 'http://mojolicious.org', 'MOJO_SELENIUM_BASE_URL set';
is $t->_live_base, 'http://mojolicious.org', 'base url';

done_testing;

sub mock_driver {
  return eval <<'HERE' or die $@;
  package Test::Mojo::Role::Selenium::MockDriver;
  sub debug_on {}
  sub default_finder {}
  sub get {}
  $INC{'Test/Mojo/Role/Selenium/MockDriver.pm'} = 'Test::Mojo::Role::Selenium::MockDriver';
HERE
}
