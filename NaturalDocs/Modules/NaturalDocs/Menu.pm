###############################################################################
#
#   Package: NaturalDocs::Menu
#
###############################################################################
#
#   A package handling the menu's contents and state.
#
#   Usage and Dependencies:
#
#       - The <Event Handlers> can be called by <NaturalDocs::Project> immediately.
#
#       - Prior to initialization, <NaturalDocs::Project> must be initialized, and all files that have been changed must be run
#         through <NaturalDocs::Parser::ParseForInformation()>.
#
#       - To initialize, call <LoadAndUpdate()>.  Afterwards, all other functions are available.
#
#       - To save the changes back to disk, call <Save()>.
#
###############################################################################

# This file is part of Natural Docs, which is Copyright � 2003 Greg Valure
# Natural Docs is licensed under the GPL

use Tie::RefHash;

use NaturalDocs::Menu::Entry;
use NaturalDocs::Menu::Error;

use strict;
use integer;

package NaturalDocs::Menu;


#
#   Constants: Constants
#
#   MAXFILESINGROUP - The maximum number of file entries that can be present in a group before it becomes a candidate for
#                                  sub-grouping.
#   MINFILESINNEWGROUP - The minimum number of file entries that must be present in a group before it will be automatically
#                                        created.  This is *not* the number of files that must be in a group before it's deleted.
#
use constant MAXFILESINGROUP => 6;
use constant MINFILESINNEWGROUP => 3;


###############################################################################
# Group: Variables

#
#   hash: menuSynonyms
#
#   A hash of the text synonyms for the menu tokens.  The keys are the lowercase synonyms, and the values are one of
#   the <Menu Entry Types>.
#
my %menuSynonyms = (
                                        'title'        => ::MENU_TITLE(),
                                        'subtitle'   => ::MENU_SUBTITLE(),
                                        'sub-title'  => ::MENU_SUBTITLE(),
                                        'group'     => ::MENU_GROUP(),
                                        'file'         => ::MENU_FILE(),
                                        'text'        => ::MENU_TEXT(),
                                        'link'        => ::MENU_LINK(),
                                        'url'         => ::MENU_LINK(),
                                        'footer'    => ::MENU_FOOTER(),
                                        'copyright' => ::MENU_FOOTER(),
                                        'index'     => ::MENU_INDEX(),
                                        'format'   => ::MENU_FORMAT()
                                    );

#
#   hash: indexSynonyms
#
#   A hash of the text synonyms for the index modifiers.  The keys are the all lowercase synonyms, and the values are the
#   associated <Topic Types>.
#
my %indexSynonyms = (
                                        'function' => ::TOPIC_FUNCTION(),
                                        'func' => ::TOPIC_FUNCTION(),
                                        'class' => ::TOPIC_CLASS(),
                                        'package' => ::TOPIC_CLASS(),
                                        'file' => ::TOPIC_FILE(),
                                        'variable' => ::TOPIC_VARIABLE(),
                                        'var' => ::TOPIC_VARIABLE(),
                                        'type' => ::TOPIC_TYPE(),
                                        'typedef' => ::TOPIC_TYPE(),
                                        'const' => ::TOPIC_CONSTANT(),
                                        'constant' => ::TOPIC_CONSTANT()
                                    );

#
#   hash: indexNames
#
#   A hash of text equivalents of the possible index types.  The keys are the <Topic Types>, and the values are the strings.
#
my %indexNames = (
                                    ::TOPIC_FUNCTION() => 'Function',
                                    ::TOPIC_CLASS() => 'Class',
                                    ::TOPIC_FILE() => 'File',
                                    ::TOPIC_VARIABLE() => 'Variable',
                                    ::TOPIC_TYPE() => 'Type',
                                    ::TOPIC_CONSTANT() => 'Constant'
                              );


#
#   hash: indexPluralNames
#
#   A hash of plural text equivalents of the possible index types.  The keys are the <Topic Types>, and the values are the strings.
#
my %indexPluralNames = (
                                        ::TOPIC_FUNCTION() => 'Functions',
                                        ::TOPIC_CLASS() => 'Classes',
                                        ::TOPIC_FILE() => 'Files',
                                        ::TOPIC_VARIABLE() => 'Variables',
                                        ::TOPIC_TYPE() => 'Types',
                                        ::TOPIC_CONSTANT() => 'Constants'
                                      );


#
#   bool: hasChanged
#
#   Whether the menu changed or not, regardless of why.
#
my $hasChanged;

#
#   bool: fileChanged
#
#   Whether the menu file has changed, usually meaning the user edited it.
#
my $fileChanged;

#
#   Object: menu
#
#   The parsed menu file.  Is stored as a <MENU_GROUP> <NaturalDocs::Menu::Entry> object, with the top-level entries being
#   stored as the group's content.  This is done because it makes a number of functions simpler to implement, plus it allows group
#   flags to be set on the top-level.  However, it is exposed externally via <Content()> as an arrayref.
#
#   This structure will only contain objects for <MENU_FILE>, <MENU_GROUP>, <MENU_TEXT>, <MENU_LINK>, and
#   <MENU_INDEX> entries.  Other types, such as <MENU_TITLE>, are stored in variables such as <title>.
#
my $menu;

#
#   hash: defaultTitlesChanged
#
#   An existence hash of default titles that have changed, since <OnDefaultTitleChange()> will be called before
#   <LoadAndUpdate()>.  Collects them to be applied later.  The keys are the file names.
#
my %defaultTitlesChanged;

#
#   String: title
#
#   The title of the menu.
#
my $title;

#
#   String: subTitle
#
#   The sub-title of the menu.
#
my $subTitle;

#
#   String: footer
#
#   The footer for the documentation.
#
my $footer;

#
#   hash: indexes
#
#   An existence hash of all the defined index types appearing in the menu.  Keys are the <Topic Types> or * for the general
#   index.
#
my %indexes;

#
#   hash: previousIndexes
#
#   An existence hash of all the indexes that appeared in the menu last time.  Keys are the <Topic Types> or * for the general
#   index.
#
my %previousIndexes;

#
#   hash: bannedIndexes
#
#   An existence hash of all the indexes that the user has manually deleted, and thus should not be added back to the menu
#   automatically.  Keys are the <Topic Types> or * for the general index.
#
my %bannedIndexes;


###############################################################################
# Group: Files

#
#   File: NaturalDocs_Menu.txt
#
#   The file used to generate the menu.
#
#   Format:
#
#       The file is plain text.  Blank lines can appear anywhere and are ignored.  Tags and their content must be completely
#       contained on one line with the exception of Group's braces.
#
#       > # [comment]
#
#       The file supports single-line comments via #.  They can appear alone on a line or after content.
#
#       > Format: [version]
#       > Title: [title]
#       > SubTitle: [subtitle]
#       > Footer: [footer]
#
#       The file format version, menu title, subtitle, and footer are specified as above.  Each can only be specified once, with
#       subsequent ones being ignored.  Subtitle is ignored if Title is not present.  Format must be the first entry in the file.  If it's
#       not present, it's assumed the menu is from version 0.95 or earlier, since it was added with 1.0.
#
#       > File: [title] ([file name])
#       > File: [title] (auto-title, [file name])
#       > File: [title] (no auto-title, [file name])
#
#       Files are specified as above.  If "no auto-title" is specified, the title on the line is used.  If not, the title is ignored and the
#       default file title is used instead.  Auto-title defaults to on, so specifying "auto-title" is for compatibility only.
#
#       > Group: [title]
#       > Group: [title] { ... }
#
#       Groups are specified as above.  If no braces are specified, the group's content is everything that follows until the end of the
#       file, the next group (braced or unbraced), or the closing brace of a parent group.  Group braces are the only things in this
#       file that can span multiple lines.
#
#       There is no limitations on where the braces can appear.  The opening brace can appear after the group tag, on its own line,
#       or preceding another tag on a line.  Similarly, the closing brace can appear after another tag or on its own line.  Being
#       bitchy here would just get in the way of quick and dirty editing; the package will clean it up automatically when it writes it
#       back to disk.
#
#       > Text: [text]
#
#       Arbitrary text is specified as above.  As with other tags, everything must be contained on the same line.
#
#       > Link: [URL]
#       > Link: [title] ([URL])
#
#       External links can be specified as above.  If the titled form is not used, the URL is used as the title.
#
#       > Index: [name]
#       > [modifier] Index: [name]
#
#       Indexes are specified with the types above.  Valid modifiers are defined in <indexSynonyms> and include Function and
#       Class.  If no modifier is specified, the line specifies a general index.
#
#       > Don't Index: [type]
#       > Don't Index: [type], [type], ...
#
#       The option above prevents indexes that exist but are not on the menu from being automatically added.  "General" is
#       used to specify the general index.
#
#   Revisions:
#
#       1.1:
#
#           - Added the "don't index" line.
#
#           This is also the point where indexes were automatically added and removed, so all index entries from prior revisions
#           were manually added and are not guaranteed to contain anything.
#
#       1.0:
#
#           - Added the format line.
#           - Added the "no auto-title" attribute.
#           - Changed the file entry default to auto-title.
#
#           This is also the point where auto-organization and better auto-titles were introduced.  All groups in prior revisions were
#           manually added, with the exception of a top-level Other group where new files were automatically added if there were
#           groups defined.
#
#       0.9:
#
#           - Added index entries.
#

#
#   File: NaturalDocs.m
#
#   The file used to store the previous state of the menu so as to detect changes.  Is named NaturalDocs.m instead of something
#   like NaturalDocs.menu to avoid confusion with <NaturalDocs_Menu.txt>.  This one is not user-editable so we don't want
#   people opening it by accident.
#
#   > [BINARY_FORMAT]
#
#   The file is binary, so the first byte is the <BINARY_FORMAT> token.
#
#   > [app version]
#
#   Immediately after is the application version it was generated with.  Manage with the binary functions in
#   <NaturalDocs::Version>.
#
#   > [UInt8: 0 (end group)]
#   > [UInt8: MENU_FILE] [UInt8: noAutoTitle] [AString16: title] [AString16: target]
#   > [UInt8: MENU_GROUP] [AString16: title]
#   > [UInt8: MENU_INDEX] [AString16: title] [UInt8: type (0 for general)]
#   > [UInt8: MENU_LINK] [AString16: title] [AString16: url]
#   > [UInt8: MENU_TEXT] [AString16: text]
#
#   The first UInt8 of each following line is either zero or one of the <Menu Entry Types>.  What follows is contextual.  AString16s
#   are big-endian UInt16's followed by that many ASCII characters.
#
#   There are no entries for title, subtitle, or footer.  Only the entries present in <menu>.
#
#   Dependencies:
#
#       - Because the type is represented by a UInt8, the <Menu Entry Types> must all be <= 255.
#       - Because the index target is represented by a UInt8, the <Topic Types> must all be <= 255.
#
#   Revisions:
#
#       Prior to 1.0, the file was a text file consisting of the app version and a line which was a tab-separated list of the indexes
#       present in the menu.  * meant the general index.
#
#       Prior to 0.95, the version line was 1.  Test for "1" instead of "1.0" to distinguish.
#
#       Prior to 0.9, this file didn't exist.
#


###############################################################################
# Group: File Functions

#
#   Function: LoadAndUpdate
#
#   Loads the menu file from disk and updates it.  Will add, remove, rearrange, and remove auto-titling from entries as
#   necessary.
#
sub LoadAndUpdate
    {
    my ($errors, $filesInMenu, $oldLockedTitles) = LoadMenuFile();

    if (defined $errors)
        {  HandleErrors($errors);  };  # HandleErrors will end execution if necessary.

    my ($previousMenu, $previousIndexes, $previousFiles) = LoadPreviousMenuStateFile();

    if (defined $previousIndexes)
        {  %previousIndexes = %$previousIndexes;  };

    if (defined $previousFiles)
        {  LockUserTitleChanges($previousFiles);  };

    # Don't need these anymore.  We keep this level of detail because it may be used more in the future.
    $previousMenu = undef;
    $previousFiles = undef;
    $previousIndexes = undef;

    # We flag title changes instead of actually performing them at this point for two reasons.  First, contents of groups are still
    # subject to change, which would affect the generated titles.  Second, we haven't detected the sort order yet.  Changing titles
    # could make groups appear unalphabetized when they were beforehand.

    my $updateAllTitles;

    # If the menu file changed, we can't be sure which groups changed and which didn't without a comparison, which really isn't
    # worth the trouble.  So we regenerate all the titles instead.  Also, since LoadPreviousMenuStateFile() isn't affected by
    # NaturalDocs::Settings::RebuildData(), we'll pick up some of the slack here.  We'll regenerate all the titles in this case too.
    if ($fileChanged || NaturalDocs::Settings::RebuildData())
        {  $updateAllTitles = 1;  }
    else
        {  FlagAutoTitleChanges();  };

    # We add new files before deleting old files so their presence still affects the grouping.  If we deleted old files first, it could
    # throw off where to place the new ones.

    AutoPlaceNewFiles($filesInMenu);

    my $numberRemoved = RemoveDeadFiles();

    CheckForTrashedMenu(scalar keys %$filesInMenu, $numberRemoved);

    BanAndUnbanIndexes();

    # Index groups need to be detected before adding new ones.

    DetectIndexGroups();

    AddAndRemoveIndexes();

   # We wait until after new files are placed to remove dead groups because a new file may save a group.

    RemoveDeadGroups();

    CreateDirectorySubGroups();

    # We detect the sort before regenerating the titles so it doesn't get thrown off by changes.  However, we do it after deleting
    # dead entries and moving things into subgroups because their removal may bump it into a stronger sort category (i.e.
    # SORTFILESANDGROUPS instead of just SORTFILES.)  New additions don't factor into the sort.

    DetectOrder($updateAllTitles);

    GenerateAutoFileTitles($updateAllTitles);

    # Check if any of the generated titles are different from the old locked titles.  If so, restore the old locked titles and lock the
    # entries.  We do this test because, due to the crappy auto-titling present pre-1.0, users may have edited the titles to do the
    # exact same effect as the new auto-titling system.  If that's the case, we want to unlock those titles.

    if (defined $oldLockedTitles)
        {
        while (my ($file, $oldLockedTitle) = each %$oldLockedTitles)
            {
            my $fileEntry = $filesInMenu->{$file};

            if (defined $fileEntry && $fileEntry->Title() ne $oldLockedTitle)
                {
                $fileEntry->SetTitle($oldLockedTitle);
                $fileEntry->SetFlags( $fileEntry->Flags() | ::MENU_FILE_NOAUTOTITLE() );
                };
            };
        };

    ResortGroups($updateAllTitles);


    # Don't need this anymore.
    %defaultTitlesChanged = ( );
    };



