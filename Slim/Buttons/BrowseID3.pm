package Slim::Buttons::BrowseID3;
# $Id: BrowseID3.pm,v 1.23 2004/12/07 20:19:47 dsully Exp $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Buttons::VarietyCombo;
use Slim::Utils::Misc;

# Code to browse music folder by ID3 information.
Slim::Buttons::Common::addMode('browseid3',Slim::Buttons::BrowseID3::getFunctions(),\&Slim::Buttons::BrowseID3::setMode);

sub init {

	my %browse = (

		'BROWSE_BY_GENRE' => {
			'useMode' => 'browseid3',
		},

		'BROWSE_BY_ARTIST' => {
			'useMode' => 'browseid3',
			'genre'=>'*',
		},

		'BROWSE_BY_ALBUM' => {
			'useMode' => 'browseid3',
			'genre'=>'*',
			'artist'=>'*',
		},

		'BROWSE_BY_SONG' => {
			'useMode' => 'browseid3',
			'genre'=>'*',
			'artist'=>'*',
			'album'=>'*',
		},
	);
	
	foreach my $name (sort keys %browse) {

		if ($name ne 'BROWSE_BY_SONG') {
			Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $browse{$name});
		}

		Slim::Buttons::Home::addMenuOption($name, $browse{$name});
	};
}

# Each button on the remote has a function:

