=head1 NAME

Mj::MTAConfig.pm - Mailer configuration routines for Majordomo

=head1 SYNOPSIS

blah

=head1 DESCRIPTION

This module contains functions which deal with MTA-specific configuration
issues.  Support of as many MTAs as possible is an important goal of the
Majordomo project.

There is an entry point per supported MTA which should return a string
containing information that will be sent to the responsible parties.
Future plans call for including the ability to have these functions
actually do some or all of the required configuration.

=cut

package Mj::MTAConfig;
use Mj::Log;
use strict;
use vars (qw(%sendsep %supported));

%sendsep = (
	    sendmail => '+'
	   );

%supported = (
	      'sendmail' => 'sendmail',
	     );

=head2 sendmail

This produces a block of aliases suitable for cut and paste into a sendmail
aliases file, along with a bit of explanation.

Things we need:

  owner  => name of list owner
  list   => name of list (no list -> produce global aliases)
  bindir => path to executables
  domain => domain this list or majordomo is to serve

=cut
sub sendmail {
  my $log  = new Log::In 150;
  my %args = @_;

  my $bin  = $args{'bindir'} || $log->abort("bindir not specified");
  my $dom  = $args{'domain'} || $log->abort("domain not specified");
  my $own  = $args{'owner'}  || $log->abort("owner not specified");
  my $list = $args{'list'}   || 'GLOBAL';

  my $head = <<EOS;
Please add the following lines to your aliases file, if they are not
already present.  You may have to run the "newaliases" command afterwards
to enable these aliases.
EOS

  if ($list eq 'GLOBAL') {
    return ($head, qq(# Aliases for Majordomo
majordomo:       "|$bin/mj_email -d $dom"
owner-majordomo: $own,
majordomo-owner: $own,
# End aliases for Majordomo
));
  }
  else {
    return ($head, qq(# Aliases for $list
$list:         "|$bin/mj_resend -d $dom -l $list"
$list-request: "|$bin/mj_email  -d $dom -l $list"
$list-owner:   $own,
owner-$list:   $own,
# End aliases for $list
));
  }
}

=head1 COPYRIGHT

Copyright (c) 1997, 1998 Jason Tibbitts for The Majordomo Development
Group.  All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the license detailed in the LICENSE file of the
Majordomo2 distribution.

his program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the Majordomo2 LICENSE file for more
detailed information.

=cut

1;
#
### Local Variables: ***
### mode:cperl ***
### cperl-indent-level:2 ***
### End: ***