#
#   Function: LoadUnchanged
#
#   Loads the menu, assuming neither the menu file nor any of the source files have changed, and thus it definitely doesn't need
#   to be updated.
#
sub LoadUnchanged
    {
    my ($errors, $filesInMenu, $oldLockedTitles) = LoadMenuFile();

    if (defined $errors)
        {  HandleErrors($errors);  };  # HandleErrors will end execution if necessary.

    my ($previousMenu, $previousIndexes, $previousFiles) = LoadPreviousMenuStateFile();

    if (defined $previousIndexes)
        {  %previousIndexes = %$previousIndexes;  };
    };


#
#   Function: Save
#
#   Writes the changes to the menu files.
#
sub Save
    {
    if ($hasChanged)
        {
        SaveMenuFile();
        SavePreviousMenuStateFile();
        };
    };


###############################################################################
# Group: Information Functions

#
#   Function: HasChanged
#
#   Returns whether the menu has changed or not.
#
sub HasChanged
    {  return $hasChanged;  };

#
#   Function: Content
#
#   Returns the parsed menu as an arrayref of <NaturalDocs::Menu::Entry> objects.  Do not change the arrayref.
#
#   The arrayref will only contain <MENU_FILE>, <MENU_GROUP>, <MENU_INDEX>, <MENU_TEXT>, and <MENU_LINK>
#   entries.  Entries such as <MENU_TITLE> are parsed out and are only accessible via functions such as <Title()>.
#
sub Content
    {  return $menu->GroupContent();  };

#
#   Function: Title
#
#   Returns the title of the menu, or undef if none.
#
sub Title
    {  return $title;  };

#
#   Function: SubTitle
#
#   Returns the sub-title of the menu, or undef if none.
#
sub SubTitle
    {  return $subTitle;  };

#
#   Function: Footer
#
#   Returns the footer of the documentation, or undef if none.
#
sub Footer
    {  return $footer;  };

#
#   Function: Indexes
#
#   Returns an existence hashref of all the indexes appearing in the menu.  The keys are the <Topic Types> or * for the general
#   index.  Do not change the arrayref.
#
sub Indexes
    {  return \%indexes;  };

#
#   Function: PreviousIndexes
#
#   Returns an existence hashref of all the indexes that previously appeared in the menu.  The keys are the <Topic Types> or *
#   for the general index.  Do not change the arrayref.
#
sub PreviousIndexes
    {  return \%previousIndexes;  };


###############################################################################
# Group: Event Handlers
#
#   These functions are called by <NaturalDocs::Project> only.  You don't need to worry about calling them.  For example, when
#   changing the default menu title of a file, you only need to call <NaturalDocs::Project::SetDefaultMenuTitle()>.  That function
#   will handle calling <OnDefaultTitleChange()>.


#
#   Function: OnFileChange
#
#   Called by <NaturalDocs::Project> if it detects that the menu file has changed.
#
sub OnFileChange
    {
    $fileChanged = 1;
    $hasChanged = 1;
    };


#
#   Function: OnDefaultTitleChange
#
#   Called by <NaturalDocs::Project> if the default menu title of a source file has changed.
#
#   Parameters:
#
#       file    - The source file that had its default menu title changed.
#
sub OnDefaultTitleChange #(file)
    {
    my $file = shift;

    # Collect them for later.  We'll deal with them in LoadAndUpdate().

    $defaultTitlesChanged{$file} = 1;
    };


###############################################################################
# Group: Support Functions


#
#   Function: LoadMenuFile
#
#   Loads and parses the menu file <NaturalDocs_Menu.txt>.  This will fill <menu>, <title>, <subTitle>, <footer>, <indexes>,
#   and <bannedIndexes>.
#
#   Returns:
#
#       The array ( errors, filesInMenu, oldLockedTitles ).
#
#       errors - An arrayref of errors appearing in the file, each one being an <NaturalDocs::Menu::Error> object.  Undef if none.
#       filesInMenu - A hashref of all the source files that appear in the menu.  The keys are the file names, and the values are
#                          references to their entries in <menu>.  Will be an empty hashref if none.
#       oldLockedTitles - A hashref of all the locked titles in pre-1.0 menu files.  The keys are the file names, and the values are
#                                the old locked titles.  Will be undef if none.  If a file entry from a pre-1.0 file was locked, it's
#                                entry in <menu> is unlocked and its title is placed here instead, so that it can be compared with the
#                                generated title and only locked again if absolutely necessary.
#
sub LoadMenuFile
    {
    my $errors = [ ];
    my $filesInMenu = { };
    my $oldLockedTitles = { };

    # A stack of Menu::Entry object references as we move through the groups.
    my @groupStack;

    $menu = NaturalDocs::Menu::Entry->New(::MENU_GROUP(), undef, undef, undef);
    my $currentGroup = $menu;

    # Whether we're currently in a braceless group, since we'd have to find the implied end rather than an explicit one.
    my $inBracelessGroup;

    # Whether we're right after a group token, which is the only place there can be an opening brace.
    my $afterGroupToken;

    my $lineNumber = 1;

    if (open(MENUFILEHANDLE, '<' . NaturalDocs::Project::MenuFile()))
        {
        my $menuFileContent;
        read(MENUFILEHANDLE, $menuFileContent, -s MENUFILEHANDLE);
        close(MENUFILEHANDLE);

        # We don't check if the menu file is from a future version because we can't just throw it out and regenerate it like we can
        # with other data files.  So we just keep going regardless.  Any syntactic differences will show up as errors.

        my $version;

        if ($menuFileContent =~ /^[^\#]*format:[ \t]([0-9\.]+)/mi)
            {  $version = $1;  }
        else
            {
            # If there's no format tag, the menu version is 0.95 or earlier.
            $version = '0.95';
            };

        # Strip tabs.
        $menuFileContent =~ tr/\t/ /s;

        my @segments = split(/([\n{}\#])/, $menuFileContent);
        my $segment;
        $menuFileContent = undef;

        while (scalar @segments)
            {
            $segment = shift @segments;

            # Ignore empty segments caused by splitting.
            if (!length $segment)
                {  next;  };

            # Ignore line breaks.
            if ($segment eq "\n")
                {
                $lineNumber++;
                next;
                };

            # Ignore comments.
            if ($segment eq '#')
                {
                while (scalar @segments && $segments[0] ne "\n")
                    {  shift @segments;  };

                next;
                };


            # Check for an opening brace after a group token.  This has to be separate from the rest of the code because the flag
            # needs to be reset after every non-ignored segment.
            if ($afterGroupToken)
                {
                $afterGroupToken = undef;

                if ($segment eq '{')
                    {
                    $inBracelessGroup = undef;
                    next;
                    }
                else
                    {  $inBracelessGroup = 1;  };
                };


            # Now on to the real code.

            if ($segment eq '{')
                {
                push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'Opening braces are only allowed after Group tags.');
                }
            elsif ($segment eq '}')
                {
                # End a braceless group, if we were in one.
                if ($inBracelessGroup)
                    {
                    $currentGroup = pop @groupStack;
                    $inBracelessGroup = undef;
                    };

                # End a braced group too.
                if (scalar @groupStack)
                    {  $currentGroup = pop @groupStack;  }
                else
                    {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'Unmatched closing brace.');  };
                }

            # If the segment is a segment of text...
            else
                {
                $segment =~ s/^ +//;
                $segment =~ s/ +$//;

                # If the segment is keyword: name or keyword: name (extras)...
                if ($segment =~ /^([^:]+): +([^ ].*)$/)
                    {
                    my $type = lc($1);
                    my $name = $2;
                    my @extras;
                    my $modifier;

                    # Split off the extra.
                    if ($name =~ /^(.+)\(([^\)]+)\)$/)
                        {
                        $name = $1;
                        my $extraString = $2;

                        $name =~ s/ +$//;
                        $extraString =~ s/ +$//;
                        $extraString =~ s/^ +//;

                        @extras = split(/ *\, */, $extraString);
                        };

                    # Split off the modifier.
                    if ($type =~ / /)
                        {
                        ($modifier, $type) = split(/ +/, $type, 2);
                        };

                    if (exists $menuSynonyms{$type})
                        {
                        $type = $menuSynonyms{$type};

                        # Currently index is the only type allowed modifiers.
                        if (defined $modifier && $type != ::MENU_INDEX())
                            {
                            push @$errors, NaturalDocs::Menu::Error->New($lineNumber,
                                                                                                 $modifier . ' ' . $menuSynonyms{$type}
                                                                                                 . ' is not a valid keyword.');
                            next;
                            };

                        if ($type == ::MENU_GROUP())
                            {
                            # End a braceless group, if we were in one.
                            if ($inBracelessGroup)
                                {
                                $currentGroup = pop @groupStack;
                                $inBracelessGroup = undef;
                                };

                            my $entry = NaturalDocs::Menu::Entry->New(::MENU_GROUP(), $name, undef, undef);

                            $currentGroup->PushToGroup($entry);

                            push @groupStack, $currentGroup;
                            $currentGroup = $entry;

                            $afterGroupToken = 1;
                            }

                        elsif ($type == ::MENU_FILE())
                            {
                            my $flags = 0;

                            no integer;

                            if ($version >= 1.0)
                                {
                                if (lc($extras[0]) eq 'no auto-title')
                                    {
                                    $flags |= ::MENU_FILE_NOAUTOTITLE();
                                    shift @extras;
                                    }
                                elsif (lc($extras[0]) eq 'auto-title')
                                    {
                                    # It's already the default, but we want to accept the keyword anyway.
                                    shift @extras;
                                    };
                                }
                            else
                                {
                                # Prior to 1.0, the only extra was "auto-title" and the default was off instead of on.
                                if (lc($extras[0]) eq 'auto-title')
                                    {  shift @extras;  }
                                else
                                    {
                                    # We deliberately leave it auto-titled, but save the original title.
                                    $oldLockedTitles->{$extras[0]} = $name;
                                    };
                                };

                            use integer;

                            if (!scalar @extras)
                                {
                                push @$errors, NaturalDocs::Menu::Error->New($lineNumber,
                                                                                                     'File entries need to be in format '
                                                                                                     . '"File: [title] ([location])"');
                                next;
                                };

                            my $entry = NaturalDocs::Menu::Entry->New(::MENU_FILE(), $name, $extras[0], $flags);

                            $currentGroup->PushToGroup($entry);

                            $filesInMenu->{$extras[0]} = $entry;
                            }

                        # There can only be one title, subtitle, and footer.
                        elsif ($type == ::MENU_TITLE())
                            {
                            if (!defined $title)
                                {  $title = $name;  }
                            else
                                {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'Title can only be defined once.');  };
                            }
                        elsif ($type == ::MENU_SUBTITLE())
                            {
                            if (defined $title)
                                {
                                if (!defined $subTitle)
                                    {  $subTitle = $name;  }
                                else
                                    {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'SubTitle can only be defined once.');  };
                                }
                            else
                                {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'Title must be defined before SubTitle.');  };
                            }
                        elsif ($type == ::MENU_FOOTER())
                            {
                            if (!defined $footer)
                                {  $footer = $name;  }
                            else
                                {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'Copyright can only be defined once.');  };
                            }

                        elsif ($type == ::MENU_TEXT())
                            {
                            $currentGroup->PushToGroup( NaturalDocs::Menu::Entry->New(::MENU_TEXT(), $name, undef, undef) );
                            }

                        elsif ($type == ::MENU_LINK())
                            {
                            my $target;

                            if (scalar @extras)
                                {
                                $target = $extras[0];
                                }

                            # We need to support # appearing in urls.
                            elsif (scalar @segments >= 2 && $segments[0] eq '#' && $segments[1] =~ /^[^ ].*\) *$/ &&
                                    $name =~ /^.*\( *[^\(\)]*[^\(\)\ ]$/)
                                {
                                $name =~ /^(.*)\(\s*([^\(\)]*[^\(\)\ ])$/;

                                $name = $1;
                                $target = $2;

                                $name =~ s/ +$//;

                                $segments[1] =~ /^([^ ].*)\) *$/;

                                $target .= '#' . $1;

                                shift @segments;
                                shift @segments;
                                }

                            else
                                {
                                $target = $name;
                                };

                            $currentGroup->PushToGroup( NaturalDocs::Menu::Entry->New(::MENU_LINK(), $name, $target, undef) );
                            }

                        elsif ($type == ::MENU_INDEX())
                            {
                            if (!defined $modifier)
                                {
                                my $entry = NaturalDocs::Menu::Entry->New(::MENU_INDEX(), $name, undef, undef);
                                $currentGroup->PushToGroup($entry);

                                $indexes{'*'} = 1;
                                }
                            elsif ($modifier eq 'don\'t')
                                {
                                # We'll tolerate splits by spaces as well as commas.
                                my @splitLine = split(/ +|, */, lc($name));

                                foreach my $bannedIndex (@splitLine)
                                    {
                                    if ($bannedIndex eq 'general')
                                        {  $bannedIndex = '*';  }
                                    else
                                        {  $bannedIndex = $indexSynonyms{$bannedIndex};  };

                                    $bannedIndexes{$bannedIndex} = 1;
                                    };
                                }
                            elsif (exists $indexSynonyms{$modifier})
                                {
                                $modifier = $indexSynonyms{$modifier};
                                $indexes{$modifier} = 1;
                                $currentGroup->PushToGroup( NaturalDocs::Menu::Entry->New(::MENU_INDEX(), $name, $modifier, undef) );
                                }
                            else
                                {
                                push @$errors, NaturalDocs::Menu::Error->New($lineNumber, $modifier . ' is not a valid index type.');
                                };
                            }

                        # There's also MENU_FORMAT, but that was already dealt with.  We don't need to parse it, just make sure it
                        # doesn't cause an error.

                        }

                    # If the keyword doesn't exist...
                    else
                        {
                        push @$errors, NaturalDocs::Menu::Error->New($lineNumber, $1 . ' is not a valid keyword.');
                        };

                    }

                # If the text is not keyword: name or whitespace...
                 elsif (length $segment)
                    {
                    # We check the length because the segment may just have been whitespace between symbols (i.e. "\n  {" or
                    # "} #")  If that's the case, the segment content would have been erased when we clipped the leading and trailing
                    # whitespace from the line.
                    push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'Every line must start with a keyword.');
                    };

                }; # segment of text
            }; #while segments


        # End a braceless group, if we were in one.
        if ($inBracelessGroup)
            {
            $currentGroup = pop @groupStack;
            $inBracelessGroup = undef;
            };

        # Close up all open groups.
        my $openGroups = 0;
        while (scalar @groupStack)
            {
            $currentGroup = pop @groupStack;
            $openGroups++;
            };

        if ($openGroups == 1)
            {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'There is an unclosed group.');  }
        elsif ($openGroups > 1)
            {  push @$errors, NaturalDocs::Menu::Error->New($lineNumber, 'There are ' . $openGroups . ' unclosed groups.');  };


        no integer;

        if ($version < 1.0)
            {
            # Prior to 1.0, there was no auto-placement.  New entries were either tacked onto the end of the menu, or if there were
            # groups, added to a top-level group named "Other".  Since we have auto-placement now, delete "Other" so that its
            # contents get placed.

            my $index = scalar @{$menu->GroupContent()} - 1;
            while ($index >= 0)
                {
                if ($menu->GroupContent()->[$index]->Type() == ::MENU_GROUP() &&
                    lc($menu->GroupContent()->[$index]->Title()) eq 'other')
                    {
                    splice( @{$menu->GroupContent()}, $index, 1 );
                    last;
                    };

                $index--;
                };

            # Also, prior to 1.0 there was no auto-grouping and crappy auto-titling.  We want to apply these the first time a post-1.0
            # release is run.

            my @groupStack = ( $menu );
            while (scalar @groupStack)
                {
                my $groupEntry = pop @groupStack;

                $groupEntry->SetFlags( $groupEntry->Flags() | ::MENU_GROUP_UPDATETITLES() | ::MENU_GROUP_UPDATEORDER() |
                                                   ::MENU_GROUP_UPDATESTRUCTURE() );

                foreach my $entry (@{$groupEntry->GroupContent()})
                    {
                    if ($entry->Type() == ::MENU_GROUP())
                        {  push @groupStack, $entry;  };
                    };
                };
            };

        use integer;
        };


    if (!scalar @$errors)
        {  $errors = undef;  };
    if (!scalar keys %$oldLockedTitles)
        {  $oldLockedTitles = undef;  };

    return ($errors, $filesInMenu, $oldLockedTitles);
    };