my %functions = (

	'up' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my $count = scalar @{browseID3dir($client)};
		if ($count < 2) {
			$client->bumpUp();
		} else {
			$inc = ($inc =~ /\D/) ? -1 : -$inc;
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $count, browseID3dirIndex($client));
			browseID3dirIndex($client,$newposition);
			updateLastSelection($client);
			$client->update();
		}
	},
	'down' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my $count = scalar @{browseID3dir($client)};
		if ($count < 2) {
			$client->bumpDown();
		} else {
			if ($inc =~ /\D/) {$inc = 1}
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $count, browseID3dirIndex($client));
			browseID3dirIndex($client,$newposition);
			updateLastSelection($client);
			$client->update();
		}
	},
	'left' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);
		my $genre = selection($client,'curgenre');
		my $artist = selection($client,'curartist');
		my $album = selection($client,'curalbum');
		my $song = selection($client,'cursong');
		my $startgenre = selection($client, 'genre');
		my $startartist = selection($client, 'artist');
		my $startalbum = selection($client, 'album');
		my $startsong = selection($client, 'song');
		updateLastSelection($client);
		if (equal($genre, $startgenre) && equal($artist, $startartist) && equal($album, $startalbum) && equal($song, $startsong)) {
			# we don't know anything, go back to where we came from
			Slim::Buttons::Common::popMode($client);
		} else {
			# go up one level
			if (specified($album)) {
				# we're at the song level
				# forget we knew the album
				setSelection($client,'curalbum', selection($client,'album'));
				loadDir($client);
				# disabled: skip album, if there is only one
				#if (scalar @{browseID3dir($client)} == 1) {
				#	setSelection($client,'curartist', selection($client,'artist'));
				#	loadDir($client);
				#}
			} elsif (specified($artist)) {
				# we're at the album level
				# forget we knew the artist
				setSelection($client,'curartist', selection($client,'artist'));
				loadDir($client);
			} elsif (specified($genre)) {
				# we're at the artist level
				# forget we knew the genre
				setSelection($client,'curgenre', selection($client,'genre'));
				loadDir($client);
			}
			loadDir($client);
		}
		$client->pushRight( \@oldlines, [Slim::Display::Display::curLines($client)]);
	},
	'right' => sub  {
		my $client = shift;
		if (scalar @{browseID3dir($client)} == 0) {
			# don't do anything if the list is empty, which shouldn't happen anyways...
			$client->bumpRight();
		} else {
			my $currentItem = browseID3dir($client,browseID3dirIndex($client));
			$::d_files && msg("currentItem == $currentItem\n");
			my @oldlines = Slim::Display::Display::curLines($client);
			updateLastSelection($client);
			my $genre = selection($client,'curgenre');
			my $artist = selection($client,'curartist');
			my $album = selection($client,'curalbum');
			my $song = selection($client,'cursong');
			if (picked($genre) && picked($artist) && picked($album)) {
				# we know the genre, artist, album and song.  show the song info for the track in $currentitem
				Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $currentItem});
			} elsif (picked($genre) && picked($artist)) {
				# we know the genre, artist and album.  show the songs.
				setSelection($client,'curalbum', $currentItem);
				loadDir($client);
			} elsif (picked($genre)) {
				# we know the genre and artist.  show the album.
				setSelection($client,'curartist', $currentItem);
				loadDir($client);
				# Disabled: skip album, if there is only one
				#if (scalar @{browseID3dir($client)} == 1) {
				#	setSelection($client,'curalbum', browseID3dir($client, 0));
				#	loadDir($client);
				#}
			} else {
				# we just chose the genre, show it...
				setSelection($client,'curgenre', $currentItem);
				loadDir($client);
			}
			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $newposition;
		my $genre = selection($client,'curgenre');
		my $artist = selection($client,'curartist');
		my $album = selection($client,'curalbum');
		# if it's just songs, then
		if (defined($genre) && defined($artist) && defined($album)) {
			# do an unsorted jump
			$newposition = Slim::Buttons::Common::numberScroll($client, $digit, browseID3dir($client), 0);
		} else {
			# otherwise, scroll to the appropriate letter
			$newposition = Slim::Buttons::Common::numberScroll($client, $digit, browseID3dir($client), 1,
			sub {
				my $ignored = browseID3dir($client)->[shift];
				my $articles =  Slim::Utils::Prefs::get("ignoredarticles");
				$articles =~ s/\s+/|/g;
				$ignored =~ s/^($articles)\s+//i;
				return $ignored;
			}
			);
		}
		browseID3dirIndex($client,$newposition);
		updateLastSelection($client);
		$client->update();
	},

	# this routine handles play, add and insert ($addorinsert would be undef, 1 or 2 respectively)
	'play' => sub  {
		my $client = shift;
		my $button = shift;
		my $addorinsert = shift || 0;
		my $genre = selection($client,'curgenre');
		my $artist = selection($client,'curartist');
		my $album = selection($client,'curalbum');
		my $all_albums;
		my $sortbytitle;

		if (defined($album) && ($album eq $client->string('ALL_SONGS'))) {
			$album = '*';
			$sortbytitle = 1;
		}

		if (defined($artist) && ($artist eq $client->string('ALL_ALBUMS'))) {
			$artist = '*';
			$sortbytitle = 1;
		}

		if (defined($genre) && ($genre eq $client->string('ALL_ARTISTS'))) {
			$genre = '*';
		}
		
		my $currentItem = browseID3dir($client, browseID3dirIndex($client));

		my ($line1, $line2) = lines($client);
		
		my $command;
		my $songcommand;
		
		if ($addorinsert == 1) {
			$line1 = $client->string('ADDING_TO_PLAYLIST');
			$command = "addalbum";	
		} elsif ($addorinsert == 2) {
			$line1 = $client->string('INSERT_TO_PLAYLIST');
			$command = "insertalbum";
		} else {
			$command = "loadalbum";			
			if (Slim::Player::Playlist::shuffle($client)) {
				$line1 = $client->string('PLAYING_RANDOMLY_FROM');
			} else {
				$line1 = $client->string('NOW_PLAYING_FROM');
			}
		}
		
		$client->showBriefly(
			$client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')),
			undef,
			1
		);
		
		# if we've chosen a particular song to append, then append it
		if (picked($genre) && picked($artist) && picked($album)) {
			if ($addorinsert || $album eq '*' || !Slim::Utils::Prefs::get('playtrackalbum')) {
				$command = 'play';
				if ($addorinsert == 1) { $command = 'append'; }
				if ($addorinsert == 2) { $command = 'insert'; }
				Slim::Control::Command::execute($client, ["playlist", $command, $currentItem]);
			} else {
				my $wasShuffled = Slim::Player::Playlist::shuffle($client);
				Slim::Player::Playlist::shuffle($client, 0);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", $genre, $artist, picked($album) ? $album : $currentItem]);
				Slim::Control::Command::execute($client, ["playlist", "jump", picked($album) ? browseID3dirIndex($client) : "0"]);
				if ($wasShuffled) { Slim::Control::Command::execute($client, ["playlist", "shuffle", 1]); }
			}	
					
		# if we've picked an album or song to play then play the album 
		# if we've picked an album to append, then append the album
		} elsif (picked($genre) && picked($artist)) {
			$::d_files && msg("song  or album $currentItem\n"); 
			my $whichalbum = picked($album) ?  $album : (($currentItem eq $client->string('ALL_SONGS')) ? '*' : $currentItem);
			Slim::Control::Command::execute($client, ["playlist", $command, $genre, $artist, $whichalbum,undef,  $currentItem eq $client->string('ALL_SONGS')]);	
		# if we've picked an artist to append or play, then do so.
		} elsif (picked($genre)) {
			$::d_files && msg("artist $currentItem\n");
			my $whichartist = picked($artist) ? $artist : (($currentItem eq $client->string('ALL_ALBUMS')) ? '*' : $currentItem);
			#TODO this sometime causes a warning
			my $whichalbum = (defined $album && $album ne $client->string('ALL_ALBUMS')) ? $currentItem : '*';
			my $whichgenre = ($genre eq $client->string('ALL_ARTISTS')) ? '*' : $genre;
			Slim::Control::Command::execute($client, ["playlist", $command, $whichgenre, $whichartist, $whichalbum,undef, $sortbytitle]);		
		# if we've picked a genre to play or append, then do so
		} else {
			$::d_files && msg("genre: $currentItem\n");
			$currentItem = ($currentItem eq $client->string('ALL_ALBUMS')) ? '*' : $currentItem;
			Slim::Control::Command::execute($client, ["playlist", $command,$currentItem, "*", "*"]);
		}
		$::d_files && msg("currentItem == $currentItem\n");
	},

	'create_mix' => sub  {
		my $client = shift;
		# Check for moodlogic
		if (Slim::Music::MoodLogic::useMoodLogic()) {
			my $genre = selection($client,'curgenre');
			my $artist = selection($client,'curartist');
			my $album = selection($client,'curalbum');
			my $currentItem = browseID3dir($client,browseID3dirIndex($client));
			my @oldlines = Slim::Display::Display::curLines($client);
	
			# if we've chosen a particular song
			if (picked($genre) && picked($artist) && picked($album) && Slim::Music::Info::isSongMixable($currentItem)) {
					Slim::Buttons::Common::pushMode($client, 'moodlogic_variety_combo', {'song' => $currentItem});
					$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
			# if we've picked an artist 
			} elsif (picked($genre) && ! picked($album) && Slim::Music::Info::isArtistMixable($currentItem)) {
					Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'artist' => $currentItem});
					$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
			# if we've picked a genre 
			} elsif (Slim::Music::Info::isGenreMixable($currentItem)) {
					Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'genre' => $currentItem});
					$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
			# don't do anything if nothing is mixable
			} else {
					$client->bumpLeft();
			}
		# Check for musicmagic
		} elsif (Slim::Music::MusicMagic::useMusicMagic()) {
			my $genre = selection($client,'curgenre');
			my $artist = selection($client,'curartist');
			my $album = selection($client,'curalbum');
			my $currentItem = browseID3dir($client,browseID3dirIndex($client));
			my @oldlines = Slim::Display::Display::curLines($client);
			
			# if we've chosen a particular song
			if (picked($genre) && picked($artist) && picked($album) && Slim::Music::Info::isSongMMMixable($currentItem)) {
				
				# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				Slim::Buttons::Common::pushMode($client, 'instant_mix', {'song' => Slim::Utils::Misc::pathFromFileURL($currentItem)});
				Slim::Buttons::VarietyCombo::specialPushLeft($client, 0, @oldlines);
				
			# if we've picked an artist 
			} elsif (picked($genre) && ! picked($album) && Slim::Music::Info::isArtistMMMixable($currentItem)) {
				
				# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				Slim::Buttons::Common::pushMode($client, 'instant_mix', {'artist' => $currentItem});
				Slim::Buttons::VarietyCombo::specialPushLeft($client, 0, @oldlines);
				
			# if we've picked an album 
			} elsif (picked($genre) && picked($artist) && !picked($album) && Slim::Music::Info::isAlbumMMMixable($artist, $currentItem)) {
				
				# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				my $key = "$artist\@\@$currentItem";
				Slim::Buttons::Common::pushMode($client, 'instant_mix', {'album' => $key});
				Slim::Buttons::VarietyCombo::specialPushLeft($client, 0, @oldlines);
				
			# if we've picked a genre 
			} elsif (Slim::Music::Info::isGenreMMMixable($currentItem)) {
				
			       # For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				Slim::Buttons::Common::pushMode($client, 'instant_mix', {'genre' => $currentItem});
				Slim::Buttons::VarietyCombo::specialPushLeft($client, 0, @oldlines);
				
			# don't do anything if nothing is mixable
			} else {
				$client->bumpLeft();
			}
		} else {
			# if we don't have mix generation, then just play
			(getFunctions())->{'play'}($client);
		}
		
	},

);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push = shift;

	if ($push eq 'push') {
		setSelection($client,'curgenre', selection($client,'genre'));
		setSelection($client,'curartist', selection($client,'artist'));
		setSelection($client,'curalbum', selection($client,'album'));
		setSelection($client,'cursong', selection($client,'song'));
	}
	
	$client->lines(\&lines);
	loadDir($client);
}

