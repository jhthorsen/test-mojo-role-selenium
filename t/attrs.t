use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

use Mojolicious::Lite;
get '/' => sub { shift->render(text => 'dummy') };

my $t = Test::Mojo::WithRoles->new;

ok $t->isa('Test::Mojo'),                  'isa';
ok $t->does('Test::Mojo::Role::Selenium'), 'does';

isa_ok($t->ua, 'Test::Mojo::Role::Selenium::UserAgent');
is $t->ua->ioloop, Mojo::IOLoop->singleton, 'ua ioloop';

isa_ok($t->_server, 'Mojo::Server::Daemon');

done_testing;
