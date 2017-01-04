use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

my $t = Test::Mojo::WithRoles->new;

plan skip_all => $@ || 'TEST_BASE_URL=http://mojolicious.org'
  unless $ENV{TEST_BASE_URL} and eval { $t->driver };

$ENV{MOJO_SELENIUM_BASE_URL} = $ENV{TEST_BASE_URL};
$t->navigate_ok('/perldoc')->live_text_is('a[href="#GUIDES"]' => 'GUIDES')
  ->click_ok('a[href="#GUIDES"]');

eval { $t->status_is(200) };
like $@, qr{undefined value}, 'cannot call Test::Mojo methods on external results';

done_testing;