sub safe {
	my $i = shift;
	
	return defined($i) ? $i : "";
}

sub updateLastSelection {
	my $client = shift;
	my $artist = safe(selection($client,'curartist'));
	my $album = safe(selection($client,'curalbum'));
	my $song = safe(selection($client,'cursong'));
	my $genre = safe(selection($client,'curgenre'));
	lastSelection($client, $genre . "-" . $artist . "-" . $album . "-" . $song, browseID3dirIndex($client));
	$client->lastID3Selection($genre . "-" . $artist . "-" . $album . "-" . $song, browseID3dirIndex($client));
}

sub getLastSelection {
	my $client = shift;
	my $artist = safe(selection($client,'curartist'));
	my $album = safe(selection($client,'curalbum'));
	my $song = safe(selection($client,'cursong'));
	my $genre = safe(selection($client,'curgenre'));
	my $last = lastSelection($client, $genre . "-" . $artist . "-" . $album . "-" . $song);
	if (!defined($last)) {
		$last = $client->lastID3Selection($genre . "-" . $artist . "-" . $album . "-" . $song);
	}
	if (!defined($last)) {
		$last = 0;
	}
	return $last;
}

# create a directory listing, and append it to dirItems
sub loadDir {
	my ($client) = @_;

	my $genre  = selection($client,'curgenre');
	my $artist = selection($client,'curartist');
	my $album  = selection($client,'curalbum');
	my $song   = selection($client,'cursong');

	my $sortbytitle;

	if (defined($album) && $album eq $client->string('ALL_SONGS')) {
		$album = '*';
		$sortbytitle = 1;
	};

	if (defined($artist) && ($artist eq $client->string('ALL_ALBUMS'))) {
		$artist = '*';
		$sortbytitle = picked($album) ? 0 : 1;
	};

	if (defined($genre) && ($genre eq $client->string('ALL_ARTISTS'))) {
		$genre = '*';
		$sortbytitle = picked($album) ? 0 : 1;
	};

	if ($genre  && $genre  eq '*' &&
		$artist && $artist eq '*' &&
		$album  && $album  eq '*' && !specified($song)) {

		$sortbytitle = 1;
	};

	$::d_files && msg("loading dir for $genre - $artist - $album - $song\n");

	if (picked($genre) && picked($artist) && picked($album)) {

		@{browseID3dir($client)} = Slim::Music::Info::songs(
			singletonRef($genre),
			singletonRef($artist),
			singletonRef($album),
			singletonRef($song),
			$sortbytitle
		);

	} elsif (picked($genre) && picked($artist)) {

		@{browseID3dir($client)} = Slim::Music::Info::albums(
			singletonRef($genre),
			singletonRef($artist),
			singletonRef($album),
			singletonRef($song)
		);

		if (scalar @{browseID3dir($client)} > 1) {

			push @{browseID3dir($client)}, $client->string('ALL_SONGS');
		}

	} elsif (picked($genre)) {

		@{browseID3dir($client)} = Slim::Music::Info::artists(
			singletonRef($genre),
			singletonRef($artist),
			singletonRef($album),
			singletonRef($song)
		);

		if (scalar @{browseID3dir($client)} > 1) {
			push @{browseID3dir($client)}, $client->string('ALL_ALBUMS');
		}

	} else {
		@{browseID3dir($client)} = Slim::Music::Info::genres(
			singletonRef($genre),
			singletonRef($artist),
			singletonRef($album),
			singletonRef($song)
		);
		
		if (scalar @{browseID3dir($client)} > 1) { 
			push @{browseID3dir($client)}, $client->string('ALL_ARTISTS'); }
	}

	return browseID3dirIndex($client, getLastSelection($client));
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay1, $overlay2);

	my $songlist = 0;
	
	my $genre = selection($client,'curgenre');
	my $artist = selection($client,'curartist');
	my $album = selection($client,'curalbum');
	my $song = selection($client,'cursong');
	my $plural = scalar @{browseID3dir($client)} > 1 ? 'S' : '';

	if (!defined($genre)) {
		$line1 = $client->string('GENRES');
	} elsif ($genre eq '*' && !defined($artist)) {
		$line1 = $client->string('ARTISTS');
	} elsif ($genre eq '*' && $artist eq '*' && !defined($album)) {
		$line1 = $client->string('ALBUMS');
	} elsif ($genre eq '*' && $artist eq '*' && $album eq '*' && !defined($song)) {
		$line1 = $client->string('SONGS');
		$songlist = 1;
	} elsif ($genre eq '*' && $artist eq '*' && $album eq '*' && !specified($song)) {
		$line1 = $client->string('SONG'.$plural.'MATCHING') . " \"" . searchTerm($song) . "\"";
		$songlist = 1;
	} elsif ($genre eq '*' && $artist eq '*' && !specified($album)) {
		$line1 = $client->string('ALBUM'.$plural.'MATCHING') . " \"" . searchTerm($album) . "\"";
	} elsif ($genre eq '*' && $artist eq '*' && specified($album) && !defined($song)) {
		$line1 = $album;
		$songlist = 1;
	} elsif ($genre eq '*' && !specified($artist)) {
		$line1 = $client->string('ARTIST'.$plural.'MATCHING') . " \"" . searchTerm($artist) . "\"";
	} elsif (specified($genre) && !defined($artist)) {
		$line1 = $genre;
	} elsif ($genre eq '*' && specified($artist) && !defined($album)) {
		$line1 = $artist;
	} elsif (specified($genre) && specified($artist) && !defined($album)) {
		$line1 = $genre.'/'.$artist;
	} elsif (specified($genre) && specified($artist) && specified($album) && !defined($song)) {
		$line1 = $artist.'/'.$album;
		$songlist = 1;
	} elsif ($genre eq '*' && specified($artist) && specified($album) && !defined($song)) {
		$line1 = $artist.'/'.$album;
		$songlist = 1;
	} else {
		die "can't calculate string for $genre $artist $album $song";
	}

	if (scalar @{browseID3dir($client)} == 0) {

			$line2 = $client->string('EMPTY');
	} else {

		$line1 .= sprintf(" (%d %s %s)", browseID3dirIndex($client) + 1, $client->string('OUT_OF'), scalar @{browseID3dir($client)});

		if ($songlist) {

			$line2 = Slim::Music::Info::standardTitle($client, browseID3dir($client,browseID3dirIndex($client)));

			if (Slim::Music::Info::isSongMixable(browseID3dir($client,browseID3dirIndex($client)))) {
				$overlay1 = Slim::Display::Display::symbol('moodlogic');
			}

			if (Slim::Music::Info::isSongMMMixable(browseID3dir($client,browseID3dirIndex($client)))) {
				$overlay1 = Slim::Display::Display::symbol('musicmagic');
			}

			$overlay2 = Slim::Display::Display::symbol('notesymbol');

		} else {

			$line2 = browseID3dir($client,browseID3dirIndex($client));

			if (! defined($genre) && ! defined($artist) && ! defined($album) && Slim::Music::Info::isGenreMixable($line2)) {
				$overlay1 = Slim::Display::Display::symbol('moodlogic');
			}

			if (defined($genre) && ! defined($artist) && ! defined($album) && Slim::Music::Info::isArtistMixable($line2)) {
				$overlay1 = Slim::Display::Display::symbol('moodlogic');
			}

			if (! defined($genre) && ! defined($artist) && ! defined($album) && Slim::Music::Info::isGenreMMMixable($line2)) {
				$overlay1 = Slim::Display::Display::symbol('musicmagic');
			}

			if (defined($genre) && ! defined($artist) && ! defined($album) && Slim::Music::Info::isArtistMMMixable($line2)) {
				$overlay1 = Slim::Display::Display::symbol('musicmagic');
			}

			if (defined($genre) && defined($artist) && ! defined($album) && Slim::Music::Info::isAlbumMMMixable($artist, $line2)) {
				$overlay1 = Slim::Display::Display::symbol('musicmagic');
			}

			$overlay2 = Slim::Display::Display::symbol('rightarrow');
		}
	}

	return ($line1, $line2, $overlay1, $overlay2);
}

