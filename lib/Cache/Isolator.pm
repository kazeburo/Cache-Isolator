package Cache::Isolator;

use strict;
use warnings;
use Carp;
use Time::HiRes;
use List::Util qw/shuffle/;
use Class::Accessor::Lite (
    ro  => [ qw(cache interval timeout concurrency) ],
);

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my %args = (
        interval => 0.01,
        timeout => 10,
        trial => 0,
        concurrency => 1,
        @_
    );

    croak('cache value should be object and appeared add, set and delete methods.')
      unless ( $args{cache}
        && UNIVERSAL::can( $args{cache}, 'set' )
        && UNIVERSAL::can( $args{cache}, 'add' )
        && UNIVERSAL::can( $args{cache}, 'delete' ) );

    bless \%args, $class;
}

sub get_or_set {
    my ($self, $key, $cb, $expires ) = @_;

    my $value;
    my $try = 0;

    TRYLOOP: while  ( 1 ) {
        $value = $self->cache->get($key);
        last TRYLOOP if $value;
        
        my @lockkeys = map { $key .":lock:". $_ } shuffle 1..$self->concurrency;
        foreach my $lockkey ( @lockkeys ) {
            $try++;
            my $locked = $self->cache->add($lockkey, 1, $self->timeout );
            if ( $locked ) {
                try {
                    $value = $cb->();
                    $self->cache->set( $key, $value, $expires );
                }
                catch {
                    die $_;
                }
                finally {
                    $self->cache->delete( $lockkey );
                };
                last TRYLOOP;
            }
            die "timeout" if $self->trial > 0 && $try >= $self->trial;
        }
        Time::HiRes::sleep( $self->interval );
    }
    return $value;
}


1;
__END__

=head1 NAME

Cache::Isolator - Controls concurrency of operation when cache misses occurred.

=head1 SYNOPSIS

  use Cache::Isolator;
  use Cache::Memcached::Fast;

  my $isolator = Cache::Isolator->new(
      cache => Cache::Memcached::Fast->new(...),
      concurrency => 4,
  );

  my $key   = 'query:XXXXXX';
  $isolator->get_or_set(
      $key, 
      sub { # This callback invoked when miss cache
          get_from_db($key);
      },
      3600
  );

=head1 DESCRIPTION

Cache::Isolator is

=head1 METHODS

=head2 new( %args )

Following parameters are recognized.

=over

=item cache

B<Required>. L<Cache::Memcached::Fast> object or similar interface object.

=item concurrency

Optional. Number of get_or_set callback executed in parallel.
If many process need to run callback, they wait until lock becomes released or able to get values.
Defaults to 1. It means no concurrency. 

=item interval

Optional. The seconds for busy loop interval. Defaults to 0.01 seconds.

=item trial

Optional. When the value is being set zero, get_or_set will be waiting until lock becomes released.
When the value is being set positive integer value, get_or_set will die on reached trial count.
Defaults to 0.

=item timeout

Optional. The seconds until lock becomes released. Defaults to 30 seconds.

=back

=head2 get_or_set( $key, $callback, $expires )

$callback is subroutine reference. That invoked when cache miss occurred.

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo {at} gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
