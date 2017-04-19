package JSONTemplate;

use strict;
use warnings;
use JSON::XS qw(encode_json decode_json);

our %Funcs = (
    "array" => sub {
        my $params = shift;
        return \@_;
    },
    "flatten" => sub {
        my $params = shift;
        return map { ref $_ eq 'ARRAY' ? @$_ : $_ } @_
    },
    "quote" => sub {
        my $params = shift;
        return map { '"' . $_ . '"' } @_;
    },
    "join" => sub {
        my $char = shift()->[0] || '';
        return unless @_;
        no warnings 'uninitialized';
        return join $char, map {
            ( ref($_) eq 'ARRAY' || ref($_) eq 'HASH' )
                ? encode_json($_)
                : $_
        } @_;
    },
    "json" => sub {
        my $params = shift;
        return map { decode_json($_) } @_;
    },
    "string" => sub {
        my $params = shift;
        return map { ref $_ ? encode_json($_) : $_ } @_;
    }

);

#===================================
sub new {
#===================================
    my $class = shift;
    bless {}, $class;
}

#===================================
sub _render {
#===================================
    my $self  = shift;
    my $input = shift;
    $self->_input($input);
    $self->_original($input);
    $self->_params( shift() || {} );
    $self->_tokens( [] );
    $self->_has_opaque(0);
    $self->_reset_offset;
    $self->_tokenize;
    return $self->_execute;
}

my %Escape = (
    "\b" => '\b',
    "\f" => '\f',
    "\n" => '\n',
    "\r" => '\r',
    "\t" => '\t',
    '"'  => '\"',
    "\\" => '\\'
);

#===================================
sub render_json {
#===================================
    my $self   = shift;
    my @output = $self->_render(@_);
    if ( @output == 0 ) {
        return 'null';
    }
    if ( $self->_has_opaque ) {
        no warnings 'uninitialized';
        my $val = join "", @output;
        $val =~ s/([^\w])/$Escape{$1}||$1/ge;
        return '"' . $val . '"';
    }
    if ( @output > 1 ) {
        return encode_json( \@output );
    }

    my $val = $output[0];
    if ( ref $val ) {
        return encode_json($val);
    }
    if ( !defined $val ) {
        return 'null';
    }
    if ( $val =~ /^\d+(?:\.\d+)?$/ ) {
        return $val;
    }
    $val =~ s/([^\w])/$Escape{$1}||$1/ge;
    return '"' . $val . '"';
}

#===================================
sub render_text {
#===================================
    my $self   = shift;
    my @output = $self->_render(@_);
    if ( @output == 0 ) {
        return '';
    }
    if ( $self->_has_opaque ) {
        no warnings 'uninitialized';
        return join "", @output;
    }
    if ( @output > 1 ) {
        return encode_json( \@output );
    }

    my $val = $output[0];
    if ( ref $val ) {
        return encode_json($val);
    }
    if ( !defined $val ) {
        return 'null';
    }
    return $val;
}

#===================================
sub _execute {
#===================================
    my $self = shift;

    my @output = @_;

    while ( my $token = $self->_next_token ) {
        my ( $type, $item ) = @$token;

        if ( $type eq 'OPAQUE' ) {
            push @output, $item;
            $self->_has_opaque(1);
            next;
        }

        if ( $type eq 'VAL' ) {
            push @output, $self->_apply_functions($item);
            next;
        }

        if ( $type eq 'VAR' ) {
            my $val = $self->_lookup_var($item);
            push @output, $self->_apply_functions($val);
            next;
        }

        if ( $type eq 'CONCAT' ) {
            my @next = $self->_execute;
            no warnings 'uninitialized';
            if (@output) {
                $output[-1] = $output[-1] . shift(@next);
            }
            push @output, @next;
            next;
        }

        if ( $type eq 'OPEN_PAREN' ) {
            push @output, $self->_apply_functions( $self->_execute );
            next;
        }

        if ( $type eq 'OPEN_SECTION' ) {
            push @output,
                $self->_apply_functions( $self->_execute_section($item) );
            next;
        }

        return @output;

    }

    return @output;
}