sub browseID3dir {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	# get a reference to the browseID3dir array that's kept in param stack
	my $arrayref = Slim::Buttons::Common::param($client, 'browseID3dir');

	# if it doesn't exist, make a new one (anonymously)
	if (!defined $arrayref) {
		$arrayref = [];
		Slim::Buttons::Common::param($client, 'browseID3dir', $arrayref);
	}

	# if the value is set, then save it in the array
	if (defined $value) {
		$arrayref->[$index] = $value;
	}

	# if the index is set, then return it, otherwise return a reference to the array itself
	if (defined $index) {
		return $arrayref->[$index];
	} else {
		return $arrayref;
	}
}

#	get the current selection parameter from the parameter stack (artist, album, genre, etc...)
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = Slim::Buttons::Common::param($client, $index);

	if (defined $value  && $value eq '__undefined') {
		undef $value;
	}

	return $value;
	}

#	set the current selection parameter from the parameter stack (artist, album, genre, etc...)
sub setSelection {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	if (!defined $value) {
		$value = '__undefined';
	}

	Slim::Buttons::Common::param($client, $index, $value);
}

#	get or set the lastSelection in the hash in the parameter stack
sub lastSelection {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	my $arrayref = Slim::Buttons::Common::param($client, 'lastSelection');

	if (!defined $arrayref) {
		$arrayref = {};
		Slim::Buttons::Common::param($client, 'lastSelection', $arrayref);
	}

	if (defined $value) {
		$arrayref->{$index} = $value;
	}

	if (defined $index) {
		return $arrayref->{$index};
	} else {
		return $arrayref;
	}
}

