package Test::Mojo::Selenium;
use Mojo::Base 'Test::Mojo';

use Mojo::Util qw(encode);
use Selenium::Chrome;
use Selenium::Remote::WDKeys;

our $VERSION = '0.01';

has base => sub {
  my $self = shift;
  my $port = Mojo::IOLoop::Server->generate_port;
  return Mojo::URL->new("http://127.0.0.1:$port");
};

has driver => sub {
  my $self = shift;
  my $ua   = Test::Mojo::Selenium::UserAgent->new;
  Scalar::Util::weaken($ua->{t} = $self);
  my $driver = $self->_driver_class->new(ua => $ua);
  $driver->default_finder('css');
  return $driver;
};

has _driver_class => 'Selenium::Chrome';

has _server => sub {
  my $self = shift;
  my $server = Mojo::Server::Daemon->new(silent => 1);

  $server->app($self->app)->listen([$self->base->to_string])
    ->start->ioloop->acceptor($server->acceptors->[0]);

  my $pid = fork // exit $server->ioloop->start, 0;
  die $! unless defined $pid;
  return $pid;
};

# Install proxy methods
# Note: These methods are experimental and might change to testing methods instead
sub button_down        { _proxy(button_down        => @_) }
sub button_up          { _proxy(button_up          => @_) }
sub capture_screenshot { _proxy(capture_screenshot => @_) }
sub get_orientation    { _proxy(get_orientation    => @_) }
sub go_back            { _proxy(go_back            => @_) }
sub go_forward         { _proxy(go_forward         => @_) }
sub maximize_window    { _proxy(maximize_window    => @_) }
sub refresh            { _proxy(refresh            => @_) }
sub set_orientation    { _proxy(set_orientation    => @_) }

sub active_element_is {
  my ($self, $selector, $desc) = @_;
  my $driver = $self->driver;
  my $active = $driver->get_active_element;
  my $el     = $driver->find_element($selector);
  my $same   = $active && $el ? $driver->compare_elements($active, $el) : 0;

  return $self->_test('ok', $same, _desc($desc, "active element is $selector"));
}

sub cache_status_is {
  my ($self, $status, $desc) = @_;
  return $self->_test('is', $self->driver->cache_status,
    uc $status, _desc($desc, "cache status is $status"));
}

sub content_like {
  my ($self, $regex, $desc) = @_;
  return $self->_test('like', $self->driver->get_body, $regex, _desc($desc, 'content is similar'));
}

sub content_unlike {
  my ($self, $regex, $desc) = @_;
  return $self->_test('unlike', $self->driver->get_body, $regex,
    _desc($desc, 'content is not similar'));
}

sub click_ok { _element_action(click => @_); }

sub element_count_is {
  my ($self, $selector, $count, $desc) = @_;
  my $els = $self->driver->find_elements($selector);
  return $self->_test('is', int(@$els), $count,
    _desc($desc, qq{element count for selector "$selector"}));
}

sub element_exists {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{element for selector "$selector" exists});
  return $self->_test('ok', $self->driver->find_element($selector), $desc);
}

sub element_exists_not {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{no element for selector "$selector"});
  return $self->_test('ok', !$self->driver->find_element($selector), $desc);
}

sub element_is_displayed { _element(is_displayed => @_) }
sub element_is_enabled   { _element(is_enabled   => @_) }
sub element_is_hidden    { _element(is_hidden    => @_) }
sub element_is_selected  { _element(is_selected  => @_) }

sub get_ok {
  my ($self, $url) = (shift, shift);
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  $url = Mojo::URL->new($url)->base($self->base);
  $self->driver->get($url->to_string);

  my $err = $self->tx->error;
  Test::More::diag $err->{message} if !(my $ok = !$err->{message} || $err->{code}) && $err;
  return $self->_test('ok', $ok, _desc("get $url"));
}

sub local_storage_item_is {
  my ($self, $key, $exp, $desc) = @_;
  $self->_test(
    'is', $self->driver->get_local_storage_item($key),
    $exp, _desc($desc, "exact match for local storage item $key")
  );
}