#
#   Function: SaveMenuFile
#
#   Saves the current menu to <NaturalDocs_Menu.txt>.
#
sub SaveMenuFile
    {
    open(MENUFILEHANDLE, '>' . NaturalDocs::Project::MenuFile())
        or die "Couldn't save menu file " . NaturalDocs::Project::MenuFile() . "\n";


    print MENUFILEHANDLE

    "# Do not change or remove this line.\n"
    . "Format: " . NaturalDocs::Settings::TextAppVersion() . "\n\n";


    if (defined $title)
        {
        print MENUFILEHANDLE 'Title: ' . $title . "\n";

        if (defined $subTitle)
            {
            print MENUFILEHANDLE 'SubTitle: ' . $subTitle . "\n";
            }
        else
            {
            print MENUFILEHANDLE
            "\n"
            . "# You can also add a sub-title to your menu by adding a\n"
            . "# \"SubTitle: [subtitle]\" line.\n";
            };
        }
    else
        {
        print MENUFILEHANDLE
        "# You can add a title and sub-title to your menu.\n"
        . "# Just add \"Title: [project name]\" and \"SubTitle: [subtitle]\" lines here.\n";
        };

    print MENUFILEHANDLE "\n";

    if (defined $footer)
        {
        print MENUFILEHANDLE 'Footer: ' . $footer . "\n";
        }
    else
        {
        print MENUFILEHANDLE
        "# You can add a footer to your documentation.  Just add a\n"
        . "# \"Footer: [text]\" line here.  If you want to add a copyright notice,\n"
        . "# this would be the place to do it.\n";
        };

    print MENUFILEHANDLE

    "\n"

    # Remember to keep lines below eighty characters.

    . "# ------------------------------------------------------------------------ #\n\n"

    . "# Cut and paste the lines below to change the order in which your files\n"
    . "# appear on the menu.  Don't worry about adding or removing files, Natural\n"
    . "# Docs will take care of that.\n"
    . "# \n"
    . "# You can further organize the menu by grouping the entries.  Add a\n"
    . "# \"Group: [name] {\" line to start a group, and add a \"}\" to end it.  Groups\n"
    . "# can appear within each other.\n"
    . "# \n"
    . "# You can add text and web links to the menu by adding \"Text: [text]\" and\n"
    . "# \"Link: [name] ([URL])\" lines, respectively.\n"
    . "# \n"
    . "# The formatting and comments are auto-generated, so don't worry about\n"
    . "# neatness when editing the file.  Natural Docs will clean it up the next\n"
    . "# time it is run.  When working with groups, just deal with the braces and\n"
    . "# forget about the indentation and comments.\n"

    . "\n"
    . "# ------------------------------------------------------------------------ #\n"

    . "\n";

    if (scalar keys %bannedIndexes)
        {
        print MENUFILEHANDLE

        "# These are indexes you deleted, so Natural Docs will not add them again\n"
        . "# unless you remove them from this line.\n"
        . "\n"
        . "Don't Index: ";

        my $first = 1;

        foreach my $index (keys %bannedIndexes)
            {
            if (!$first)
                {  print MENUFILEHANDLE ', ';  }
            else
                {  $first = undef;  };

            if ($index eq '*')
                {  print MENUFILEHANDLE 'General';  }
            else
                {  print MENUFILEHANDLE $indexNames{$index};  };
            };

        print MENUFILEHANDLE "\n\n\n";
        };

    WriteMenuEntries($menu->GroupContent(), \*MENUFILEHANDLE, undef);

    close(MENUFILEHANDLE);
    };


#
#   Function: WriteMenuEntries
#
#   A recursive function to write the contents of an arrayref of <NaturalDocs::Menu::Entry> objects to disk.
#
#   Parameters:
#
#       entries          - The arrayref of menu entries to write.
#       fileHandle      - The handle to the output file.
#       indentChars   - The indentation _characters_ to add before each line.  It is not the number of characters, it is the characters
#                              themselves.  Use undef for none.
#
sub WriteMenuEntries #(entries, fileHandle, indentChars)
    {
    my ($entries, $fileHandle, $indentChars) = @_;

    foreach my $entry (@$entries)
        {
        if ($entry->Type() == ::MENU_FILE())
            {
            print $fileHandle $indentChars . 'File: ' . $entry->Title()
                                  . '  (' . ($entry->Flags() & ::MENU_FILE_NOAUTOTITLE() ? 'no auto-title, ' : '') . $entry->Target() . ")\n";
            }
        elsif ($entry->Type() == ::MENU_GROUP())
            {
            print $fileHandle "\n" . $indentChars . 'Group: ' . $entry->Title() . "  {\n\n";
            WriteMenuEntries($entry->GroupContent(), $fileHandle, '   ' . $indentChars);
            print $fileHandle '   ' . $indentChars . '}  # Group: ' . $entry->Title() . "\n\n";
            }
        elsif ($entry->Type() == ::MENU_TEXT())
            {
            print $fileHandle $indentChars . 'Text: ' . $entry->Title() . "\n";
            }
        elsif ($entry->Type() == ::MENU_LINK())
            {
            print $fileHandle $indentChars . 'Link: ' . $entry->Title() . '  (' . $entry->Target() . ')' . "\n";
            }
        elsif ($entry->Type() == ::MENU_INDEX())
            {
            my $type;
            if (defined $entry->Target())
                {
                $type = $indexNames{$entry->Target()} . ' ';
                };

            print $fileHandle $indentChars . $type . 'Index: ' . $entry->Title() . "\n";
            };
        };
    };


