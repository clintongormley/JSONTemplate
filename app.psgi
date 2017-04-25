#!/usr/bin/env perl

use strict;
use warnings;

use lib 'lib';
use Encode qw(encode_utf8);
use Plack::Request;
use Plack::Builder;
use Plack::Response;
use Plack::App::File;
use JSONTemplate;
use HTML::Entities qw(encode_entities decode_entities);
use JSON::XS;

use FindBin;

our $JSON = JSON::XS->new->utf8->canonical;
our $J    = JSONTemplate->new;

builder {
    mount '/render' => \&render;
    enable "Plack::Middleware::DirIndex", dir_index => 'index.html';
    mount '/' => Plack::App::File->new( root => "$FindBin::Bin/html/" )->to_app;
};

#===================================
sub render {
#===================================
    my $req = Plack::Request->new(@_);
    my $qs  = $req->query_parameters;

    my $params   = $JSON->decode( '{' . $qs->get_one('params') . '}' );
    my $template = $qs->get_one('template');
    my ( $result, $error );
    eval { $result = $J->render_json( $template, $params ); 1 }
        or $error = $@;

    if ($error) {
        utf8::encode($error);
        return [ 400, [ 'Content-Type', 'text/plain' ], [$error] ];
    }

    return [ 200, [ 'Content-Type', 'text/plain' ], [$result] ];
}
