# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2024 Rother OSS GmbH, https://otobo.de/
# --
# $origin: otobo - 64d95578480e81261eefac7e2fc1c7686ee79038 - Kernel/Modules/AdminService.pm
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::Modules::AdminService;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;
# ---
# ITSMCore
# ---
use Kernel::System::VariableCheck qw(:all);
# ---

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # set pref for columns key
    $Self->{PrefKeyIncludeInvalid} = 'IncludeInvalid' . '-' . $Self->{Action};

    my %Preferences = $Kernel::OM->Get('Kernel::System::User')->GetPreferences(
        UserID => $Self->{UserID},
    );

    $Self->{IncludeInvalid} = $Preferences{ $Self->{PrefKeyIncludeInvalid} };

    # ---
    # RotherOSS
    # ---
    # get form id
    $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'FormID' );

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
    }

    $Self->{DynamicFieldLookup} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        ObjectType => 'Service',
    );
    # ---

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject  = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject   = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');

    $Param{IncludeInvalid} = $ParamObject->GetParam( Param => 'IncludeInvalid' );

    if ( defined $Param{IncludeInvalid} ) {
        $Kernel::OM->Get('Kernel::System::User')->SetPreferences(
            UserID => $Self->{UserID},
            Key    => $Self->{PrefKeyIncludeInvalid},
            Value  => $Param{IncludeInvalid},
        );

        $Self->{IncludeInvalid} = $Param{IncludeInvalid};
    }

# ---
# RotherOSS
# ---
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
# ---

# ---
# ITSMCore
# ---
    my $DynamicFieldObject   = $Kernel::OM->Get('Kernel::System::DynamicField');

    # get the dynamic field for ITSMCriticality
    my $DynamicFieldConfigArrayRef = $DynamicFieldObject->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket' ],
        FieldFilter => {
            ITSMCriticality => 1,
        },
    );

    # get the dynamic field value for ITSMCriticality
    my %PossibleValues;
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $DynamicFieldConfigArrayRef } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # get PossibleValues
        $PossibleValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldConfig->{Config}->{PossibleValues} || {};
    }

    # set the criticality list
    $Self->{CriticalityList} = $PossibleValues{ITSMCriticality};
# ---

    # ------------------------------------------------------------ #
    # service edit
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'ServiceEdit' ) {

        # header
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        # html output
        $Output .= $Self->_MaskNew(
            %Param,
        );
        $Output .= $LayoutObject->Footer();

        return $Output;
    }

    # ------------------------------------------------------------ #
    # service save
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ServiceSave' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # get params
        my %GetParam;
# ---
# ITSMCore
# ---
#        for (qw(ServiceID ParentID Name ValidID Comment)) {
#        for (qw(ServiceID ParentID Name ValidID Comment TypeID Criticality)) {
# ---

# ---
# RotherOSS
# ---
        @{ $GetParam{TicketTypeIDs} } = $ParamObject->GetArray( Param => 'TicketTypeIDs' );
        for (qw(ServiceID ParentID Name DescriptionShort Criticality ValidID Comment CustomerDefaultService DestQueueID)) {
# ---
            $GetParam{$_} = $ParamObject->GetParam( Param => $_ ) || '';
        }

# ---
# RotherOSS
# ---
        $GetParam{'DescriptionLong'} = $ParamObject->GetParam(
            Param => 'DescriptionLong',
            Raw   => 1
        ) || '';

        # get composed content type
        $GetParam{ContentType} = 'text/plain';
        if ( $LayoutObject->{BrowserRichText} ) {
            $GetParam{ContentType} = 'text/html';
        }

        # get dynamic field values
        my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

        for my $DynamicField ( @{ $Self->{DynamicFieldLookup} }) {

            $GetParam{ 'DynamicField_' . $DynamicField->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
                DynamicFieldConfig => $DynamicField,
                ParamObject        => $ParamObject,
                LayoutObject       => $LayoutObject,
            );
        }
