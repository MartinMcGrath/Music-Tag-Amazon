package Music::Tag::Amazon;
our $VERSION = 0.30;

# Copyright (c) 2007 Edward Allen III. Some rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.
#

=pod

=head1 NAME

Music::Tag::Amazon - Plugin module for Music::Tag to get information from Amazon.com

=head1 SYNOPSIS

	use Music::Tag

	my $info = Music::Tag->new($filename);
   
	my $plugin = $info->add_plugin("Amazon");
	$plugin->get_tag;

	print "Record Label is ", $info->label();

=head1 DESCRIPTION

Music::Tag::Amazon is normally created in Music::Tag. This plugin gathers additional information about a track from amazon, and updates the tag object.

=head1 REQUIRED VALUES

=over 4

=item artist

=back

=head1 USED VALUES

=over 4

=item asin

If the asin is set, this is used to look up the results instead of the artist name.

=item album

This is used to filter results. 

=item releasedate

This is used to filter results. 

=item totaltracks

This is used to filter results. 

=item title

title is used only if track is not true, or if trust_title option is set.

=item tracknum

tracknum is used only if title is not true, or if trust_track option is set.

=back

=head1 SET VALUES

=over 4

=item album

Album name is set if necessary.

=item title

title is set only if trust_track is true.

=item track

track is set only if track is not true or trust_title is true.

=item picture

highres is tried, then medium-res, then low. If low-res is a gif, it gives up.

=item asin

Amazon Store Identification Number

=item label

Label of Album

=item releasedate

Release Date

=item upc

UPC / Barcode 

=item ean

EAN. Valid outside of US only.

=item B<Amazon Optional Values>

These requires amazon_info optiom be true.

=over 4

=item amazon_salesrank

=item amazon_description

=item amazon_price

=item amazon_listprice

=item amazon_usedprice

=item amazon_usedcount

=back


=cut

use strict;
use warnings;
use Net::Amazon;
use Net::Amazon::Request::Artist;
use Net::Amazon::Request::ASIN;
use Cache::FileCache;
use LWP::UserAgent;
use Data::Dumper;
our @ISA = qw(Music::Tag::Generic);

sub default_options {
    {  quiet            => 0,
       verbose          => 0,
       trust_title      => 0,
       trust_track      => 0,
       coveroverwrite   => 0,
       token            => "0V2FQAQSWYH6XMJB8G82",
       min_album_points => 10,
       ignore_asin      => 0,
       max_pages        => 10,
       locale           => "us",
	   amazon_info		=> 0,
    };
}

=pod

=back

=head1 OPTIONS

Music::Tag::Amazon accepts the following options:

=over 4

=item  quiet

Setting to true turns off status messages.

=item verbose

Setting to true increases verbosity.

=item trust_title

When this is true, and a tag object's track number is different than the track number of the song with the same title in the Amazon listing, then the tagobject's tracknumber is updated. In other words, we trust that the song has accurate titles, but the tracknumbers may not be accurate.  If this is true and trust_track is true, then trust_track is ignored.

=item trust_track

When this is true, and a tag objects's title conflicts with the title of the corresponding track number on the Amazon listing, then the tag object's title is set to that of the track number on amazon.  In other words, we trust that the track numbers are accurate in the tag object. If trust_title is true, this option is ignored.

=item coveroverwrite

When this is true, a new cover is downloaded and the current cover is replaced.  The current cover is only replaced if a new cover is found.

=item token

Amazon Developer token. Change to one given to you by Amazon.

=item amazon_ua

A Net::Amazon object. Used if you want to define your own options for Net::Amazon. 

=item lwp_ua

A LWP::UserAgent object. Used if you want to define your own options.

=item amazon_cache

A cache object. Used by default Net::Amazon object to store results. A Cache::FileCache object by default.

=item coverart_cache

A cache object. Used to store coverart in. A Cache::FileCache object by default.

=item min_album_points

Minimum number of points an album must have to win election. Default 10.