sub local_storage_item_like {
  my ($self, $key, $regex, $desc) = @_;
  $self->_test(
    'like', $self->driver->get_local_storage_item($key),
    $regex, _desc($desc || "local storage item $key is similar")
  );
}

sub send_keys_ok {
  my ($self, $selector, $keys, $desc) = @_;
  my $el = $self->driver->find_element($selector);
  map { $self->send_keys(ref $_ ? KEYS->{$_} : $_) } ref $keys ? @$keys : ($keys) if $el;
  return $self->_test('ok', $el, _desc($desc, "keys sent to $selector"));
}

sub set_active_element_ok { _element_action(set_selected => @_); }

sub set_window_size_ok {
  my ($self, $exp, $desc) = @_;
  $self->driver->set_window_size(@$exp);
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  return $self->window_size_is($exp, $desc);
}

sub submit_ok { _element_action(submit => @_); }

sub title_is {
  my ($self, $exp, $desc) = @_;
  $self->_test('is', $self->driver->get_title, $exp, _desc($desc, 'exact match for current title'));
}

sub title_like {
  my ($self, $exp, $desc) = @_;
  $self->_test('like', $self->driver->get_title, $exp, _desc($desc, 'current title is similar'));
}

sub url_is {
  my ($self, $exp, $desc) = @_;
  $self->_test('is', $self->driver->get_current_url, $exp, _desc($desc, 'exact match for url'));
}

sub url_like {
  my ($self, $exp, $desc) = @_;
  $self->_test('like', $self->driver->get_current_url, $exp,
    _desc($desc, 'current url is similar'));
}

sub value_is {
  my ($self, $selector, $exp, $desc) = @_;
  my $el = $self->driver->find_element($selector);
  $self->_test('is', ($el ? $el->get_value : ''),
    $exp, _desc($desc, "exact match for $selector value"));
}

sub value_like {
  my ($self, $selector, $exp, $desc) = @_;
  my $el = $self->driver->find_element($selector);
  $self->_test('like', ($el ? $el->get_value : ''),
    $exp, _desc($desc, "current value for $selector is similar"));
}

sub window_size_is {
  my ($self, $exp, $desc) = @_;
  my $size = $self->driver->get_window_size;
  $self->_test('is_deeply', [@$size{qw(width height)}],
    $exp, _desc($desc, "window size is $exp->[0]x$exp->[1]"));
}

sub _desc { encode 'UTF-8', shift || shift }

sub _element_action {
  my ($method, $self, $selector, $desc) = @_;
  my $el = $self->driver->find_element($selector);
  $el->$method if $el;
  $desc ||= sprintf '%s on %s', join(join ' ', split /_/, $method), $selector;
  return $self->_test('ok', $el, _desc($desc));
}

sub _element {
  my ($method, $self, $selector, $desc) = @_;
  my $el = $self->driver->find_element($selector);
  $desc ||= sprintf 'element %s %s', $selector, join(join ' ', split /_/, $method);
  return $self->_test('ok', ($el && $el->$method), _desc($desc, "enabled $selector"));
}

sub _proxy {
  my ($method, $self, @args) = @_;
  $self->driver->$method(@args);
  return $self;
}

# Hack to allow text_is(), text_isnt(), text_like(), ...
sub _text {
  my $self = $shift;
  my $el   = $self->driver->find_element(shift);
  return $el ? $el->get_text : '';
}

sub DESTROY {
  my $self = shift;
  kill KILL => $self->{_server} if $self->{_server};
}

package    # hide from pause
  Test::Mojo::Selenium::UserAgent;
use Mojo::Base 'Mojo::UserAgent';

sub request {
  my ($ua, $req) = @_;
  my $method = lc $req->method || 'get';
  my $tx = $ua->$method($req->uri->as_string, {$req->headers->flatten}, $req->content);

  $ua->{t}->tx($tx) if $ua->{t};    # (in cleanup) Can't call method "tx" on an undefined value

  return HTTP::Response->parse($tx->res->to_string);
}

1;
