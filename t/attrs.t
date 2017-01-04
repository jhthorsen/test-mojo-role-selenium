use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

use Mojolicious::Lite;
get '/' => sub { shift->render(text => 'dummy') };

my $driver = mock_driver();
my $t      = Test::Mojo::WithRoles->new->driver($driver);
$t->driver($driver);

ok $t->isa('Test::Mojo'),                  'isa';
ok $t->does('Test::Mojo::Role::Selenium'), 'does';

isa_ok($t->ua, 'Test::Mojo::Role::Selenium::UserAgent');
is $t->ua->ioloop, Mojo::IOLoop->singleton, 'ua ioloop';

isa_ok($t->_live_server, 'Mojo::Server::Daemon');
is $t->_live_server->listen->[0], $t->_live_base, 'listen';

$t = Test::Mojo::WithRoles->new->driver($driver);
$ENV{MOJO_SELENIUM_BASE_URL} = 'http://mojolicious.org';
is $t->_live_base, 'http://mojolicious.org', 'custom base';
$t->navigate_ok('/perldoc');
is $t->_live_url, 'http://mojolicious.org/perldoc', 'live url';
ok !$t->{_live_server}, 'server not built';

done_testing;

sub mock_driver {
  eval <<'HERE' or die $@;
  package Test::Mojo::Role::Selenium::MockDriver;
  sub get {}
  1;
HERE

  return bless {}, 'Test::Mojo::Role::Selenium::MockDriver';
}
