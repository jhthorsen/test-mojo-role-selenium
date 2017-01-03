use Mojo::Base -strict;
use Test::Mojo::WithRoles 'Selenium';
use Test::More;

use Mojolicious::Lite;
get '/' => 'index';
my $t = Test::Mojo::WithRoles->new;

# Make sure the driver can be initialized
plan skip_all => $@ unless eval { $t->driver };

$t->live_get_ok('/')->status_is(200)->text_is('a.logo' => 'Logo')->live_text_is('a.logo' => 'Logo')
  ->live_element_exists('nav')->element_is_displayed('nav')->active_element_is('input[name=q]')
  ->send_keys_ok('input[name=q]', 'Mojo');

$t->submit_ok('form')->status_is(200)->current_url_like(qr{q=Mojo})
  ->live_element_exists('input[name=q][value=Mojo]');

$t->click_ok('nav a.logo')->status_is(200);

$t->live_get_ok('/not-found')->status_is(404);

done_testing;

__DATA__
@@ index.html.ep
<!DOCTYPE html>
<html>
<head>
  <title>test title</title>
</head>
<body>
<nav>
  <a href="/" class="logo">Logo</a>
</nav>
%= form_for '', begin
  %= text_field 'q'
% end
%= javascript begin
document.querySelector("input").focus();
% end
</body>
