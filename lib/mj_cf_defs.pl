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
 'faq_access'           => "open",
 'get_access'           => "list",
 'archive_access'       => "list",
 'index_access'         => "open",
 'who_access'           => "open",
 'which_access'         => "open",
 'info_access'          => "open",
 'intro_access'         => "open",
 'advertise'            => [],
 'noadvertise'          => [],
 'advertise_subscribed' => 1,
 'access_password_override' => 1,
 'access_rules'         => [],
 'addr_allow_at_in_phrase' => 0,
 'addr_allow_ending_dot'=> 0,
 'addr_allow_bang_paths'=> 0,
 'addr_allow_comments_after_route' => 0,
 'addr_limit_length'    => 1,
 'addr_require_fqdn'    => 1,
 'addr_strict_domain_check' => 1,
 'aliases'              => 'ORQ',
 'allowed_classes'      => [qw(each digest nomail unique)],
 'allowed_flags'        => 'ACHPRSW',
 'archive_dir'          => '',
 'archive_size'         => 'unlimited',
 'archive_split'        => 'monthly',
 'archive_url'          => '',
 'attachment_rules'     => [],
 'bounce_recipients'    => [],
 'category'             => '',
 'install_dir'          => undef,
 'lists_dir'            => undef,
 'sublists'             => [],
 'templates'            => [],
 'triggers'             => ($list eq 'GLOBAL') ? 
                           [ 
                             'checksum | daily', 
                             'delay    | hourly', 
                             'log      | daily',
                             'session  | daily', 
                             'token    | daily' 
                           ] : 
                           [ 
                             'bounce   | daily',
                             'checksum | daily',
                             'delay    | hourly',
                             'post     | daily',
                           ],
 'default_class'        => 'each',
 'default_flags'        => 'SPR',
 'delivery_rules'       => [],
 'description'          => undef,
 'description_long'     => [],
 'digests'              => [],
 'digest_index_format'  => 'subject',
 'digest_issues'        => [],
 'set_policy'           => "open+confirm",
 'subscribe_policy'     => "open+confirm",
 'unsubscribe_policy'   => "open",
 'mungedomain'          => 0,
 'date_info'            => 1,
 'date_intro'           => 1,
 'moderate'             => 0,
 'moderator'            => undef,
 'moderators'           => [],
 'moderator_group'      => 0,
 'sender'               => ($list eq 'GLOBAL') ? 'SITE_DFLT' : '$LIST-owner',
 'maxlength'            => 40000,
 'precedence'           => "bulk",
 'reply_to'             => undef,
 'restrict_post'        => [],
 'purge_received'       => 0,
 'administrivia'        => 1,
 'resend_host'          => ($list eq 'GLOBAL') ? '' : 'SITE_DFLT',
 'debug'                => 0,
 'message_fronter'      => [],
 'message_fronter_frequency' => 100,
 'message_footer'       => [],
 'message_footer_frequency' => 100,
 'message_headers'      => ($list eq 'GLOBAL') ?
                           [
                            'Reply-To: $MJ',
                            'X-Loop: majordomo',
                           ] : [],
 'delete_headers'       => [qw(X-Confirm-Reading-To
			       X-Ack
			       Sender
			       Return-Receipt-To
			       Flags
			       Priority
			       X-Pmrqc
			       Return-Path
			       Delivered-To
			      )],
 'subject_prefix'       => undef,
 'admin_headers'        => (#'
			    ($list eq 'GLOBAL') ? 
			    ['/^subject:\s*subscribe\b/i',
			     '/^subject:\s*unsubscribe\b/i',
			     '/^subject:\s*uns\w*b/i',
			     '/^subject:\s*.*un-sub/i',
			     '/^subject:\s*help\b/i',
			     '/^subject:\s.*\bchange\b.*\baddress\b/i',
			     '/^subject:\s*request\b(.*\b)?addition\b/i',
			     '/^subject:\s*cancel\b/i',
                             '/MSGRCPT/',
			    ] : []),
 'admin_body'           => (($list eq 'GLOBAL') ?
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
 'taboo_headers'        => ($list eq 'GLOBAL') ? [] : [],
 'taboo_body'           => ($list eq 'GLOBAL') ? [] : [],
 'block_headers'        => ['/X-Loop:.*majordomo/i'],
 'override_reply_to'    => 0,
 'comments'             => [],
 'addr_xforms'          => [],
 'apply_global_xforms'  => 1,
 'master_password'      => ($list eq 'GLOBAL') ? 'SITE_DFLT' : '$LIST.pass',
 'passwords'            => [],
 'password_min_length'  => 4,
 'site_name'            => 'SITE_DFLT',
 'whereami'             => 'SITE_DFLT',
 'whoami'               => ($list eq 'GLOBAL') ? 'SITE_DFLT' : '$LIST',
 'whoami_owner'         => ($list eq 'GLOBAL') ? 'SITE_DFLT' : '$LIST-owner',
 'tmpdir'               => 'SITE_DFLT',
 'max_in_core'          => '20000',
 'return_subject'       => 1,
 'chunksize'            => 1000,
 'welcome'              => 1,
 'welcome_files'        => (($list eq 'GLOBAL') ?
			    [
			     'You have been registered at $SITE.',
			     'registered | NS',
			    ]
			    :
			    [
			     'Welcome to the $LIST mailing list!',
			     'welcome | NS',
			     'List introductory information',
			     'info | PS',
			    ]),
 'file_search'          => [':$LANG', ':'],
 'file_share'           => [],
 'filedir'              => undef,
 'default_lists_format' => 'short',
 'description_max_lines'=> 0,
 'confirm_url'          => 'SITE_DFLT',
 'dup_lifetime'         => 28,
 'save_denial_checksums'=> 0,
 'latchkey_lifetime'    => 60,
 'log_lifetime'         => 31,
 'session_lifetime'     => 14,
 'token_lifetime'       => 7,
 'token_remind'         => 4,
 'mta'                  => undef,
 'inform'               => [],
 'post_limits'          => [],
 'sequence_number'      => 1,
 'bounce_probe_frequency' => 0,
 'bounce_probe_pattern' => '',
 'bounce_max_age'       => 31,
 'bounce_max_count'     => 100,
 'bounce_rules'         => [],
 'default_language'     => 'en',
 'quote_pattern'        => '/^( - | : | > | [a-z]+> )/xi',
 'max_header_line_length'=> 448,
 'max_total_header_length'=> 2048,
 'max_mime_header_length'=> 128,
 'nonmember_flags'      => '',
 'request_answer'       => 'majordomo',
 'owners'               => ($list eq 'GLOBAL') ? ['SITE_DFLT'] : [],
 'signature_separator'  => '/^[-_]/',
 'ack_attach_original'  => [qw(fail stall)],
};
);