# ---

        my %Error;

        if ( !$GetParam{Name} ) {
            $Error{'NameInvalid'} = 'ServerError';
        }

        my $ServiceName = '';
        if ( $GetParam{ParentID} ) {
            my $Prefix = $ServiceObject->ServiceLookup(
                ServiceID => $GetParam{ParentID},
            );

            if ($Prefix) {
                $ServiceName = $Prefix . "::";
            }
        }
        $ServiceName .= $GetParam{Name};

        if ( length $ServiceName > 200 ) {
            $Error{'NameInvalid'} = 'ServerError';
            $Error{LongName}      = 1;
        }

# ---
# RotherOSS
# ---
        if ( !$GetParam{DescriptionShort} ) {
            $Error{'DescriptionShortServerError'} = 'ServerError';
        }
# ---

        if ( !%Error ) {

            my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

            # save to database
            if ( $GetParam{ServiceID} eq 'NEW' ) {
                $GetParam{ServiceID} = $ServiceObject->ServiceAdd(
                    %GetParam,
                    UserID => $Self->{UserID},
                );
                if ( !$GetParam{ServiceID} ) {
                    $Error{Message} = $LogObject->GetLogEntry(
                        Type => 'Error',
                        What => 'Message',
                    );
                }
            }
            else {
                my $Success = $ServiceObject->ServiceUpdate(
                    %GetParam,
                    UserID => $Self->{UserID},
                );
                if ( !$Success ) {
                    $Error{Message} = $LogObject->GetLogEntry(
                        Type => 'Error',
                        What => 'Message',
                    );
                }
            }

            # set customer user service member
            $ServiceObject->CustomerUserServiceMemberAdd(
                CustomerUserLogin => '<DEFAULT>',
                ServiceID         => $GetParam{ServiceID},
                Active            => $GetParam{CustomerDefaultService},
                UserID            => $Self->{UserID},
            );

            if ( !%Error ) {

                # update preferences
                my %ServiceData = $ServiceObject->ServiceGet(
                    ServiceID => $GetParam{ServiceID},
                    UserID    => $Self->{UserID},
                );
                my %Preferences = ();
                if ( $ConfigObject->Get('ServicePreferences') ) {
                    %Preferences = %{ $ConfigObject->Get('ServicePreferences') };
                }
                for my $Item ( sort keys %Preferences ) {
                    my $Module = $Preferences{$Item}->{Module}
                        || 'Kernel::Output::HTML::ServicePreferences::Generic';

                    # load module
                    if ( !$Kernel::OM->Get('Kernel::System::Main')->Require($Module) ) {
                        return $LayoutObject->FatalError();
                    }

                    my $Object = $Module->new(
                        %{$Self},
                        ConfigItem => $Preferences{$Item},
                        Debug      => $Self->{Debug},
                    );
                    my $Note;
                    my @Params = $Object->Param( ServiceData => \%ServiceData );
                    if (@Params) {
                        my %GetParam = ();
                        for my $ParamItem (@Params) {
                            my @Array = $ParamObject->GetArray( Param => $ParamItem->{Name} );
                            $GetParam{ $ParamItem->{Name} } = \@Array;
                        }
                        if (
                            !$Object->Run(
                                GetParam    => \%GetParam,
                                ServiceData => \%ServiceData
                            )
                            )
                        {
                            $Note .= $LayoutObject->Notify( Info => $Object->Error() );
                        }
                    }
                }

# ---
# RotherOSS
# ---
                # get all attachments
                my @Attachments = $UploadCacheObject->FormIDGetAllFilesData(
                    FormID => $Self->{FormID},
                );

                # Get all existing attachments.
                my @ExistingAttachments = $ServiceObject->AttachmentIndex(
                    ServiceID  => $GetParam{ServiceID},
                    ShowInline => 1,
                    UserID     => $Self->{UserID},
                );

                # Lookup old inline attachments (initially loaded to AdminService.pm screen)
                # and push to Attachments array if they still exist in the form.
                ATTACHMENT:
                for my $Attachment (@ExistingAttachments) {
                    if (
                        $ServiceData{DescriptionLong}
                        =~ m{ Action=AgentITSMServiceZoom;Subaction=DownloadAttachment;ServiceID=$GetParam{ServiceID};FileID=$Attachment->{FileID} }msx
                        )
                    {
                        # Get the existing inline attachment data.
                        my %File = $ServiceObject->AttachmentGet(
                            ServiceID => $GetParam{ServiceID},
                            FileID    => $Attachment->{FileID},
                            UserID    => $Self->{UserID},
                        );

                        push @Attachments, {
                            Content     => $File{Content},
                            ContentType => $File{ContentType},
                            Filename    => $File{Filename},
                            Filesize    => $File{Filesize},
                            Disposition => 'inline',
                            FileID      => $Attachment->{FileID},
                        };
                    }
                }

                # Build a lookup hash of the new attachments.
                my %NewAttachment;
                for my $Attachment (@Attachments) {

                    # The key is the filename + filesize + content type.
                    my $Key = $Attachment->{Filename}
                        . $Attachment->{Filesize}
                        . $Attachment->{ContentType};

                    # Append content id if available (for new inline images).
                    if ( $Attachment->{ContentID} ) {
                        $Key .= $Attachment->{ContentID};
                    }

                    # Store all of the new attachment data.
                    $NewAttachment{$Key} = $Attachment;
                }

                # Check the existing attachments.
                ATTACHMENT:
                for my $Attachment (@ExistingAttachments) {

                # The key is the filename + filesizeraw + content type (no content id, as existing attachments don't have it).
                    my $Key = $Attachment->{Filename}
                        . $Attachment->{FilesizeRaw}
                        . $Attachment->{ContentType};

                    # Attachment is already existing, we can delete it from the new attachment hash.
                    if ( $NewAttachment{$Key} ) {
                        delete $NewAttachment{$Key};
                    }

                    # Existing attachment is no longer in new attachments hash.
                    else {

                        # Delete the existing attachment.
                        my $DeleteSuccessful = $ServiceObject->AttachmentDelete(
                            ServiceID => $GetParam{ServiceID},
                            FileID    => $Attachment->{FileID},
                            UserID    => $Self->{UserID},
                        );
                        if ( !$DeleteSuccessful ) {
                            return $LayoutObject->FatalError();
                        }
                    }
                }

                for my $Attachment (@Attachments) {
                    # Upload attachments.
                    my $FileID = $ServiceObject->AttachmentAdd(
                        ServiceID   => $GetParam{ServiceID},
                        FileName    => $Attachment->{Filename},
                        ContentSize => $Attachment->{Filesize},
                        ContentType => $Attachment->{ContentType},
                        Content     => $Attachment->{Content},
                        Inline      => 1,
                        UserID      => $Self->{UserID},
                    );

                    if ( !$FileID ) {
                        return $LayoutObject->FatalError();
                    }

                    # Rewrite the URLs of the inline images for the uploaded pictures.
                    my $Success = $ServiceObject->ServiceInlineAttachmentURLUpdate(
                        Attachment => $Attachment,
                        FormID     => $Self->{FormID},
                        ServiceID  => $GetParam{ServiceID},
                        FileID     => $FileID,
                        UserID     => $Self->{UserID},
                    );
                    if ( !$Success ) {
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "Could not update the inline image URLs "
                                . "for ServiceID '$GetParam{ServiceID}'!",
                        );
                    }
                }

                $UploadCacheObject->FormIDRemove( FormID => $Self->{FormID} );

                DYNAMICFIELD:
                for my $DynamicField ( @{ $Self->{DynamicFieldLookup} } ) {
                    my $ValueSet = $DynamicFieldBackendObject->ValueSet(
                        DynamicFieldConfig => $DynamicField,
                        ObjectID           => $GetParam{ServiceID},
                        Value              => $GetParam{ 'DynamicField_' . $DynamicField->{Name} },
                        UserID             => $Self->{UserID},
                    );

                    if ( !$ValueSet ) {
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => $LayoutObject->{LanguageObject}->Translate(
                                'Unable to set value for dynamic field %s!',
                                $DynamicField->{Name},
                            ),
                        );
                        next DYNAMICFIELD;
                    }
                }
