=head1 NAME

Mj::Resend - filtering and transformation functions for Majordomo

=head1 SYNOPSIS

  $mj->resend($list, $file);

=head1 DESCRIPTION

This performs two important functions: filtering (including MIME
transformation), and delivery.  Incoming messages are filtered by checking
headers and body against various regular expressions.  Then the message is
decomposed into MIME parts and the various parts are transformed, decoded,
saved, and deleted according to a configuration table.  Messages which fail
the various filters are sent of for approval.  The transformed versions of
messages which pass are delivered to the various recipients who receive
each message.  The message is also passed on for archiving and
digestifying.

Future cool things to investigate include: users who do not receive
their own messages.  (I implemented everything else on my list.)

Order of operation:

 Pull in message, parse into MIME entities and header [1]
 Check for approval.
 Apply admin_headers and taboo_headers.
 Apply admin_body to first n lines of first text part.
 Apply taboo_body to all text parts.  (What is a text part?)
 Find "illegal" MIME parts.
 *** Bounce now if necessary ***
 Strip out approvals to get the real article; parse it if necessary
 Make two copies of the entity
 Convert or drop MIME parts for list and archive/digest
 Deposit in archive.
 Strip unwanted headers from list, archive/digest.
 Add headers, fronter and footer [3] to outgoing copy.
 Compose final message.
 Pass to digest.
 Deliver.

1. MIME parsing automatically handles QP and base64 decoding (and
   some other weird ones, like x-gzip64).

2. There are six supported approval methods.  Briefly:
     Approved: in the header
     Single-part messages:
       Approved: as first non-blank line of the body, followed by a
         blank line and the body.
       Approved: as first non-blank line of the body, followed by a
         complete message including headers and body.
     Multipart messages:
       Approved: as first non-blank line of the preamble.
       Approved: as first non-blank of first body part.
       Approved: as first non-blank line of the first body part of a
         multipart message with exactly two parts, the second of which
         is of ty0e message/rfc822 and contains the complete message
         to be sent to the list.
   There is also the post command, which allows out-of-band approval,
   and the normal token-based approval method.

3. Fronter and footer get separate MIME parts when configured to do so, and
   always for Multipart messages.  This is to prevent non-MIME messages
   from being gratuitously turned into MIME messages.  Non-MIME messages
   will not generally be hurt by adding fronters and footers right into the
   body, but this should be configurable.  The mangling of true MIME
   messages should not be allowed to occur.

Note that the bodyhandles get opened and closed and things are copied
more than once in some cases.  This is inefficient, but is also
conceptually easy to deal with and relatively easy to maintain and
extend.  Eventually this should all be restructured to recurse down
the MIME tree once, doing what ever is required, and to open the body
exactly once, doing all the copying and checksumming that is required.

=cut

package Mj::Resend;
use Mj::Log;
use IO::File;
use strict;

use vars qw($line $text $type);

use AutoLoader 'AUTOLOAD';
1;
__END__

use Mj::MIMEParser;
use File::Copy 'mv';
sub post {
  my($self, $user, $passwd, $auth, $int, $cmd, $mode, $list, $file) = @_;
  my ($owner,                # The list owner address
      $token,                # Token lifted from approval check, to be deleted
      $parser,               # MIME::Parser
      $tmpdir,               # duh
      $fh,                   # File handle to parse from
      $ent,                  # Parsed entity
      $head,                 # Message headers
      $thead,                # Temporary copy of message headers
      $avars,                # Hashref containing access variables
      $reasons,              # Listref containing bounce reasons
      $ok,
      $nent,
      $mess, 
      $desc,
      $c_type,
      $c_t_encoding,
      $approved,             # Is the message approved?
      $fileinfo,             # Info from list_file_get
      $subs,                 # Hash of substitutions
      $ack_attach,           # Should acks attach the message (fron config)
      $spool,                # File to spool 
      $subject,              # Header 
      $date,                 # Header
     );
  my $log = new Log::In 30, "$list, $user, $file"; 
  $tmpdir = $self->_global_config_get("tmpdir");

  $parser = new Mj::MIMEParser;
  $parser->output_to_core($self->_global_config_get("max_in_core"));
  $parser->output_dir($tmpdir);
  $parser->output_prefix("mjr");
  
  $fh = new IO::File "<$file";
  $ent = $parser->read($fh);
  # If perl is configured without Config{'d_flock'}, this close call
  # will cause the lock on the queue file to be dropped, creating
  # a race condition.  Do not call close() explicitly.
  # $fh->close;

  # Fail gracefully: 
  if (! $ent) {
    $spool = "$tmpdir/unparsed." . Majordomo::unique();
    mv ($file, $spool);
    $self->inform("GLOBAL", "post", $user, $user, $cmd, "resend",
        0, 0, -1, "Unable to parse message; moved to $spool.");
    return (0, "Unable to parse message.");
  }

  # Get the header.
  $::log->in(80, undef, "info", "Parsing the header");
  $head = $ent->head;
  $head->modify(0);
  
  # Make a copy that we can mess with.
  $thead = $head->dup;
  $thead->decode;
  $thead->unfold;
  $::log->out;
  
  # Snarf user from headers XXX Is this really the victim?  The user
  # is the one who made the command happen; that may be unset if
  # called from mj_resend but will exist if calling from the post
  # command.
  chomp($user = $thead->get('from') ||
	$thead->get('apparently-from'));

  if (! $user) {
    $spool = "$tmpdir/unparsed." . Majordomo::unique();
    mv ($file, $spool);
    $self->inform("GLOBAL", "post", $user, $user, $cmd, "resend",
        0, 0, -1, "Unable to determine sender; moved to $spool.");
    return (0, "Unable to parse message.");
  }

  $user = new Mj::Addr($user);
  $reasons = []; $avars = {};

  # XXX Pass in the password we were called with, so that passwords
  # can be passed out-of-band.
  ($ok, $passwd, $token) =
    $self->_check_approval($list, $thead, $ent, $user);
  $approved = ($ok>0) && $passwd;

  unless ($ok) {
    $avars->{bad_approval} = "Invalid Approve Header";
    push @$reasons, "Invalid Approve Header";
  }

  # Check poster
  $self->_check_poster($list, $user, $reasons, $avars);

  # Check header
  $self->_check_header($list, $thead, $reasons, $avars);

  # Recursively check bodies
  $self->_check_body($list, $ent, $reasons, $avars);

  # Construct some aggregate variables;
  $avars->{dup} = $avars->{dup_msg_id} || $avars->{dup_checksum} ||
    $avars->{dup_partial_checksum} || '';
  $avars->{mime} = $avars->{mime_consult} || $avars->{mime_deny} || '';
  $avars->{any} = $avars->{dup} || $avars->{mime} || $avars->{taboo} ||
    $avars->{admin} || $avars->{bad_approval} || '';

  # Bounce if necessary: concatenate all possible reasons with \002, call
  # access_check with filename as arg1 and reasons as arg2.  XXX Victim
  # here should be the user in the headers; requester should be the user
  # making the request.  We should only regenerate user if it is not set.
  # This adds a modicum of security to the post command.
  if ($approved) {
    $ok = 1;
  }
  else {
    # Generate a spool filename, just in case we have to stash the message.
    # Just call t_gen and make sure the file doesn't exist
    while (1) {
      $spool = $self->t_gen;
      last unless -f "$self->{ldir}/GLOBAL/spool/$spool";
    }
    mv($file, "$self->{'ldir'}/GLOBAL/spool/$spool");
    $file = "$self->{'ldir'}/GLOBAL/spool/$spool";

    ($ok, $mess, $fileinfo) =
      $self->list_access_check
	($passwd, undef, $int, $mode, $cmd, $list, "post", $user, '',
	 $file, join("\002", @$reasons), join("\002", %$avars), %$avars);
  }

  $owner = $self->_list_config_get($list, 'sender');
  if ($ok > 0) {
    return $self->_post($list, $user, $user, $mode, $cmd,
			$file, '', join("\002", %$avars), $ent);
  }

  # Some substitutions will be done by the access routine, but we have
  # extensive information about the message here so we can do some more.
  $subs = {LIST     => $list,
	   HEADERS  => $ent->head->stringify,
	   SUBJECT  => ($ent->head->get('subject') || '(none)'),
	   VERSION  => $Majordomo::VERSION,
	   MJ       => $self->_global_config_get('whoami'),
	   MJOWNER  => $self->_global_config_get('sender'),
	   SITE     => $self->_global_config_get('site_name'),
	   WHEREAMI => $self->_global_config_get('whereami'),
	  };

  $desc = $fileinfo->{description};
  if ($desc) {
    $desc = $self->substitute_vars_string($desc, $subs);
  }
  $ack_attach = $self->_list_config_get($list, 'ack_attach_original');
  chomp($date = $thead->get('date')); 
  chomp($subject = ($thead->get('subject')|| '')); 

  # We handled the OK case, so we have either a stall or a denial.
  # If we got an empty return message, this is a signal not to ack anything
  # and so we just return;
  $rtnhdr = $user->full;
  return ($ok, $rtnhdr) 
    unless defined $mess && length $mess;

  # Otherwise, decide what to ack
  # Stall:  ack if flags say so
  # Denial: ack if flags say so or if ack_denials_always is set
  if ($self->{'lists'}{$list}->flag_set('ackimportant', $user)
      ||
      $self->{'lists'}{$list}->flag_set('ackall', $user)
      ||
      ($ok == 0 && $self->_list_config_get($list, 'ack_denials_always'))
     )
    {
      $nent = build MIME::Entity
	(
	 Data        => [ $mess ],
	 Type        => $fileinfo->{'c-type'},
	 Encoding    => $fileinfo->{'c-t-encoding'},
	 Charset     => $fileinfo->{'charset'},
	 Filename    => undef,
	 -From       => $owner,
	 -To         => "$user", # Note stringification
	 -Subject    => $desc,
	 'Content-Language:' => $fileinfo->{'language'},
	);

      if (($ok <  0 && $ack_attach->{stall}) ||
	  ($ok == 0 && $ack_attach->{fail})  ||
	  ($ok <= 0 && $ack_attach->{all}))
      {
        $nent->make_multipart;
        $nent->attach(Type        => 'message/rfc822',
                      Description => 'Original message',
                      Path        => $file,
                      Filename    => undef,
                     );
      }
      $self->mail_entity($owner, $nent, $user);
    }

  # If the request failed, we need to unlink the file.
  if (!$ok) {
    unlink $file;
  }

  # Clean up after ourselves;
  $nent->purge if $nent;
  $ent->purge;
  ($ok, $rtnhdr);
}