# get (and optionally set) the directory index
sub browseID3dirIndex {
	my $client = shift;
	my $line = Slim::Buttons::Common::param($client, 'browseID3dirIndex', shift);
	if (!defined($line)) {  $line = 0; }
	return $line
}


# undefined or contains a *
sub any {
	my $i = shift;
	return (!defined $i || $i =~ /\*/);
}

sub equal {
	my $a = shift;
	my $b = shift;
	if (!defined($a) && !defined($b)) { return 1; }
	if (!defined($a) || !defined($b)) { return 0; }
	if ($a eq $b) { return 1; }
	return 0;
}

# defined, but does not contain a *
sub specified {
	my $i = shift;
	if (!defined $i) { return 0};
	return $i !~ /\*/;
}

# defined and does not contain a star or equals star
sub picked {
	my $i = shift;
	if (!defined $i) { return 0};
	return (specified($i) || $i eq "*");
}

sub searchTerm {
	my $t = shift;
	$t =~ s/^\*(.+)\*$/$1/;
	return $t;
}

sub singletonRef {
	my $arg = shift;

	unless (defined($arg)) {

		return $arg;

	} elsif ($arg eq '*') {

		return [];

	} elsif (my ($g1) = ($arg =~ /^\*(.*)\*$/)) {

		my @sa = ();
		foreach my $ss (split(' ',$g1)) {
			push @sa, "*" . $ss . "*";
		}

		return \@sa;

	} elsif ($arg) {

		return [$arg];

	} else {

		return [];
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