# Rother OSS / ServiceCatalog
        # Create Acl if config is enabled
        # We create one Acl per Ticket-Type
        if ( $ConfigObject->Get('ServiceCatalog::CreateTypeServiceRelatedAcls') ) {
            for my $TicketType ( @{ $GetParam{TicketTypeIDs} } ) {
                    my $Success = $ServiceObject->UpdateTypServiceACL(
                        TicketTypeID => $TicketType,
                        ServiceID   => $GetParam{ServiceID},
                        ServiceValid => $GetParam{ValidID},
                        UserID => 1,
                    );
                }
            }
# EO Rother OSS
# ---

                # if the user would like to continue editing the service, just redirect to the edit screen
                if (
                    defined $ParamObject->GetParam( Param => 'ContinueAfterSave' )
                    && ( $ParamObject->GetParam( Param => 'ContinueAfterSave' ) eq '1' )
                    )
                {
                    my $ID = $ParamObject->GetParam( Param => 'ServiceID' ) || '';
                    return $LayoutObject->Redirect(
                        OP => "Action=$Self->{Action};Subaction=ServiceEdit;ServiceID=$ID"
                    );
                }
                else {

                    # otherwise return to overview
                    return $LayoutObject->Redirect( OP => "Action=$Self->{Action}" );
                }
            }
        }

        # something went wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $Error{Message}
            ? $LayoutObject->Notify(
                Priority => 'Error',
                Info     => $Error{Message},
            )
            : '';

        # html output
        $Output .= $Self->_MaskNew(
            %Error,
            %GetParam,
            %Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;

    }

    # ------------------------------------------------------------ #
    # service overview
    # ------------------------------------------------------------ #
    else {

        # output header
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        # check if service is enabled to use it here
        if ( !$ConfigObject->Get('Ticket::Service') ) {
            $Output .= $LayoutObject->Notify(
                Priority => 'Error',
                Data     => $LayoutObject->{LanguageObject}->Translate( "Please activate %s first!", "Service" ),
                Link     =>
                    $LayoutObject->{Baselink}
                    . 'Action=AdminSystemConfiguration;Subaction=View;Setting=Ticket%3A%3AService;',
            );
        }

        # output overview
        $LayoutObject->Block(
            Name => 'Overview',
            Data => { %Param, },
        );

        $LayoutObject->Block( Name => 'ActionList' );
        $LayoutObject->Block( Name => 'ActionAdd' );
        $LayoutObject->Block(
            Name => 'IncludeInvalid',
            Data => {
                IncludeInvalid        => $Self->{IncludeInvalid},
                IncludeInvalidChecked => $Self->{IncludeInvalid} ? 'checked' : '',
            },
        );
        $LayoutObject->Block( Name => 'Filter' );

        # output overview result
        $LayoutObject->Block(
            Name => 'OverviewList',
            Data => { %Param, },
        );

        # get service list
        my $ServiceList = $ServiceObject->ServiceListGet(
            Valid  => $Self->{IncludeInvalid} ? 0 : 1,
            UserID => $Self->{UserID},
        );

        # if there are any services defined, they are shown
        if ( @{$ServiceList} ) {

            # get valid list
            my %ValidList = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();

            # sort the service list by long service name
            @{$ServiceList} = sort { $a->{Name} . '::' cmp $b->{Name} . '::' } @{$ServiceList};

            for my $ServiceData ( @{$ServiceList} ) {

                # output row
                $LayoutObject->Block(
                    Name => 'OverviewListRow',
                    Data => {
                        %{$ServiceData},
                        Valid => $ValidList{ $ServiceData->{ValidID} },
                    },
                );
            }

        }

        # otherwise a no data found msg is displayed
        else {
            $LayoutObject->Block(
                Name => 'NoDataFoundMsg',
                Data => {},
            );
        }

        # generate output
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminService',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();

        return $Output;
    }
    return;
}

