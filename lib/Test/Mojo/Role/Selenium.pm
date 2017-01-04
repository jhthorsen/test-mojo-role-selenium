package Test::Mojo::Role::Selenium;
use Mojo::Base -base;
use Role::Tiny;

use File::Basename ();
use File::Spec;
use Mojo::Util qw(encode monkey_patch);
use Selenium::Remote::WDKeys;

use constant DEBUG => $ENV{MOJO_SELENIUM_DEBUG} || 0;

our $VERSION = '0.01';

my $SCRIPT_NAME = File::Basename::basename($0);
my $SCREENSHOT  = 1;

has driver => sub {
  my $self   = shift;
  my $args   = $self->driver_args;
  my $driver = $ENV{MOJO_SELENIUM_DRIVER} || $args->{driver_class} || 'Selenium::PhantomJS';
  eval "require $driver;1" or die $@;
  warn "[Selenium] Using $driver\n" if DEBUG;
  $driver = $driver->new(%$args, ua => $self->ua);
  $driver->debug_on if DEBUG > 1;
  $driver->default_finder('css');
  $driver;
};

has driver_args          => sub { +{} };
has screenshot_directory => sub { File::Spec->tmpdir };

has _live_base => sub {
  my $self = shift;
  return Mojo::URL->new($ENV{MOJO_SELENIUM_BASE_URL}) if $ENV{MOJO_SELENIUM_BASE_URL};
  $self->{live_port} = Mojo::IOLoop::Server->generate_port;
  return Mojo::URL->new("http://127.0.0.1:$self->{live_port}");
};

has _live_server => sub {
  my $self   = shift;
  my $app    = $self->app or die 'Cannot start server without $t->app(...) set';
  my $server = Mojo::Server::Daemon->new(silent => DEBUG ? 0 : 1);

  Scalar::Util::weaken($self);
  $server->on(
    request => sub {
      my ($server, $tx) = @_;
      $self->tx($tx) if $tx->req->url->to_abs eq $self->_live_url;
    }
  );

  $server->app($app)->listen([$self->_live_base->to_string])
    ->start->ioloop->acceptor($server->acceptors->[0]);

  return $server;
};

has _live_url => sub { Mojo::URL->new };

sub active_element_is {
  my ($self, $selector, $desc) = @_;
  my $driver = $self->driver;
  my $active = $driver->get_active_element;
  my $el     = $self->_proxy(find_element => $selector);
  my $same   = $active && $el ? $driver->compare_elements($active, $el) : 0;

  return $self->_test('ok', $same, _desc($desc, "active element is $selector"));
}

sub capture_screenshot {
  my ($self, $path) = @_;
  $path = _screenshot_name($path ? "$path.png" : "%0-%t-%n.png");
  $path = File::Spec->catfile($self->screenshot_directory, $path);
  Test::More::diag("Saving screenshot to $path");
  $self->driver->capture_screenshot($path);
  return $self;
}

sub click_ok {
  my ($self, $selector, $desc) = @_;
  my $el = $selector ? $self->_proxy(find_element => $selector) : $self->driver->get_active_element;
  $el->click if $el;
  return $self->_test('ok', $el, _desc($desc, "click on $selector"));
}

sub current_url_is {
  my $self = shift;
  my $url  = $self->_live_abs_url(shift);

  return $self->_test('is', $self->driver->get_current_url,
    $url->to_string, _desc('exact match for current url'));
}

sub current_url_like {
  my ($self, $match, $desc) = @_;
  return $self->_test('like', $self->driver->get_current_url,
    $match, _desc($desc, 'current url is similar'));
}

sub element_is_displayed {
  my ($self, $selector, $desc) = @_;
  my $el = $self->_proxy(find_element => $selector);
  return $self->_test('ok', ($el && $el->is_displayed),
    _desc($desc, "element $selector is displayed"));
}

sub element_is_hidden {
  my ($self, $selector, $desc) = @_;
  my $el = $self->_proxy(find_element => $selector);
  return $self->_test('ok', ($el && $el->is_hidden), _desc($desc, "element $selector is hidden"));
}