=head2 post_start, post_chunk, post_done

These provide an iterative interface to the post function, so that it can
be used from the command interfaces and from a network source.

There is no access checking here, because that happens once the
to-be-posted message is parsed.  It may be useful to place some
restrictions here, because it makes forging messages even more trivial,
since the message doesn''t actually have to pass through the mail system.
Hmmm.

=cut
sub post_start  {
  my ($self, $user, $passwd, $auth, $interface, $cmdline, $mode,
      $list) = @_;
  my $log  = new Log::In 30, "$list";

  my $tmp  = $self->_global_config_get('tmpdir');
  my $file = "$tmp/post." . Majordomo::unique();
  $self->{'post_file'} = $file;
  $self->{'post_fh'} = new IO::File ">$file" or
    $log->abort("Can't open $file, $!");

  1;
}

sub post_chunk {
  my ($self, $user, $passwd, $auth, $interface, $cmdline, $mode,
      $list, $vict, $data) = @_;
  $self->{'post_fh'}->print($data);
}

sub post_done {
  my ($self, $user, $passwd, $auth, $interface, $cmdline, $mode,
      $list) = @_;
  my $log  = new Log::In 30;
  my ($ok, $mess);

  $self->{'post_fh'}->close;

  ($ok, $mess) =
    $self->post($user, $passwd, $auth, $interface, $cmdline, $mode,
	      $list, $self->{'post_file'});

  unlink $self->{'post_file'};
  undef $self->{'post_fh'};
  undef $self->{'post_file'};

  ($ok, $mess);
}

