=head1 NAME

mj_cf_defs.pl - default values for config variables

=head1 DESCRIPTION

This file holds the configuration defaults that are supplied to new lists.
It is require''d into the config package when the defaults need to be
written.  This means that you can put real code to be evaluated here in
place of the clunky #! mechanism that was there before.  You must use 0 or
1 for bool values, not "no" and "yes".  Use undef if the keyword has no
default.  This is executed in the Mj::Config package, so be sure to qualify
variables and functions from other packages.

=cut

$Mj::Config::default_string = q(
{
 'faq_access'           => "list",
 'get_access'           => "list",
 'index_access'         => "open",
 'who_access'           => "open",
 'which_access'         => "open",
 'info_access'          => "open",
 'intro_access'         => "list",
 'advertise'            => [],
 'noadvertise'          => [],
 'access_password_override' => 1,
 'access_rules'         => [],
 'addr_allow_at_in_phrase' => 0,
 'addr_allow_ending_dot'=> 0,
 'addr_allow_bang_paths'=> 0,
 'addr_allow_comments_after_route' => 0,
 'addr_limit_length'    => 1,
 'addr_require_fqdn'    => 1,
 'addr_strict_domain_check' => 1,
 'archive_dir'          => '',
 'archive_split'        => 'monthly',
 'attachment_rules'     => [],
 'install_dir'          => undef,
 'lists_dir'            => undef,
 'delivery_rules'       => [],
 'description'          => undef,
 'description_long'     => [],
 'digests'              => [],
 'subscribe_policy'     => "open+confirm",
 'unsubscribe_policy'   => "open",
 'mungedomain'          => 0,
 'date_info'            => 1,
 'date_intro'           => 1,
 'moderate'             => 0,
 'moderator'            => undef,
 'moderators'           => [],
 'moderator_group'      => 0,
 'sender'               => $list eq 'GLOBAL' ? "majordomo-owner" : "owner-$list",
 'maxlength'            => 40000,
 'precedence'           => "bulk",
 'reply_to'             => undef,
 'restrict_post'        => [],
 'purge_received'       => 0,
 'administrivia'        => 1,
 'resend_host'          => $list eq 'GLOBAL' ? '' : global_get("whereami"),
 'debug'                => 0,
 'message_fronter'      => [],
 'message_fronter_frequency' => 100,
 'message_footer'       => [],
 'message_footer_frequency' => 100,
 'message_headers'      => [],
 'delete_headers'       => [qw(X-Confirm-Reading-To
			       X-Ack
			       Sender
			       Return-Receipt-To
			       Flags
			       Priority
			       X-Pmrqc
			       Return-Path
			      )],
 'subject_prefix'       => undef,
 'admin_headers'        => (#'
			    $list eq 'GLOBAL' ? 
			    ['/^subject:\s*subscribe\b/i',
			     '/^subject:\s*unsubscribe\b/i',
			     '/^subject:\s*uns\w*b/i',
			     '/^subject:\s*.*un-sub/i',
			     '/^subject:\s*help\b/i',
			     '/^subject:\s.*\bchange\b.*\baddress\b/i',
			     '/^subject:\s*request\b(.*\b)?addition\b/i',
			     '/^subject:\s*cancel\b/i',
			    ] : []),
 'admin_body'           => ($list eq 'GLOBAL' ?
			    [
			     '/\bcancel\b/i',
			     '/\badd me\b/i',
			     '/\bdelete me\b/i',
			     '/\bremove\s+me\b/i',
			     '/\bchange\b.*\baddress\b/',
			     '/\bsubscribe\b/i',
			     '/^sub\b/i',
			     '/\bunsubscribe\b/i',
			     '/^unsub\b/i',
			     '/\buns\w*b/i',
			     '/^\s*help\s*$/i',
			     '/^\s*info\s*$/i',
			     '/^\s*info\s+\S+\s*$/i',
			     '/^\s*lists\s*$/i',
			     '/^\s*which\s*$/i',
			     '/^\s*which\s+\S+\s*$/i',
			     '/^\s*index\s*$/i',
			     '/^\s*index\s+\S+\s*$/i',
			     '/^\s*who\s*$/i',
			     '/^\s*who\s+\S+\s*$/i',
			     '/^\s*get\s+\S+\s*$/i',
			     '/^\s*get\s+\S+\s+\S+\s*$/i',
			     '/^\s*approve\b/i',
			     '/^\s*passwd\b/i',
			     '/^\s*newinfo\b/i',
			     '/^\s*config\b/i',
			     '/^\s*newconfig\b/i',
			     '/^\s*writeconfig\b/i',
			     '/^\s*mkdigest\b/i',
			    ] : []),
 'taboo_headers'        => $list eq 'GLOBAL' ? [] : [],
 'taboo_body'           => $list eq 'GLOBAL' ? [] : [],
 'override_reply_to'    => 0,
 'comments'             => [],
 'addr_xforms'          => [],
 'apply_global_xforms'  => 1,
 'master_password'      => "$list.pass",
 'passwords'            => [],
 'site_name'            => 'Majordomo',
 'whereami'             => undef,
 'whoami'               => $list eq 'GLOBAL' ? 'majordomo' : $list,
 'whoami_owner'         => $list eq 'GLOBAL' ? 'owner-majordomo' : "owner-$list",
 'tmpdir'               => '/tmp',
 'max_in_core'          => '20000',
 'return_subject'       => 1,
 'chunksize'            => 1000,
 'welcome'              => 1,
 'welcome_files'        => [],
 'file_search'          => [':$LANG', ':'],
 'file_share'           => [],
 'filedir'              => undef,
 'default_lists_format' => 'compact',
 'description_max_lines'=> 0,
 'confirm_url'          => 'http://www.hpc.uh.edu/cgi-bin/mj_confirm?t=$TOKEN',
 'dup_lifetime'         => 28,
 'session_lifetime'     => 14,
 'token_lifetime'       => 7,
 'token_remind'         => 4,
 'mta'                  => undef,
 'inform'               => [],
 'sequence_number'      => 1,
 'bounce_probe_frequency' => 0,
 'default_language'     => 'en',
 'quote_regexp'         => '/^( - | : | > | [a-z]+> )/xi',
 'max_header_line_length'=> 448,
 'max_total_header_length'=> 2048,
 'nonmember_flags'      => '',
 'default_flags'        => 'S',
};
);