sub live_element_count_is {
  my ($self, $selector, $count, $desc) = @_;
  my $els = $self->_proxy(find_elements => $selector);
  return $self->_test('is', int(@$els), $count,
    _desc($desc, qq{element count for selector "$selector"}));
}

sub live_element_exists {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{element for selector "$selector" exists});
  return $self->_test('ok', $self->_proxy(find_element => $selector), $desc);
}

sub live_element_exists_not {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{no element for selector "$selector"});
  return $self->_test('ok', !$self->_proxy(find_element => $selector), $desc);
}

sub live_text_is {
  my ($self, $selector, $value, $desc) = @_;
  return $self->_test('is', $self->_live_text($selector),
    $value, _desc($desc, qq{exact match for selector "$selector"}));
}

sub live_text_like {
  my ($self, $selector, $regex, $desc) = @_;
  return $self->_test('like', $self->_live_text($selector),
    $regex, _desc($desc, qq{similar match for selector "$selector"}));
}

sub navigate_ok {
  my $self = shift;
  my $url  = $self->_live_abs_url(shift);
  my ($desc, $err);

  $self->tx(undef)->_live_url($url);
  $self->_live_server if $self->{live_port};    # Make sure server is running
  $self->driver->get($url->to_string);

  if ($self->tx) {
    $desc = "navigate to $url";
    $err  = $self->tx->error;
    Test::More::diag($err->{message}) if $err and $err->{message};
  }
  else {
    $desc = "navigate to $url (\$t->tx() is not set)";
  }

  return $self->_test('ok', !$err, _desc($desc));
}

around new => sub {
  my $next = shift;
  my $self = $next->(@_);
  $self->ua(Test::Mojo::Role::Selenium::UserAgent->new->ioloop(Mojo::IOLoop->singleton));
  return $self;
};

sub send_keys_ok {
  my ($self, $selector, $keys, $desc) = @_;
  my $el = $self->_proxy(find_element => $selector);
  map { $el->send_keys(ref $_ ? KEYS->{$_} : $_) } ref $keys ? @$keys : ($keys) if $el;
  return $self->_test('ok', $el, _desc($desc, "keys sent to $selector"));
}

sub set_window_size {
  my ($self, $size, $desc) = @_;
  $self->driver->set_window_size(reverse @$size);
  return $self;
}

sub submit_ok {
  my ($self, $selector, $desc) = @_;
  my $el = $self->_proxy(find_element => $selector);
  $el->submit if $el;
  return $self->_test('ok', $el, _desc($desc, "click on $selector"));
}

sub window_size_is {
  my ($self, $exp, $desc) = @_;
  my $size = $self->driver->get_window_size;
  $self->_test('is_deeply', [@$size{qw(width height)}],
    $exp, _desc($desc, "window size is $exp->[0]x$exp->[1]"));
}

sub _desc { encode 'UTF-8', shift || shift }

sub _live_abs_url {
  my $self = shift;
  my $url  = Mojo::URL->new(shift);

  unless ($url->is_abs) {
    my $base = $self->_live_base;
    $url->scheme($base->scheme)->host($base->host)->port($base->port);
  }

  return $url;
}

sub _proxy {
  my ($self, $method) = (shift, shift);
  my $res = eval { $self->driver->$method(@_) };
  warn $@ if DEBUG and $@;
  return $res;
}

sub _live_text {
  my $self = shift;
  my $el = $self->_proxy(find_element => shift);
  return $el ? $el->get_text : '';
}

sub _screenshot_name {
  local $_ = shift;
  s!\%0\b!{$SCRIPT_NAME}!ge;
  s!\%n\b!{sprintf '%04s', $SCREENSHOT++}!ge;
  s!\%t\b!{$^T}!ge;
  return $_;
}

package    # hide from pause
  Test::Mojo::Role::Selenium::UserAgent;
use Mojo::Base 'Mojo::UserAgent';

use constant DEBUG => $ENV{MOJO_SELENIUM_DEBUG} || 0;