use Mj::MIMEParser;
sub _post {
  my($self, $list, $user, $victim, $mode, $cmdline, $file, $arg2,
     $avars, $ent) = @_;
  my $log  = new Log::In 35, "$list, $user, $file";

  my(%avars, %deliveries, %digest, @dfiles, @dtypes, @ent, @files, @refs,
     @tmp, @skip, $arcdata, $arcent, $archead, $digests, $dissues, $rtnhdr,
     $exclude, $head, $i, $j, $msgnum, $precedence, $prefix, $replyto,
     $sender, $seqno, $subject, $date, $subs, $tmp, $tmpdir, $tprefix, $whereami);

  $self->_make_list($list);
  $tmpdir   = $self->_global_config_get('tmpdir');
  $whereami = $self->_global_config_get('whereami');
  $sender   = $self->_list_config_get($list, "sender");
  
  %avars = split("\002", $avars);

  # Atomically update the sequence number
  $self->_list_config_lock($list);
  $seqno  = $self->_list_config_get($list, 'sequence_number');
  $self->_list_config_set($list, 'sequence_number', $seqno+1);
  $self->_list_config_unlock($list);
  $log->message(35,'info',"Sending message $seqno");
  $self->{sessionfh}->print("Post: sequence #$seqno.\n");

  # trick: we take a pre-parsed entity as an extra argument; if it's
  # defined, we can skip the parse step.  Note that after this, $file will
  # refer to the source message file regardless of whether it was spooled
  # or not.
  if ($ent) {
    $ent[0] = $ent;
  }
  else {
    if (!open SPOOL, "<$file") {
      # The spool file, containing the message to be posted, is missing.
      # Inform the site owner, and return.
      $self->inform("GLOBAL", "post", $user, $victim, $cmdline, "resend", 
        0, 0, -1, "Spool file $file is missing; unable to post message."); 
      return (0, "The message was not delivered, due to a malfunction.\n");
    }
    my $mime_parser = new Mj::MIMEParser;
    $mime_parser->output_to_core($self->_global_config_get("max_in_core"));
    $mime_parser->output_dir($tmpdir);
    $mime_parser->output_prefix("mjr");
    $ent[0] = $mime_parser->read(\*SPOOL);
  }

  # Trim off approvals, get back a new entity
  $ent[0] = $self->_trim_approved($ent[0]);
  $head = $ent[0]->head;
  $head->modify(0);

  # Make duplicate archive/digest entity
  $arcent = $ent[0]->dup;
  $archead = $arcent->head;
  $archead->modify(0);
  $rtnhdr = $user->full;

  # Convert/drop MIME parts.  Bill?
  
  # Remove skippable headers, including Approved:.
  @skip = ('Approved');
  push @skip, $self->_list_config_get($list, 'delete_headers');
  push @skip, 'Received' if $self->_list_config_get($list, 'purge_received');
  for $i (@skip) {
    $head->delete($i);
    $archead->delete($i);
  }

  # Pass to archiver; first extract all references
  $tmp = $archead->get('references') || '';
  while ($tmp =~ s/<([^>]*)>//) {
    push @refs, $1;
  }
  $tmp = $archead->get('in-reply-to') || '';
  while ($tmp =~ s/<([^>]*)>//) {
    push @refs, $1;
  }

  # Strip the subject prefix from the archive copy.  Note that this
  # function can have odd side effects because it plays with the entities,
  # so we re-extract $archead at this point.
  (undef, $arcent) = $self->_munge_subject($arcent, $list, $seqno);
  $archead = $arcent->head;

  # Pass to archive.  XXX Is $user good enough, or should we re-extract?
  $subject = $archead->get('subject') || ''; chomp $subject;
  $date = $archead->get('date') || ''; chomp $date;
  ($msgnum) = $self->{'lists'}{$list}->archive_add_start
    ($sender,
     {
      'body_lines' => $avars{lines},
      'from'       => "$user", # Stringify on purpose
      'quoted'     => $avars{quoted_lines},
      'refs'       => join("\002",@refs),
      'subject'    => $subject,
      'bytes'      => (stat($file))[7],
     },
    );

  # Only call this if we got back a message number because there isn't an
  # archive around if we didn't.
  if ($msgnum) {
    $archead->replace('X-Archive-Number', $msgnum);

    # Print out the archive copy
    $tmp = "$tmpdir/mjr.$$.arc";
    open FINAL, ">$tmp" ||
      $::log->abort("Couldn't open archive output file, $!");
    $arcent->print(\*FINAL);
    close FINAL;

    ($msgnum, $arcdata) = $self->{'lists'}{$list}->archive_add_done($tmp);

    unlink "$tmp";
  }

  if ($mode ne "archive") {
    # Cook up a substitution hash
    $subs = {
         LIST     => $list,
         VERSION  => $Majordomo::VERSION,
         SENDER   => "$user",
         USER     => "$user",
         SEQNO    => $seqno,
         ARCHIVE  => $msgnum,
         SUBJECT  => $subject,
         WHEREAMI => $whereami,
         MJ       => $self->_global_config_get('whoami'),
         MJOWNER  => $self->_global_config_get('sender'),
         SITE     => $self->_global_config_get('site_name'),
        };

    # Add headers
    for $i ($self->_list_config_get($list, 'message_headers')) {
      $i = $self->substitute_vars_string($i, $subs);
      $head->add(undef, $i);
    }
    if ($precedence = $self->_list_config_get($list, 'precedence')) {
      $head->add('Precedence', $precedence);
    }
    $head->add('Sender', $sender);

    # Add list-headers standard headers

    # Add fronter and footer.
    $self->_add_fters($ent[0], $list, $subs);

    # Hack up the From: and CC: headers
    $self->_munge_from($ent[0], $list);

    # Add in subject prefix
    ($ent[0], $ent[1]) = $self->_munge_subject($ent[0], $list, $seqno);

    # Add in Reply-To:
    $ent[2] = $self->_reply_to($ent[0]->dup, $list, $seqno, $user);
    $ent[3] = $self->_reply_to($ent[1]->dup, $list, $seqno, $user);

    # Generate the exclude list
    $exclude = $self->_exclude($ent[0], $list, $user);

    # Print delivery messages to files
    for ($i = 0; $i < @ent; $i++) {
      $files[$i] = "$tmpdir/mjr.$$.final$i";
      open FINAL, ">$files[$i]" ||
        $::log->abort("Couldn't open final output file, $!");
      $ent[$i]->print(\*FINAL);
      close FINAL;
    }

    # These are the deliveries we always make.  If pushing digests, we'll add
    # those later.
    %deliveries =
      ('each-prefix-noreplyto' =>
       {
        exclude => $exclude,
        file    => $files[0],
       },
       'each-noprefix-noreplyto' =>
       {
        exclude => $exclude,
        file    => $files[1],
       },
       'each-prefix-replyto' =>
       {
        exclude => $exclude,
        file    => $files[2],
       },
       'each-noprefix-replyto' =>
       {
        exclude => $exclude,
        file    => $files[3],
       }
      );

    # Build digests if we have a message number from the archives
    # (%deliveries is modified)
    if ($msgnum) {
      $self->do_digests('list'      => $list,     'deliveries' => \%deliveries,
                'substitute'=> $subs,     'msgnum'     => $msgnum,
                'arcdata'   => $arcdata,  'sender'     => $sender,
                'whereami'  => $whereami, 'tmpdir'     => $tmpdir,
                'headers'   => [['Predecence', $precedence]],
                # 'run' => 0, 'force' => 0,
               );
    }

    # Invoke delivery routine
    $self->deliver($list, $sender, $seqno, \%deliveries);

    # Inform sender of successful delivery
    
    # Clean up and say goodbye
    for $i (keys %deliveries) {
      unlink $deliveries{$i}{file}
        if $deliveries{$i}{file};
    }
  }  
  for ($i = 0; $i < @ent; $i++) {
    $ent[$i]->purge;
  }
  $arcent->purge;

  # We're done with the file by this point, so we should remove it.
  # This step must be done last: if _post is called by Mj::Token::t_accept,
  # and the program aborts between the deletion of the file
  # and the removal of the token, we will have a request in the 
  # queue for a token with no associated spool file. 
  unlink $file;

  (1, $rtnhdr);
}

=head2 _check_approval(list, head, entity, user)

This takes a ref to a MIME::Entity and checks to see if it is approved by
one of several methods:

  In header 
  First line of preamble
  First line of first part
  First line of body
  First line of first part followed by a message/rfc822 attachment.

Head should be a copy of the message header, already decoded and unfolded.

Return flag, password, token. 

The password is validated and the token unspooled if they are given.

Note that this routine doesn''t do any processing on the message;
specifically, it does not remove any Approved: lines or extract any
embedded messages.  This is done in the bottom half of the post
function.