=item locale

Locale code for store to use. Valid are ca, de, fr, jp, uk or us as of now.  Maybe more...

=item amazon_info

Return optional info.

=back

=head1 METHODS

=over 4

=item get_tag

Updates current tag object with information from Amazon database.

=cut

sub get_tag {
    my $self = shift;

    my $filename = $self->info->filename;

    unless ( $self->info->artist ) {
        $self->status("Amazon lookup requires ARTIST already set!");
    }

    my $p = $self->_album_lookup( $self->info, $self->options );
    unless ( ( defined $p ) && ( $p->{album} ) ) {
        $self->status("Amazon lookup failed");
        return $self->info;
    }
    $self->status("Amazon lookup successfull");

    my $totaldiscs = 0;
    my $discs      = $self->_tracks_by_discs($p);
	#print STDERR Dumper($p);


    if ((defined $discs) && ($discs->[0])) {
        my $tracknum = 0;
        my $discnum = $self->info->disc || 1;
        if ( ( $self->options->{trust_title} ) or ( not $self->info->track ) ) {
            foreach my $tr ( values %{ $self->_tracks_by_name($p) } ) {
                if (($self->info->title) && ( $self->simple_compare( $self->info->title, $tr->{content}, ".90" ) )) {
                    unless (($self->info->track) && ( $self->info->track == $tr->{Number} )) {
                        $self->info->track( $tr->{Number} );
                        $self->tagchange("TRACK");
                    }
                    $tracknum = $tr->{Number};
                    unless (($self->info->disc) && ( $self->info->disc eq $tr->{Disc} )) {
                        $self->info->disc( $tr->{Disc} );
                        $self->tagchange("DISC");
                    }
                    $discnum = $tr->{Disc};
                    last;
                }
            }
        }
        elsif ( $self->options->{trust_track} && $self->info->track() ) {
            $tracknum = $self->info->track();
        }
        if ( $tracknum && $discnum ) {
            if (    ( exists $discs->[ $discnum - 1 ] )
                 && ( exists $discs->[ $discnum - 1 ]->[ $tracknum - 1 ] ) ) {
                $self->info->title( $discs->[ $discnum - 1 ]->[ $tracknum - 1 ] );
                $self->tagchange("TITLE");
            }
        }
            my $totaltracks = scalar @{ $discs->[ $discnum - 1 ] };
            unless ( ($self->info->totaltracks) && ($totaltracks) && ( $totaltracks == $self->info->totaltracks() ) ) {
                $self->info->totaltracks($totaltracks);
                $self->tagchange("TOTALTRACKS");
            }
            my $totaldiscs = scalar @{$discs};
            unless ( ($self->info->totaldiscs) &&  ($totaldiscs) && ( $totaldiscs == $self->info->totaldiscs() ) ) {
                $self->info->totaldiscs($totaldiscs);
                $self->tagchange("TOTALDISCS");
            }
    }
    my $releasedate = $self->_amazon_to_sql( $p->ReleaseDate );
    unless ( ($releasedate) && ( $releasedate eq $self->info->releasedate ) ) {
        $self->info->releasedate($releasedate);
        $self->tagchange("RELEASEDATE");
    }
    unless ( $self->info->url) { 
		#my $url = "http://amazon.com/o/ASIN/".$asin;
		my $url = $p->DetailPageURL;
		$self->info->url($url);
		$self->tagchange("URL");
    }

	my %method_map = (
		album => "album",
		label => "label",
		ASIN => "asin",
		upc => "upc",
		ean => "ean",
	   ($self->options->{amazon_info}) ?
	   ( SalesRank => "amazon_salesrank",
	   	 ProductDescription => "amazon_description",
		 OurPrice	=> "amazon_price",
		 Availability	=> "amazon_availability",
		 ListPrice	=> "amazon_listprice",
		 UsedPrice	=> "amazon_usedprice",
		 UsedCount	=> "amazon_usedcount",
	   ) :
	   ()
	);
	while (my ($am, $mm) = each %method_map) {
		#Make sure datamethod exists
		$self->info->datamethods($mm);
		unless ( ( $p->$am ) && (defined $p->$am) && (defined $self->info->$mm) && ( $p->$am eq $self->info->$mm  ) ) {
			$self->info->$mm( $p->$am );
			$self->tagchange(uc($mm));
		}
	}
    if (    ( $p->ImageUrlLarge )
         && ( ( not $self->info->picture ) || ( $self->options('coveroverwrite') ) ) ) {
        $self->status( "DOWNLOADING LARGE COVER ART ", $p->ImageUrlLarge );
        $self->info->picture( $self->_cover_art( $p->ImageUrlLarge ) );
    }

    if (    ( $p->ImageUrlMedium )
         && ( ( not $self->info->picture ) ) ) {
        $self->status( "DOWNLOADING MEDIUM COVER ART ", $p->ImageUrlMedium );
        $self->info->picture( $self->_cover_art( $p->ImageUrlMedium ) );
    }
    return $self;
}

