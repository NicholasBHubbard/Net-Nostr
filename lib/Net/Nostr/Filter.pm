package Net::Nostr::Filter;

use strictures 2;

my @SCALAR_FIELDS = qw(since until limit);
my @LIST_FIELDS   = qw(ids authors kinds);

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless {}, $class;

    for my $f (@SCALAR_FIELDS) {
        $self->{$f} = $args{$f} if exists $args{$f};
    }
    for my $f (@LIST_FIELDS) {
        $self->{$f} = $args{$f} if exists $args{$f};
    }

    # extract #<letter> tag filters
    for my $k (keys %args) {
        if ($k =~ /^#([a-zA-Z])$/) {
            $self->{_tag_filters}{$1} = $args{$k};
        }
    }

    return $self;
}

sub ids     { shift->{ids} }
sub authors { shift->{authors} }
sub kinds   { shift->{kinds} }
sub since   { shift->{since} }
sub until   { shift->{until} }
sub limit   { shift->{limit} }

sub tag_filter {
    my ($self, $letter) = @_;
    return $self->{_tag_filters}{$letter};
}

sub matches {
    my ($self, $event) = @_;

    if ($self->{ids}) {
        my $eid = $event->id;
        return 0 unless grep { $_ eq $eid } @{ $self->{ids} };
    }

    if ($self->{authors}) {
        my $pk = $event->pubkey;
        return 0 unless grep { $_ eq $pk } @{ $self->{authors} };
    }

    if ($self->{kinds}) {
        my $k = $event->kind;
        return 0 unless grep { $_ == $k } @{ $self->{kinds} };
    }

    if (defined $self->{since}) {
        return 0 unless $event->created_at >= $self->{since};
    }

    if (defined $self->{until}) {
        return 0 unless $event->created_at <= $self->{until};
    }

    if ($self->{_tag_filters}) {
        for my $letter (keys %{ $self->{_tag_filters} }) {
            my $filter_values = $self->{_tag_filters}{$letter};
            my @event_tag_values;
            for my $tag (@{ $event->tags }) {
                push @event_tag_values, $tag->[1] if $tag->[0] eq $letter;
            }
            my $found = 0;
            for my $fv (@$filter_values) {
                if (grep { $_ eq $fv } @event_tag_values) {
                    $found = 1;
                    last;
                }
            }
            return 0 unless $found;
        }
    }

    return 1;
}

sub to_hash {
    my ($self) = @_;
    my %h;

    for my $f (@LIST_FIELDS, @SCALAR_FIELDS) {
        $h{$f} = $self->{$f} if defined $self->{$f};
    }

    if ($self->{_tag_filters}) {
        for my $letter (keys %{ $self->{_tag_filters} }) {
            $h{"#$letter"} = $self->{_tag_filters}{$letter};
        }
    }

    return \%h;
}

1;