=cut
use Mj::Token;
sub _check_approval {
  my $self = shift;
  my $list = shift;
  my $head = shift;
  my $ent  = shift;
  my $user = shift;
  my $log  = new Log::In 40;
  my ($body, $fh, $i, $line, $part, $passwd, $pre, $token);

  $pre = $ent->preamble;

  # Approved: header; the header will be deleted later, but we leave
  # it in because if it's wrong we want to bounce with it in.
  if ($head->count('approved')) {
    $line = $head->get('approved');
    chomp $line;
    ($passwd, $token) = split('\s*,\s*', $line);
  }
  
  # Check that we have a preamble and that it contains something that
  # looks like Approved: password, token in the first few lines
  elsif ($pre) {
    for $i (0..3) {
      if ($$pre[$i] && $$pre[$i] =~ /Approved:\s*([^\s,]+)\s*,?\s*(.*)\s*/i) {
	($passwd, $token) = ($1, $2);
	last;
      }
    }
  }

  # Check in the body
  unless ($password) {
    # If multipart, grab first part.  Cope with nested multipart messages.
    $part = $ent;
    while (defined $part->parts(0)) {
      last if $part->bodyhandle;
      $part = $part->parts(0);
    }
   
    return unless $part->bodyhandle; 
    # Check in first few of lines of that entity; skip blank lines but
    # stop as soon as we see any text
    $fh = $part->bodyhandle->open('r');
    return unless $fh;
    while (defined ($line = $fh->getline)) {
      last if $line =~ /\S/;
    }
    if (defined($line) && $line =~ /Approved:\s*([^\s,]+)\s*,?\s*(.*)\s*/i) {
      ($passwd, $token) = ($1, $2);
    }
  }
  
  # Now check validity of the password and existance of the token if
  # provided; unspool the token if it exists.  (If it doesn't, just
  # ignore it.  The password must be good, though.)
  if ($passwd) {
    return
      unless $self->validate_passwd($user, $passwd, undef,
				    'resend', $list, 'post') > 0;
  }
  
  if ($token) {
    $token = undef unless $self->t_remove($token);
  }

  return (1, $passwd, $token);
}

=head2 _check_poster(list, head, reasons, avars)

This computes various pieces of data about the poster:

  days since the user subscribed

=cut
sub _check_poster {
  my $self    = shift;
  my $list    = shift;
  my $user    = shift; # Already in an Mj::Addr object
  my $reasons = shift;
  my $avars   = shift;
  my $log     = new Log::In 40, "$user";

  # Grab the list data
  my $data = $self->{'lists'}{$list}->is_subscriber($user);

  # If not a subscriber...
  unless ($data) {
    $avars->{days_since_subscribe} = -1;
    return;
  }
  
  # Extract subscribe date
  $avars->{days_since_subscribe} 
    = (time - $data->{subtime})/86400;
}

=head2 _check_header(list, head)

This investigates all header improprieties.

=cut
sub _check_header {
  my $self    = shift;
  my $list    = shift;
  my $head    = shift;
  my $reasons = shift;
  my $avars   = shift;
  my $log     = new Log::In 40;
  my ($data, $id, $maxhdrl, $maxthdr, $msg);
  
  $self->_make_list($list);

  # Check for duplicate message ID
  chomp($id = $head->get('Message-ID') || '(none)');
  if ($data = $self->{'lists'}{$list}->check_dup($id, 'id')) {
    $msg = "Duplicate Message-ID - $id (".localtime($data->{changetime}).")";
    push @$reasons, $msg;
    $avars->{dup_msg_id} = $msg;
  }

  # Taboo check the header; this also computes the header size since it
  # iterates over the whole thing.
  $self->_ck_theader($list, $head, $reasons, $avars);

  # Comb the Received: headers for IP addresses to RBL.
  # Make sure we have a subject
  # Make sure the list shows up somewhere in To: or CC:.

  # Check size of header
  $maxhdrl = $self->_list_config_get($list, 'max_header_line_length');
  if ($maxhdrl && $maxhdrl <= $avars->{max_header_length}) {
    push @$reasons, "A header line is too long ($avars->{max_header_length} > $maxhdrl)";
    $avars->{max_header_length_exceeded} = 1;
  }
  $maxthdr = $self->_list_config_get($list, 'max_total_header_length');
  if ($maxthdr && $maxthdr <= $avars->{total_header_length}) {
    push @$reasons, "The header is too large ($avars->{total_header_length} > $maxthdr)";
    $avars->{total_header_length_exceeded} = 1;
  }
  
  # Run user-supplied procedures to check the headers.
}

=head2 _check_body

This investigates a body part for improprieties.  Builds all preliminary
code and data, then calls _r_ck_body to do the dirty work, then builds any
bounce reasons due to missed inverted matches.

=cut
use Safe;
sub _check_body {
  my $self    = shift;
  my $list    = shift;
  my $ent     = shift;
  my $reasons = shift;
  my $avars   = shift;
  my $log     = new Log::In 150;
  my (@inv, $class, $data, $i, $inv, $j, $l, $max, $maxbody, $maxlen, 
      $mcode, $qreg, $rule, $safe, $sev, $tcode, $var);
  $inv = {}; $mcode = {}; $tcode = {};

  # Extract the code from the config variables XXX Move to separate func
  for $i ('GLOBAL', $list) {
    for $j ('admin_body', 'taboo_body') {
      $data = $self->_list_config_get($i, $j);
      push @inv, @{$data->{'inv'}};
      $tcode->{$i}{$j} = $data->{'code'};

      # Sigh.  max = 0 means unlimited, so we must preserve it
      if ($data->{'max'} == 0 ||
	  !defined($max) ||
	  ($data->{'max'} > $max && $data->{'max'} > 0))
	{
	  $max = $data->{'max'};
	}
    }
  }
  # Build a hash for fast lookup
  for $i (@inv) {
    $inv->{$i} = $i;
  }

  $i      = $self->_list_config_get($list, 'attachment_rules');
  $mcode  = $i->{check_code};
  $qreg   = $self->_list_config_get($list, 'quote_pattern');
  $maxlen = $self->_list_config_get($list, 'max_mime_header_length');

  # Create a Safe comaprtment
  $safe = new Safe;
  $safe->permit_only(qw(aassign const le leaveeval null padany push
			pushmark return rv2sv stub));

  # Recursively check the body
  $avars->{'mime_header_length'} = 0;
  $self->_r_ck_body($list, $ent, $reasons, $avars, $safe, $qreg, $mcode, 
            $tcode, $inv, $max, , $maxlen, 'toplevel', 1);

  $maxbody = $self->_list_config_get($list, 'maxlength');
  if ($maxbody && $maxbody < $avars->{'body_length'}) {
    push @$reasons, "The message body is too long ($avars->{'body_length'} > $maxbody)";
    $avars->{'body_length_exceeded'} = 1;
  }
  # Now look at what's left in %$inv and build reasons from it
  for $i (keys %$inv) {
    ($l, $var, $rule, $sev, $class) = split('\t', $i);
    _describe_taboo($reasons, $avars, $list, $var, $rule, undef, undef,
		    $sev, $class, 1)
  }
}