=item lwp

Returns and optionally sets reference to underlying LWP user agent.

=cut

sub lwp {
    my $self = shift;
	my $new = shift;
	if ($new) {
		$self->{lwp_ua} = $new;
	}
    unless ( ( exists $self->{lwp_ua} ) && ( $self->{lwp_ua} ) ) {
        if ( $self->options->{amazon_ua} ) {
            $self->{lwp_ua} = $self->options->{lwp_ua};
        }
        else {
            $self->{lwp_ua} = LWP::UserAgent->new();
        }

    }
    return $self->{lwp_ua};
}

=item amazon_cache

Returns and optionally sets a reference to the Cache::FileCache object used to cache amazon requests.

=cut

sub amazon_cache {
    my $self = shift;
	my $new = shift;
	if ($new) {
		$self->{amazon_cache} = $new;
	}
    unless ( ( exists $self->{amazon_cache} ) && ( $self->{amazon_cache} ) ) {
        if ( $self->options->{amazon_cache} ) {
            $self->{amazon_cache} = $self->options->{amazon_cache};
        }
        else {
            $self->{amazon_cache} =
              Cache::FileCache->new(
                                     { namespace          => "amazon_cache",
                                       default_expires_in => 60000,
                                     }
                                   );
        }
    }
    return $self->{amazon_cache};
}

=item amazon_cache

Returns and optionally sets reference to the Cache::FileCache object used to cache downloaded cover art.

=cut

sub coverart_cache {
    my $self = shift;
	my $new = shift;
	if ($new) {
		$self->{coverart_cache} = $new;
	}
    unless ( ( exists $self->{coverart_cache} ) && ( $self->{coverart_cache} ) ) {
        if ( $self->options->{coverart_cache} ) {
            $self->{coverart_cache} = $self->options->{coverart_cache};
        }
        else {
            $self->{coverart_cache} =
              Cache::FileCache->new(
                                     { namespace          => "coverart_cache",
                                       default_expires_in => 60000,
                                     }
                                   );
        }
    }
    return $self->{coverart_cache};

}

=item amazon_ua

Returns and optionally sets reference to Net::Amazon object.

=cut

sub amazon_ua {
    my $self = shift;
	my $new = shift;
	if ($new) {
		$self->{amazon_ua} = $new;
	}
    unless ( ( exists $self->{amazon_ua} ) && ( $self->{amazon_ua} ) ) {
        if ( $self->options->{amazon_ua} ) {
            $self->{amazon_ua} = $self->options->{amazon_ua};
        }
        else {
            $self->{amazon_ua} = Net::Amazon->new( token      => $self->options->{token},
                                                   cache      => $self->amazon_cache,
                                                   max_pages  => $self->options->{max_pages},
                                                   locale     => $self->options->{locale},
                                                   strict     => 1,
                                                   rate_limit => 1,
                                                 );
        }
    }
    return $self->{amazon_ua};
}

