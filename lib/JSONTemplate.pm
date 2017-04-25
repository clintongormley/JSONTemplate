package JSONTemplate;

use strict;
use warnings;
use JSON::XS qw(encode_json decode_json);
use JSON();
use JSON::PP();
use URI::Escape();
use HTML::Entities();

our %Funcs = (
    "array" => sub {
        my $params = shift;
        return \@_;
    },
    "flatten" => sub {
        my $params = shift;
        return map { ref $_ eq 'ARRAY' ? @$_ : $_ } @_;
    },
    "html" => sub {
        my $params = shift;
        return map { HTML::Entities::encode_entities( $_, '<>&"' ) } @_;
    },
    "join" => sub {
        my $char = shift()->[0] || '';
        no warnings 'uninitialized';
        return join $char, map { _var_to_str($_) } grep {defined} @_;
    },
    "quote" => sub {
        my $params = shift;
        return map { '"' . $_ . '"' } @_;
    },
    "json" => sub {
        my $params = shift;
        return map { decode_json($_) } @_;
    },
    "lower" => sub {
        my $params = shift;
        return map { lc $_ } @_;
    },
    "string" => sub {
        my $params = shift;
        return _var_to_str(@_);
    },
    "upper" => sub {
        my $params = shift;
        return map { uc $_ } @_;
    },
    "uri" => sub {
        my $params = shift;
        return map { URI::Escape::uri_escape $_ } @_;
    }
);

#===================================
sub _var_to_str {
#===================================
    return
          @_ == 0                 ? ()
        : @_ > 1                  ? encode_json( \@_ )
        : !defined $_[0]          ? 'null'
        : !ref $_[0]              ? shift()
        : !JSON::is_bool( $_[0] ) ? encode_json( shift() )
        : $_[0]                   ? 'true'
        :                           'false';
}

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
    return $self->_process_list;
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

