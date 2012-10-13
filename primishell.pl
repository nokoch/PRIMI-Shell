#!/bin/perl

use warnings;
use strict;
use Cwd;
use Term::ANSIColor;
use Data::Dumper;
use Term::ReadKey;
use Time::HiRes;
use Sys::Hostname;

$| = 1;
our $programsAreRunning = 0;
$SIG{INT} = sub{};
our @userinfo = getpwuid($<);
our @allPrograms = ();
getAllPrograms();
our @shellInternalPrograms = qw(exit ver cd showhistory showshellpid shellperl);
push @allPrograms, @shellInternalPrograms;
@allPrograms = removeDoubleElementsFromArray(@allPrograms);
our $ARROW_UP = chr(27);
our $BACKSPACE = chr(0x08);
our $CLEAR = chr(12);
our @folder_history = (cwd());
our @commandHistory = ();

print "PID: $$\n";
execute("ver");

while (1) {
	printBeginning();
	ReadMode('cbreak');
	my $input = ReadKey(0);
	print $input;
	if($input eq "\t") {
		my $vorschlag = cycleThrough($input, [], "", completetion($input, 0));
		if($vorschlag) {
			$input = $vorschlag;
			print "\e[1K\r";
			printBeginning();
			print $input;
		} else {
			$input = "";
		}
	} elsif ($input eq $CLEAR) {
		$input = "";
		print "\n";
		system("clear");
		printBeginning();
	} elsif ($input eq chr(127)) {
		$input = "";
		print "\b";
		print " ";
		print "\b";
	} elsif ($input eq chr(27)) {
		print "\n";
		print "\b";
		print " ";
		print "\b";
		printBeginning();
		$input = $commandHistory[$#commandHistory];
		print "$input\n";
	}
	ReadMode("normal");
	if($input ne "\n") {
		while ($input !~ /\n/) {
			ReadMode 'cbreak';
			my $tkey = ReadKey(0);
			ReadMode 'normal';
			if($tkey eq "\t") {
				my $prog_done = 0;
				if($input =~ /\s/) {
					$prog_done = 1;
				}
				my $vorschlag = cycleThrough($input.$tkey, [], "", completetion($input.$tkey, $prog_done));
				if($vorschlag) {
					print "\e[1K\r";
					printBeginning();
					if($input !~ /^(rm|rmdir) / && $prog_done) {
						my ($prog, @params) = split(/\s+/, $input);
						$input = "$prog $vorschlag";
						print $input;
						$input .= "\n";
						print "\n";
					} else {
						$input = $vorschlag;
						print $input;
					}
				}
		 	} elsif ($tkey eq chr(127)) {
				$input = substr($input, 0, length($input) - 1);
				print "\b" x (length($input) + 1);
				print " " x (length($input) + 1);
				print "\b" x (length($input) + 1);
				print $input;
			} elsif ("$input$tkey" =~ /^.* .*(\.{3,})$/) {
				$input = $input.$tkey;
				$input = dotsToPath($input);
				print "\n";
				printBeginning();
				print $input;
			} elsif ($input =~ $CLEAR) {
				system("clear");
				print "\n";
				printBeginning();
				$input = "";
			} else {
				$input .= $tkey;
				print $tkey;
			}
		}	
		chomp($input);
		last if $input eq "exit"; 
		if($input && $input ne $CLEAR && $input ne $ARROW_UP && $input ne ".." && $input !~ /\t/) {
			my ($prog, @params) = split(/\s+/, $input);
			no warnings;
			unless(grep($_ eq $prog, @allPrograms)) {
				$prog = spellcheck($prog);
			}
			use warnings;
			execute($prog, @params) if $prog;
		} elsif ($input eq "..") {
			execute("cd", $input);
		}
	}
}

sub execute {
	my $prog = shift;
	my @params = @_;

	$programsAreRunning = 1;

	my $commandHistString = $prog." ".join(" ", @params);
	$commandHistString =~ s/(.*)(\[A)?/$1/g;
	push @commandHistory, $commandHistString;

	my $pid = fork;
	if ($pid == 0) {
		if(!$prog) {

		} elsif($prog eq "cd") {
			if(!defined($params[0])) { 
				my $homePath = qx(echo \$HOME);
				chomp($homePath);
				$homePath .= "/";
				push @folder_history, $homePath if $folder_history[$#folder_history] ne $homePath;
				chdir($homePath);
			} elsif (-d $params[0]) {
				chdir($params[0]);
				push @folder_history, cwd() if $folder_history[$#folder_history] ne cwd();
			} elsif ($params[0] =~ /^-([0-9]*)/) {
				my $prevnr = $1 ? $1 : 0;
				my $prev = $folder_history[$#folder_history - $prevnr - 1];
				if($prev && -d $prev) {
					chdir($prev);
				}
			} elsif ($params[0] =~ /^\.{3,}$/) {
				my $backPath = dotsToPath($params[0]);
				chdir($backPath);
			} else {
				print color("red"), "Der Ordner $params[0] existiert nicht...\n", color("reset");
			}
		} elsif ($prog eq "mkdir") {
			foreach (@params) {
				mkdir($_);
			}
		} elsif ($prog eq "ver") {
			print	color("red"), "P",color("reset"), "erl-", 
				color("red"), "R",color("reset"), "unning, ",
				color("red"), "I",color("reset"), "nstable ",
				color("red"), "M",color("reset"), "inimal-",
				color("red"), "I",color("reset"), "ntelligence",
				color("red"), "-Shell\n", color("reset");
			print color("red"), "PRIMI", color("reset"), "-", color("red"), "Shell", color("reset")."\n";
			print "Version 1.0\n";
		} elsif ($prog eq "showhistory") {
			print join("\n", @folder_history);
			print "\n";
		} elsif ($prog eq "showshellpid") {
			print $$;
			print "\n";
		} elsif ($prog eq "shellperl") {
			eval join(" ", @params).";";
			if($@) {
				print "Fehler bei der Ausführung der shellperl-Befehle:\n$@\n";
			}
			print "\n";
		} else {
			if($prog eq "ls") {
				push @params, "--color";
			}
			exec $prog, @params;
		}
	} else {
		my $start = Time::HiRes::gettimeofday();
		wait;
		$programsAreRunning = 0;
		my $end = Time::HiRes::gettimeofday();
		print "\n";
		print "Fehlercode: $?\n" if $?;
		print color("white"), "Laufzeit: ".($end - $start)."\n", color("reset");
	}
}

sub cutPath {
	my $pwd = shift;

	my $pathLength = 30;

	if(length($pwd) > $pathLength) {
		my @folders = reverse split("/", $pwd);
		my @printFolders = ();
		my $l = 0;
		foreach (0 .. $#folders) {
			$l += length($folders[$_]);
			if($l < $pathLength) {
				push @printFolders, $folders[$_];
			}
		}
		$pwd = ".../".join("/", reverse @printFolders);
	}
	return $pwd;
}

sub completetion {
	my $prog = shift;
	my $prog_done = shift || 0;
	
	my @results = ();

	if($prog =~ /(.*)\t/ && !$prog_done) {
		my @programme = getFileList("program", ($1 ? $1 : undef));
		print "\n";
		@results = @programme;
	} elsif($prog =~ /^ls (.*)/) {
		print "\n";
		my @files = getFileList("dir", ($1 ? $1 : undef));
		@results = @files;
	} elsif ($prog =~ /^perl (.*)/) {
		print "\n";
		my @files = getFileList("file", ($1 ? $1 : undef), "pl");
		@results = @files;
	} elsif ($prog =~ /^cat (.*)/) {
		print "\n";
		my @files = getFileList("file", ($1 ? $1 : undef));
		@results = @files;
	} elsif ($prog =~ /^cd (.*)/) {
		print "\n";
		my @folders = ();
		@folders = getFileList("dir", ($1 ? $1 : undef));
		@results = @folders;
	} elsif ($prog =~ /^(cp|mv) (.*) (.*)/) {
		my @filesanddirs = getFileList("dirandfile", ($3 ? $3 : undef));
		print "\n";
	} elsif ($prog =~ /^(rm|cp|mv) (.*)/) {
		my @filesanddirs = getFileList("dirandfile", ($2 ? $2 : undef));
		print "\n";
	} elsif ($prog =~ /^rmdir (.*)/) {
		print "\n";
		my @filesanddirs = getFileList("dir", ($1 ? $1 : undef));
		@results = @filesanddirs;
	} elsif ($prog =~ /^sudo\s(.*)/) {
		my @programme = getFileList("program", ($1 ? $1 : undef));
		print "\n";
		@results = @programme;
	} elsif ($prog =~ /^(sudo )?apt-get install\s(.*)/) {
		my @programme = getFileList("apt", ($2 ? $2 : undef));
		print "\n";
		@results = map { "install $_" } @programme;
	} elsif ($prog =~ /^(sudo )?aptitude install\s(.*)/) {
		my @programme = getFileList("apt", ($2 ? $2 : undef));
		print "\n";
		@results = map { "install $_" } @programme;
	} elsif ($prog =~ /^(sudo )?aptitude remove\s(.*)/) {
		my @programme = getFileList("aptinstalled", ($2 ? $2 : undef));
		print "\n";
		@results = map { "remove $_" } @programme;
	} elsif ($prog =~ /^(sudo )?apt-get remove\s(.*)/) {
		my @programme = getFileList("aptinstalled", ($2 ? $2 : undef));
		print "\n";
		@results = map { "remove $_" } @programme;
	} elsif ($prog =~ /^(sudo )?aptitude purge\s(.*)/) {
		my @programme = getFileList("aptinstalled", ($2 ? $2 : undef));
		print "\n";
		@results = map { "purge $_" } @programme;
	} elsif ($prog =~ /^(sudo )?kill\s(.*)/) {
		my @programme = getFileList("psauxf", ($2 ? $2 : undef));
		print "\n";
		@results = map { "purge $_" } @programme;
	} elsif($prog =~ /(.+?)\s(.*)/) {
		my @files = getFileList("dirandfile", ($2 ? $2 : undef));
		print "\n";
		@results = @files;
	}
	print "\n";
	$prog =~ s/\t//g;

	return @results;
}

sub getFileList {
	my $type = shift;
	my $name_part = shift;
	my $ending = shift;

	$name_part =~ s/\t// if $name_part;

	my @list = ();
	my $path = cwd();

	my $go_back = "";

	if($name_part) {
		if($name_part =~ /\.\./ || $name_part =~ /^\//) {
			my $folder = "";
			foreach (split("", $name_part)) {
				if($_ eq "." || $_ eq "/") {
					$go_back .= $_ if $_;
				} else {
					$folder .= $_;
				}
			}
			$go_back =~ s/[^.]{1}\/$//;
			chdir($go_back);
			print color("bold green"), cwd(), color("reset"), "\n";
			$name_part = $folder;
		}
	}


	if($type eq "dir") {
		if($name_part) {
			@list = qx(ls -d -1 */ | sed -e 's/\\///' | grep '^$name_part');
		} else {
			@list = qx(ls -d -1 */ | sed -e 's/\\///');
		}
	} elsif ($type eq "file") {
		if(defined $name_part) {
			@list = qx(ls -1 | grep '^$name_part');
		} else {
			@list = qx(ls --color);
		}

		if($ending) {
			foreach (0 .. $#list) {
				delete $list[$_] if $list[$_] !~ /\.$ending$/;
			}
		}
	} elsif ($type eq "program") {
		foreach (@allPrograms) {
			if($name_part) {
				push @list, $_ if $_ =~ /^$name_part/;
			} else {
				@list = @allPrograms;
			}
		}
	} elsif ($type eq "dirandfile") {
		if($name_part) {
			if($ending) {
				push @list, getFileList("file", $name_part, $ending);
				push @list, getFileList("dir", $name_part, $ending);
			} else {
				push @list, getFileList("file", $name_part);
				push @list, getFileList("dir", $name_part);
			}
		} else {
			if($ending) {
				push @list, getFileList("file", undef, $ending);
				push @list, getFileList("dir", undef, $ending);
			} else {
				push @list, getFileList("file");
				push @list, getFileList("dir");
			}
		}
	} elsif($type eq "apt") {
		if($name_part) {
			push @list, qx(apt-cache pkgnames | grep '^$name_part');
		} else {
			push @list, qx(apt-cache pkgnames);
		}
	} elsif ($type eq "aptinstalled") {
		if($name_part) {
			push @list, qx(dpkg --list | awk '{print \$2}' | grep '^$name_part');
		} else {
			push @list, qx(dpkg --list | awk '{print \$2}');
		}
	} elsif ($type eq "psauxf") {
		if($name_part) {
			push @list, qx(ps auxf | awk '{print \$2 " " \$11}' | grep '$name_part');
		} else {
			push @list, qx(ps auxf | awk '{print \$2 " " \$11}');
		}
	}

	chdir($path);

	@list = deleteEmptyValues(@list);
	@list = map { my $x = $_; $x =~ s/(\t|\n)$//; $x } @list;

	if($go_back) {
		@list = map { my $x = $_; $x = "$go_back/$x"; $x } @list;
		@list = map { my $x = $_; $x =~ s/\/\//\//; $x } @list;
	}

	return @list;
}

sub printBeginning {
	print "[";
	if($userinfo[0] eq "root") {
		print color("bold red"), $userinfo[0], color("reset");
	} else {
		print color("bold cyan"), $userinfo[0], color("reset");
	}
	print color("blue"), "@", color("reset");
	print color("yellow"), hostname(), color("reset");
	print ":";
	print color("bold bright_green"), cutPath(cwd), color("reset");
	print "] ";
}

sub getAllPrograms {
	my $pathString = qx(echo \$PATH);
	my @paths = split(":", $pathString);

	foreach my $p (@paths) {
		no warnings;
		next unless -d $p;
		use warnings;
		push @allPrograms, map { $_ =~ s/\n$//; $_; } qx(ls $p);
	}
}

sub spellcheck {
	my $progname = shift;
	return unless $progname;
	return if $progname =~ /\Q$ARROW_UP\E/;
	return if $progname =~ /\Q$BACKSPACE\E/;
	return if $progname !~ /[a-z0-9]/i;

	my %check = ();
	foreach (@allPrograms) {
		$check{$_} = levenshtein($_, $progname);
	}

	my $i = 1;

	print "Das Programm `$progname` wurde nicht gefunden. Meintest du..?\n";
	my @vorschlaege = sort { $check{$a} <=> $check{$b} || $a cmp $b } keys %check;
	my $returnThis = cycleThrough($progname, [], "", @vorschlaege[0 .. 10], "Keinen davon!");

	return ($returnThis eq "Keinen davon!" ? undef : $returnThis);
}

sub levenshtein {
	my ($s1, $s2) = @_;
	my ($len1, $len2) = (length $s1, length $s2);

	return $len2 if ($len1 == 0);
	return $len1 if ($len2 == 0);

	my %mat;

	for (my $i = 0; $i <= $len1; ++$i) {
		for (my $j = 0; $j <= $len2; ++$j) {
			$mat{$i}{$j} = 0;
			$mat{0}{$j} = $j;
		}

		$mat{$i}{0} = $i;
	}

	my @ar1 = split(//, $s1);
	my @ar2 = split(//, $s2);

	for (my $i = 1; $i <= $len1; ++$i) {
		for (my $j = 1; $j <= $len2; ++$j) {
			my $cost = ($ar1[$i-1] eq $ar2[$j-1]) ? 0 : 1;
			$mat{$i}{$j} = min([$mat{$i-1}{$j} + 1, $mat{$i}{$j-1} + 1, $mat{$i-1}{$j-1} + $cost]);
		}
	}

	return $mat{$len1}{$len2};
}

sub min {
	my @list = @{$_[0]};
	my $min = $list[0];

	foreach my $i (@list) {
		$min = $i if ($i < $min);
	}

	return $min;
}


sub printNice {
	my @elements = @_;

	my $maxLength = 0;

	foreach (@elements) {
		$maxLength = length($_) if length($_) > $maxLength;
	}

	my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();

	my $le = 0;
	foreach (@elements) {
		my $str = $_.(" " x (($maxLength - length($_)) + 5));
		$le += length($str);
		if($le > int($wchar / 1.5)) {
			print "\n";
			$le = 0;
		}
		print $str;
	}
}

sub dotsToPath {
	my $dots = shift;
	$dots =~ s/\.\.\./..\//g;
	return $dots;
}

sub removeDoubleElementsFromArray {
	no warnings;
	my %h = map { $_ => 1 } @_;
	use warnings;
	return keys %h;
}

sub deleteEmptyValues {
	my @z = removeDoubleElementsFromArray(@_);
	my @l;

	foreach (0 .. $#z) {
		push @l, $z[$_] if $z[$_];
	}

	return @l;
}

sub cycleThrough {
	my ($prog, $befehleref, $beginning) = (shift, shift, shift);
	my @el = @_;
	return $el[0] if $#el == 0;
	return undef if $#el == -1;

	@el = grep($_ =~ /^$beginning/, @el);

	my $w = 0;
	my $str = "";

	print $str;
	my $choice = -1;
	ReadMode('cbreak');
	my $key = "";
	do {
		unless($choice == -1) {
			$key = ReadKey(0) ;
		}
		$choice = 0 if $choice == -1;
		my $intstr = "";
		if($key eq "\t" || $key eq "") {
			foreach (0 .. $#el) {
				if($choice eq $_) {
					$intstr .= color("on_green black").$el[$_].color("reset")."\t";
				} else {
					$intstr .= "$el[$_]\t";
				}
			}
			$choice++;
			$choice = 0 if $choice > $#el;
		}
		print "\e[1K\r";
		print $intstr;
	} while ($key ne "\n");
	ReadMode 'normal';
	my $ch = $el[$choice - 1];
	$ch =~ s/ /\ /g;
	return ($ch ? $ch : undef);
}