=pod

=item default_options

Returns the default options for the plugin.  

=item set_tag

Not used by this plugin.

=back

=head1 METHEDOLOGY

If the asin value is true in the tag object, then the lookup is done with this value. Otherwise, it performs a search for all albums by artist, and then waits each album to see which is the most likely. It assigns point using the following values:

  Matches ASIN:            128 pts
  Matches UPC or EAN:      64 pts
  Full name match:         32 pts
   or close name match:    20 pts
  Contains name of track:  10 pts
   or title match:         8 pts 
  Matches totaltracks:     4 pts
  Matches year:            2 pts
  Older than last match:   1 pts

Highest album wins. A minimum of 10 pts needed to win the election by default (set by min_album_points option).

Close name match means that both names are the same, after you get rid of white space, articles (the, a, an), lower case everything, translate roman numerals to decimal, etc.

=cut

sub _album_lookup {
    my $self = shift;

    my $req = Net::Amazon::Request::Artist->new( artist => $self->info->artist );

	# UPC and EAN are not currently a core datamethod, let's add...
	$self->info->datamethods("upc");
	$self->info->datamethods("ean");

    if ( ( $self->info->asin ) && ( not $self->options->{ignore_asin} ) ) {
        $self->status( "Doing ASIN lookup with ASIN: ", $self->info->asin );
        $req = Net::Amazon::Request::ASIN->new( asin => $self->info->asin );
    }
    elsif ( ( $self->info->upc ) && ( not $self->options->{ignore_upc} ) ) {
        $self->status( "Doing UPC lookup with UPC: ", $self->info->upc );
        $req = Net::Amazon::Request::UPC->new( upc => $self->info->upc, mode => 'music' );
    }
    elsif ( ( $self->info->ean ) && ( not $self->options->{ignore_ean} ) && (not $self->options->{locale} eq 'us' )) {
        $self->status( "Doing EAN lookup with EAN: ", $self->info->ean );
        $req = Net::Amazon::Request::EAN->new( ean => $self->info->ean );
    }

    my $resp = $self->amazon_ua->request($req);
    my $n    = 0;

    my $maxscore = 0;
    my $curmatch = undef;

    if ( $resp->is_error() ) {
        $self->error( $resp->message() );
        return;
    }

    for my $p ( $resp->properties ) {
        $n++;
        my $score = 0;
        unless ( exists $p->{tracks} ) {
            next;
        }
        unless ($curmatch) {
            $curmatch = $p;
        }
        my $asin = $p->ASIN;
        $self->status( "Checking out ASIN: ", $asin );
        if (    ($asin)
             && ( uc($asin) eq uc( $self->info->asin ) )
             && ( not $self->options->{ignore_asin} ) ) {
            $score += 128;
        }
        if ((($self->info->upc) && ( $p->upc eq $self->info->upc )) or
			(($self->info->ean) && ( $p->ean eq $self->info->ean )))  {
            $score += 64;
        }
        if (($self->info->album) && ( $p->album eq $self->info->album )) {
            $score += 32;
        }
        elsif (($self->info->album) && ( $self->simple_compare( $p->album, $self->info->album, ".80" ) )) {
            $score += 20;
        }
        if  ((defined $self->info->totaltracks) && ( scalar @{ $p->{tracks} } == $self->info->totaltracks )) {
            $score += 4;
        }
        if ((defined $self->info->year) && ( $p->year == $self->info->year )) {
            $score += 2;
        }
        if ( $p->year < $curmatch->{year} ) {
            $score += 1;
        }
        my $m = 0;
        my $t = 0;
        foreach ( @{ $p->{tracks} } ) {
            if (($self->info->title) && ( $self->simple_compare( $_, $self->info->title, ".90" ) )) {
                $m++;
                $t = $m;
            }
        }
        if ($m) {
            $score += 8;
            if (($self->info->track) && ( $t == $self->info->track )) {
                $score += 2;
            }
        }
        if ( $score > $maxscore ) {
            $curmatch = $p;
            $maxscore = $score;
        }
    }
    if ( $maxscore < $self->options->{min_album_points} ) {
        $self->status(   "No album scored over "
                       . $self->options->{min_album_points} . " [ "
                       . $n
                       . " canidates ]" );
        return;
    }
    $self->status(   "Album title "
                   . $curmatch->{album}
                   . " won with score of $maxscore [ "
                   . $n
                   . " canidates]" );
    return $curmatch;
}