sub request {
  my ($ua, $req) = @_;
  my $method = lc $req->method || 'get';
  warn "[Selenium] @{[uc $method]} @{[$req->uri->as_string]}\n" if DEBUG;
  my $tx = $ua->$method($req->uri->as_string, {$req->headers->flatten}, $req->content);
  return HTTP::Response->parse($tx->res->to_string);
}

1;

=encoding utf8

=head1 NAME

Test::Mojo::Role::Selenium - Test::Mojo in a real browser

=head1 SYNOPSIS

  use Mojo::Base -strict;
  use Test::Mojo::WithRoles "Selenium";
  use Test::More;

  my $t = Test::Mojo::WithRoles->new("MyApp");

  # All the standard Test::Mojo methods are available
  ok $t->isa("Test::Mojo");
  ok $t->does("Test::Mojo::Role::Selenium");

  # Make sure the selenium driver can be initialized
  plan skip_all => $@ unless eval { $t->driver };

  $t->navigate_ok("/")
    ->status_is(200)
    ->header_is("Server" => "Mojolicious (Perl)")
    ->text_is("div#message" => "Hello!")
    ->live_text_is("div#message" => "Hello!")
    ->live_element_exists("nav")
    ->element_is_displayed("nav")
    ->active_element_is("input[name=q]")
    ->send_keys_ok("input[name=q]", "Mojo")
    ->capture_screenshot;

  $t->submit_ok
    ->status_is(200)
    ->current_url_like(qr{q=Mojo})
    ->value_is("input[name=q]", "Mojo");

  $t->click_ok("nav a.logo")->status_is(200);

  done_testing;

=head1 DESCRIPTION

L<Test::Mojo::Role::Selenium> is a role that extends L<Test::Mojo> with
additional methods which checks behaviour in a browser. All the heavy lifting
is done by L<Selenium::Remote::Driver>.

Some of the L<Selenium::Remote::Driver> methods are available directly in this
role, while the rest are available through the object held by the L</driver>
attribute. Please let me know if you think more tests or methods should be
provided directly by L<Test::Mojo::Role::Selenium>.

This role is EXPERIMENTAL and subject to change.

=head1 OPTIONAL DEPENDENCIES

L<Selenium::Remote::Driver> require some external dependencies to work. Here
are a quick intro to install some of the dependencies to make this module work.

=over 2

=item * L<Selenium::Chrome>

  # osx
  $ brew install chromedriver

  # ubuntu
  $ sudo apt-get install chromium-chromedriver

  # run tests
  $ MOJO_SELENIUM_DRIVER=Selenium::Chrome prove -l

=item * L<Selenium::PhantomJS>

  # osx
  $ brew install phantomjs

  # ubuntu
  $ sudo apt-get install phantomjs

  # run tests
  $ MOJO_SELENIUM_DRIVER=Selenium::PhantomJS prove -l

=back

=head1 CAVEAT

L<Test::Mojo/tx> is only populated by this role, if the initial request is done
by passing a relative path to L</navigate_ok>. This means that methods such as
L<Test::Mojo/header_is> will not work as expected (probably fail completely) if
L</navigate_ok> is issued with an absolute path like L<http://mojolicious.org>.

=head1 ENVIRONMENT VARIABLES

=head2 MOJO_SELENIUM_BASE_URL

Setting this variable will make this test send the requests to a remote server,
instead of starting a local server. Note that this will disable L<Test::Mojo>
methods such as L</status_is>, since L<Test::Mojo/tx> will not be set. See
also L</CAVEAT>.

=head2 MOJO_SELENIUM_DRIVER

This variable can be set to a classname, such as L<Selenium::Chrome> or
L<Selenium::PhantomJS>, which will force the selenium driver.

=head1 ATTRIBUTES

=head2 driver

  $driver = $self->driver;

An instance of L<Selenium::Remote::Driver>.

=head2 driver_args

  $hash = $self->driver_args;
  $self = $self->driver_args({driver_class => "Selenium::PhantomJS"});

Used to set args passed on to the L</driver> on construction time. In addition,
a special key "driver_class" can be set to use another driver class, than the
default L<Selenium::PhantomJS>.

