use 5.006;
use strict;
use warnings;
package CPAN::Meta::Prereqs;
# VERSION

=head1 DESCRIPTION

A CPAN::Meta::Prereqs object represents the prerequisites for a CPAN
distribution or one of its optional features.  Each set of prereqs is
organized by phase and type, as described in L<CPAN::Meta::Prereqs>.

=cut

use Carp qw(confess);
use Scalar::Util qw(blessed);
use CPAN::Meta::Requirements 2.121;

=method new

  my $prereq = CPAN::Meta::Prereqs->new( \%prereq_spec );

This method returns a new set of Prereqs.  The input should look like the
contents of the C<prereqs> field described in L<CPAN::Meta::Spec>, meaning
something more or less like this:

  my $prereq = CPAN::Meta::Prereqs->new({
    runtime => {
      requires => {
        'Some::Module' => '1.234',
        ...,
      },
      ...,
    },
    ...,
  });

You can also construct an empty set of prereqs with:

  my $prereqs = CPAN::Meta::Prereqs->new;

This empty set of prereqs is useful for accumulating new prereqs before finally
dumping the whole set into a structure or string.

=cut

sub __legal_phases { qw(configure build test runtime develop)   }
sub __legal_types  { qw(requires recommends suggests conflicts) }

# expect a prereq spec from META.json -- rjbs, 2010-04-11
sub new {
  my ($class, $prereq_spec) = @_;
  $prereq_spec ||= {};

  my %is_legal_phase = map {; $_ => 1 } $class->__legal_phases;
  my %is_legal_type  = map {; $_ => 1 } $class->__legal_types;

  my %guts;
  PHASE: for my $phase (keys %$prereq_spec) {
    next PHASE unless $phase =~ /\Ax_/i or $is_legal_phase{$phase};

    my $phase_spec = $prereq_spec->{ $phase };
    next PHASE unless keys %$phase_spec;

    TYPE: for my $type (keys %$phase_spec) {
      next TYPE unless $type =~ /\Ax_/i or $is_legal_type{$type};

      my $spec = $phase_spec->{ $type };

      next TYPE unless keys %$spec;

      $guts{prereqs}{$phase}{$type} = CPAN::Meta::Requirements->from_string_hash(
        $spec
      );
    }
  }

  return bless \%guts => $class;
}

=method requirements_for

  my $requirements = $prereqs->requirements_for( $phase, $type );

This method returns a L<CPAN::Meta::Requirements> object for the given
phase/type combination.  If no prerequisites are registered for that
combination, a new CPAN::Meta::Requirements object will be returned, and it may
be added to as needed.

If C<$phase> or C<$type> are undefined or otherwise invalid, an exception will
be raised.

=cut

sub requirements_for {
  my ($self, $phase, $type) = @_;

  confess "requirements_for called without phase" unless defined $phase;
  confess "requirements_for called without type"  unless defined $type;

  unless ($phase =~ /\Ax_/i or grep { $phase eq $_ } $self->__legal_phases) {
    confess "requested requirements for unknown phase: $phase";
  }

  unless ($type =~ /\Ax_/i or grep { $type eq $_ } $self->__legal_types) {
    confess "requested requirements for unknown type: $type";
  }

  my $req = ($self->{prereqs}{$phase}{$type} ||= CPAN::Meta::Requirements->new);

  $req->finalize if $self->is_finalized;

  return $req;
}

=method with_merged_prereqs

  my $new_prereqs = $prereqs->with_merged_prereqs( $other_prereqs );

  my $new_prereqs = $prereqs->with_merged_prereqs( \@other_prereqs );

This method returns a new CPAN::Meta::Prereqs objects in which all the
other prerequisites given are merged into the current set.  This is primarily
provided for combining a distribution's core prereqs with the prereqs of one of
its optional features.

The new prereqs object has no ties to the originals, and altering it further
will not alter them.

=cut

sub with_merged_prereqs {
  my ($self, $other) = @_;

  my @other = blessed($other) ? $other : @$other;

  my @prereq_objs = ($self, @other);

  my %new_arg;

  for my $phase ($self->__legal_phases) {
    for my $type ($self->__legal_types) {
      my $req = CPAN::Meta::Requirements->new;

      for my $prereq (@prereq_objs) {
        my $this_req = $prereq->requirements_for($phase, $type);
        next unless $this_req->required_modules;

        $req->add_requirements($this_req);
      }

      next unless $req->required_modules;

      $new_arg{ $phase }{ $type } = $req->as_string_hash;
    }
  }

  return (ref $self)->new(\%new_arg);
}

=method as_string_hash

This method returns a hashref containing structures suitable for dumping into a
distmeta data structure.  It is made up of hashes and strings, only; there will
be no Prereqs, CPAN::Meta::Requirements, or C<version> objects inside it.

=cut

sub as_string_hash {
  my ($self) = @_;

  my %hash;

  for my $phase ($self->__legal_phases) {
    for my $type ($self->__legal_types) {
      my $req = $self->requirements_for($phase, $type);
      next unless $req->required_modules;

      $hash{ $phase }{ $type } = $req->as_string_hash;
    }
  }

  return \%hash;
}

=method is_finalized

This method returns true if the set of prereqs has been marked "finalized," and
cannot be altered.

=cut

sub is_finalized { $_[0]{finalized} }

=method finalize

Calling C<finalize> on a Prereqs object will close it for further modification.
Attempting to make any changes that would actually alter the prereqs will
result in an exception being thrown.

=cut

sub finalize {
  my ($self) = @_;

  $self->{finalized} = 1;

  for my $phase (keys %{ $self->{prereqs} }) {
    $_->finalize for values %{ $self->{prereqs}{$phase} };
  }
}

=method clone

  my $cloned_prereqs = $prereqs->clone;

This method returns a Prereqs object that is identical to the original object,
but can be altered without affecting the original object.  Finalization does
not survive cloning, meaning that you may clone a finalized set of prereqs and
then modify the clone.

=cut

sub clone {
  my ($self) = @_;

  my $clone = (ref $self)->new( $self->as_string_hash );
}

1;

# ABSTRACT: a set of distribution prerequisites by phase and type

__END__

=head1 BUGS

Please report any bugs or feature using the CPAN Request Tracker.
Bugs can be submitted through the web interface at
L<http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Meta>

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

=cut


