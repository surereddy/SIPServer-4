#
# Sip.pm: General Sip utility functions
#

package Sip;

use strict;
use warnings;
use English;
use Exporter;

use Sys::Syslog qw(syslog);
use POSIX qw(strftime);

use Sip::Constants qw(SIP_DATETIME);
use Sip::Checksum qw(checksum);

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(y_or_n timestamp add_field maybe_add add_count
		    denied sipbool boolspace write_msg read_SIP_packet
		    $error_detection $protocol_version $field_delimiter
		    $last_response);

our %EXPORT_TAGS = (
		    all => [qw(y_or_n timestamp add_field maybe_add
			       add_count denied sipbool boolspace write_msg
			       read_SIP_packet
			       $error_detection $protocol_version
			       $field_delimiter $last_response)]);


our $error_detection = 0;
our $protocol_version = "1.00";
our $field_delimiter = '|'; 	# Protocol Default

# We need to keep a copy of the last message we sent to the SC,
# in case there's a transmission error and the SC sends us a
# REQUEST_ACS_RESEND.  If we receive a REQUEST_ACS_RESEND before
# we've ever sent anything, then we are to respond with a
# REQUEST_SC_RESEND (p.16)

our $last_response = '';

sub timestamp {
    my $time = $_[0] || time();

    return strftime(SIP_DATETIME, localtime($time));
}

#
# add_field(field_id, value)
#    return constructed field value
#
sub add_field {
    my ($field_id, $value) = @_;
    my ($i, $ent);

    if (!defined($value)) {
	syslog("LOG_DEBUG", "add_field: Undefined value being added to '%s'",
	       $field_id);
	$value = '';
    }

    # Replace any occurences of the field delimiter in the
    # field value with the HTML character entity
    $ent = sprintf("&#%d;", ord($field_delimiter));

    while (($i = index($value, $field_delimiter)) != ($[-1)) {
	substr($value, $i, 1) = $ent;
    }

    return $field_id . $value . $field_delimiter;
}
#
# maybe_add(field_id, value):
#    If value is defined and non-empty, then return the
#    constructed field value, otherwise return the empty string
#
sub maybe_add {
    my ($fid, $value) = @_;

    return (defined($value) && $value) ? add_field($fid, $value) : '';
}

#
# add_count()  produce fixed four-character count field,
# or a string of four spaces if the count is invalid for some
# reason
#
sub add_count {
    my ($label, $count) = @_;

    # If the field is unsupported, it will be undef, return blanks
    # as per the spec.
    if (!defined($count)) {
	return ' ' x 4;
    }

    $count = sprintf("%04d", $count);
    if (length($count) != 4) {
	syslog("LOG_WARNING", "handle_patron_info: %s wrong size: '%s'",
	       $label, $count);
	$count = ' ' x 4;
    }
    return $count;
}

#
# denied($bool)
# if $bool is false, return true.  This is because SIP statuses
# are inverted:  we report that something has been denied, not that
# it's permitted.  For example, 'renewal priv. denied' of 'Y' means
# that the user's not permitted to renew.  I assume that the ILS has
# real positive tests.
#
sub denied {
    my $bool = shift;

    return boolspace(!$bool);
}

sub sipbool {
    my $bool = shift;

    return $bool ? 'Y' : 'N';
}

#
# boolspace: ' ' is false, 'Y' is true. (don't ask)
#
sub boolspace {
    my $bool = shift;

    return $bool ? 'Y' : ' ';
}


# read_SIP_packet($file)
#
# Read a packet from $file, using the correct record separator
#
sub read_SIP_packet {
    my $file = shift;
    local $/ = "\r";

    return readline($file);
}

#
# write_msg($msg, $file)
#
# Send $msg to the SC.  If error detection is active, then
# add the sequence number (if $seqno is non-zero) and checksum
# to the message, and save the whole thing as $last_response
#
# If $file is set, then it's a file handle: write to it, otherwise
# just write to the default destination.
#

sub write_msg {
    my ($self, $msg, $file) = @_;
    my $cksum;

    if ($error_detection) {
	if (defined($self->{seqno})) {
	    $msg .= 'AY' . $self->{seqno};
	}
	$msg .= 'AZ';
	$cksum = checksum($msg);
	$msg .= sprintf('%4X', $cksum);
    }


    if ($file) {
	print $file "$msg\r";
    } else {
	print "$msg\r";
	syslog("LOG_DEBUG", "OUTPUT MSG: '$msg'");
    }

    $last_response = $msg;
}

1;