use MD5;
sub _r_ck_body {
  my ($self, $list, $ent, $reasons, $avars, $safe, $qreg, $mcode, $tcode,
      $inv, $max, $maxlen, $part, $first) = @_;
  my $log  = new Log::In 150, "$part";
  my (@parts, $body, $data, $i, $line, $spart, $sum1, $sum2, $text);

  # If we have parts, we don't have any text so we process the parts and
  # exit.  Note that we try to preserve the $first setting down the chain
  # if appropriate.  We also construct an appropriate name for the part
  # we're processing.
  @parts = $ent->parts;
  if (@parts) {
    for ($i=0; $i<@parts; $i++) {
      if ($part eq 'toplevel') {
	$spart = "part ".($i+1);
      }
      else {
	$spart = "$part, subpart ".($i+1);
      }
      $self->_r_ck_body($list, $parts[$i], $reasons, $avars, $safe, $qreg,
			$mcode, $tcode, $inv, $max, $maxlen, $spart,
			($first && $i==0));
    }
    return;
  }

  # Now do some inits
  $sum1 = new MD5; $sum2 = new MD5;

  # Check MIME status and any other features of the entity as a whole
  _check_mime($reasons, $avars, $safe, $ent, $mcode, $maxlen, $part);

  # Now the meat.  Open the body
  $body = $ent->bodyhandle->open('r');
  $line = 1;

  # Iterate over the lines
  while (defined($text = $body->getline)) {
    # Call the taboo matcher on the line if we're not past the max line;
    # pay attention to $max == 0 case
    if (!$max || $line <= $max) {
      _ck_tbody_line($list, $reasons, $avars, $safe, $tcode, $inv, $line,
		     $text);
    }

    # Update checksum counters
    if ($first) {$sum1->add($text); $sum2->add($text) if $line <= 10;}    
    
    # Calculate a few message metrics
    $avars->{lines}++;
    $avars->{body_length} += length($text);
    $avars->{quoted_lines}++ if Majordomo::_re_match($qreg, $text);
    $line++;
  }

  # Do final calculations
  $avars->{quoted_lines} ||= 0; $avars->{lines} ||= 1;
  $avars->{percent_quoted} =
    int(100*($avars->{quoted_lines} / $avars->{lines}));

  if ($first) {
    $sum1 = $sum1->hexdigest;
    $avars->{checksum} = $sum1;
    if($data = $self->{'lists'}{$list}->check_dup($sum1, 'sum')) {
      push @$reasons,
      "Duplicate Message Checksum (".localtime($data->{changetime}).")";
      $avars->{dup_checksum} = 1;
    }
    $sum2 = $sum2->hexdigest;
    $avars->{partial_checksum} = $sum2;
    if($data = $self->{'lists'}{$list}->check_dup($sum2, 'partial')) {
      push @$reasons,
      "Duplicate Partial Message Checksum (".localtime($data->{changetime}).")";
      $avars->{dup_partial_checksum} = 1;
    }
  }
}

=head2 _ck_theader

This checks for taboo and admin headers, based upon the various
taboo_headers and admin_headers variables.

No returns; implicitly modifies the the list referenced by reasons and the
hash referenced by avars.

=cut
sub _ck_theader {
  my $self    = shift;
  my $list    = shift;
  my $head    = shift;
  my $reasons = shift;
  my $avars   = shift;
  my (%inv, @inv, @matches, $class, $code, $data, $i, $inv, $j, $k, $l,
      $match, $maxthdr, $maxhdrl, $rule, $safe, $sev);
  local ($text);

  $code = {};
  for $i ('GLOBAL', $list) {
    for $j ('admin_headers', 'taboo_headers') {
      $data = $self->_list_config_get($i, $j);
      push @inv, @{$data->{'inv'}};
      $code->{$j}{$i} = $data->{'code'};
    }
  }

  # Make a hash of these for fast lookup
  for $i (@inv) {
    $inv{$i} = $i;
  }

  # Set up the Safe compartment
  $safe = new Safe;
  $safe->permit_only(qw(aassign const leaveeval null padany push pushmark
			return rv2sv stub));
  $safe->share('$text');
  $avars->{total_header_length} = 0;
  $avars->{max_header_length}   = 0;
  
  # Process the header; mega-nesting!  Iterate over each tag present in the
  # header.
  for $i ($head->tags) {
    
    # Skip the mailbox separator, if we get one
    next if $i eq 'From ';
    
    # Grab all of the occurrences of that tag and iterate over them
    for $j ($head->get($i)) {
      chomp $j;
      $text = "$i: $j";

      # Check lengths
      $avars->{total_header_length}+= length($text)+1;
      $avars->{max_header_length}   = length($text)+1
	if $avars->{max_header_length} < length($text)+1;

      # Now run all of the taboo codes
      for $k ('GLOBAL', $list) {
	for $l ('admin_headers', 'taboo_headers') {
	  
	  # Eval the code
	  @matches = $safe->reval($code->{$l}{$k});
	  warn $@ if $@;
	  
	  # Run over the matches that resulted
	  while (($rule, $match, $sev, $class, $inv) = splice(@matches, 0, 5)) {
	    
	    # An inverted match; remove it from the list
	    if ($inv) {
	      delete $inv{"$k\t$l\t$rule\t$sev\t$class"};
	    }
	    else {
	      _describe_taboo($reasons, $avars, $k, $l, $rule, $match,
			      undef, $sev, $class, $inv);
	    }
	  }
	}
      }
    }
  }
  # Now complain about missed inverted matches
  for $i (keys %inv) {
    ($k, $l, $rule, $sev, $class) = split('\t', $i);
    _describe_taboo($reasons, $avars, $k, $l, $rule, undef, undef, $sev,
		    $class, 1)
  }
}

=head2 _ck_tbody_line

This checks a line from the message against the prebuilt taboo code from
the config file.

=cut
sub _ck_tbody_line {
  my $list    = shift;
  my $reasons = shift;
  my $avars   = shift;
  my $safe    = shift;
  my $code    = shift;
  my $inv     = shift;
  local $line = shift;
  local $text = shift;
#  my $log = new Log::In 250, "$list, $line, $text";
  my (@matches, $class, $i, $invert, $j, $k, $l, $match, $rule, $sev);

  # Share some variables with the compartment
  $safe->share(qw($text $line));
  
  for $i ('GLOBAL', $list) {
    for $j ('admin_body', 'taboo_body') {
      # Eval the code
      @matches = $safe->reval($code->{$i}{$j});
      warn $@ if $@;
      
      # Run over the matches that resulted
      while (($rule, $match, $sev, $class, $invert) = splice(@matches, 0, 5)) {
	# An inverted match; remove it from the list
	if ($invert) {
	  delete $inv->{"$i\t$j\t$rule\t$sev\t$class"};
	}
	else {
	  _describe_taboo($reasons, $avars, $i, $j, $rule, $match,
			  $line, $sev, $class, $invert);
	}
      }
    }
  }
}