#
#   Function: LoadPreviousMenuStateFile
#
#   Loads and parses the previous menu state file.
#
#   Note that this is not affected by <NaturalDocs::Settings::RebuildData()>.  Since this is used to detect user changes, the
#   information here can't be ditched on a whim.
#
#   Returns:
#
#       The array ( previousMenu, previousIndexes, previousFiles ).
#
#       previousMenu - A <MENU_GROUP> <NaturalDocs::Menu::Entry> object, similar to <menu>, which contains the entire
#                              previous menu.
#       previousIndexes - An existence hashref of the indexes present in the previous menu.  The keys are the <Topic Types> or
#                                  '*' for general.
#       previousFiles - A hashref of the files present in the previous menu.  The keys are the file names, and the entries are
#                             references to its object in previousMenu.
#
#       If there is no data available on a topic, it will be undef.  For example, if the file didn't exist, all three will be undef.  If the
#       file was from 0.95 or earlier, previousIndexes will be set but the other two would be undef.
#
sub LoadPreviousMenuStateFile
    {
    my $fileIsOkay;

    my $menu;
    my $indexes;
    my $files;

    my $previousStateFileName = NaturalDocs::Project::PreviousMenuStateFile();

    # We ignore NaturalDocs::Settings::RebuildData() because otherwise user changes can be lost.
    if (open(PREVIOUSSTATEFILEHANDLE, '<' . $previousStateFileName))
        {
        # See if it's binary.
        binmode(PREVIOUSSTATEFILEHANDLE);

        my $firstChar;
        read(PREVIOUSSTATEFILEHANDLE, $firstChar, 1);

        if ($firstChar == ::BINARY_FORMAT())
            {
            my $version = NaturalDocs::Version::FromBinaryFile(\*PREVIOUSSTATEFILEHANDLE);

            # The file format has not changed since switching to binary.

            if ($version <= NaturalDocs::Settings::AppVersion())
                {  $fileIsOkay = 1;  }
            else
                {  close(PREVIOUSSTATEFILEHANDLE);  };
            }

        else # it's not in binary
            {
            # Reopen it in text mode.
            close(PREVIOUSSTATEFILEHANDLE);
            open(PREVIOUSSTATEFILEHANDLE, '<' . $previousStateFileName);

            # Check the version.
            my $version = NaturalDocs::Version::FromTextFile(\*PREVIOUSSTATEFILEHANDLE);

            # We'll still read the pre-1.0 text file, since it's simple.
            if ($version <= NaturalDocs::Version::FromString('0.95'))
                {
                my $indexLine = <PREVIOUSSTATEFILEHANDLE>;
                chomp($indexLine);

                $indexes = { };

                my @indexesInLine = split(/\t/, $indexLine);
                foreach my $indexInLine (@indexesInLine)
                    {  $indexes->{$indexInLine} = 1;  };
                };

            close(PREVIOUSSTATEFILEHANDLE);
            };
        };

    if ($fileIsOkay)
        {
        $menu = NaturalDocs::Menu::Entry->New(::MENU_GROUP(), undef, undef, undef);
        $indexes = { };
        $files = { };

        my @groupStack;
        my $currentGroup = $menu;
        my $raw;

        # [UInt8: type or 0 for end group]

        while (read(PREVIOUSSTATEFILEHANDLE, $raw, 1))
            {
            my ($type, $flags, $title, $titleLength, $target, $targetLength);
            $type = unpack('C', $raw);

            if ($type == 0)
                {  $currentGroup = pop @groupStack;  }

            elsif ($type == ::MENU_FILE())
                {
                # [UInt8: noAutoTitle] [AString16: title] [AString16: target]

                read(PREVIOUSSTATEFILEHANDLE, $raw, 3);
                (my $noAutoTitle, $titleLength) = unpack('Cn', $raw);

                if ($noAutoTitle)
                    {  $flags = ::MENU_FILE_NOAUTOTITLE();  };

                read(PREVIOUSSTATEFILEHANDLE, $title, $titleLength);
                read(PREVIOUSSTATEFILEHANDLE, $raw, 2);

                $targetLength = unpack('n', $raw);

                read(PREVIOUSSTATEFILEHANDLE, $target, $targetLength);
                }

            elsif ($type == ::MENU_GROUP())
                {
                # [AString16: title]

                read(PREVIOUSSTATEFILEHANDLE, $raw, 2);
                $titleLength = unpack('n', $raw);

                read(PREVIOUSSTATEFILEHANDLE, $title, $titleLength);
                }

            elsif ($type == ::MENU_INDEX())
                {
                # [AString16: title] [UInt8: type (0 for general)]

                read(PREVIOUSSTATEFILEHANDLE, $raw, 2);
                $titleLength = unpack('n', $raw);

                read(PREVIOUSSTATEFILEHANDLE, $title, $titleLength);
                read(PREVIOUSSTATEFILEHANDLE, $raw, 1);
                $target = unpack('C', $raw);

                if ($target == 0)
                    {  $target = undef;  };
                }

            elsif ($type == ::MENU_LINK())
                {
                # [AString16: title] [AString16: url]

                read(PREVIOUSSTATEFILEHANDLE, $raw, 2);
                $titleLength = unpack('n', $raw);

                read(PREVIOUSSTATEFILEHANDLE, $title, $titleLength);
                read(PREVIOUSSTATEFILEHANDLE, $raw, 2);
                $targetLength = unpack('n', $raw);

                read(PREVIOUSSTATEFILEHANDLE, $target, $targetLength);
                }

            elsif ($type == ::MENU_TEXT())
                {
                # [AString16: text]

                read(PREVIOUSSTATEFILEHANDLE, $raw, 2);
                $titleLength = unpack('n', $raw);

                read(PREVIOUSSTATEFILEHANDLE, $title, $titleLength);
                };


            my $entry = NaturalDocs::Menu::Entry->New($type, $title, $target, ($flags || 0));
            $currentGroup->PushToGroup($entry);


            if ($type == ::MENU_FILE())
                {
                $files->{$target} = $entry;
                }
            elsif ($type == ::MENU_GROUP())
                {
                push @groupStack, $currentGroup;
                $currentGroup = $entry;
                }
            elsif ($type == ::MENU_INDEX())
                {
                if (!defined $target)
                    {  $target = '*';  };

                $indexes->{$target} = 1;
                };

            };

        close(PREVIOUSSTATEFILEHANDLE);
        };

    return ($menu, $indexes, $files);
    };


#
#   Function: SavePreviousMenuStateFile
#
#   Saves changes to <NaturalDocs.m>.
#
sub SavePreviousMenuStateFile
    {
    open (PREVIOUSSTATEFILEHANDLE, '>' . NaturalDocs::Project::PreviousMenuStateFile())
        or die "Couldn't save " . NaturalDocs::Project::PreviousMenuStateFile() . ".\n";

    binmode(PREVIOUSSTATEFILEHANDLE);

    print PREVIOUSSTATEFILEHANDLE '' . ::BINARY_FORMAT();

    NaturalDocs::Version::ToBinaryFile(\*PREVIOUSSTATEFILEHANDLE, NaturalDocs::Settings::AppVersion());

    WritePreviousMenuStateEntries($menu->GroupContent(), \*PREVIOUSSTATEFILEHANDLE);

    close(PREVIOUSSTATEFILEHANDLE);
    };


#
#   Function: WritePreviousMenuStateEntries
#
#   A recursive function to write the contents of an arrayref of <NaturalDocs::Menu::Entry> objects to disk.
#
#   Parameters:
#
#       entries          - The arrayref of menu entries to write.
#       fileHandle      - The handle to the output file.
#
sub WritePreviousMenuStateEntries #(entries, fileHandle)
    {
    my ($entries, $fileHandle) = @_;

    foreach my $entry (@$entries)
        {
        if ($entry->Type() == ::MENU_FILE())
            {
            # We need to do length manually instead of using n/A in the template because it's not supported in earlier versions
            # of Perl.

            # [UInt8: MENU_FILE] [UInt8: noAutoTitle] [AString16: title] [AString16: target]
            print $fileHandle pack('CCnA*nA*', ::MENU_FILE(), ($entry->Flags() & ::MENU_FILE_NOAUTOTITLE() ? 1 : 0),
                                                                length($entry->Title()), $entry->Title(),
                                                                length($entry->Target()), $entry->Target());
            }

        elsif ($entry->Type() == ::MENU_GROUP())
            {
            # [UInt8: MENU_GROUP] [AString16: title]
            print $fileHandle pack('CnA*', ::MENU_GROUP(), length($entry->Title()), $entry->Title());
            WritePreviousMenuStateEntries($entry->GroupContent(), $fileHandle);
            print $fileHandle pack('C', 0);
            }

        elsif ($entry->Type() == ::MENU_INDEX())
            {
            # [UInt8: MENU_INDEX] [AString16: title] [UInt8: type (0 for general)]
            print $fileHandle pack('CnA*C', ::MENU_INDEX(), length($entry->Title()), $entry->Title(), $entry->Target());
            }

        elsif ($entry->Type() == ::MENU_LINK())
            {
            # [UInt8: MENU_LINK] [AString16: title] [AString16: url]
            print $fileHandle pack('CnA*nA*', ::MENU_LINK(), length($entry->Title()), $entry->Title(),
                                                             length($entry->Target()), $entry->Target());
            }

        elsif ($entry->Type() == ::MENU_TEXT())
            {
            # [UInt8: MENU_TEXT] [AString16: hext]
            print $fileHandle pack('CnA*', ::MENU_TEXT(), length($entry->Title()), $entry->Title());
            };
        };

    };


#
#   Function: HandleErrors
#
#   Handles errors appearing in the menu file.
#
#   Parameters:
#
#       errors - An arrayref of the errors as <NaturalDocs::Menu::Error> objects.
#
sub HandleErrors #(errors)
    {
    my $errors = shift;

    my $menuFile = NaturalDocs::Project::MenuFile();
    my $menuFileContent;

    open(MENUFILEHANDLE, '<' . $menuFile);
    read(MENUFILEHANDLE, $menuFileContent, -s MENUFILEHANDLE);
    close(MENUFILEHANDLE);

    my @lines = split(/\n/, $menuFileContent);
    $menuFileContent = undef;

    # We need to keep track of both the real and the original line numbers.  The original line numbers are for matching errors in the
    # errors array, and don't include any comment lines added or deleted.  Line number is the current line number including those
    # comment lines for sending to the display.
    my $lineNumber = 1;
    my $originalLineNumber = 1;

    my $error = 0;


    open(MENUFILEHANDLE, '>' . $menuFile);

    if ($lines[0] =~ /^\# There (?:is an error|are \d+ errors) in this file\./)
        {
        shift @lines;
        $originalLineNumber++;

        if (!length $lines[0])
            {
            shift @lines;
            $originalLineNumber++;
            };
        };

    if (scalar @$errors == 1)
        {  print MENUFILEHANDLE "# There is an error in this file.  Search for ERROR to find it.\n\n";  }
    else
        {  print MENUFILEHANDLE "# There are " . (scalar @$errors) . " errors in this file.  Search for ERROR to find them.\n\n";  };

    $lineNumber += 2;


    foreach my $line (@lines)
        {
        while ($error < scalar @$errors && $originalLineNumber == $errors->[$error]->Line())
            {
            print MENUFILEHANDLE "# ERROR: " . $errors->[$error]->Description() . "\n";

            # Use the GNU error format, which should make it easier to handle errors when Natural Docs is part of a build process.
            # See http://www.gnu.org/prep/standards_15.html

            my $gnuError = lcfirst($errors->[$error]->Description());
            $gnuError =~ s/\.$//;

            print STDERR 'NaturalDocs:' . $menuFile . ':' . $lineNumber . ': ' . $gnuError . "\n";

            $lineNumber++;
            $error++;
            };

        # We want to remove error lines from previous runs.
        if (substr($line, 0, 9) ne '# ERROR: ')
            {
            print MENUFILEHANDLE $line . "\n";
            $lineNumber++;
            };

        $originalLineNumber++;
        };

    close(MENUFILEHANDLE);

    if (scalar @$errors == 1)
        {  die "There is an error in the menu file.\n";  }
    else
        {  die "There are " . (scalar @$errors) . " errors in the menu file.\n";  };
    };


#
#   Function: CheckForTrashedMenu
#
#   Checks the menu to see if a significant number of file entries didn't resolve to actual files, and if so, saves a backup of the
#   menu and issues a warning.
#
#   Parameters:
#
#       numberOriginallyInMenu - A count of how many file entries were in the menu orignally.
#       numberRemoved - A count of how many file entries were removed from the menu.
#
sub CheckForTrashedMenu #(numberOriginallyInMenu, numberRemoved)
    {
    my ($numberOriginallyInMenu, $numberRemoved) = @_;

    no integer;

    if ( ($numberOriginallyInMenu >= 6 && $numberRemoved == $numberOriginallyInMenu) ||
         ($numberOriginallyInMenu >= 12 && ($numberRemoved / $numberOriginallyInMenu) >= 0.4) ||
         ($numberRemoved >= 15) )
        {
        my $backupFile = NaturalDocs::Project::MenuBackupFile();

        NaturalDocs::File::Copy( NaturalDocs::Project::MenuFile(), $backupFile );

        print STDERR
        "\n"
        # GNU format.  See http://www.gnu.org/prep/standards_15.html
        . "NaturalDocs: warning: possible trashed menu\n"
        . "\n"
        . "   Natural Docs has detected that a significant number file entries in the\n"
        . "   menu did not resolve to actual files.  A backup of your original menu file\n"
        . "   has been saved as\n"
        . "\n"
        . "   " . $backupFile . "\n"
        . "\n"
        . "   - If you recently rearranged your source tree, you may want to restore your\n"
        . "     menu from the backup and do a search and replace to preserve your layout.\n"
        . "     Otherwise the position of any moved files will be reset.\n"
        . "   - If you recently deleted a lot of files from your project, you can safely\n"
        . "     ignore this message.  They have been deleted from the menu as well.\n"
        . "   - If neither of these is the case, you may have gotten the -i parameter\n"
        . "     wrong in the command line.  You should definitely restore the backup and\n"
        . "     try again, because otherwise every file in your menu will be reset.\n"
        . "\n";
        };

    use integer;
    };


###############################################################################
# Group: Auto-Adjustment Functions


#
#   Function: LockUserTitleChanges
#
#   Detects if the user manually changed any file titles, and if so, automatically locks them with <MENU_FILE_NOAUTOTITLE>.
#
#   Parameters:
#
#       previousMenuFiles - A hashref of the files from the previous menu state.  The keys are the file names, and the values are
#                                    references to their <NaturalDocs::Menu::Entry> objects.
#
sub LockUserTitleChanges #(previousMenuFiles)
    {
    my $previousMenuFiles = shift;

    my @groupStack = ( $menu );
    my $groupEntry;

    while (scalar @groupStack)
        {
        $groupEntry = pop @groupStack;

        foreach my $entry (@{$groupEntry->GroupContent()})
            {

            # If it's an unlocked file entry
            if ($entry->Type() == ::MENU_FILE() && ($entry->Flags() & ::MENU_FILE_NOAUTOTITLE()) == 0)
                {
                my $previousEntry = $previousMenuFiles->{$entry->Target()};

                # If the previous entry was also unlocked and the titles are different, the user changed the title.  Automatically lock it.
                if (defined $previousEntry && ($previousEntry->Flags() & ::MENU_FILE_NOAUTOTITLE()) == 0 &&
                    $entry->Title() ne $previousEntry->Title())
                    {
                    $entry->SetFlags($entry->Flags() | ::MENU_FILE_NOAUTOTITLE());
                    $hasChanged = 1;
                    };
                }

            elsif ($entry->Type() == ::MENU_GROUP())
                {
                push @groupStack, $entry;
                };

            };
        };
    };


#
#   Function: FlagAutoTitleChanges
#
#   Finds which files have auto-titles that changed and flags their groups for updating with <MENU_GROUP_UPDATETITLES> and
#   <MENU_GROUP_UPDATEORDER>.
#
sub FlagAutoTitleChanges
    {
    my @groupStack = ( $menu );
    my $groupEntry;

    while (scalar @groupStack)
        {
        $groupEntry = pop @groupStack;

        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_FILE() && ($entry->Flags() & ::MENU_FILE_NOAUTOTITLE()) == 0 &&
                exists $defaultTitlesChanged{$entry->Target()})
                {
                $groupEntry->SetFlags($groupEntry->Flags() | ::MENU_GROUP_UPDATETITLES() | ::MENU_GROUP_UPDATEORDER());
                $hasChanged = 1;
                }
            elsif ($entry->Type() == ::MENU_GROUP())
                {
                push @groupStack, $entry;
                };
            };
        };
    };


