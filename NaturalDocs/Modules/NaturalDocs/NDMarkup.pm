###############################################################################
#
#   Section: NDMarkup
#
###############################################################################
#
#   A markup format used by the parser, both internally and in <NaturalDocs::Parser::ParsedTopic> objects.  Text formatted in
#   NDMarkup will only have the tags documented below.
#
###############################################################################

# This file is part of Natural Docs, which is Copyright � 2003 Greg Valure
# Natural Docs is licensed under the GPL


#
#   About: Top-Level Tags
#
#       All content will be surrounded by one of the top-level tags.  These tags will not appear within each other.
#
#       <p></p>         - Surrounds a paragraph.  Paragraph breaks will replace double line breaks, and single line breaks will
#                             be removed completely.
#
#       <code></code>   - Surrounds code or text diagrams that should appear literally in the output.
#
#       <h></h>         - Surrounds a heading.
#
#       <ul></ul>       - Surrounds a bulleted (unordered) list.
#       <dl></dl>       - Surrounds a description list, which is what you are reading.
#
#
#   About: List Item Tags
#
#       These tags will only appear within their respective lists.
#
#       <li></li>       - Surrounds a bulleted list item.
#       <de></de>   - Surrounds a description list entry, which is the left side.  It will always be followed by a description list
#                         description.
#       <ds></ds>   - Surrounds a description list symbol.  This is the same as a description list entry, except that the content
#                         is also a referencable symbol.  This occurs when the section type is <TOPIC_LIST>.  This tag will always
#                         be followed by a description list description.
#       <dd></dd>   - Surrounds a description list description, which is the right side.  It will always be preceded by a description
#                         list entry or symbol.
#
#   About: Text Tags
#
#       These tags will only appear in paragraphs, headings, or description list descriptions.
#
#       <b></b>         - Bold
#       <i></i>         - Italics
#       <u></u>         - Underline
#
#       <link></link>   - Surrounds a potential link to a symbol; potential because the target is not guaranteed to exist.  This
#                             tag merely designates an attempted link.  No other tags will appear between them.
#
#   About: Amp Chars
#
#       These are the only amp chars supported, and will appear everywhere.  Every other character will appear as is.
#
#       &amp;       - The ampersand &.
#       &quot;      - The double quote ".
#       &lt;        - The less than sign <.
#       &gt;        - The greater than sign >.
#
#
#   About: General Tag Properties
#
#       Since the tags are generated, they will always have the following properties, which will make pattern matching much
#       easier.
#
#       - Tags and amp chars will always be in all lowercase.
#       - There will be no properties or extraneous whitespace within tags.  They will only appear exactly as documented here.
#       - All code is valid, meaning tags will always be closed, <li>s will only appear within <ul>s, etc.
#
#       So, for example, you can match symbol links with /<link>([^<]+)<\/link>/ and $1 will be the symbol.  No surprises or
#       gotchas.  No need for sophisticated parsing routines.
#
#       Remember that for symbol definitions, the text should appear as is, but internally (such as for the anchor) they need to
#       be passed through <NaturalDocs::SymbolTable::Defines()> so that the output file is just as tolerant as
#       <NaturalDocs::SymbolTable>.
#


###############################################################################
#
#   Package: NaturalDocs::NDMarkup
#
###############################################################################
#
#   A package of support functions for dealing with <NDMarkup>.
#
#   Usage and Dependencies:
#
#       The package doesn't depend on any Natural Docs packages and is ready to use right away.
#
###############################################################################

use strict;
use integer;

package NaturalDocs::NDMarkup;

#
#   Function: ConvertAmpChars
#
#   Substitutes certain characters with their <NDMarkup> amp chars.
#
#   Parameters:
#
#       text - The block of text to convert.
#
#   Returns:
#
#       The converted text block.
#
sub ConvertAmpChars #(text)
    {
    my $text = shift;

    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/\"/&quot;/g;

    return $text;
    };


#
#   Function: RestoreAmpChars
#
#   Replaces <NDMarkup> amp chars with their original symbols.
#
#   Parameters:
#
#       text - The text to restore.
#
#   Returns:
#
#       The restored text.
#
sub RestoreAmpChars #(text)
    {
    my $text = shift;

    $text =~ s/&quot;/\"/g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&lt;/</g;
    $text =~ s/&amp;/&/g;

    return $text;
    };


1;