=head2 _check_mime

This checks a given MIME type against the mime matching code built from
attachment_rules and modifies the bounce reasons and access variables as
appropriate.

=cut
sub _check_mime {
  my $reasons = shift;
  my $avars   = shift;
  my $safe    = shift;
  my $ent     = shift;
  my $code    = shift;
  my $maxlen  = shift;
  my $part    = shift;
  my $type    = $ent->mime_type;
  my $log = new Log::In 250, "$type";
  local($_);
  my ($action, $head, $len);

  # Evaluate the matching code
  $_      = $type;
  $action = $safe->reval($code);
  $::log->complain($@) if $@;
  if ($action eq 'consult') {
    push @$reasons, "Questionable MIME part in $part: $type";
    $avars->{mime_consult} = 1;
    $avars->{mime} = 1;
    $log->out('consult');
  }
  elsif ($action eq 'deny') {
    push @$reasons, "Illegal MIME part in $part: $type";
    $avars->{mime_deny} = 1;
    $avars->{mime} = 1;
    $log->out('deny');
  }    

  # Unless we're parsing the top level (where we've already checked the
  # header closely), extract and unfold the MIME headers, then check for
  # long lines.  Don't decode, because it takes time and we want to see the
  # longest strings here.  XXX Further limit this for message/rfc822
  # inclusions?
  unless ($part eq 'toplevel') {
    $head = $ent->head; $head->unfold;
   HEAD:
    for my $i ($head->tags) {
      for my $j ($head->get($i)) {
        $len = length($i)+length($j)+2;
        $avars->{mime_header_length} = $len 
          if ($len > $avars->{mime_header_length});
        if ($len > $maxlen) {
          push(@$reasons,
               "A MIME header is too long in $part ($len > $maxlen)");
          $avars->{mime_header_length_exceeded} = 1;
          last HEAD;
        }
      }
    }
  }
}

=head2 _describe_taboo

Takes the various results from a taboo match (i.e. what an eval of thematch
code returns), builds the proper descriptions and such, and modifies the
supplied array and hashrefs to reflect the reasons and the variables given
in the match data.

Note that there is no return value, other than the modification of reasons
and avars.

=cut
sub _describe_taboo {
  my $reasons = shift;
  my $avars   = shift;
  my ($list, $var, $rule, $match, $line, $sev, $class, $inv) = @_;
  my $log = new Log::In 300, "$list, $var, $class";
  my ($admin, $global, $reason, $trunc, $type);

  # Make sure messages are pretty
  $match =~ s/\s+$// if defined $match;

  # Remove ^A characters, the token database field separator. 
  $match =~ s/\001//g if defined $match;

  # Chomp the match down to something manageable, so we don't get hideously
  # long strings in bounce messages.  Include a bit more than the length of
  # a standard line here.
  $trunc = '';
  if (length($match) > 100) {
    $match = substr($match, 0, 100);
    $trunc = ' (truncated)';
  }

  # Build match type and set the appropriate access variable
  if ($list eq 'GLOBAL') {
    $type .= "global_";
    $global = 1;
  }
  if ($var =~ /^admin/i) {
    $type .= "admin_$class";
    $admin = 1;
  }
  else {
    $type .= "taboo_$class";
  }
  $avars->{$type} += $sev;

  # Set bounce variables and push a reason; note that classes in upper case
  # don't generate reasons.
  unless ($class eq uc($class)) {
    $type =~ s/\_/ /g; # underscores to spaces
    if ($inv) {
      $reason = uc("inverted $type") . ": $rule failed to match";
    }
    elsif ($line) {
      $reason = uc($type) . ": $rule matched \"$match\"$trunc at line $line";
    }
    else {
      $reason = uc($type) . ": $rule matched \"$match\"$trunc";
    }
    push @$reasons, $reason;
    
    # Bump the combined match variables
    if ($admin) {
      $avars->{admin} += $sev;
    }
    else {
      $avars->{taboo} += $sev;
    }
  }
}

=head2 _trim_approved

This removes Approved: pseudo-headers from the body of the message.

If present in the preamble, it is removed.

If present in the first line of the body of the message and followed
immediately by a blank line, it and the blank line are removed by
creating a new body copying all but the new body into it.

If present in the first line of the body and not followed immediately
by a blank line, everything directly after the Aproved: line is parsed
as a new MIME entity and the old entity is completely obliterated.

If the message is multipart, the first body part is checked for the
header, and it is removed if present.

If the message is multipart, consists of exactly two parts, the first
part contains nothing but the Approved: line and the second part has
type message/rfc822, then the second part is parsed as a MIME message
and the original entity is completely obliterated.

This returns an entity and a head; they may be the same, they may be
different.

Note that Approved: headers are removed along with the rest of the
skip headers after this step is complete.

XXX Perhaps call this function recursively?  Are there situations
where many approvals can be stacked up?

XXX Need to purge all of the bodies and entities that we get rid of in
the course of this function.

=cut
use Mj::MIMEParser;
sub _trim_approved {
  my $self  = shift;
  my $oent  = shift;
  my $log   = new Log::In 40;
  my ($i, $line, $nbody, $nent, $nfh, $obody, $ofh, $part,
      $parser, $passwd, $pos, $pre, $token);

  # Nuke Approved:-looking lines in the preamble
  $pre = $oent->preamble;
  if ($pre) {
    for $i (0..3) {
      last unless $$pre[$i];
      if ($$pre[$i] && $$pre[$i] =~ /Approved:\s*([^\s,]+)\s*,?\s*(.*)/i) {
	splice @$pre, $i, 1;
	return $oent;
      }
      last if $$pre[$i] =~ /\S/;
    }
  }
  
  # Now check the body; if multipart:
  $part = $oent->parts(0);
  if ($part) {
    # Look for approved.
    $ofh = $part->open('r');
    if ($ofh) {
      while (defined ($line = $ofh->getline)) {
	last if $line =~ /\S/;
      }
      if (defined($line) && $line =~ /Approved:\s*([^\s,]+)\s*,?\s*(.*)/i) {
	# Look a single additional part of type message/rfc822 and if so,
	# parse it and return it.
	if (scalar($oent->parts) == 2 &&
	    $oent->parts(1)->effective_type eq 'message/rfc822')
	  {
	    # We could turn on parse_nested_message, but that's more
	    # pain than its worth.
	    $nfh = $oent->parts(1)->open('r');
	    $parser = new Mj::MIMEParser;
	    $parser->output_to_core($self->_global_config_get('max_in_core'));
	    $parser->output_dir($self->_global_config_get('tmpdir'));
	    $parser->output_prefix('mjr');
	    $nent = $parser->read($nfh);
	    $oent->purge;
	    return $nent;	  
	  }
	# Otherwise make a new body and copy everything after the approved
	# line into it, set part 0's body to the new value, and return.
	$nbody = new MIME::Body::File $self->tempname;
	$nfh   = $nbody->open('w');

	# Skip the single blank line that follows the Approve: line.
	$ofh->getline;
	while (defined ($line = $ofh->getline)) {
	  $nfh->print($line);
	}
	$obody = $part->bodyhandle($nbody);
	$obody->purge;
	return $oent;
      }
    }
  }
  else {
    # We have a single part message.  Look for approved.
    $ofh = $oent->open('r');
    if ($ofh) {
      while (defined ($line = $ofh->getline)) {
	last if $line =~ /\S/;
      }
      if (defined($line) && $line =~ /Approved:\s*([^\s,]+)\s*,?\s*(.*)/i) {
	# Found it; save the file position and read one more line.
	$pos = $ofh->tell;
	$line = $ofh->getline;
	
	# If it's blank, make a new body and copy everything after the
	# blank into it, replace the old body with the new one and return
	# the entity.
	if (!defined($line) || $line !~ /\S/) {
	  $nbody = new MIME::Body::File $self->tempname;
	  $obody = $oent->bodyhandle;
	  $nfh   = $nbody->open('w');
	  while (defined ($line = $ofh->getline)) {
	    $nfh->print($line);
	  }
	  $oent->bodyhandle($nbody);
	  $obody->purge;
	  return $oent;
	}
	# Else we have headers; seek back (unless we're at a possibly
	# quoted mailbox separator) and parse from the body to a new
	# entity; return it.
	$ofh->seek($pos, 0) unless $line =~ /^>?From /;
	$parser = new Mj::MIMEParser;
	$parser->output_to_core($self->_global_config_get('max_in_core'));
	$parser->output_dir($self->_global_config_get('tmpdir'));
	$parser->output_prefix('mjr');
	$nent =  $parser->read($ofh);
	$oent->purge;
	return $nent;	  
      }
    }
  }

  # No approvals found; just return what we got.
  return $oent;
}