sub _MaskNew {
    my ( $Self, %Param ) = @_;

    my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');
    my %ServiceData;

    # get params
    $ServiceData{ServiceID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => "ServiceID" );
    if ( $ServiceData{ServiceID} ne 'NEW' ) {
        %ServiceData = $ServiceObject->ServiceGet(
            ServiceID => $ServiceData{ServiceID},
            UserID    => $Self->{UserID},
        );
    }

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    # ---
    # RotherOSS
    # ---
    $Param{FormID} = $Self->{FormID};

    my $HTMLUtilsObject = $Kernel::OM->Get('Kernel::System::HTMLUtils');
    # ---

    # output overview
    $LayoutObject->Block(
        Name => 'Overview',
        Data => {
            ServiceID   => $ServiceData{ServiceID},
            ServiceName => $ServiceData{Name},
            %Param,
        },
    );

    # ---
    # RotherOSS
    # ---

    # output service option reference
    $LayoutObject->Block(
        Name => 'ServiceReference',
    );
    # ---

    $LayoutObject->Block( Name => 'ActionList' );
    $LayoutObject->Block( Name => 'ActionOverview' );

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get list type
    my $ListType = $ConfigObject->Get('Ticket::Frontend::ListType');

    # generate ParentOptionStrg
    my $KeepChildren = $ConfigObject->Get('Ticket::Service::KeepChildren') // 0;
    my %ServiceList  = $ServiceObject->ServiceList(
        Valid        => !$KeepChildren,
        KeepChildren => $KeepChildren,
        UserID       => $Self->{UserID},
    );
    $ServiceData{ParentOptionStrg} = $LayoutObject->BuildSelection(
        Data           => \%ServiceList,
        Name           => 'ParentID',
        SelectedID     => $Param{ParentID} || $ServiceData{ParentID},
        PossibleNone   => 1,
        TreeView       => ( $ListType eq 'tree' ) ? 1 : 0,
        DisabledBranch => $ServiceData{Name},
        Translation    => 0,
        Class          => 'Modernize',
    );

# ---
# RotherOSS
# ---
    my %TicketTypeList = $Kernel::OM->Get('Kernel::System::Type')->TypeList(
        Valid => 1,
    );

    # Build ticket type selection.
    $ServiceData{TicketTypeOptionStrg} = $LayoutObject->BuildSelection(
        Data         => \%TicketTypeList,
        Name         => 'TicketTypeIDs',
        Multiple     => 1,
        PossibleNone => 1,
        SelectedID   => $Param{TicketTypeIDs} || $ServiceData{TicketTypeIDs},
        Class        => 'Modernize',
    );

    # Move Ticket to queue
    my %TicketQueueList = $Kernel::OM->Get('Kernel::System::Queue')->GetAllQueues(
        Valid => 1,
    );

    # Build ticket queue selection.
    $ServiceData{TicketQueueOptionStrg} = $LayoutObject->BuildSelection(
        Data         => \%TicketQueueList,
        Name         => 'DestQueueID',
        Multiple     => 0,
        PossibleNone => 1,
        TreeView       => ( $ListType eq 'tree' ) ? 1 : 0,
        SelectedID   => $Param{DestQueueID} || $ServiceData{DestQueueID},
        Class        => 'Modernize',
    );

# Rother OSS: Default Customer Service
    my %DefaultServices = $ServiceObject->CustomerUserServiceMemberList(
        CustomerUserLogin => '<DEFAULT>',
        Result            => 'HASH',
        DefaultServices   => 1,
    );

    $ServiceData{CustomerServiceChecked} = '';

    DEFAULTSERVICE:
    for my $DefService ( keys %DefaultServices ) {

        if ( $ServiceData{ServiceID} eq $DefService ) {
            $ServiceData{CustomerServiceChecked} = 'checked';
            last DEFAULTSERVICE;
        }
    }
# EO Rother OSS
    # add rich text editor
    if ( $LayoutObject->{BrowserRichText} ) {

        # reformat from plain to html
        if ( $Param{ContentType} && $Param{ContentType} =~ /text\/plain/i ) {
            $Param{DescriptionLong} = $HTMLUtilsObject->ToHTML(
                String => $Param{DescriptionLong},
            );
        }
    }
    else {

        # reformat from html to plain
        if ( $Param{ContentType} && $Param{ContentType} =~ /text\/html/i ) {
            $Param{DescriptionLong} = $HTMLUtilsObject->ToAscii(
                String => $Param{DescriptionLong},
            );
        }
    }

    # add rich text editor
    if ( $LayoutObject->{BrowserRichText} ) {

        # set up rich text editor
        $LayoutObject->SetRichTextParameters(
            Data => \%Param,
        );
    }
# ---

# ---
# ITSMCore
# ---
#    # generate TypeOptionStrg
#    my $TypeList = $Kernel::OM->Get('Kernel::System::GeneralCatalog')->ItemList(
#        Class => 'ITSM::Service::Type',
#    );

#    # build the type dropdown
#    $ServiceData{TypeOptionStrg} = $LayoutObject->BuildSelection(
#        Data       => $TypeList,
#        Name       => 'TypeID',
#        SelectedID => $Param{TypeID} || $ServiceData{TypeID},
#        Class      => 'Modernize',
#    );

    # build the criticality dropdown
    $ServiceData{CriticalityOptionStrg} = $LayoutObject->BuildSelection(
        Data       => $Self->{CriticalityList},
        Name       => 'Criticality',
        SelectedID => $Param{Criticality} || $ServiceData{Criticality},
        Class      => 'Modernize',
    );
# ---

    # get valid list
    my %ValidList        = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();
    my %ValidListReverse = reverse %ValidList;

    $ServiceData{ValidOptionStrg} = $LayoutObject->BuildSelection(
        Data       => \%ValidList,
        Name       => 'ValidID',
        SelectedID => $ServiceData{ValidID} || $ValidListReverse{valid},
        Class      => 'Modernize',
    );

    # output service edit
    $LayoutObject->Block(
        Name => 'ServiceEdit',
        Data => { %Param, %ServiceData, },
    );

# ---
# RotherOSS
# ---
    # Get dynamic field backend object.
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $ParamObject               = $Kernel::OM->Get('Kernel::System::Web::Request');

    DYNAMICFIELD:
    for my $DynamicField ( @{ $Self->{DynamicFieldLookup} } ) {

        my $ValueGet = $DynamicFieldBackendObject->ValueGet(
            DynamicFieldConfig => $DynamicField,
            ObjectID           => $ServiceData{ServiceID},
            UserID             => $Self->{UserID},
        );

        # Get HTML for dynamic field
        my $DynamicFieldHTML = $DynamicFieldBackendObject->EditFieldRender(
            DynamicFieldConfig => $DynamicField,
            Value              => $ValueGet,
            # Mandatory          => 0,
            LayoutObject       => $LayoutObject,
            ParamObject        => $ParamObject,

            # Server error, if any
            # %{ $Param{Errors}->{ $Entry->[0] } },
        );

        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldHTML);

        $LayoutObject->Block(
            Name => 'DynamicField',
            Data => {
                Name  => $DynamicField->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );
    }
# ---

    # show each preferences setting
    my %Preferences = ();
    if ( $ConfigObject->Get('ServicePreferences') ) {
        %Preferences = %{ $ConfigObject->Get('ServicePreferences') };
    }
    for my $Item ( sort keys %Preferences ) {
        my $Module = $Preferences{$Item}->{Module}
            || 'Kernel::Output::HTML::ServicePreferences::Generic';

        # load module
        if ( !$Kernel::OM->Get('Kernel::System::Main')->Require($Module) ) {
            return $LayoutObject->FatalError();
        }
        my $Object = $Module->new(
            %{$Self},
            ConfigItem => $Preferences{$Item},
            Debug      => $Self->{Debug},
        );
        my @Params = $Object->Param( ServiceData => \%ServiceData );
        if (@Params) {
            for my $ParamItem (@Params) {
                $LayoutObject->Block(
                    Name => 'Item',
                    Data => { %Param, },
                );
                if (
                    ref( $ParamItem->{Data} ) eq 'HASH'
                    || ref( $Preferences{$Item}->{Data} ) eq 'HASH'
                    )
                {
                    my %BuildSelectionParams = (
                        %{ $Preferences{$Item} },
                        %{$ParamItem},
                    );
                    $BuildSelectionParams{Class} = join( ' ', $BuildSelectionParams{Class} // '', 'Modernize' );

                    $ParamItem->{'Option'} = $LayoutObject->BuildSelection(
                        %BuildSelectionParams,
                    );
                }
                $LayoutObject->Block(
                    Name => $ParamItem->{Block} || $Preferences{$Item}->{Block} || 'Option',
                    Data => {
                        %{ $Preferences{$Item} },
                        %{$ParamItem},
                    },
                );
            }
        }
    }

    # generate output
    return $LayoutObject->Output(
        TemplateFile => 'AdminService',
        Data         => \%Param
    );
}

1;