#
#   Function: AutoPlaceNewFiles
#
#   Adds files to the menu that aren't already on it, attempting to guess where they belong.
#
#   New files are placed after a dummy <MENU_ENDOFORIGINAL> entry so that they don't affect the detected order.  Also, the
#   groups they're placed in get <MENU_GROUP_UPDATETITLES>, <MENU_GROUP_UPDATESTRUCTURE>, and
#   <MENU_GROUP_UPDATEORDER> flags.
#
#   Parameters:
#
#       filesInMenu - An existence hash of all the files present in the menu.
#
sub AutoPlaceNewFiles #(fileInMenu)
    {
    my $filesInMenu = shift;
    my $files = NaturalDocs::Project::FilesWithContent();

    my $directories;

    foreach my $file (keys %$files)
        {
        if (!exists $filesInMenu->{$file})
            {
            # This is done on demand because new files shouldn't be added very often, so this will save time.
            if (!defined $directories)
                {  $directories = MatchDirectoriesAndGroups();  };

            my $targetGroup;
            my $fileDirectoryString = (NaturalDocs::File::SplitPath($file))[1];

            $targetGroup = $directories->{$fileDirectoryString};

            if (!defined $targetGroup)
                {
                # Okay, if there's no exact match, work our way down.

                my @fileDirectories = NaturalDocs::File::SplitDirectories($fileDirectoryString);

                do
                    {
                    pop @fileDirectories;
                    $targetGroup = $directories->{ NaturalDocs::File::JoinDirectories(@fileDirectories) };
                    }
                while (!defined $targetGroup && scalar @fileDirectories);

                if (!defined $targetGroup)
                    {  $targetGroup = $menu;  };
                };

            $targetGroup->MarkEndOfOriginal();
            $targetGroup->PushToGroup( NaturalDocs::Menu::Entry->New(::MENU_FILE(), undef, $file, undef) );

            $targetGroup->SetFlags( $targetGroup->Flags() | ::MENU_GROUP_UPDATETITLES() |
                                                 ::MENU_GROUP_UPDATESTRUCTURE() | ::MENU_GROUP_UPDATEORDER() );

            $hasChanged = 1;
            };
        };
    };


#
#   Function: MatchDirectoriesAndGroups
#
#   Determines which groups files in certain directories should be placed in.
#
#   Returns:
#
#   A hashref.  The keys are the directory names, and the values are references to the group objects they should be placed in.
#
#   This only repreesents directories that currently have files on the menu, so it shouldn't be assumed that every possible directory
#   will exist.  To match, you should first try to match the directory, and then strip the deepest directories one by one until there's
#   a match or there's none left.  If there's none left, use the root group <menu>.
#
sub MatchDirectoriesAndGroups
    {
    # The keys are the directory names, and the values are hashrefs.  For the hashrefs, the keys are the group objects, and the
    # values are the number of files in them from that directory.  In other words,
    # $directories{$directory}->{$groupEntry} = $count;
    my %directories;
    # Note that we need to use Tie::RefHash to use references as keys.  Won't work otherwise.  Also, not every Perl distro comes
    # with Tie::RefHash::Nestable, so we can't rely on that.

    # We're using an index instead of pushing and popping because we want to save a list of the groups in the order they appear
    # to break ties.
    my @groups = ( $menu );
    my $groupIndex = 0;


    # Count the number of files in each group that appear in each directory.

    while ($groupIndex < scalar @groups)
        {
        my $groupEntry = $groups[$groupIndex];

        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_GROUP())
                {
                push @groups, $entry;
                }
            elsif ($entry->Type() == ::MENU_FILE())
                {
                my $directory = (NaturalDocs::File::SplitPath($entry->Target()))[1];

                if (!exists $directories{$directory})
                    {
                    my $subHash = { };
                    tie %$subHash, 'Tie::RefHash';
                    $directories{$directory} = $subHash;
                    };

                if (!exists $directories{$directory}->{$groupEntry})
                    {  $directories{$directory}->{$groupEntry} = 1;  }
                else
                    {  $directories{$directory}->{$groupEntry}++;  };
                };
            };

        $groupIndex++;
        };


    # Determine which group goes with which directory, breaking ties by using whichever group appears first.

    my $finalDirectories = { };

    while (my ($directory, $directoryGroups) = each %directories)
        {
        my $bestGroup;
        my $bestCount = 0;
        my %tiedGroups;  # Existence hash

        while (my ($group, $count) = each %$directoryGroups)
            {
            if ($count > $bestCount)
                {
                $bestGroup = $group;
                $bestCount = $count;
                %tiedGroups = ( );
                }
            elsif ($count == $bestCount)
                {
                $tiedGroups{$group} = 1;
                };
            };

        # Break ties.
        if (scalar keys %tiedGroups)
            {
            $tiedGroups{$bestGroup} = 1;

            foreach my $group (@groups)
                {
                if (exists $tiedGroups{$group})
                    {
                    $bestGroup = $group;
                    last;
                    };
                };
            };


        $finalDirectories->{$directory} = $bestGroup;
        };


    return $finalDirectories;
    };


#
#   Function: RemoveDeadFiles
#
#   Removes files from the menu that no longer exist or no longer have Natural Docs content.
#
#   Returns:
#
#       The number of file entries removed.
#
sub RemoveDeadFiles
    {
    my @groupStack = ( $menu );
    my $numberRemoved = 0;

    my $filesWithContent = NaturalDocs::Project::FilesWithContent();

    while (scalar @groupStack)
        {
        my $groupEntry = pop @groupStack;
        my $groupContent = $groupEntry->GroupContent();

        my $index = 0;
        while ($index < scalar @$groupContent)
            {
            if ($groupContent->[$index]->Type() == ::MENU_FILE() &&
                !exists $filesWithContent->{ $groupContent->[$index]->Target() } )
                {
                $groupEntry->DeleteFromGroup($index);

                $groupEntry->SetFlags( $groupEntry->Flags() | ::MENU_GROUP_UPDATETITLES() |
                                                   ::MENU_GROUP_UPDATESTRUCTURE() );
                $numberRemoved++;
                $hasChanged = 1;
                }

            elsif ($groupContent->[$index]->Type() == ::MENU_GROUP())
                {
                push @groupStack, $groupContent->[$index];
                $index++;
                }

            else
                {  $index++;  };
            };
        };

    return $numberRemoved;
    };


#
#   Function: BanAndUnbanIndexes
#
#   Adjusts the indexes that are banned depending on if the user added or deleted any.
#
sub BanAndUnbanIndexes
    {
    # Unban any indexes that are present, meaning the user added them back manually without deleting the ban.
    foreach my $index (keys %indexes)
        {  delete $bannedIndexes{$index};  };

    # Ban any indexes that were in the previous menu but not the current, meaning the user manually deleted them.
    foreach my $index (keys %previousIndexes)
        {
        if (!exists $indexes{$index})
            {  $bannedIndexes{$index} = 1;  };
        };
    };


#
#   Function: AddAndRemoveIndexes
#
#   Automatically adds and removes index entries on the menu as necessary.  <DetectIndexGroups()> should be called
#   beforehand.
#
sub AddAndRemoveIndexes
    {
    # A quick way to get the possible indexes...
    my $validIndexes = { %indexNames, '*' => 1 };

    # Strip the banned indexes first so it's potentially less work for SymbolTable.
    foreach my $index (keys %bannedIndexes)
        {  delete $validIndexes->{$index};  };

    $validIndexes = NaturalDocs::SymbolTable::HasIndexes($validIndexes);


    # Delete dead indexes and find the best index group.

    my @groupStack = ( $menu );

    my $bestIndexGroup;
    my $bestIndexCount = 0;

    while (scalar @groupStack)
        {
        my $currentGroup = pop @groupStack;
        my $index = 0;

        my $currentIndexCount = 0;

        while ($index < scalar @{$currentGroup->GroupContent()})
            {
            my $entry = $currentGroup->GroupContent()->[$index];

            if ($entry->Type() == ::MENU_INDEX())
                {
                $currentIndexCount++;

                if ($currentIndexCount > $bestIndexCount)
                    {
                    $bestIndexCount = $currentIndexCount;
                    $bestIndexGroup = $currentGroup;
                    };

                # Remove it if it's dead.

                if (!exists $validIndexes->{ ($entry->Target() || '*') })
                    {
                    $currentGroup->DeleteFromGroup($index);
                    delete $indexes{ ($entry->Target() || '*') };
                    $hasChanged = 1;
                    }
                else
                    {  $index++;  };
                }

            else
                {
                if ($entry->Type() == ::MENU_GROUP())
                    {  push @groupStack, $entry;  };

                $index++;
                };
            };
        };


    # Now add the new indexes.

    foreach my $index (keys %indexes)
        {  delete $validIndexes->{$index};  };

    if (scalar keys %$validIndexes)
        {
        # Add a group if there are no indexes at all.

        if ($bestIndexCount == 0)
            {
            $menu->MarkEndOfOriginal();

            my $newIndexGroup = NaturalDocs::Menu::Entry->New(::MENU_GROUP(), 'Indexes', undef,
                                                                                             ::MENU_GROUP_ISINDEXGROUP());
            $menu->PushToGroup($newIndexGroup);

            $bestIndexGroup = $newIndexGroup;
            $menu->SetFlags( $menu->Flags() | ::MENU_GROUP_UPDATEORDER() | ::MENU_GROUP_UPDATESTRUCTURE() );
            };

        # Add the new indexes.

        $bestIndexGroup->MarkEndOfOriginal();
        my $isIndexGroup = $bestIndexGroup->Flags() & ::MENU_GROUP_ISINDEXGROUP();

        foreach my $index (keys %$validIndexes)
            {
            my $title;

            if ($isIndexGroup)
                {
                if ($index eq '*')
                    {  $title = 'Everything';  }
                else
                    {  $title = $indexPluralNames{$index};  };
                }
            else
                {
                if ($index eq '*')
                    {  $title = 'General Index';  }
                else
                    {  $title .= $indexNames{$index} . ' Index';  };
                };

            my $newEntry = NaturalDocs::Menu::Entry->New(::MENU_INDEX(), $title, ($index eq '*' ? undef : $index), undef);
            $bestIndexGroup->PushToGroup($newEntry);

            $indexes{$index} = 1;
            };

        $bestIndexGroup->SetFlags( $bestIndexGroup->Flags() |
                                                   ::MENU_GROUP_UPDATEORDER() | ::MENU_GROUP_UPDATESTRUCTURE() );
        $hasChanged = 1;
        };
    };


#
#   Function: RemoveDeadGroups
#
#   Removes groups with less than two entries.  It will always remove empty groups, and it will remove groups with one entry if it
#   has the <MENU_GROUP_UPDATESTRUCTURE> flag.
#
sub RemoveDeadGroups
    {
    my $index = 0;

    while ($index < scalar @{$menu->GroupContent()})
        {
        my $entry = $menu->GroupContent()->[$index];

        if ($entry->Type() == ::MENU_GROUP())
            {
            my $removed = RemoveIfDead($entry, $menu, $index);

            if (!$removed)
                {  $index++;  };
            }
        else
            {  $index++;  };
        };
    };


#
#   Function: RemoveIfDead
#
#   Checks a group and all its sub-groups for life and remove any that are dead.  Empty groups are removed, and groups with one
#   entry and the <MENU_GROUP_UPDATESTRUCTURE> flag have their entry moved to the parent group.
#
#   Parameters:
#
#       groupEntry - The group to check for possible deletion.
#       parentGroupEntry - The parent group to move the single entry to if necessary.
#       parentGroupIndex - The index of the group in its parent.
#
#   Returns:
#
#       Whether the group was removed or not.
#
sub RemoveIfDead #(groupEntry, parentGroupEntry, parentGroupIndex)
    {
    my ($groupEntry, $parentGroupEntry, $parentGroupIndex) = @_;


    # Do all sub-groups first, since their deletions will affect our UPDATESTRUCTURE flag and content count.

    my $index = 0;
    while ($index < scalar @{$groupEntry->GroupContent()})
        {
        my $entry = $groupEntry->GroupContent()->[$index];

        if ($entry->Type() == ::MENU_GROUP())
            {
            my $removed = RemoveIfDead($entry, $groupEntry, $index);

            if (!$removed)
                {  $index++;  };
            }
        else
            {  $index++;  };
        };


    # Now check ourself.

    my $count = scalar @{$groupEntry->GroupContent()};
    if ($groupEntry->Flags() & ::MENU_GROUP_HASENDOFORIGINAL())
        {  $count--;  };

    if ($count == 0)
        {
        $parentGroupEntry->DeleteFromGroup($parentGroupIndex);

        $parentGroupEntry->SetFlags( $parentGroupEntry->Flags() | ::MENU_GROUP_UPDATESTRUCTURE() );

        $hasChanged = 1;
        return 1;
        }
    elsif ($count == 1 && ($groupEntry->Flags() & ::MENU_GROUP_UPDATESTRUCTURE()) )
        {
        my $onlyEntry = $groupEntry->GroupContent()->[0];
        if ($onlyEntry->Type() == ::MENU_ENDOFORIGINAL())
            {  $onlyEntry = $groupEntry->GroupContent()->[1];  };

        $parentGroupEntry->DeleteFromGroup($parentGroupIndex);

        $parentGroupEntry->MarkEndOfOriginal();
        $parentGroupEntry->PushToGroup($onlyEntry);

        $parentGroupEntry->SetFlags( $parentGroupEntry->Flags() | ::MENU_GROUP_UPDATETITLES() |
                                                     ::MENU_GROUP_UPDATEORDER() | ::MENU_GROUP_UPDATESTRUCTURE() );

        $hasChanged = 1;
        return 1;
        }
    else
        {  return undef;  };
    };