=head2 _add_fters(entity, list, subs)

This adds fronters and footers to the entity.  If the message is
multipart or the only part is not text/plain, then we have to do
things via attachments.  For a first pass, we will only deal with
multipart messages or text/plain single-part messages; trying to
convert a single-part message into a multipart one just to attach some
goodies is not a really good idea (and might never happen).  We need
to decide if we really want to add a fronter or footer, figure out
which one to use, then attach it.

=cut
sub _add_fters {
  my $self = shift;
  my $ent  = shift;
  my $list = shift;
  my $subs = shift;
  my $log  = new Log::In 40;
  my($foot, $footers, $foot_ent, $foot_freq, $front, $fronters,
     $front_ent, $front_freq, $line, $nbody, $nfh, $obody, $ofh);

  # Extract fter arrays and frequencies from storage.
  $fronters   = $self->_list_config_get($list, 'message_fronter');
  $front_freq = $self->_list_config_get($list, 'message_fronter_frequency');
  $footers    = $self->_list_config_get($list, 'message_footer');
  $foot_freq  = $self->_list_config_get($list, 'message_footer_frequency');

  # Choose the proper items if we need them at all; also, tack on line
  # endings and stuff into useful arrayrefs.  (This makes it easy to
  # build entities out of them if necessary.)
  if (@$fronters && $front_freq > rand(100)) {
      $front = [];
      for $line (@{@$fronters[rand(@$fronters)]}) {
	  push @$front, "$line\n";
      }
  }
  if (@$footers && $foot_freq > rand(100)) {
      $foot = [];
      for $line (@{@$footers[rand(@$footers)]}) {
	  push @$foot, "$line\n";
      }
  }

  # Bail unless we're adding something
  return unless $front || $foot;

  # Substitute values
  $front = $self->substitute_vars_string($front, $subs) if $front;
  $foot  = $self->substitute_vars_string($foot,  $subs) if $foot;

  # We take different actions if the message is multipart
  if ($ent->is_multipart) {
      if ($front) {
	  $front_ent = build MIME::Entity(Type       => "text/plain",
					  Data       => $front,
					  'X-Mailer' => undef,
					 );
	  # Add the part at the beginning of the message
	  $ent->add_part($front_ent, 0);
      }
      if ($foot) {
	  $foot_ent = build MIME::Entity(Type       => "text/plain",
					 Data       => $foot,
					 'X-Mailer' => undef,
					);
	  # Add the part at the end of the message
	  $ent->add_part($foot_ent, -1);
      }
      return 1;
  }
  # Else we have a single part message; make sure it's a type we can mess with
  return 0 unless $ent->effective_type eq 'text/plain';

  # prepare to copy the body
  $nbody = new MIME::Body::File $self->tempname;
  $obody = $ent->bodyhandle;
  $nfh   = $nbody->open('w');
  $ofh   = $obody->open('r');

  # Copy in the fronter
  if ($front) {
      for $line (@$front) {
	  $nfh->print($line);
      }
  }
  # Copy the message
  while (defined ($line = $ofh->getline)) {
      $nfh->print($line);
  }
  # Copy in the footer
  if ($foot) {
      for $line (@$foot) {
	  $nfh->print($line);
      }
  }

  # Put the new body in place.  We don't purge the old body because
  # the archive copy still references the backing file.
  $ent->bodyhandle($nbody);
  return 1;
}

=head2 _munge_from(ent, list)

This hacks up the From: header and perhaos CC: as well.  Currently the only
function is to check to see if the user in the From: header has the
rewritefrom flag set and if so replace it with the version from the list.

=cut
sub _munge_from {
  my ($self, $ent, $list) = @_;
  my ($data, $from);

  $from = new Mj::Addr($ent->head->get('From'));
  if ($from->isvalid &&
      $self->{lists}{$list}->flag_set('rewritefrom', $from))
    {
      $data = $self->{lists}{$list}->is_subscriber($from);
      return unless $data;
      $ent->head->replace('From', $data->{fulladdr});
    }
}

=head2 _munge_subject(ent, sequence_number)

Prepend the subject prefix.  $SENDER is is expanded under 1.94 but it is
done is such a broken manner that nobody would ever use it.  We disable it;
if someone needs it we can probably find a way to make it work at the
expense of some accuracy in prefix removal.

Returns two entities: one with the prefix, one with any existing prefix
removed.

