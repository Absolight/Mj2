sub ask_basic {
  $config = shift;

  #---- Ask about clearing screen
  $nosep = 1; $sepclear = 0;
  $msg = <<EOM;

Clear the screen before each question?
EOM
  $def = defined($config->{'sepclear'}) ? $config->{sepclear} : 0;
  $config->{sepclear} = get_bool($msg, $def);
  $sepclear = $config->{sepclear}; $nosep = 0;

  #---- Ask for startperl
  $msg = <<EOM;
Where is Perl located on this system?
EOM
  $def = $config->{startperl};
  unless ($def) {
    $def = $Config{startperl};
    $def =~ s/[\#\!]*\s*(\S+).*/$1/;
    unless (-x $def) {
      $msg .= "
Normally the default answer to this question is taken
from the 'startperl' variable in Config.pm (containing
\"$Config{startperl}\" which is supposed
to be correct in any proper Perl installation.
Your installation does not seem to be correct.
";
      $def = '';
    }
  }

  # Get an existing executable without searching $PATH, force existing.
  $config->{startperl} = get_file($msg, $def, 1, 1, 0, 1);

  #---- Ask for UID
  $msg = <<EOM;
Basic Security Configuration

What is the user ID that Majordomo will run as?
 Either the numeric ID or the user name is fine.
EOM
  $def = $config->{'uid'} ||
    (getpwnam("majordom") && "majordom") ||
      (getpwnam("lists") && "lists");
  $config->{'uid'} = get_uid($msg, $def);

  #---- Ask for GID
  $msg = <<EOM;
Basic Security Configuration

What is the group ID that Majordomo will run as?
 Either the numeric ID or the group name is fine.
EOM
  $def = $config->{'gid'} ||
    (getgrnam("majordom") && "majordom") ||
      (getgrnam("lists") && "lists");
  $config->{gid} = get_gid($msg, $def);

  #---- Ask about wrappers
  $msg = <<EOM;
Basic Security Configuration

Should the SETID wrappers be installed?
 Majordomo needs to be able to run as the proper user no matter who is
  running it.  This requires that it be installed SETID.  On some systems,
  the Majordomo programs can be installed SETID, but this requires both
  that the operating system support it ant that perl be built to support
  it.  If this is not possible, a set of tiny wrapper programs can be built
  which will take care of the SETID needs of Majordomo.
 If you\'re not sure of how to answer this question, just answer YES.
  There is no loss of functionality when the wrappers are enabled.  Curious
  users may want to answer NO; if wrappers are required, the installation
  process will fail later.
Install the wrappers? 
EOM
  $def = defined($config->{'wrappers'}) ? $config->{'wrappers'} : 1;
  $config->{'wrappers'} = get_bool($msg, $def);

  #---- Ask for umask
  $msg = <<EOM;
Basic Security Configuration

What umask should Majordomo use?
 The umask is the Unix method of restricting the permissions on newly
  created files and directories.
 Useful values are:
  077 (nobody except Majordomo can read any Majordomo files)
  027 (users in the Majordomo group can read the files)
  007 (users in the Majordomo group can read and write the files)
 Choose 077 for maximum security.  Majordomo2 can operate with very strict
  permissions.

What should umask be set to?
EOM
  $def = $config->{'umask'} || '077';
  $config->{'umask'} = get_enum($msg, $def, [qw(077 027 007 002 000)]);

  #---- Ask for insecure stored passwords
  $msg = <<EOM;
Basic Security Configuration

For developers: the install process needs to know various passwords.
 They can either be saved along with the rest of your install
  configuration, or prompted for at the end of the installation.  Saving
  your passwords can save typing if you are installing repeatedly (as
  happens during development) but this leaves the passwords in the build
  directory which can compromise security.
 If you choose to save your passwords, the .mj_config file will be created
  with strict permissions.

Should the installer save your passwords?
EOM
  $def = $config->{save_passwords};
  $config->{save_passwords} = get_bool($msg, $def);
  unless ($config->{save_passwords}) {
    # Just in case, clean out any stored passwords.
    for my $i (@{$config->{'domains'}}, keys(%{$config->{'domain'}})) {
      warn "Nuking $i";
      delete $config->{'domain'}{$i}{'master_password'};
    }
  }

  #---- Get site password
  $msg = <<EOM;
Basic Security Configuration

Please choose a site password.
  Majordomo allows a single site password that allows the holder to perform
  any function on any list in any virtual domain at the site, in addition
  to various more specific passwords.  It should be chosen with care.  It
  can be of arbitrary length, but cannot contain spaces.
EOM
  $def = $config->{'site_password'};
  if ($config->{save_passwords}) {
    $config->{'site_password'} = get_str($msg, $def);
  }
  else {
    delete $config->{'site_password'};
  }

  #---- Ask about database storage mechanism
  if ($have{'DB_File'}) {
    $msg = <<EOM;
Database Storage

Majordomo needs to know which database backend to use.
 You have the DB_File module installed, so Perl has access to advanced
  database routines that Majordomo can use to store the various data it
  collects.  Majordomo also has a simple database interface implemented
  with text files which will be used if you answer no to this question;
  databases using this method can be viewed and edited by hand, but access
  to them is very slow.
 Note that the database backend cannot easily be changed after the fact.
 IMPORTANT: if you are upgrading, you must convert your existing databases;
  Majordomo will not do this for you.  Please read the README.UPGRADE
  document for more information.

Should Majordomo use DB_File databases?
EOM
    $def = (defined($config->{database_backend}) && $config->{database_backend} eq 'db') || 1;
    if (get_bool($msg, $def)) {
      $config->{database_backend} = 'db';
    }
  }
  else {
    $msg = <<EOM;
Database Storage

Majordomo will use flat text file databases.

 You do not have the Berkeley DB library and the DB_File module installed,
  so Majordomo will instead use flat text file databases.  These databases
  are significantly slower to access then DB_File ones; if performance is
  important then it is recommended that you install these libraries and
  rerun the installation.

 The Berkeley DB database library is located at http://www.sleepycat.com;
 the DB_File module is part of Perl and can also be obtained from CPAN with
 the following command line:

   perl -MCPAN -e\'CPAN::Shell->install(\"DB_File\")\';

Please press enter.
EOM
    get_str($msg);
    $config->{database_backend} = 'text';
  }

  #---- Ask for default install location
  $msg = <<EOM;
Storage Locations

Where will the Majordomo libraries, executables and documentation be kept?
 This could be something like \"/usr/local/majordomo\"; Majordomo will make
   this directory and several directories under it to hold its various
   components.
 Note that this is not necessarily where your lists must be stored.
EOM
  $def = $config->{'install_dir'};
  $config->{'install_dir'} = get_dir($msg, $def);

  #---- Ask for list directory
  $msg = <<EOM;
Storage Locations

Where will the Majordomo list data be kept?
 Note that under this directory will be a directory for each domain your
   site supports, and under that a directory for each list at your site.
 Note also that this should _not_ be a directory containing lists
   maintained by Majordomo 1.x, as Majordomo 2 stores its lists in a
   different format.
EOM
  $def = $config->{'lists_dir'};
  $config->{'lists_dir'} = get_dir($msg, $def);

  #---- Ask for writable temporary dir
  $msg = <<EOM;
Storage Locations

Where can Majordomo place temporary files?
 Majordomo occasionally needs to write out short-lived files in a place
   that all users can write to.  These files are generally small and are
   deleted after the operations are complete.
EOM
  $def = $config->{'wtmpdir'} || "/tmp";
  $config->{'wtmpdir'} = get_dir($msg, $def);

  #---- Ask for secure temporary dir
  $msg = <<EOM;
Storage Locations

Where can Majordomo place secure temporary files?
  Majordomo also needs to write out private temporary files.  For maximum
    security, this should be a special directory that is neither readable
    nor writable by normal users.  (In other words, it should not be /tmp
    unless you know what you\'re doing.)  Many security problems can arise
    when any user can create files and links in the temporary directory with
    the same names that Majordomo would use.
  The installation process will create this directory if it does not exist,
    but will not enforce any permissions.
EOM
  $def = $config->{'tmpdir'} || "$config->{'wtmpdir'}/mj";
  $config->{'tmpdir'} = get_dir($msg, $def);
  $config->{'lockdir'} = "$config->{'tmpdir'}/locks";

  #---- Ask for cgi-bin directory
  $msg = <<EOM;
Web Component Setup

Where is the web server\'s cgi-bin directory?
  Majordomo comes with a program that enables users to conform operations
    such as subscriptions by using a web page.  It needs to put this program
    in the proper directory so that the web server will run it.
  If the machine running Majordomo does not also run a web server, leave
    this blank.
EOM
  $def = $config->{cgi_bin} ||
    (-d "/home/www/cgi-bin" && "/home/www/cgi-bin") ||
    (-d "/home/httpd/cgi-bin" && "/home/httpd/cgi-bin") || '';
  $config->{cgi_bin} = get_dir($msg, $def, 1);

  #---- Ask if we can link to cgi-bin
  $msg = <<EOM;
Web Component Setup

Can Majordomo make a link to the program in cgi-bin?
  Some web servers will allow a link to the file in cgi-bin; others require
    a separate copy.  Majordomo tries to avoid confusion by keeping all of
    its files together but if necessary it will put a separate copy of the
    program.
  If in doubt, just answer no.
EOM
  if ($config->{cgi_bin}) {
    $def = $config->{cgi_link} || 0;
    $config->{cgi_link} = get_bool($msg, $def);
  }

  #---- Ask for the URL of programs in cgi-bin
  $msg = <<EOM;
Web Component Setup

What is the URL for programs in cgi-bin?
  Majordomo needs to know how to make a URL that points to a program in the
    cgi-bin directory of your web server.
  For example, if you can call "blah.cgi" at
      http://www.example.com/cgi-bin/blah.cgi
    you would enter
      http://www.example.com/cgi-bin/

EOM
  if ($config->{cgi_bin}) {
    $def = $config->{cgi_url} || '';
    $config->{cgi_url} = get_str($msg, $def);
    $config->{cgi_url} .= '/' unless $config->{cgi_url} =~ m!/$!;
  }

  #---- Ask about queueing
  $msg = <<EOM;
Mail Handling Setup

Would you like to run Majordomo in queueing mode, or in direct mode?
  Majordomo can be run in two modes:
    In direct mode, every message that comes in is fully processed and
    delivered by a new Majordomo process.  No limits are placed on the
    number of messages processed concurrently.
    In queueing mode, incoming messages are put in a queue to be processed
    by a separate program.  Generally queued messages are processed
    immediately, but the number of messages processed concurrently is
    restricted.
    Queueing mode is generally faster (because one program can handle many
    messages without having to be run for each one) and uses system
    resources much more sparingly (because under heavy load only a limited
    number of processes can be active at a time) than direct mode, but it
    is also much more experimental at this time.
Use queueing mode?
EOM
  $def = defined($config->{queue_mode}) ?
    $config->{queue_mode} : 1;
  $config->{queue_mode} = get_bool($msg, $def);
  if ($config->{queue_mode}) {
    require "setup/ask_queueing.pl";
    ask_queueing($config);
  }

  #---- Ask about case smashing
  $msg = <<EOM;
Mail Handling Setup

Would you like Majoromo to ignore case in addresses by default?
  The user portion of an address is not usually case sensitive, though on
    some systems it is.  By default Majordomo pays attention to case when
    comparing addresses in order to follow all relevant standards and be
    completely safe when faced with the innumerable number of addresses it
    must deal with, but this may be surprising to those who expect the
    opposite behavior.

EOM
  $def = $config->{ignore_case};
  $config->{ignore_case} = get_bool($msg, $def);

  #---- Ask for MTA
  $msg = <<EOM;
Mail Handling Setup

What Mail Transfer Agent will be feeding mail to Majordomo?
 Majordomo needs to know the MTA that you\'re running so that it can suggest
  configuration details.
 Currently supported MTAs are:
  sendmail
  exim
  qmail
  postfix
  (sorry, no more!  Look in MTAConfig.pm and write your own!)
 Enter \'none\' if you use an unsupported MTA.
EOM

  $def = ($config->{'mta'} ||
          (-x '/var/qmail/bin/qmail-inject' && 'qmail')    ||
          (-x '/usr/sbin/qmail-inject'      && 'qmail')    ||
          # Sendmail goes last because most MTAs have some sendmail-like
          # wrapper there
          (-x '/usr/lib/sendmail'           && 'sendmail') ||
          (-x '/usr/sbin/sendmail'          && 'sendmail') ||
          'none'
         );
  $config->{'mta'} = get_enum($msg, $def, [qw(none sendmail exim qmail postfix)]);

  if ($config->{'mta'} eq 'sendmail') {
    require "setup/mta_sendmail.pl";
    ask_sendmail($config);
  }
  elsif ($config->{'mta'} eq 'exim') {
    require "setup/mta_exim.pl";
    ask_exim($config);
  }
  elsif ($config->{'mta'} eq 'postfix') {
    require "setup/mta_postfix.pl";
    ask_postfix($config);
  }
  elsif ($config->{'mta'} eq 'qmail') {
    require "setup/mta_qmail.pl";
    ask_qmail($config);
  }

  #---- Ask for virtual domains
  $msg = <<EOM;
Virtual Domains

Which domains will this Majordomo installation support?
  Majordomo 2 includes support for virtual domain setups, where one machine
    serves several distinct sets of lists.  You can name these collections
    of lists anything you choose, but it is customary to name them after
    the domains which they serve.
  If you have too many domains to list here, you may add them later.
    Consult the documentation.
  If you do not intend to make use of virtual domains, just enter your
    domain.
  Enter a single domain at a time, or a blank line to end.  Enter a space
    to cancel a default value.
EOM
  $def = $config->{'domains'} || [$Net::Config::NetConfig{'inet_domain'}] || undef;
  $config->{'domains'} = get_list($msg, $def);

  require "setup/ask_domain.pl";
  for $i (@{$config->{'domains'}}) {
    ask_domain($config, $i);
  }
  sep();
}

=head1 COPYRIGHT

Copyright (c) 1999 Jason Tibbitts for The Majordomo Development
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
### indent-tabs-mode: nil ***
### End: ***