#
#   Function: DetectIndexGroups
#
#   Finds groups that are primarily used for indexes and gives them the <MENU_GROUP_ISINDEXGROUP> flag.
#
sub DetectIndexGroups
    {
    my @groupStack = ( $menu );

    while (scalar @groupStack)
        {
        my $groupEntry = pop @groupStack;

        my $isIndexGroup = -1;  # -1: Can't tell yet.  0: Can't be an index group.  1: Is an index group so far.

        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_INDEX())
                {
                if ($isIndexGroup == -1)
                    {  $isIndexGroup = 1;  };
                }

            # Text is tolerated, but it still needs at least one index entry.
            elsif ($entry->Type() != ::MENU_TEXT())
                {
                $isIndexGroup = 0;

                if ($entry->Type() == ::MENU_GROUP())
                    {  push @groupStack, $entry;  };
                };
            };

        if ($isIndexGroup == 1)
            {
            $groupEntry->SetFlags( $groupEntry->Flags() | ::MENU_GROUP_ISINDEXGROUP() );
            };
        };
    };


#
#   Function: CreateDirectorySubGroups
#
#   Where possible, creates sub-groups based on directories for any long groups that have <MENU_GROUP_UPDATESTRUCTURE>
#   set.  Clears the flag afterwards on groups that are short enough to not need any more sub-groups, but leaves it for the rest.
#
sub CreateDirectorySubGroups
    {
    my @groupStack = ( $menu );

    foreach my $groupEntry (@groupStack)
        {
        if ($groupEntry->Flags() & ::MENU_GROUP_UPDATESTRUCTURE())
            {
            # Count the number of files.

            my $fileCount = 0;

            foreach my $entry (@{$groupEntry->GroupContent()})
                {
                if ($entry->Type() == ::MENU_FILE())
                    {  $fileCount++;  };
                };


            if ($fileCount > MAXFILESINGROUP)
                {
                my @sharedDirectories = SharedDirectoriesOf($groupEntry);
                my $unsharedIndex = scalar @sharedDirectories;

                # The keys are the first directory entries after the shared ones, and the values are the number of files that are in
                # that directory.  Files that don't have subdirectories after the shared directories aren't included because they shouldn't
                # be put in a subgroup.
                my %directoryCounts;

                foreach my $entry (@{$groupEntry->GroupContent()})
                    {
                    if ($entry->Type() == ::MENU_FILE())
                        {
                        my @entryDirectories = NaturalDocs::File::SplitDirectories( (NaturalDocs::File::SplitPath($entry->Target()))[1] );

                        if (scalar @entryDirectories > $unsharedIndex)
                            {
                            my $unsharedDirectory = $entryDirectories[$unsharedIndex];

                            if (!exists $directoryCounts{$unsharedDirectory})
                                {  $directoryCounts{$unsharedDirectory} = 1;  }
                            else
                                {  $directoryCounts{$unsharedDirectory}++;  };
                            };
                        };
                    };


                # Now create the subgroups.

                # The keys are the first directory entries after the shared ones, and the values are the groups for those files to be
                # put in.  There will only be entries for the groups with at least MINFILESINNEWGROUP files.
                my %directoryGroups;

                while (my ($directory, $count) = each %directoryCounts)
                    {
                    if ($count >= MINFILESINNEWGROUP)
                        {
                        my $newGroup = NaturalDocs::Menu::Entry->New( ::MENU_GROUP(), ucfirst($directory), undef,
                                                                                                  ::MENU_GROUP_UPDATETITLES() |
                                                                                                  ::MENU_GROUP_UPDATEORDER() );

                        if ($count > MAXFILESINGROUP)
                            {  $newGroup->SetFlags( $newGroup->Flags() | ::MENU_GROUP_UPDATESTRUCTURE());  };

                        $groupEntry->MarkEndOfOriginal();
                        push @{$groupEntry->GroupContent()}, $newGroup;

                        $directoryGroups{$directory} = $newGroup;
                        $fileCount -= $count;
                        };
                    };


                # Now fill the subgroups.

                if (scalar keys %directoryGroups)
                    {
                    my $afterOriginal;
                    my $index = 0;

                    while ($index < scalar @{$groupEntry->GroupContent()})
                        {
                        my $entry = $groupEntry->GroupContent()->[$index];

                        if ($entry->Type() == ::MENU_FILE())
                            {
                            my @entryDirectories = NaturalDocs::File::SplitDirectories( (NaturalDocs::File::SplitPath($entry->Target()))[1] );
                            my $unsharedDirectory = $entryDirectories[$unsharedIndex];

                            if (exists $directoryGroups{$unsharedDirectory})
                                {
                                my $targetGroup = $directoryGroups{$unsharedDirectory};

                                if ($afterOriginal)
                                    {  $targetGroup->MarkEndOfOriginal();  };
                                $targetGroup->PushToGroup($entry);

                                $groupEntry->DeleteFromGroup($index);
                                }
                            else
                                {  $index++;  };
                            }

                        elsif ($entry->Type() == ::MENU_ENDOFORIGINAL())
                            {
                            $afterOriginal = 1;
                            $index++;
                            }

                        elsif ($entry->Type() == ::MENU_GROUP())
                            {
                            # See if we need to relocate this group.

                            my @groupDirectories = SharedDirectoriesOf($entry);

                            # The group's shared directories must be at least two levels deeper than the current.  If the first level deeper
                            # is a new group, move it there because it's a subdirectory of that one.
                            if (scalar @groupDirectories - scalar @sharedDirectories >= 2)
                                {
                                my $unsharedDirectory = $groupDirectories[$unsharedIndex];

                                if (exists $directoryGroups{$unsharedDirectory} &&
                                    $directoryGroups{$unsharedDirectory} != $entry)
                                    {
                                    my $targetGroup = $directoryGroups{$unsharedDirectory};

                                    if ($afterOriginal)
                                        {  $targetGroup->MarkEndOfOriginal();  };
                                    $targetGroup->PushToGroup($entry);

                                    $groupEntry->DeleteFromGroup($index);

                                    # We need to retitle the group if it has the name of the unshared directory.

                                    my $oldTitle = $entry->Title();
                                    $oldTitle =~ s/ +//g;
                                    $unsharedDirectory =~ s/ +//g;

                                    if (lc($oldTitle) eq lc($unsharedDirectory))
                                        {
                                        $entry->SetTitle($groupDirectories[$unsharedIndex + 1]);
                                        };
                                    }
                                else
                                    {  $index++;  };
                                }
                            else
                                {  $index++;  };
                            }

                        else
                            {  $index++;  };
                        };

                    $hasChanged = 1;

                    if ($fileCount <= MAXFILESINGROUP)
                        {  $groupEntry->SetFlags( $groupEntry->Flags() & ~::MENU_GROUP_UPDATESTRUCTURE() );  };

                    $groupEntry->SetFlags( $groupEntry->Flags() | ::MENU_GROUP_UPDATETITLES() |
                                                                                         ::MENU_GROUP_UPDATEORDER() );
                    };

                };  # If group has >MAXFILESINGROUP files
            };  # If group has UPDATESTRUCTURE


        # Okay, now go through all the subgroups.  We do this after the above so that newly created groups can get subgrouped
        # further.

        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_GROUP())
                {  push @groupStack, $entry;  };
            };

        };  # For each group entry
    };


#
#   Function: CreatePrefixSubGroups
#
#   Where possible, creates sub-groups based on name prefix for any long groups that have the
#   <MENU_GROUP_UPDATESTRUCTURE> flag set.  Clears the flag for any group that becomes short enough to not need any more
#   sub-groups, but leaves it for the rest.
#
#   Important:
#
#       This function isn't ready for prime time yet.  While it works somewhat on its own, it needs to be improved and to integrate
#       better with the directory sub-groups.  Probably most importantly, <AutoPlaceNewFiles()> needs to be aware of it.
#
sub CreatePrefixSubGroups
    {
    # XXX This function hasn't been converted to use PushToGroup(), DeleteFromGroup(), MarkEndOfOriginal() etc. which would
    # improve readability.
    my @groupStack = ( $menu );

    while (scalar @groupStack)
        {
        my $groupEntry = pop @groupStack;

        if ($groupEntry->Flags() & ::MENU_GROUP_UPDATESTRUCTURE())
            {
            # Count the files and find the global prefixes, if any.

            my $fileCount = 0;
            my @globalPrefixes;
            my $noGlobalPrefixes;

            foreach my $entry (@{$groupEntry->GroupContent()})
                {
                if ($entry->Type() == ::MENU_FILE())
                    {
                    $fileCount++;

                    # We want to ignore titles with spaces in them.  Otherwise we'll group on manual titles starting with "The" or
                    # something.  This is meant for code only.
                    if (!$noGlobalPrefixes &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) ne $entry->Target() &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) !~ / /)
                        {
                        my @tokens = NaturalDocs::Project::DefaultMenuTitleOf($entry->Target())
#                                                                                                            =~ /[A-Z]+[a-z0-9]*(?:\.|::)?|[a-z0-9]+(?:\.|::)?|./g;
                                                                                                            =~ /([A-Z]+[a-z0-9]*|[a-z0-9]+|.)(?:\.|::)?/g;

                        if (!scalar @globalPrefixes)
                            {  @globalPrefixes = @tokens;  }
                        else
                            {
                            ::ShortenToMatchStrings(\@globalPrefixes, \@tokens);
                            if (!scalar @globalPrefixes)
                                {  $noGlobalPrefixes = 1;  };
                            };
                        };
                    };
                };


            if ($fileCount > MAXFILESINGROUP)
                {
                # Count the number of files that start with each prefix.

                # The keys are the first prefixes of the titles after the globally shared prefixes.  The values in %prefixCounts are the
                # number of files that have it, and the values in %sharedPrefixes are arrayrefs of all the shared prefixes including that
                # one.
                my %prefixCounts;
                my %sharedPrefixes;

                foreach my $entry (@{$groupEntry->GroupContent()})
                    {
                    if ($entry->Type() == ::MENU_FILE() &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) ne $entry->Target() &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) !~ / /)
                        {
                        my @tokens = NaturalDocs::Project::DefaultMenuTitleOf($entry->Target())
#                                                                                                            =~ /[A-Z]+[a-z0-9]*(?:\.|::)?|[a-z0-9]+(?:\.|::)?|./g;
                                                                                                            =~ /([A-Z]+[a-z0-9]*|[a-z0-9]+|.)(?:\.|::)?/g;

                        if (scalar @tokens > scalar @globalPrefixes)
                            {
                            my $leadToken = $tokens[scalar @globalPrefixes];

                            if (!exists $prefixCounts{$leadToken})
                                {
                                $prefixCounts{$leadToken} = 1;
                                $sharedPrefixes{$leadToken} = [ @tokens ];
                                }
                            else
                                {
                                $prefixCounts{$leadToken}++;
                                ::ShortenToMatchStrings($sharedPrefixes{$leadToken}, \@tokens);
                                };
                            };
                        };
                    };


                # Create the sub-groups if they have enough entries and if the shared prefix isn't merely a package prefix.  We don't
                # want to deal with package prefixes here because combining it with directory grouping gets really messy and hard.

                # The keys are the first prefixes of the titles after the globally shared prefixes.  The values are the groups they should
                # go into.  There will only be entries for groups that have at least MINFILESINNEWGROUP entries.
                my %prefixGroups;

                while (my ($leadPrefix, $count) = each %prefixCounts)
                    {
                    if ($count >= MINFILESINNEWGROUP)# && $sharedPrefixes{$leadPrefix}->[-1] !~ /(?:\.|::)$/)
                        {
                        my @newTitle = @{$sharedPrefixes{$leadPrefix}};

                        if (scalar @globalPrefixes)
                            {
                            # If the last section is text, we keep it as is because the following section is either distinctive text
                            # (WindowText and WindowBorder) or symbols.  In that case, grouping with the word (Window) is appropriate.
                            if ($newTitle[-1] =~ /[a-zA-Z0-9]$/)
                                {
                                splice(@newTitle, 0, scalar @globalPrefixes);
                                }
                            # However, if the last section is a symbol (PackageName::) we want to keep the leading word complete
                            # (PackageName:: as opposed to Name::)  This could happen if you have PackageName and a number of
                            # PackageName::X's being grouped this way.  You'd have one group for PackageName and a sub-group
                            # Name:: for all the X's.
                            else #if ($newTitle[scalar @globalPrefixes] !~ /[a-zA-Z0-9]$/)
                                {
                                my $index = scalar @globalPrefixes;

                                while ($index > 0 && $newTitle[$index - 1] =~ /[a-zA-Z0-9]$/)
                                    {  $index--;  };

                                if ($index > 0)
                                    {  splice(@newTitle, 0, $index);  };
                                };
                            };

                        #$newTitle[-1] =~ s/[:\.]+$//;

                        my $newGroup = NaturalDocs::Menu::Entry->New(::MENU_GROUP(), join('', @newTitle),
                                                                                                 undef, ::MENU_GROUP_UPDATETITLES());
                        if ($count > MAXFILESINGROUP)
                            {
                            $newGroup->SetFlags( $newGroup->Flags() | ::MENU_GROUP_UPDATESTRUCTURE() );
                            };

                        if (($groupEntry->Flags() & ::MENU_GROUP_HASENDOFORIGINAL()) == 0)
                            {
                            push @{$groupEntry->GroupContent()},
                                    NaturalDocs::Menu::Entry->New(::MENU_ENDOFORIGINAL(), undef, undef, undef);
                            $groupEntry->SetFlags( $groupEntry->Flags() | ::MENU_GROUP_HASENDOFORIGINAL() );
                            };

                        push @{$groupEntry->GroupContent()}, $newGroup;
                        $prefixGroups{$leadPrefix} = $newGroup;

                        $fileCount -= $count;
                        };
                    };


                # Fill the new sub-groups.

                my $index = 0;
                my $afterOriginal;

                while ($index < scalar @{$groupEntry->GroupContent()})
                    {
                    my $entry = $groupEntry->GroupContent()->[$index];

                    if ($entry->Type() == ::MENU_FILE() &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) ne $entry->Target() &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) !~ / /)
                        {
                        my @tokens =  NaturalDocs::Project::DefaultMenuTitleOf($entry->Target())
#                                                                                                            =~ /[A-Z]+[a-z0-9]*(?:\.|::)?|[a-z0-9]+(?:\.|::)?|./g;
                                                                                                            =~ /([A-Z]+[a-z0-9]*|[a-z0-9]+|.)(?:\.|::)?/g;

                        my $leadToken = $tokens[scalar @globalPrefixes];

                        if (defined $leadToken && exists $prefixGroups{$leadToken})
                            {
                            my $targetGroup = $prefixGroups{$leadToken};

                            if ($afterOriginal && ($targetGroup->Flags() & ::MENU_GROUP_HASENDOFORIGINAL()) == 0)
                                {
                                push @{$targetGroup->GroupContent()},
                                        NaturalDocs::Menu::Entry->New(::MENU_ENDOFORIGINAL(), undef, undef, undef);
                                $targetGroup->SetFlags( $targetGroup->Flags() | ::MENU_GROUP_HASENDOFORIGINAL() );
                                };

                            push @{$targetGroup->GroupContent()}, $entry;
                            splice(@{$groupEntry->GroupContent()}, $index, 1);
                            }
                        else
                            {  $index++;  };
                        }

                    elsif ($entry->Type() == ::MENU_ENDOFORIGINAL())
                        {
                        $afterOriginal = 1;
                        $index++;
                        }

                    else
                        {  $index++;  };
                    };

                if ($fileCount <= MAXFILESINGROUP)
                    {
                    $groupEntry->SetFlags( $groupEntry->Flags() & ~::MENU_GROUP_UPDATESTRUCTURE() );
                    };

                $groupEntry->SetFlags( $groupEntry->Flags() | ::MENU_GROUP_UPDATETITLES() | ::MENU_GROUP_UPDATEORDER() );

                };  # if count >MAXFILESINGROUP
            };  # if group has UPDATESTRUCTURE


        # Check any sub-groups.

        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_GROUP())
                {  push @groupStack, $entry;  };
            };
        };
    };