#===================================
sub _apply_functions {
#===================================
    my $self = shift;
    my @vals = @_;

    while ( my $token = $self->_peek_next_token ) {
        last unless $token->[0] eq 'FUNC';
        $token = $self->_next_token;
        my $func = $Funcs{ $token->[1] }
            or die "Unknown function name: " . $token->[1];
        my @params;
        my $next = $self->_peek_next_token;
        if ( $next && $next->[0] eq 'OPEN_PARAM' ) {
            $self->_next_token;
            while ( my $token = $self->_next_token ) {
                last if $token->[0] eq 'CLOSE_PARAM';
                if ( $token->[0] eq 'VAL' ) {
                    push @params, $token->[1];
                    next;
                }

                if ( $token->[0] eq 'VAR' ) {
                    my $val = $self->_lookup_var( $token->[1] );
                    push @params, $val;
                    next;
                }
                die "Unknown token: " . $token->[0];
            }
        }
        @vals = $func->( \@params, @vals );
    }
    return @vals;
}

#===================================
sub _execute_section {
#===================================
    my $self = shift;
    my $name = shift;
    my $negate;
    if ( $name =~ s/^!// ) {
        $negate = 1;
    }

    my @tokens;
    my $nested = 1;
    while ( my $next = $self->_next_token ) {
        last if $next->[0] eq 'CLOSE_SECTION' && 0 == --$nested;
        $nested++ if $next->[0] eq 'OPEN_SECTION';
        push @tokens, $next;
    }

    my $val = $self->_lookup_var($name);

    my @items;
    if ($negate) {
        return if ref $val eq 'ARRAY' ? @$val : $val;
        @items = ('');
    }
    else {
        if ( ref $val eq 'ARRAY' ) {
            return if @$val == 0;
            @items = @$val;
        }
        else {
            return if !$val;
            @items = $val;
        }
    }

    my @output;
    my $old_tokens = $self->_tokens;
    my $old_params = $self->_params;

    for my $item (@items) {

        if ( ref $item eq 'HASH' ) {
            $self->_params( { %$item, _ => $item } );
        }
        else {
            $self->_params( { %$old_params, _ => $item } );
        }

        $self->_tokens( [@tokens] );
        push @output, $self->_execute;
        $self->_params($old_params);
    }
    $self->_tokens($old_tokens);
    return @output;
}

#===================================
sub _lookup_var {
#===================================
    my $self   = shift;
    my $name   = shift;
    my @parts  = split /\./, $name;
    my $params = $self->_params;
    while (@parts) {
        my $part = shift @parts;
        $part = '' unless defined $part;
        if ( ref $params eq 'HASH' ) {
            return undef unless exists $params->{$part};
            $params = $params->{$part};
            next;
        }
        if ( ref $params eq 'ARRAY' ) {
            die "Cannot access array with key <$part>"
                unless $part =~ /^-?\d+/;
            $params = $params->[$part];
            next;
        }
        return undef;
    }
    return $params;
}