Note that the environment variavble C<MOJO_SELENIUM_DRIVER> can also be used to
override the driver class.

=head2 screenshot_directory

  $path = $self->screenshot_directory;
  $self = $self->screenshot_directory(File::Spec->tmpdir);

Where screenshots are saved.

=head1 METHODS

=head2 active_element_is

  $self = $self->active_element_is("input[name=username]");

Test that the current active element on the page match the selector.

=head2 button_down

  $self = $self->button_down;

See L<Selenium::Remote::Driver/button_down>.

=head2 button_up

  $self = $self->button_up;

See L<Selenium::Remote::Driver/button_up>.

=head2 capture_screenshot

  $self = $self->capture_screenshot;
  $self = $self->capture_screenshot("%t-page-x");
  $self = $self->capture_screenshot("%0-%t-%n");

Capture screenshot to L</screenshot_directory> with filename specified by the
input format. The format supports these special strings:

  Format | Description
  -------|----------------------
  %t     | Start time for script
  %0     | Name of script
  %n     | Auto increment

=head2 click_ok

  $self = $self->click_ok("a", "left");

Click on an element.

=head2 current_url_is

  $self = $self->current_url_is("http://mojolicious.org/");
  $self = $self->current_url_is("/whatever");

Test the current browser URL.

=head2 current_url_like

  $self = $self->current_url_like(qr{/whatever});

Test the current browser URL.

=head2 element_is_displayed

  $self = $self->element_is_displayed("nav");

Test if an element is displayed on the web page.

See L<Selenium::Remote::WebElement/is_displayed>.

=head2 element_is_hidden

  $self = $self->element_is_hidden("nav");

Test if an element is hidden on the web page.

See L<Selenium::Remote::WebElement/is_hidden>.

=head2 go_back

  $self = $self->go_back;

See L<Selenium::Remote::Driver/go_back>.

=head2 go_forward

  $self = $self->go_forward;

See L<Selenium::Remote::Driver/go_forward>.

=head2 live_element_count_is

See L<Test::Mojo/element_count_is>.

=head2 live_element_exists

See L<Test::Mojo/element_exists>.

=head2 live_element_exists_not

See L<Test::Mojo/element_exists_not>.

=head2 live_text_is

  $self = $self->live_text_is("div.name", "Mojo");

Checks text content of the CSS selectors first matching HTML element in the
browser matches the given string.

=head2 live_text_like

  $self = $self->live_text_is("div.name", qr{Mojo});

Checks text content of the CSS selectors first matching HTML element in the
browser matches the given regex.

=head2 navigate_ok

  $self = $self->navigate_ok("/");
  $self = $self->navigate_ok("http://mojolicious.org/");

Open a browser window and go to the given location.

=head2 maximize_window

  $self = $self->maximize_window;

See L<Selenium::Remote::Driver/maximize_window>.

=head2 refresh

  $self = $self->refresh;

See L<Selenium::Remote::Driver/refresh>.

=head2 send_keys_ok

  $self->send_keys_ok("input[name=username]", "jhthorsen");
  $self->send_keys_ok("input[name=name]", ["jan", \"space", "henning"]);

Used to sen keys to a given element. Scalar refs will be sent as
L<Selenium::Remote::WDKeys> strings.

=head2 set_selected_element_ok

  $self = $self->set_selected_element_ok("input[name=email]");

Select and option, checkbox or radiobutton.

See L<Selenium::Remote::WebElement/set_selected>

=head2 set_window_size

  $self = $self->set_window_size([$width, $height]);
  $self = $self->set_window_size([375, 667]);

Set the browser window size.

=head2 submit_ok

  $self = $self->submit_ok("form");
  $self = $self->submit_ok;

Submit a form, either by selector or the current active form.

See L<Selenium::Remote::WebElement/submit>.

=head2 window_size_is

  $self = $self->window_size_is([$width, $height]);
  $self = $self->window_size_is([375, 667]);

Test if window has the expected width and height.

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Test::Mojo>.

L<Selenium::Remote::Driver>

=cut