my %Unescape = (
    "b"  => "\b",
    "f"  => "\f",
    "n"  => "\n",
    "r"  => "\r",
    "t"  => "\t",
    '"'  => '"',
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
        my $val = join "", map { _var_to_str($_) } @output;
        $val =~ s/(\\\\|[\b\f\n\r\t"\\])/$Escape{$1}||$1/ge;
        return '"' . $val . '"';
    }
    if ( @output > 1 ) {
        return encode_json( \@output );
    }

    my $val = $output[0];
    if ( ref $val ) {
        if ( JSON::is_bool($val) ) {
            return $val ? 'true' : 'false';
        }
        return encode_json($val);
    }
    if ( !defined $val ) {
        return 'null';
    }
    if ( $val =~ /^\d+(?:\.\d+)?$/ ) {
        return $val;
    }
    $val =~ s/(\\\\|[\b\f\n\r\t"\\])/$Escape{$1}||$1/ge;
    utf8::encode($val);
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
        return join "", map { ref $_ ? encode_json($_) : $_ } @output;
    }
    if ( @output > 1 ) {
        return encode_json( \@output );
    }

    my $val = $output[0];
    if ( ref $val ) {
        if ( JSON::is_bool($val) ) {
            return $val ? 'true' : 'false';
        }
        return encode_json($val);
    }
    if ( !defined $val ) {
        return 'null';
    }
    return $val;
}

#===================================
sub _process_list {
#===================================
    my $self = shift;

    my @vals;

    while ( my $token = $self->_peek_next_token ) {
        my ( $type, $item ) = @$token;

        if ( $type eq 'OPAQUE' ) {
            push @vals, $item;
            $self->_has_opaque(1);
            $self->_next_token;
            next;
        }

        if ( $type =~ /^(VAL|VAR|OPEN_PAREN|OPEN_SECTION)$/ ) {
            push @vals, $self->_process_expression;
            next;
        }

        if ( $type =~ /^(CLOSE_PAREN|CLOSE_SECTION)$/ ) {
            last;
        }

        die "Unknown token type <$type>";
    }
    return @vals;
}

#===================================
sub _process_expression {
#===================================
    my $self  = shift;
    my $token = $self->_next_token;
    my ( $type, $item ) = @$token;

    my @vals
        = $type eq 'VAL'          ? $item
        : $type eq 'VAR'          ? $self->_lookup_var($item)
        : $type eq 'OPEN_PAREN'   ? $self->_process_list
        : $type eq 'OPEN_SECTION' ? $self->_process_section($item)
        :   do { $self->_replace_token($token); return };

    my $close
        = $type eq 'OPEN_PAREN'   ? 'CLOSE_PAREN'
        : $type eq 'OPEN_SECTION' ? 'CLOSE_SECTION'
        :                           '';

    if ($close) {
        my $next_token = $self->_next_token;
        my $got = $next_token && $next_token->[0] || '';
        unless ( $got eq $close ) {
            die "Expecting token <$close> but got <$got>";
        }
    }

    while ( my $token = $self->_peek_next_token ) {
        last unless $token->[0] eq 'FUNC';
        $self->_next_token;
        my ( $func, $params ) = $self->_get_func( $token->[1] );
        @vals = $func->( $params, @vals );
    }

    while ( my $token = $self->_peek_next_token ) {
        last unless $token->[0] eq 'CONCAT';
        $self->_next_token;
        my @next = $self->_process_expression();
        no warnings 'uninitialized';
        if ( @vals == 1 && @next == 1 ) {
            $vals[-1] = $vals[-1] . shift(@next);
        }
        else {
            push @vals, @next;
        }
    }
    return @vals;
}

#===================================
sub _get_func {
#===================================
    my $self = shift;
    my $name = shift;
    my $func = $Funcs{$name}
        or die "Unknown function name: <$name>\n";

    # no next token
    my $token = $self->_next_token || return ( $func, [] );

    # no param list
    if ( $token->[0] ne 'OPEN_PARAM' ) {
        $self->_replace_token($token);
        return ( $func, [] );
    }

    # build param list
    my @params;
    while ( $token = $self->_next_token ) {
        my ( $type, $item ) = @$token;
        last if $type eq 'CLOSE_PARAM';
        push @params,
              $type eq 'VAL' ? $item
            : $type eq 'VAR' ? $self->_lookup_var($item)
            :                  die "Unknown token type <$type>\n";
    }
    return ( $func, \@params );
}

#===================================
sub _process_section {
#===================================
    my $self = shift;
    my $name = shift;
    my $negate;
    if ( $name =~ s/^!// ) {
        $negate = 1;
    }

    my @tokens;
    my $nested = 1;
    while ( my $next = $self->_peek_next_token ) {
        last if $next->[0] eq 'CLOSE_SECTION' && 0 == --$nested;
        $nested++ if $next->[0] eq 'OPEN_SECTION';
        push @tokens, $self->_next_token;
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

    my @vals;
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
        push @vals, $self->_process_list;
        $self->_params($old_params);
    }
    $self->_tokens($old_tokens);
    return @vals;
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
            die "Cannot access array with key <$part>\n"
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

                   $self->_bool
                || $self->_null
                || $self->_number
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
    $self->_check_stack( pop @stack || '', '' );

}

my %Opening = (
    CODE    => '<<',
    PARAM   => '(',
    PAREN   => '(',
    SECTION => 'varname<'
);

my %Closing = (
    CODE    => '>>',
    PARAM   => ')',
    PAREN   => ')',
    SECTION => '>'
);

#===================================
sub _check_stack {
#===================================
    my $self     = shift;
    my $expected = shift;
    my $got      = shift || '';
    return if $expected eq $got;

    my $msg;
    if ($expected) {
        my $op = $Closing{$expected};
        if ($got) {
            $msg = "Expected $op but found " . $Closing{$got};
        }
        else {
            $msg = "Expected closing $op";
        }
    }
    else {
        my $op = $Closing{$got};
        $msg = "Found closing $op without opening " . $Opening{$got};
    }
    die "$msg:\n"
        . substr( $self->_original, 0, $self->_get_offset )
        . " \x{2B05} "
        . substr( $self->_original, $self->_get_offset ) . "\n";
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
sub _bool {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(true|false)\b/;
    my $val = $1 eq 'true' ? JSON::PP::true() : JSON::PP::false();
    $self->_add_token( 'VAL', $val, length($1) );
    return 1;
}

#===================================
sub _null {
#===================================
    my $self = shift;
    return unless $self->_input =~ /^(null)\b/;
    $self->_add_token( 'VAL', undef, length($1) );
    return 1;
}

#===================================
sub _number {
#===================================
    my $self = shift;
    if ( $self->_input =~ /^(\d+(?:\.\d+)?)/ ) {
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

    return unless $self->_input =~ /^"((?:\\"|[^"])*)"/;
    my $orig = my $str = $1;
    $str =~ s/\\([bfnrt"\\])/$Unescape{$1}/ge;
    $self->_skip_token('"');
    $self->_add_token( 'VAL', $str, length $orig );
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
    my $self   = shift;
    my $type   = shift;
    my $token  = shift;
    my $length = shift || length $token;
    push @{ $self->{_tokens} }, [ $type, $token ];
    $self->_add_offset($length);
}

#===================================
sub _skip_token {
#===================================
    my $self   = shift;
    my $token  = shift;
    my $length = shift || length $token;
    $self->_add_offset($length);
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
        . " \x{27A1} "
        . substr( $input, $offset );
    die "Syntax error:\n$exception\n$expected\n";
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
sub _replace_token {
#===================================
    my $self = shift;
    unshift @{ $self->_tokens }, shift();
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