#===================================
sub _tokenize {
#===================================
    my $self = shift;

    my $mode = "start";
    my @stack;

    while ( length $self->_input ) {

        # opaque string or <<
        if ( $mode eq 'start' ) {
            if ( $self->_open_code ) {
                $mode = 'start_code';
                push @stack, 'CODE';
                next;
            }

            $self->_opaque_string
                and next;
        }

        # remove any spaces
        $self->_spaces && next;

        # pipe >>
        if ( $mode eq 'pipe_or_concat' ) {
            if ( $self->_pipe ) {
                $mode = 'func';
                next;
            }

            if ( $self->_concat ) {
                $mode = 'start_code';
                next;
            }

        }

        # value or variable
        if ( $mode eq 'start_code' || $mode eq 'pipe_or_concat' ) {

            if (   $stack[-1]
                && $stack[-1] eq 'SECTION'
                && $self->_close_section )
            {
                $self->_check_stack( pop(@stack), 'SECTION' );
                next;
            }

            if ( $self->_close_code ) {
                $mode = 'start';
                $self->_check_stack( pop(@stack), 'CODE' );
                next;
            }

            if ( $self->_open_paren ) {
                push @stack, 'PAREN';
                next;
            }

            if ( $self->_close_paren ) {
                $self->_check_stack( pop(@stack), 'PAREN' );
                next;
            }

            if ( $self->_open_section ) {
                push @stack, 'SECTION';
                next;
            }

            if ( $self->_close_section ) {
                $self->_check_stack( pop(@stack), 'SECTION' );
                next;
            }

                   $self->_number
                || $self->_double_quoted_string
                || $self->_single_quoted_string
                || $self->_var
                || $self->_unknown_token(
                "a value or a variable, a section, or an opening parenthesis");

            $mode = 'pipe_or_concat';
            next;
        }

        # function name with optional param list
        if ( $mode eq 'func' ) {
            if ( $self->_func ) {
                if ( $self->_open_param ) {
                    $mode = 'param';
                    push @stack, 'PARAM';
                }
                else {
                    $mode = 'pipe_or_concat';
                }
                next;
            }
            $self->_unknown_token('a function name');
        }

        # parameter
        if ( $mode eq 'param' ) {
                   $self->_number
                || $self->_double_quoted_string
                || $self->_single_quoted_string
                || $self->_var
                || $self->_unknown_token("a value or a variable");
            $mode = 'param_list';
            next;
        }

        # comma or close params
        if ( $mode eq 'param_list' ) {
            if ( $self->_comma ) {
                $mode = 'param';
                next;
            }
            if ( $self->_close_param ) {
                $mode = 'pipe_or_concat';
                $self->_check_stack( pop(@stack), 'PARAM' );
                next;
            }
            $self->_unknown_token('a comma or )');
        }

        $self->_unknown_token;

    }
    if (@stack) {
        my $missing
            = $stack[-1] eq 'CODE'  ? '>>'
            : $stack[-1] eq 'PARAM' ? ')'
            :                         "UNHANDLED STACK ITEM";
        my $input = $self->_original;
        die "Missing closing $missing marked by <HERE>: $input <HERE>\n";
    }

}

#===================================
sub _check_stack {
#===================================
    my $self     = shift;
    my $expected = shift;
    my $got      = shift || '';
    return if $expected eq $got;
    my $msg;
    if ( !$expected ) {
        my $missing
            = $got eq 'CODE'    ? '<<'
            : $got eq 'PARAM'   ? '('
            : $got eq 'PAREN'   ? '('
            : $got eq 'SECTION' ? 'varname<'
            :                     'Unknown stack item: $got';
        $msg = "Found closing $got without opening $missing.";
    }
    else {
        my $expected_msg
            = $expected eq 'CODE'    ? '>>'
            : $expected eq 'PARAM'   ? ')'
            : $expected eq 'PAREN'   ? ')'
            : $expected eq 'SECTION' ? '>'
            :                          "Unknown stack item: $expected";

        $msg = "Got closing $got but was expecting $expected_msg. ";
    }
    die "$msg Marked by <-- HERE: "
        . substr( $self->_original, 0, $self->_get_offset )
        . '" <-- HERE "'
        . substr( $self->_original, $self->_get_offset );
}

#===================================
sub _spaces {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(\s+)/;
    $self->_skip_token($1);
    return 1;
}

#===================================
sub _open_code {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(<<)/;
    $self->_skip_token($1);
    return 1;
}

#===================================
sub _close_code {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(>>)/;
    $self->_skip_token($1);
    return 1;
}

#===================================
sub _opaque_string {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(.+?)(?:$|(?=<<))/;
    $self->_add_token( "OPAQUE", $1 );
    return 1;
}

#===================================
sub _pipe {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([|])/;
    $self->_skip_token($1);
    return 1;
}

#===================================
sub _func {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([a-z]+)/;
    $self->_add_token( 'FUNC', $1 );
    return 1;
}

#===================================
sub _open_param {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([(])/;
    $self->_add_token( 'OPEN_PARAM', $1 );
    return 1;
}

#===================================
sub _close_param {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([)])/;
    $self->_add_token( 'CLOSE_PARAM', $1 );
    return 1;
}

#===================================
sub _open_paren {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([(])/;
    $self->_add_token( 'OPEN_PAREN', $1 );
    return 1;
}

#===================================
sub _close_paren {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([)])/;
    $self->_add_token( 'CLOSE_PAREN', $1 );
    return 1;
}

