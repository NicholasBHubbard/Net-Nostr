package Net::Nostr::Event;

use strictures 2;

use Carp;
use JSON;
use Digest::SHA;

### API ###

# getters
sub id         { shift->{id}         }
sub pubkey     { shift->{pubkey}     }
sub created_at { shift->{created_at} }
sub kind       { shift->{kind}       }
sub tags       { shift->{tags}       }
sub content    { shift->{content}    }
sub sig        { shift->{sig}        }

# setters
sub set_id         { shift->{id} = shift         }
sub set_pubkey     { shift->{pubkey} = shift     }
sub set_created_at { shift->{created_at} = shift }
sub set_kind       { shift->{kind} = shift       }
sub set_tags       { shift->{tags} = shift       }
sub set_content    { shift->{content} = shift    }
sub set_sig        { shift->{sig} = shift        }

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    $self->set_created_at(time())  unless $self->created_at;
    $self->set_tags([])  unless $self->tags;
    $self->set_id($self->_calc_id) unless $self->id;
    return $self;
}

sub json_serialize {
    my $self = shift;
    my $json_serialized = JSON->new->utf8->encode([ # see how Perl is converted to JSON - https://metacpan.org/pod/JSON#PERL-%3E-JSON
        0,
        $self->{pubkey} . '',
        $self->{created_at} + 0,
        $self->{kind} + 0,
        $self->{tags} . '',
        $self->{content} . ''
    ]);
    return $json_serialized;
}

### PRIVATE ###

sub _calc_id {
    my $self = shift;
    my $json_serialized = $self->json_serialize;
    my $id = Digest::SHA::sha256_hex($json_serialized);
    return $id;
}

1;