#
#   Function: DetectOrder
#
#   Detects the order of the entries in all groups that have the <MENU_GROUP_UPDATEORDER> flag set.  Will set one of the
#   <MENU_GROUP_FILESSORTED>, <MENU_GROUP_FILESANDGROUPSSORTED>, <MENU_GROUP_EVERYTHINGSORTED>, or
#   <MENU_GROUP_UNSORTED> flags.  It will always go for the most comprehensive sort possible, so if a group only has one
#   entry, it will be flagged as <MENU_GROUP_EVERYTHINGSORTED>.
#
#   <DetectIndexGroups()> should be called beforehand, as the <MENU_GROUP_ISINDEXGROUP> flag affects how the order is
#   detected.
#
#   The sort detection stops if it reaches a <MENU_ENDOFORIGINAL> entry, so new entries can be added to the end while still
#   allowing the original sort to be detected.
#
#   Parameters:
#
#       forceAll - If set, the order will be detected for all groups regardless of whether <MENU_GROUP_UPDATEORDER> is set.
#
sub DetectOrder #(forceAll)
    {
    my $forceAll = shift;
    my @groupStack = ( $menu );

    while (scalar @groupStack)
        {
        my $groupEntry = pop @groupStack;
        my $index = 0;


        # First detect the sort.

        if ($forceAll || ($groupEntry->Flags() & ::MENU_GROUP_UPDATEORDER()) )
            {
            my $order = ::MENU_GROUP_EVERYTHINGSORTED();

            my $lastFile;
            my $lastFileOrGroup;

            while ($index < scalar @{$groupEntry->GroupContent()} &&
                     $groupEntry->GroupContent()->[$index]->Type() != ::MENU_ENDOFORIGINAL() &&
                     $order != ::MENU_GROUP_UNSORTED())
                {
                my $entry = $groupEntry->GroupContent()->[$index];


                # Ignore the last entry if it's an index group.  We don't want it to affect the sort.

                if ($index + 1 == scalar @{$groupEntry->GroupContent()} &&
                    $entry->Type() == ::MENU_GROUP() && ($entry->Flags() & ::MENU_GROUP_ISINDEXGROUP()) )
                    {
                    # Ignore.

                    # This is an awkward code construct, basically working towards an else instead of using an if, but the code just gets
                    # too hard to read otherwise.  The compiled code should work out to roughly the same thing anyway.
                    }


                # Ignore the first entry if it's the general index in an index group.  We don't want it to affect the sort.

                elsif ($index == 0 && ($groupEntry->Flags() & ::MENU_GROUP_ISINDEXGROUP()) &&
                        $entry->Type() == ::MENU_INDEX() && !defined $entry->Target() )
                    {
                    # Ignore.
                    }


                # Degenerate the sort.

                else
                    {

                    if ($order == ::MENU_GROUP_EVERYTHINGSORTED() && $index > 0 &&
                        ::StringCompare($entry->Title(), $groupEntry->GroupContent()->[$index - 1]->Title()) < 0)
                        {  $order = ::MENU_GROUP_FILESANDGROUPSSORTED();  };

                    if ($order == ::MENU_GROUP_FILESANDGROUPSSORTED() &&
                        ($entry->Type() == ::MENU_FILE() || $entry->Type() == ::MENU_GROUP()) &&
                        defined $lastFileOrGroup && ::StringCompare($entry->Title(), $lastFileOrGroup->Title()) < 0)
                        {  $order = ::MENU_GROUP_FILESSORTED();  };

                    if ($order == ::MENU_GROUP_FILESSORTED() &&
                        $entry->Type() == ::MENU_FILE() && defined $lastFile &&
                        ::StringCompare($entry->Title(), $lastFile->Title()) < 0)
                        {  $order = ::MENU_GROUP_UNSORTED();  };

                    };


                # Set the lastX parameters for comparison and add sub-groups to the stack.

                if ($entry->Type() == ::MENU_FILE())
                    {
                    $lastFile = $entry;
                    $lastFileOrGroup = $entry;
                    }
                elsif ($entry->Type() == ::MENU_GROUP())
                    {
                    $lastFileOrGroup = $entry;
                    push @groupStack, $entry;
                    };

                $index++;
                };

            $groupEntry->SetFlags($groupEntry->Flags() | $order);
            };


        # Find any subgroups in the remaining entries.

        while ($index < scalar @{$groupEntry->GroupContent()})
            {
            my $entry = $groupEntry->GroupContent()->[$index];

            if ($entry->Type() == ::MENU_GROUP())
                {  push @groupStack, $entry;  };

            $index++;
            };
        };
    };


#
#   Function: GenerateAutoFileTitles
#
#   Creates titles for the unlocked file entries in all groups that have the <MENU_GROUP_UPDATETITLES> flag set.  It clears the
#   flag afterwards so it can be used efficiently for multiple sweeps.
#
#   Parameters:
#
#       forceAll - If set, forces all the unlocked file titles to update regardless of whether the group has the
#                     <MENU_GROUP_UPDATETITLES> flag set.
#
sub GenerateAutoFileTitles #(forceAll)
    {
    my $forceAll = shift;

    my @groupStack = ( $menu );

    while (scalar @groupStack)
        {
        my $groupEntry = pop @groupStack;

        if ($forceAll || ($groupEntry->Flags() & ::MENU_GROUP_UPDATETITLES()) )
            {
            # Find common prefixes and paths to strip from the default menu titles.

            my @sharedDirectories;
            my $noSharedDirectories;

            my @sharedPrefixes;
            my $noSharedPrefixes;

            foreach my $entry (@{$groupEntry->GroupContent()})
                {
                if ($entry->Type() == ::MENU_FILE())
                    {
                    # Find the common path among all file entries in this group.

                    if (!$noSharedDirectories)
                        {
                        my ($volume, $directoryString, $file) = NaturalDocs::File::SplitPath($entry->Target());
                        my @entryDirectories = NaturalDocs::File::SplitDirectories($directoryString);

                        if (!scalar @entryDirectories)
                            {  $noSharedDirectories = 1;  }
                        elsif (!scalar @sharedDirectories)
                            {  @sharedDirectories = @entryDirectories;  }
                        elsif ($entryDirectories[0] ne $sharedDirectories[0])
                            {  $noSharedDirectories = 1;  }

                        # If both arrays have entries, and the first is shared...
                        else
                            {
                            my $index = 1;

                            while ($index < scalar @sharedDirectories && $index < scalar @entryDirectories &&
                                     $entryDirectories[$index] eq $sharedDirectories[$index])
                                {  $index++;  };

                            if ($index < scalar @sharedDirectories)
                                {  splice(@sharedDirectories, $index);  };
                            };
                        };


                    # Find the common prefixes among all file entries that are unlocked and don't use the file name as their default title.

                    if (!$noSharedPrefixes && ($entry->Flags() & ::MENU_FILE_NOAUTOTITLE()) == 0 &&
                        NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()) ne $entry->Target())
                        {
                        my @entryPrefixes = split(/(\.|::|->)/, NaturalDocs::Project::DefaultMenuTitleOf($entry->Target()));

                        # Remove potential leading undef/empty string.
                        if (!length $entryPrefixes[0])
                            {  shift @entryPrefixes;  };

                        # Remove last entry.  Something has to exist for the title.
                        pop @entryPrefixes;

                        if (!scalar @entryPrefixes)
                            {  $noSharedPrefixes = 1;  }
                        elsif (!scalar @sharedPrefixes)
                            {  @sharedPrefixes = @entryPrefixes;  }
                        elsif ($entryPrefixes[0] ne $sharedPrefixes[0])
                            {  $noSharedPrefixes = 1;  }

                        # If both arrays have entries, and the first is shared...
                        else
                            {
                            my $index = 1;

                            while ($index < scalar @sharedPrefixes && $entryPrefixes[$index] eq $sharedPrefixes[$index])
                                {  $index++;  };

                            if ($index < scalar @sharedPrefixes)
                                {  splice(@sharedPrefixes, $index);  };
                            };
                        };

                    };  # if entry is MENU_FILE
                };  # foreach entry in group content.


            if (!scalar @sharedDirectories)
                {  $noSharedDirectories = 1;  };
            if (!scalar @sharedPrefixes)
                {  $noSharedPrefixes = 1;  };


            # Update all the menu titles of unlocked file entries.

            foreach my $entry (@{$groupEntry->GroupContent()})
                {
                if ($entry->Type() == ::MENU_FILE() && ($entry->Flags() & ::MENU_FILE_NOAUTOTITLE()) == 0)
                    {
                    my $title = NaturalDocs::Project::DefaultMenuTitleOf($entry->Target());

                    if ($title eq $entry->Target())
                        {
                        my ($volume, $directoryString, $file) = NaturalDocs::File::SplitPath($title);
                        my @directories = NaturalDocs::File::SplitDirectories($directoryString);

                        if (!$noSharedDirectories)
                            {  splice(@directories, 0, scalar @sharedDirectories);  };

                        # directory\...\directory\file.ext

                        if (scalar @directories > 2)
                            {  @directories = ( $directories[0], '...', $directories[-1] );  };

                        $directoryString = NaturalDocs::File::JoinDirectories(@directories);
                        $title = NaturalDocs::File::JoinPath($directoryString, $file);
                        }
                    else
                        {
                        my @segments = split(/(::|\.|->)/, $title);
                        if (!length $segments[0])
                            {  shift @segments;  };

                        if (!$noSharedPrefixes)
                            {  splice(@segments, 0, scalar @sharedPrefixes);  };

                        # package...package::target

                        if (scalar @segments > 5)
                            {  splice(@segments, 1, scalar @segments - 4, '...');  };

                        $title = join('', @segments);
                        };

                    $entry->SetTitle($title);
                    };  # If entry is an unlocked file
                };  # Foreach entry

            $groupEntry->SetFlags( $groupEntry->Flags() & ~::MENU_GROUP_UPDATETITLES() );

            };  # If updating group titles

        # Now find any subgroups.
        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_GROUP())
                {  push @groupStack, $entry;  };
            };
        };

    };