#===================================
sub _concat {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([+])/;
    $self->_add_token( 'CONCAT', $1 );
    return 1;
}

#===================================
sub _comma {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(,)/;
    $self->_skip_token($1);
    return 1;
}

#===================================
sub _number {
#===================================
    my $self = shift;
    if ( $self->_input =~ /^(\d+\.\d+)/ ) {
        $self->_add_token( 'VAL', $1 );
    }
    elsif ( $self->_input =~ /^(\d+)/ ) {
        $self->_add_token( 'VAL', $1 );
    }
    else {
        return;
    }
    return 1;
}

#===================================
sub _open_section {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(!?[a-zA-Z][.\w]+)</;
    $self->_add_token( 'OPEN_SECTION', $1 );
    $self->_skip_token('<');
    return 1;
}
#===================================
sub _close_section {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(>)/;
    $self->_add_token( 'CLOSE_SECTION', $1 );
    return 1;
}

#===================================
sub _var {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^([_a-zA-Z][.\w]*)/;
    $self->_add_token( 'VAR', $1 );
    return 1;
}

#===================================
sub _double_quoted_string {
#===================================
    my $self = shift;

    # TODO: Handle unescaping of strings - single quoted too?
    return unless $self->_input =~ /^"((?:\\"|[^"])*)"/;
    $self->_skip_token('"');
    $self->_add_token( 'VAL', $1 );
    $self->_skip_token('"');
    return 1;
}

#===================================
sub _single_quoted_string {
#===================================
    my $self = shift;

    return unless $self->_input =~ /^'((?:\\'|[^'])*)'/;
    $self->_skip_token("'");
    $self->_add_token( 'VAL', $1 );
    $self->_skip_token("'");
    return 1;
}

#===================================
sub _add_token {
#===================================
    my $self  = shift;
    my $type  = shift;
    my $token = shift;
    push @{ $self->{_tokens} }, [ $type, $token, $self->_get_offset ];
    $self->_add_offset( length $token );
}

#===================================
sub _skip_token {
#===================================
    my $self  = shift;
    my $token = shift;
    $self->_add_offset( length $token );
}

#===================================
sub _unknown_token {
#===================================
    my $self = shift;
    my $expected = shift || '';
    if ($expected) {
        $expected = "Expected: $expected\n";
    }
    my $input  = $self->_original;
    my $offset = $self->_get_offset;
    my $exception
        = substr( $input, 0, $offset )
        . " HERE --> "
        . substr( $input, $offset );
    die "Syntax error marked by HERE --> : $exception\n$expected";
}

#===================================
sub _input {
#===================================
    my $self = shift;
    if (@_) {
        $self->{_input} = shift();
    }
    return $self->{_input};
}

#===================================
sub _original {
#===================================
    my $self = shift;
    if (@_) {
        $self->{_original} = shift();
    }
    return $self->{_original};
}

#===================================
sub _params {
#===================================
    my $self = shift;
    if (@_) {
        $self->{_params} = shift();
    }
    return $self->{_params};
}
#===================================
sub _reset_offset {
#===================================
    my $self = shift;
    $self->{_offset} = 0;
}

#===================================
sub _add_offset {
#===================================
    my $self = shift;
    my $length = shift || 0;
    $self->{_input} = substr( $self->{_input}, $length );
    $self->{_offset} += $length;
}

#===================================
sub _get_offset {
#===================================
    my $self = shift;
    $self->{_offset};
}

#===================================
sub _next_token {
#===================================
    my $self = shift;
    shift @{ $self->{_tokens} };
}

#===================================
sub _peek_next_token {
#===================================
    my $self = shift;
    $self->{_tokens}->[0];
}

#===================================
sub _tokens {
#===================================
    my $self = shift;
    if (@_) {
        $self->{_tokens} = shift;
    }
    return $self->{_tokens};
}

#===================================
sub _has_opaque {
#===================================
    my $self = shift;
    if (@_) {
        $self->{_has_opaque} = shift();
    }
    return $self->{_has_opaque}

}

1;
