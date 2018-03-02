use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

$ENV{MOJO_SELENIUM_DRIVER} = mock_driver();

eval <<'HERE' or die $@;
package MyApp;
use Mojo::Base 'Mojolicious';
use FindBin qw/$Bin/;
sub startup {
  my $self = shift;
  my $cfg = $self->plugin(Config => {file => "$Bin/config-override.conf"});
  $self->routes->get('/' => sub { shift->render(text => $cfg->{value}) } );
}
1;
HERE

my $t = Test::Mojo::WithRoles->new('MyApp');
isa_ok($t->app, 'MyApp');
is($t->app->config->{value}, 'initial', 'original value in config');
$t->navigate_ok('/')
  ->get_ok('/')
  ->content_is('initial', , 'original value in response');

$t = Test::Mojo::WithRoles->new('MyApp', { value => 'override' });
isa_ok($t->app, 'MyApp');
is($t->app->config->{value}, 'override', 'overwritten value in config');
$t->navigate_ok('/')
  ->get_ok('/')
  ->content_is('override', 'overwritten value in response');

done_testing;

sub mock_driver {
  return eval <<'HERE' || die $@;
  package Test::Mojo::Role::Selenium::MockDriver;
  sub debug_on {}
  sub default_finder {}
  sub get {}
  sub new {bless {}, 'Test::Mojo::Role::Selenium::MockDriver'}
  $INC{'Test/Mojo/Role/Selenium/MockDriver.pm'} = 'Test::Mojo::Role::Selenium::MockDriver';
HERE
}