=cut
sub _munge_subject {
  my ($self, $ent1, $list, $seqno) = @_;
  my ($ent2, $gprefix, $head1, $head2, $prefix, $subject, $subject2, $subs);

  $ent2  = $ent1->dup;
  $head1 = $ent1->head;
  $head2 = $ent2->head;

  $prefix = $self->_list_config_get($list, 'subject_prefix');

  $subs = {'LIST'    => $list,
	   'VERSION' => $Majordomo::VERSION,
	   'SEQNO'   => $seqno,
	  };

  if ($prefix) {
    # Substitute constant values into the prefix and turn it into a regexp
    # matching a 'general prefix'.  We have to do this because the sequence
    # number changes.
    $gprefix = quotemeta($prefix);
    $gprefix =~ s/\\\$LIST/$list/;
    $gprefix =~ s/\\\$SEQNO/\\d+/;

    # Generate the prefix to be prepended
    $prefix = $self->substitute_vars_string($prefix, $subs);

    $subject = $subject2 = $head1->get('Subject');

    # Do we have a subject?
    if (defined $subject) {
      chomp $subject;

      # Does this subject have the prefix already on it?  If so, turn it
      # into the new prefix and (for the second copy) remove it and the
      # following space entirely.
      if ($subject =~ /$gprefix/) {
	$subject  =~ s/$gprefix/$prefix/;
	$subject2 =~ s/$gprefix ?//;

	$head1->replace('Subject', "$subject");
	$head2->replace('Subject', "$subject2");
      }

      # otherswise tack it onto one copy and leave the other alone
      else {
	$head1->replace('Subject', "$prefix $subject");
      }
    }

    # Turn an empty subject into just the prefix, leave the second copy empty.
    else {
      $head1->replace('Subject', "$prefix");
    }
  }
  ($ent1, $ent2);
}

=head2 _reply_to(ent)

This adds a Reply-To: header to an entity.

=cut
sub _reply_to {
  my($self, $ent, $list, $seqno, $user) = @_;
  my ($head, $replyto);

  $head = $ent->head;
  $replyto = $self->_list_config_get($list, 'reply_to');

  if ($replyto && (!$head->get('Reply-To') ||
		   $self->_list_config_get($list, 'override_reply_to')))
    {
      $replyto =
	$self->substitute_vars_string
	  ($replyto,
	   {
	    'HOST'    => $self->_list_config_get($list, 'resend_host'),
	    'LIST'    => $list,
	    'USER'    => $user,
	    'SENDER'  => $user,
	    'SEQNO'   => $seqno,
	   },
	  );
      $head->set('Reply-To', $replyto);
    }
  $ent;
}

=head2 _exclude

Figure out who to exclude.

This looks at the To: and CC: headers of the given entity, plus the provded
user.  It checks the settings for those addresses and adds them to the
exclude list if appropriate:

  $user is excluded if it has flags 'noselfcopy'.
  To: and CC: are excluded if they have flags 'eliminatecc'.

=cut
sub _exclude {
  my($self, $ent, $list, $user) = @_;
  my(@addrs, $addr, $cc, $exclude, $i, $to);
  $exclude = {};

  # The user doesn't get a copy if they don't have 'selfcopy' set.
  $exclude->{$user->canon} = 1
    if $user->isvalid && !$self->{'lists'}{$list}->flag_set('selfcopy', $user);

  # Extract addresses from headers
  $to = $ent->head->get('To', 0); chomp $to if $to;
  $cc = $ent->head->get('CC', 0); chomp $cc if $cc;

  push @addrs, Mj::Addr::separate($to) if $to;
  push @addrs, Mj::Addr::separate($cc) if $cc;

  for $i (@addrs) {
    $addr = new Mj::Addr($i);
    next unless $addr->isvalid;
    $exclude->{$addr->canon} = 1
      if $self->{'lists'}{$list}->flag_set('eliminatecc', $addr);
  }
  $exclude;
}

=head2 do_digests($list, $deliveries, $msgnum, $arcdata, $sender, $whereami, $tmpdir)

This handles passing the message to all defined digests and building any
digests that were triggered.

$run is a listref of digests to run.  If $run and $megnum are both defined,
$run is ignored.  (I.e. messages are always added to all digests.)

If $force is true, a digest will be generated if any messages are waiting.
If not true, the normal decision algorithm will run.

$deliveries is modified.

If $msgnum is not defined, digest_trigger will be called instead of
digest_add, so this function can be used to trigger a digest.

=cut
sub do_digests {
  my ($self, %args) = @_;
  my $log = new Log::In 40;
  my (%digest, %file, @dfiles, @dtypes, @nuke, @tmp, $digests, $dissues, $dtext,
      $file, $i, $j, $k, $l, $list, $subs);
  $list = $args{'list'}; $subs = $args{'substitute'};

  # Pass to digest if we got back good archive data and there is something
  # in the digests variable.
  $digests = $self->_list_config_get($list, 'digests');
  if (scalar keys %{$digests}) {
    if ($args{'msgnum'}) {
      # Note that digest_add will eventually call the trigger itself.
      %digest = $self->{'lists'}{$list}->digest_add($args{'msgnum'},
						    $args{'arcdata'},
						   );
    }
    else {
      %digest = $self->{'lists'}{$list}->digest_trigger($args{'run'},
							$args{'force'},
						       );
    }

    if (%digest) {
      # Extract volumes and issues, then write back the incremented values.
      # Note that when we set the new value, we must do it in an unparsed
      # form.  Hence the weird string-building code.
      $dissues = $self->{lists}{$list}->digest_incissue([keys(%digest)], $digests);

      # Now have a hash of digest name, listref of [article, data] pairs.
      # For each digest, build the three types and for each type and then
      # stuff an appropriate entry into %deliveries.
      for $i (keys(%digest)) {
	@dtypes = qw(text mime index);
	$subs->{DIGESTNAME} = $i;
	$subs->{DIGESTDESC} = $digests->{$i}{desc};
	$subs->{ISSUE}      = $dissues->{$i}{issue};
	$subs->{VOLUME}     = $dissues->{$i}{volume};

	# Fetch the files from storage.  Per digest type, we have three
	# files that we need, and we look for them under any of four names
	# of decreasing specificity.  Hence the wildly nested loop here.
	for $j (@dtypes) {
	  for $k (qw(preindex postindex footer)) {
	    $subs->{DIGESTTYPE} = $j;
	    for $l ("digest_${i}_${j}_${k}", "digest_${i}_${k}", "digest_${j}_${k}", "digest_${k}") {
	      ($file, %file) = $self->_list_file_get($list, $l, $subs);
	      next unless $file;
	      # We're guaranteed to have something by now; if the user
	      # didn't provide a file, the build routine will just leave
	      # the appropriate spot blank.
	      $dtext->{$j}{$k}{'name'} = $file;
	      $dtext->{$j}{$k}{'data'} = \%file;
	      push @nuke, $file;
	    }
	  }
	}

	@dfiles = $self->{'lists'}{$list}->digest_build
	  (messages     => $digest{$i},
	   types        => [@dtypes],
	   files        => $dtext,
	   subject      => $digests->{$i}{desc} . " V$dissues->{$i}{volume} #$dissues->{$i}{issue}",
	   from         => $args{'sender'},
	   to           => "$list\@$args{'whereami'}",
	   tmpdir       => $args{'tmpdir'},
	   index_line   => $self->_list_config_get($list, 'digest_index_format'),
	   headers      => $args{'headers'},
	  );

	# Unlink the temporaries.
	unlink @nuke;	

	for $j (@dtypes) {
	  # shifting off an element of @dfiles gives the corresponding digest
	  $args{'deliveries'}->{"digest-$i-$j"} = {exclude => {},
						   file => shift(@dfiles),
						  };
	}
      }
    }
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
### cperl-indent-level:2 ***
### cperl-label-offset:-1 ***
### End: ***
