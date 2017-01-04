use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

my $t = Test::Mojo::WithRoles->new;

$ENV{MOJO_SELENIUM_BASE_URL} = $ENV{TEST_BASE_URL} || '';
$ENV{MOJO_SELENIUM_DRIVER} ||= 'Selenium::Chrome';

plan skip_all => $@ || 'TEST_BASE_URL=http://mojolicious.org'
  unless $ENV{TEST_BASE_URL} and eval { $t->driver };

$t->set_window_size([1024, 768]);

$t->navigate_ok('/perldoc')->live_text_is('a[href="#GUIDES"]' => 'GUIDES')
  ->element_is_displayed("a");

$t->element_is_displayed("input[name=q]")->send_keys_ok("input[name=q]", ["render", \"enter"]);

$t->current_url_like(qr{q=render})->live_element_exists("input[name=search][value=render]");

eval { $t->status_is(200) };
like $@, qr{undefined value}, 'cannot call Test::Mojo methods on external results';

done_testing;