sub _cover_art {
    my $self = shift;
    my $url  = shift;
    my $art  = $self->coverart_cache->get($url);

    unless ($art) {
        $self->status("DOWNLOADING URL: $url");
        my $res = $self->lwp->get($url);
        $art = $res->content;
        $self->coverart_cache->set( $url, $art );
    }

    if ( substr( $art, 0, 6 ) eq "GIF89a" ) {
        $self->status("Current cover is gif, skipping");
        return;
    }

    #   my $image = Image::Magick->new(magick=>'jpg');
    #   $image->Resize(width=>300, height=>300);
    #   $image->BlobToImage($art);

    return {
        "Picture Type" => "Cover (front)",
        "MIME type"    => "image/jpg",
        Description    => "",

        #       _Data => $image->ImageToBlob(magick => 'jpg'),
        _Data => $art,
           }

}

sub _amazon_to_sql {
    my $self = shift;
    my $in   = shift;
    my %months = ( "january"   => 1,
                   "february"  => 2,
                   "march"     => 3,
                   "april"     => 4,
                   "may"       => 5,
                   "june"      => 6,
                   "july"      => 7,
                   "august"    => 8,
                   "september" => 9,
                   "october"   => 10,
                   "november"  => 11,
                   "december"  => 12
                 );
    if ( $in =~ /(\d\d) ([^,]+), (\d+)/ ) {
        return sprintf( "%4d-%02d-%02d", $3, $months{ lc($2) }, $1 );
    }
    else {
        return undef;
    }
}

sub _tracks_by_discs {
    my $self = shift;
    my $r    = shift;
    my $p    = $r->{xmlref};
    my @discs;
    if ( ( exists $p->{Tracks} ) && ( exists $p->{Tracks}->{Disc} ) ) {
        @discs = map {
            my @tracks = map { $_->{content} }
              sort { $a->{Number} <=> $b->{Number} } @{ $_->{Track} };
            \@tracks;
          }
          sort { $a->{Number} <=> $b->{Number} } @{ $p->{Tracks}->{Disc} };
    }
    return \@discs;
}

sub _tracks_by_name {
    my $self = shift;
    my $r    = shift;
    my $p    = $r->{xmlref};
    my %tracks;

    if ( ( exists $p->{Tracks} ) && ( exists $p->{Tracks}->{Disc} ) ) {
        foreach my $disc ( @{ $p->{Tracks}->{Disc} } ) {
            if ( exists $disc->{Track} ) {
                foreach my $track ( @{ $disc->{Track} } ) {
                    unless ( exists $tracks{ $track->{content} } ) {
                        $tracks{ $track->{content} } = $track;
                        $track->{Disc} = $disc->{Number};
                    }
                }
            }
        }
    }
    return \%tracks;
}

1;

=pod

=head1 BUGS

Does not do well with artist who have over 50 releases. Amazon sorts by most popular. 

Multi Disc / Volume sets seem to be working now, but support is still questionable.

=head1 SEE ALSO INCLUDED

L<Music::Tag>, L<Music::Tag::File>, L<Music::Tag::FLAC>, L<Music::Tag::Lyrics>,
L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::MusicBrainz>, L<Music::Tag::OGG>, L<Music::Tag::Option>

=head1 SEE ALSO

L<Net::Amazon>

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=head1 COPYRIGHT

Copyright (c) 2007,2008 Edward Allen III. Some rights reserved.

=cut