#
#   Function: ResortGroups
#
#   Resorts all groups that have <MENU_GROUP_UPDATEORDER> set.  Assumes <DetectOrder()> and <GenerateAutoFileTitles()>
#   have already been called.  Will clear the flag and any <MENU_ENDOFORIGINAL> entries on reordered groups.
#
#   Parameters:
#
#       forceAll - If set, resorts all groups regardless of whether <MENU_GROUP_UPDATEORDER> is set.
#
sub ResortGroups #(forceAll)
    {
    my $forceAll = shift;
    my @groupStack = ( $menu );

    while (scalar @groupStack)
        {
        my $groupEntry = pop @groupStack;

        if ($forceAll || ($groupEntry->Flags() & ::MENU_GROUP_UPDATEORDER()) )
            {
            my $newEntriesIndex;


            # Strip the ENDOFORIGINAL.

            if ($groupEntry->Flags() & ::MENU_GROUP_HASENDOFORIGINAL())
                {
                $newEntriesIndex = 0;

                while ($newEntriesIndex < scalar @{$groupEntry->GroupContent()} &&
                         $groupEntry->GroupContent()->[$newEntriesIndex]->Type() != ::MENU_ENDOFORIGINAL() )
                    {  $newEntriesIndex++;  };

                $groupEntry->DeleteFromGroup($newEntriesIndex);

                $groupEntry->SetFlags( $groupEntry->Flags() & ~::MENU_GROUP_HASENDOFORIGINAL() );
                }
            else
                {  $newEntriesIndex = -1;  };


            # Strip the exceptions.

            my $trailingIndexGroup;
            my $leadingGeneralIndex;

            if ( ($groupEntry->Flags() & ::MENU_GROUP_ISINDEXGROUP()) &&
                 $groupEntry->GroupContent()->[0]->Type() == ::MENU_INDEX() &&
                 !defined $groupEntry->GroupContent()->[0]->Target() )
                {
                $leadingGeneralIndex = shift @{$groupEntry->GroupContent()};
                if ($newEntriesIndex != -1)
                    {  $newEntriesIndex--;  };
                }

            elsif (scalar @{$groupEntry->GroupContent()} && $newEntriesIndex != 0)
                {
                my $lastIndex;

                if ($newEntriesIndex != -1)
                    {  $lastIndex = $newEntriesIndex - 1;  }
                else
                    {  $lastIndex = scalar @{$groupEntry->GroupContent()} - 1;  };

                if ($groupEntry->GroupContent()->[$lastIndex]->Type() == ::MENU_GROUP() &&
                    ( $groupEntry->GroupContent()->[$lastIndex]->Flags() & ::MENU_GROUP_ISINDEXGROUP() ) )
                    {
                    $trailingIndexGroup = $groupEntry->GroupContent()->[$lastIndex];
                    $groupEntry->DeleteFromGroup($lastIndex);

                    if ($newEntriesIndex != -1)
                        {  $newEntriesIndex++;  };
                    };
                };


            # If there weren't already exceptions, strip them from the new entries.

            if ( (!defined $trailingIndexGroup || !defined $leadingGeneralIndex) && $newEntriesIndex != -1)
                {
                my $index = $newEntriesIndex;

                while ($index < scalar @{$groupEntry->GroupContent()})
                    {
                    my $entry = $groupEntry->GroupContent()->[$index];

                    if (!defined $trailingIndexGroup &&
                        $entry->Type() == ::MENU_GROUP() && ($entry->Flags() & ::MENU_GROUP_ISINDEXGROUP()) )
                        {
                        $trailingIndexGroup = $entry;
                        $groupEntry->DeleteFromGroup($index);
                        }
                    elsif (!defined $leadingGeneralIndex && ($groupEntry->Flags() & ::MENU_GROUP_ISINDEXGROUP()) &&
                            $entry->Type() == ::MENU_INDEX() && !defined $entry->Target())
                        {
                        $leadingGeneralIndex = $entry;
                        $groupEntry->DeleteFromGroup($index);
                        }
                    else
                        {  $index++;  };
                    };
                };


            # If there's no order, we still want to sort the new additions.

            if ($groupEntry->Flags() & ::MENU_GROUP_UNSORTED())
                {
                if ($newEntriesIndex != -1)
                    {
                    my @newEntries =
                        @{$groupEntry->GroupContent()}[$newEntriesIndex..scalar @{$groupEntry->GroupContent()} - 1];

                    @newEntries = sort { CompareEntries($a, $b) } @newEntries;

                    foreach my $newEntry (@newEntries)
                        {
                        $groupEntry->GroupContent()->[$newEntriesIndex] = $newEntry;
                        $newEntriesIndex++;
                        };
                    };
                }

            elsif ($groupEntry->Flags() & ::MENU_GROUP_EVERYTHINGSORTED())
                {
                @{$groupEntry->GroupContent()} = sort { CompareEntries($a, $b) } @{$groupEntry->GroupContent()};
                }

            elsif ( ($groupEntry->Flags() & ::MENU_GROUP_FILESSORTED()) ||
                     ($groupEntry->Flags() & ::MENU_GROUP_FILESANDGROUPSSORTED()) )
                {
                my $groupContent = $groupEntry->GroupContent();
                my @newEntries;

                if ($newEntriesIndex != -1)
                    {  @newEntries = splice( @$groupContent, $newEntriesIndex );  };


                # First resort the existing entries.

                # A couple of support functions.  They're defined here instead of spun off into their own functions because they're only
                # used here and to make them general we would need to add support for the other sort options.

                sub IsIncludedInSort #(groupEntry, entry)
                    {
                    my ($groupEntry, $entry) = @_;

                    return ($entry->Type() == ::MENU_FILE() ||
                                ( $entry->Type() == ::MENU_GROUP() &&
                                    ($groupEntry->Flags() & ::MENU_GROUP_FILESANDGROUPSSORTED()) ) );
                    };

                sub IsSorted #(groupEntry)
                    {
                    my $groupEntry = shift;
                    my $lastApplicable;

                    foreach my $entry (@{$groupEntry->GroupContent()})
                        {
                        # If the entry is applicable to the sort order...
                        if (IsIncludedInSort($groupEntry, $entry))
                            {
                            if (defined $lastApplicable)
                                {
                                if (CompareEntries($entry, $lastApplicable) < 0)
                                    {  return undef;  };
                                };

                            $lastApplicable = $entry;
                            };
                        };

                    return 1;
                    };


                # There's a good chance it's still sorted.  They should only become unsorted if an auto-title changes.
                if (!IsSorted($groupEntry))
                    {
                    # Crap.  Okay, method one is to sort each group of continuous sortable elements.  There's a possibility that doing
                    # this will cause the whole to become sorted again.  We try this first, even though it isn't guaranteed to succeed,
                    # because it will restore the sort without moving any unsortable entries.

                    # Copy it because we'll need the original if this fails.
                    my @originalGroupContent = @$groupContent;

                    my $index = 0;
                    my $startSortable = 0;

                    while (1)
                        {
                        # If index is on an unsortable entry or the end of the array...
                        if ($index == scalar @$groupContent || !IsIncludedInSort($groupEntry, $groupContent->[$index]))
                            {
                            # If we have at least two sortable entries...
                            if ($index - $startSortable >= 2)
                                {
                                # Sort them.
                                my @sortableEntries = @{$groupContent}[$startSortable .. $index - 1];
                                @sortableEntries = sort { CompareEntries($a, $b) } @sortableEntries;
                                foreach my $sortableEntry (@sortableEntries)
                                    {
                                    $groupContent->[$startSortable] = $sortableEntry;
                                    $startSortable++;
                                    };
                                };

                            if ($index == scalar @$groupContent)
                                {  last;  };

                            $startSortable = $index + 1;
                            };

                        $index++;
                        };

                    if (!IsSorted($groupEntry))
                        {
                        # Crap crap.  Okay, now we do a full sort but with potential damage to the original structure.  Each unsortable
                        # element is locked to the next sortable element.  We sort the sortable elements, bringing all the unsortable
                        # pieces with them.

                        my @pieces = ( [ ] );
                        my $currentPiece = $pieces[0];

                        foreach my $entry (@originalGroupContent)
                            {
                            push @$currentPiece, $entry;

                            # If the entry is sortable...
                            if (IsIncludedInSort($groupEntry, $entry))
                                {
                                $currentPiece = [ ];
                                push @pieces, $currentPiece;
                                };
                            };

                        my $lastUnsortablePiece;

                        # If the last entry was sortable, we'll have an empty piece at the end.  Drop it.
                        if (scalar @{$pieces[-1]} == 0)
                            {  pop @pieces;  }

                        # If the last entry wasn't sortable, the last piece won't end with a sortable element.  Save it, but remove it
                        # from the list.
                        else
                            {  $lastUnsortablePiece = pop @pieces;  };

                        # Sort the list.
                        @pieces = sort { CompareEntries( $a->[-1], $b->[-1] ) } @pieces;

                        # Copy it back to the original.
                        if (defined $lastUnsortablePiece)
                            {  push @pieces, $lastUnsortablePiece;  };

                        my $index = 0;

                        foreach my $piece (@pieces)
                            {
                            foreach my $entry (@{$piece})
                                {
                                $groupEntry->GroupContent()->[$index] = $entry;
                                $index++;
                                };
                            };
                        };
                    };


                # Okay, the orginal entries are sorted now.  Sort the new entries and apply.

                if (scalar @newEntries)
                    {
                    @newEntries = sort { CompareEntries($a, $b) } @newEntries;
                    my @originalEntries = @$groupContent;
                    @$groupContent = ( );

                    while (1)
                        {
                        while (scalar @originalEntries && !IsIncludedInSort($groupEntry, $originalEntries[0]))
                            {  push @$groupContent, (shift @originalEntries);  };

                        if (!scalar @originalEntries || !scalar @newEntries)
                            {  last;  };

                        while (scalar @newEntries && CompareEntries($newEntries[0], $originalEntries[0]) < 0)
                            {  push @$groupContent, (shift @newEntries);  };

                        push @$groupContent, (shift @originalEntries);

                        if (!scalar @originalEntries || !scalar @newEntries)
                            {  last;  };
                        };

                    if (scalar @originalEntries)
                        {  push @$groupContent, @originalEntries;  }
                    elsif (scalar @newEntries)
                        {  push @$groupContent, @newEntries;  };
                    };
                };


            # Now re-add the exceptions.

            if (defined $leadingGeneralIndex)
                {
                unshift @{$groupEntry->GroupContent()}, $leadingGeneralIndex;
                };

            if (defined $trailingIndexGroup)
                {
                $groupEntry->PushToGroup($trailingIndexGroup);
                };

            };

        foreach my $entry (@{$groupEntry->GroupContent()})
            {
            if ($entry->Type() == ::MENU_GROUP())
                {  push @groupStack, $entry;  };
            };
        };
    };


#
#   Function: CompareEntries
#
#   A comparison function for use in sorting.  Compares the two entries by their titles with <StringCompare()>, but in the case
#   of a tie, puts <MENU_FILE> entries above <MENU_GROUP> entries.
#
sub CompareEntries #(a, b)
    {
    my ($a, $b) = @_;

    my $result = ::StringCompare($a->Title(), $b->Title());

    if ($result == 0)
        {
        if ($a->Type() == ::MENU_FILE() && $b->Type() == ::MENU_GROUP())
            {  $result = -1;  }
        elsif ($a->Type() == ::MENU_GROUP() && $b->Type() == ::MENU_FILE())
            {  $result = 1;  };
        };

    return $result;
    };


#
#   Function: SharedDirectoriesOf
#
#   Returns an array of all the directories shared by the files in the group.  If none, returns an empty array.
#
sub SharedDirectoriesOf #(group)
    {
    my $groupEntry = shift;
    my @sharedDirectories;

    foreach my $entry (@{$groupEntry->GroupContent()})
        {
        if ($entry->Type() == ::MENU_FILE())
            {
            my @entryDirectories = NaturalDocs::File::SplitDirectories( (NaturalDocs::File::SplitPath($entry->Target()))[1] );

            if (!scalar @sharedDirectories)
                {  @sharedDirectories = @entryDirectories;  }
            else
                {  ::ShortenToMatchStrings(\@sharedDirectories, \@entryDirectories);  };

            if (!scalar @sharedDirectories)
                {  last;  };
            };
        };

    return @sharedDirectories;
    };


1;
