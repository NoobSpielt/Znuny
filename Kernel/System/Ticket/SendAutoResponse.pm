# --
# Kernel/System/Ticket/SendAutoResponse.pm - send auto responses to customers
# Copyright (C) 2001-2004 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: SendAutoResponse.pm,v 1.13 2004-03-12 18:35:10 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see 
# the enclosed file COPYING for license information (GPL). If you 
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::System::Ticket::SendAutoResponse;
    
use strict;

use vars qw($VERSION);
$VERSION = '$Revision: 1.13 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

# --
sub SendAutoResponse {
    my $Self = shift;
    my %Param = @_;
    # --
    # check needed stuff
    # --
    foreach (qw(Text Realname Address CustomerMessageParams TicketNumber TicketID UserID HistoryType)) {
      if (!$Param{$_}) {
        $Self->{LogObject}->Log(Priority => 'error', Message => "Need $_!");
        return;
      }
    }
    $Param{Body} = $Param{Text} || 'No Std. Body found!';
    my %GetParam = %{$Param{CustomerMessageParams}};
    # --
    # get old article for quoteing
    # --
    my %Article = $Self->GetLastCustomerArticle(TicketID => $Param{TicketID});
    foreach (qw(From To Cc Subject Body)) {
        if (!$GetParam{$_}) {
            $GetParam{$_} = $Article{$_} || '';
        }
        chomp $GetParam{$_};
    }
    # --
    # check reply to for auto response recipient
    # --
    if ($GetParam{ReplyTo}) {
        $GetParam{From} = $GetParam{ReplyTo};
    }
    # --
    # check if sender is e. g. MAILDER-DAEMON or Postmaster
    # --
    my $NoAutoRegExp = $Self->{ConfigObject}->Get('SendNoAutoResponseRegExp');
    if ($GetParam{From} =~ /$NoAutoRegExp/i) {
        # --
        # add it to ticket history
        # --
        $Self->AddHistoryRow(
            TicketID => $Param{TicketID},
            CreateUserID => $Param{UserID},
            HistoryType => 'Misc',
            Name => "Sent not auto response, SendNoAutoResponseRegExp is matching.",
        );
        # --
        # log
        # --
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message => "Sent not auto response to '$GetParam{From}' because config".
             " option SendNoAutoResponseRegExp (/$NoAutoRegExp/i) is matching!",
        );
        return 1;
    }
    # --
    # check if original content isn't text/plain, don't use it
    # --
    if ($GetParam{'Content-Type'} && $GetParam{'Content-Type'} !~ /(text\/plain|\btext\b)/i) {
        $GetParam{Body} = "-> no quotable message <-";
    }
    # --
    # replace all scaned email x-headers with <OTRS_CUSTOMER_X-HEADER>
    # --
    foreach (keys %GetParam) {
        if (defined $GetParam{$_}) {
            $Param{Body} =~ s/<OTRS_CUSTOMER_$_>/$GetParam{$_}/gi;
        }
    }
    # --
    # replace some special stuff
    #  --
    $Param{Body} =~ s/<OTRS_TICKET_NUMBER>/$Param{TicketNumber}/gi;
    $Param{Body} =~ s/<OTRS_TICKET_ID>/$Param{TicketID}/gi;
    # prepare customer realname
    if ($Param{Body} =~ /<OTRS_CUSTOMER_REALNAME>/) {
        # get realname 
        my $From = '';
        if ($Article{CustomerUserID}) {
            $From = $Self->{CustomerUserObject}->CustomerName(UserLogin => $Article{CustomerUserID});
        }
        if (!$From) {
            $From = $GetParam{From} || '';
            $From =~ s/<.*>|\(.*\)|\"|;|,//g;
            $From =~ s/( $)|(  $)//g;
        }
        $Param{Body} =~ s/<OTRS_CUSTOMER_REALNAME>/$From/g;
    }
    # --
    # Arnold Ligtvoet - otrs@ligtvoet.org
    # get OTRS_CUSTOMER_SUBJECT from body
    # --
    if ($Param{Body} =~ /<OTRS_CUSTOMER_SUBJECT\[(.+?)\]>/) {
        my $TicketHook2 = $Self->{ConfigObject}->Get('TicketHook');
        my $SubRep = $GetParam{Subject} || 'No Std. Subject found!';
        my $SubjectChar = $1;
        $SubRep =~ s/\[$TicketHook2: $Param{TicketNumber}\] //g;
        $SubRep =~ s/^(.{$SubjectChar}).*$/$1 [...]/;
        $Param{Body} =~ s/<OTRS_CUSTOMER_SUBJECT\[.+?\]>/$SubRep/g;
    }
    # --
    # Arnold Ligtvoet - otrs@ligtvoet.org
    # get OTRS_EMAIL_DATE from body and replace with received date
    # --
    use POSIX qw(strftime);
    if ($Param{Body} =~ /<OTRS_EMAIL_DATE\[(.*)\]>/) {
        my $EmailDate = strftime('%A, %B %e, %Y at %T ', localtime);
        my $TimeZone = $1;
        $EmailDate .= "($TimeZone)";
        $Param{Body} =~ s/<OTRS_EMAIL_DATE\[.*\]>/$EmailDate/g;
    }
    # --
    # prepare subject (insert old subject)
    # --
    my $TicketHook = $Self->{ConfigObject}->Get('TicketHook');
    my $Subject = $Param{Subject} || 'No Std. Subject found!';
    if ($Subject =~ /<OTRS_CUSTOMER_SUBJECT\[(.+?)\]>/) {
        my $SubjectChar = $1;
        $GetParam{Subject} =~ s/\[$TicketHook: $Param{TicketNumber}\] //g;
        $GetParam{Subject} =~ s/^(.{$SubjectChar}).*$/$1 [...]/;
        $Subject =~ s/<OTRS_CUSTOMER_SUBJECT\[.+?\]>/$GetParam{Subject}/g;
    }
    $Subject = "[$TicketHook: $Param{TicketNumber}] $Subject";
    # --
    # prepare body (insert old email)
    # --
    if ($Param{Body} =~ /<OTRS_CUSTOMER_EMAIL\[(.+?)\]>/g) {
        my $Line = $1;
        my @Body = split(/\n/, $GetParam{Body});
        my $NewOldBody = '';
        foreach (my $i = 0; $i < $Line; $i++) {
            # 2002-06-14 patch of Pablo Ruiz Garcia
            # http://lists.otrs.org/pipermail/dev/2002-June/000012.html
            if ($#Body >= $i) {
                $NewOldBody .= "> $Body[$i]\n";
            }
        }
        chomp $NewOldBody;
        $Param{Body} =~ s/<OTRS_CUSTOMER_EMAIL\[.+?\]>/$NewOldBody/g;
    }
    # --
    # set new To address if customer user id is used
    # --
    my $Cc = '';
    my $ToAll = $GetParam{From};
    if ($Article{CustomerUserID}) {
        my %CustomerUser = $Self->{CustomerUserObject}->CustomerUserDataGet(
            User => $Article{CustomerUserID},
        );
        if ($CustomerUser{UserEmail} && $GetParam{From} !~ /\Q$CustomerUser{UserEmail}\E/i) {
            $Cc = $CustomerUser{UserEmail};
            $ToAll .= ', '.$Cc;
        }
    }
    # --
    # send email
    # --
    my $ArticleID = $Self->SendArticle(
        ArticleType => 'email-external',
        SenderType => 'system',
        TicketID => $Param{TicketID},
        HistoryType => $Param{HistoryType}, 
        HistoryComment => "Sent auto response to '$ToAll'",
        From => "$Param{Realname} <$Param{Address}>",
        To => $GetParam{From},
        Cc => $Cc,
        RealName => $Param{Realname},
        Charset => $Param{Charset},
        Subject => $Subject,
        UserID => $Param{UserID},
        Body => $Param{Body},
        InReplyTo => $GetParam{'Message-ID'},
        Loop => 1,
    );
    # --
    # log
    # --
    $Self->{LogObject}->Log(
        Priority => 'notice',
        Message => "Sent auto response ($Param{HistoryType}) for Ticket [$Param{TicketNumber}]".
         " (TicketID=$Param{TicketID}, ArticleID=$ArticleID) to '$ToAll'."
    );

    return 1;
}
# --

1;
