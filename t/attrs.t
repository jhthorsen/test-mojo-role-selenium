use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

use Mojolicious::Lite;
get '/' => sub { shift->render(text => 'dummy') };

my $t = Test::Mojo::WithRoles->new;
like $t->base, qr{http://127.0.0.1:\w+}, 'base';

isa_ok($t->_server, 'Mojo::Server::Daemon');
my $pid = $t->{server_pid};
like $pid, qr{\d+}, 'server pid';
ok kill(0, $pid), 'server is alive';

undef $t;
ok !kill(0, $pid), 'server was killed';

done_testing;
