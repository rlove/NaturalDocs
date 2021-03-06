###############################################################################
#
#   Class: NaturalDocs::Languages::JavaScriptFull
#
###############################################################################
#
#   A subclass to handle the JavaScript language with full recognition.
#
#
#   Topic: Language Support
#
#       Supported:
#
#       - Variables
#       - Functions
#       - Prototypes declared as object literals
#
#       Not supported yet:
#
#       - Method prototype declarations by assignment to a function
#       - Function declarations by assignment
#
###############################################################################

# This file is part of Extended Natural Docs, Copyright � 2013 Ferdinand Prantl
# Natural Docs is licensed under version 3 of the GNU Affero General Public License (AGPL)
# Refer to License.txt for the complete details

use strict;
use integer;

package NaturalDocs::Languages::JavaScriptFull;

use base 'NaturalDocs::Languages::Advanced';


################################################################################
# Group: Constants and Types


################################################################################
# Group: Package Variables

#
#   hash: declarationEnders
#   An existence hash of all the tokens that can end a declaration.  This is
#   important because statements don't require a semicolon to end.  The keys
#   are in all lowercase.
#
my %declarationEnders = ( ';' => 1, '}' => 1, '{' => 1,
                          'var' => 1, 'function' => 1 );



################################################################################
# Group: Interface Functions


#
#   Function: PackageSeparator
#   Returns the package separator symbol.
#
sub PackageSeparator
    {  return '.';  };


#
#   Function: TypeBeforeParameter
#   Returns whether the type appears before the parameter in prototypes.
#
sub TypeBeforeParameter
    {  return 0;  };


#
#   Function: ParseFile
#
#   Parses the passed source file, sending comments acceptable for
#   documentation to <NaturalDocs::Parser->OnComment()>.
#
#   Parameters:
#
#       sourceFile - The <FileName> to parse.
#       topicList  - A reference to the list of <NaturalDocs::Parser::ParsedTopics>
#                    being built by the file.
#
#   Returns:
#
#       The array ( autoTopics, scopeRecord ).
#
#       autoTopics  - An arrayref of automatically generated topics from the
#                     file, or undef if none.
#       scopeRecord - An arrayref of <NaturalDocs::Languages::Advanced::ScopeChanges>,
#                     or undef if none.
#
sub ParseFile #(sourceFile, topicsList)
    {
    my ($self, $sourceFile, $topicsList) = @_;

    $self->ParseForCommentsAndTokens($sourceFile, [ '//' ], [ '/*', '*/' ],
        [ '///' ], [ '/**', '*/' ]);

    my $tokens = $self->Tokens();
    my $index = 0;
    my $lineNumber = 1;

    while ($index < scalar @$tokens)
        {
        if ($self->TryToSkipWhitespace(\$index, \$lineNumber) ||
            $self->TryToGetFunction(\$index, \$lineNumber) ||
            $self->TryToGetVariable(\$index, \$lineNumber) )
            {
            # The functions above will handle everything.
            }

        elsif ($tokens->[$index] eq '{')
            {
            $self->StartScope('}', $lineNumber, undef, undef, undef);
            $index++;
            }

        elsif ($tokens->[$index] eq '}')
            {
            if ($self->ClosingScopeSymbol() eq '}')
                {  $self->EndScope($lineNumber);  };

            $index++;
            }

        else
            {
            $self->SkipToNextStatement(\$index, \$lineNumber);
            };
        };


    # Don't need to keep these around.
    $self->ClearTokens();


    my $autoTopics = $self->AutoTopics();

    my $scopeRecord = $self->ScopeRecord();
    if (defined $scopeRecord && !scalar @$scopeRecord)
        {  $scopeRecord = undef;  };

    return ( $autoTopics, $scopeRecord );
    };



################################################################################
# Group: Statement Parsing Functions
# All functions here assume that the current position is at the beginning
# of a statement.
#
# Note for developers: I am well aware that the code in these functions
# do not check if we're past the end of the tokens as often as it should.
# We're making use of the fact that Perl will always return undef in these
# cases to keep the code simpler.


#
#   Function: TryToGetFunction
#
#   Determines if the position is on a function declaration, and if so,
#   generates a topic for it, skips it, and returns true.
#
#   Supported Syntaxes:
#
#       - Functions: function myFunction(arg1, arg2)
#
sub TryToGetFunction #(indexRef, lineNumberRef, name)
    {
    my ($self, $indexRef, $lineNumberRef, $name) = @_;
    my $tokens = $self->Tokens();

    my $index = $$indexRef;
    my $lineNumber = $$lineNumberRef;

    my $startIndex = $index;
    my $startLine = $lineNumber;

    # The declaration statement starts with the keyword `function`.
    if ($tokens->[$index] ne 'function')
        {  return undef;  };

    $index++;
    $self->TryToSkipWhitespace(\$index, \$lineNumber);

    # This method may be called from a variable declaration assigning
    # a function to the variable. The name would come before the function.
    unless ($name)
      {
      # The function name follows.
      $name = $tokens->[$index];
      if (!$name)
          {  return undef;  };

      $index++;
      $self->TryToSkipWhitespace(\$index, \$lineNumber);
    }
  
    # The function parameters follow.
    if ($tokens->[$index] ne '(')
        {  return undef;  };

    my $type = ::TOPIC_FUNCTION();

    $index++;
    # Move the current position behind the last function parameter.
    $self->GenericSkipUntilAfter(\$index, \$lineNumber, ')');
    $self->TryToSkipWhitespace(\$index, \$lineNumber);

    # Format the function declaration for the documentation.
    my $prototype = $self->NormalizePrototype(
        $self->CreateString($startIndex, $index), $type, $name);

    # The function implementation follows.
    if ($tokens->[$index] ne '{')
        {  return undef;  };

    # Move the current position behind the function implementation.
    $self->GenericSkip(\$index, \$lineNumber);

    # Add the function topic.
    my $scope = $self->CurrentScope();
    $self->AddAutoTopic(NaturalDocs::Parser::ParsedTopic->New($type, $name,
        $scope, $self->CurrentUsing(), $prototype, undef, undef, $startLine));

    # Update parsing position on success.
    $$indexRef = $index;
    $$lineNumberRef = $lineNumber;

    return 1;
    };


#
#   Function: TryToGetVariable
#
#   Determines if the position is on a variable declaration statement,
#   and if so, generates a topic for each variable, skips the statement,
#   and returns true.
#
#   Supported Syntaxes:
#
#       - Variables:    var var1 = 1;
#       - Functions:    var myFunction = function (arg1, arg2)
#       - Combinations: var var1 = 1, var2, myFunction = function () {};
#
sub TryToGetVariable #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    my $index = $$indexRef;
    my $lineNumber = $$lineNumberRef;

    my $startIndex = $index;
    my $startLine = $lineNumber;

    # The declaration statement starts with the keyword `var`.
    if ($tokens->[$index] ne 'var')
        {  return undef;  };

    $index++;
    $self->TryToSkipWhitespace(\$index, \$lineNumber);

    my $endVarIndex = $index;
    my @names;

    # Variable delarations can be separated by commas.
    for (;;)
        {
        # The variable name follows.
        my $name = $tokens->[$index];
        if (!$name)
            {  return undef;  };

        $index++;
        $self->TryToSkipWhitespace(\$index, \$lineNumber);

        # The variable value assignment may follow.
        if ($tokens->[$index] eq '=')
            {
            my $functionIndex = $index + 1;
            my $functionLineNumber = $lineNumber;
            $self->TryToSkipWhitespace(\$functionIndex, \$functionLineNumber);

            # The variable may be assigned a function;
            if ($tokens->[$functionIndex] eq 'function')
                {
                $index = $functionIndex;
                $lineNumber = $functionLineNumber;
                unless ($self->TryToGetFunction(\$index, \$lineNumber, $name))
                    {  return undef;  };
                }
            # The variable is assigned a value.
            else
                {
                push @names, $name;

                do
                    {
                    $self->GenericSkip(\$index, \$lineNumber);
                    }
                while ($tokens->[$index] ne ',' &&
                    !exists $declarationEnders{$tokens->[$index]} &&
                    $index < scalar @$tokens);
                }
            }
        else
            {
            push @names, $name;
            }

        # Another variable declaration may follow.
        if ($tokens->[$index] eq ',')
            {
            $index++;
            $self->TryToSkipWhitespace(\$index, \$lineNumber);
            }
        elsif (exists $declarationEnders{$tokens->[$index]})
            {  last;  }
        else
            {  return undef;  };
        };

    # Add the variable topics.
    my $type = ::TOPIC_VARIABLE();
    my $prototypePrefix = $self->CreateString($startIndex, $endVarIndex);

    for (my $i = 0; $i < scalar @names; $i++)
        {
        # Format the variable declaration for the documentation.
        my $prototype = $self->NormalizePrototype( $prototypePrefix . ' ' . $names[$i], $type);
        my $scope = $self->CurrentScope();

        $self->AddAutoTopic(NaturalDocs::Parser::ParsedTopic->New($type, $names[$i],
            $scope, $self->CurrentUsing(), $prototype, undef, undef, $startLine));
        };

    # Update parsing position on success.
    $$indexRef = $index;
    $$lineNumberRef = $lineNumber;

    return 1;
    };



################################################################################
# Group: Low Level Parsing Functions


#
#   Function: TokenizeLine
#
#   Converts the passed line to tokens as described in <ParseForCommentsAndTokens>
#   and adds them to <Tokens()>.  Also adds a line break token after it.
#
sub TokenizeLine #(line)
    {
    my ($self, $line) = @_;
    push @{$self->Tokens()}, $line =~ /([\w\$]+|[ \t]+|.)/g, "\n";
    };


#
#   Function: GenericSkip
#
#   Advances the position one place through general code.
#
#   - If the position is on a string, it will skip it completely.
#   - If the position is on an opening symbol, it will skip until the past
#     the closing symbol.
#   - If the position is on whitespace (including comments), it will skip
#     it completely.
#   - Otherwise it skips one token.
#
#   Parameters:
#
#       indexRef - A reference to the current index.
#       lineNumberRef - A reference to the current line number.
#
sub GenericSkip #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    # We can ignore the scope stack because we're just skipping everything
    # without parsing, and we need recursion anyway.
    if ($tokens->[$$indexRef] eq '{')
        {
        $$indexRef++;
        $self->GenericSkipUntilAfter($indexRef, $lineNumberRef, '}');
        }
    elsif ($tokens->[$$indexRef] eq '(')
        {
        $$indexRef++;
        $self->GenericSkipUntilAfter($indexRef, $lineNumberRef, ')');
        }
    elsif ($tokens->[$$indexRef] eq '[')
        {
        $$indexRef++;
        $self->GenericSkipUntilAfter($indexRef, $lineNumberRef, ']');
        }

    elsif ($self->TryToSkipWhitespace($indexRef, $lineNumberRef) ||
            $self->TryToSkipString($indexRef, $lineNumberRef) ||
            $self->TryToSkipRegExp($indexRef, $lineNumberRef)  )
        {
        }

    else
        {  $$indexRef++;  };
    };


#
#   Function: GenericSkipUntilAfter
#
#   Advances the position via <GenericSkip()> until a specific token is
#   reached and passed.
#
sub GenericSkipUntilAfter #(indexRef, lineNumberRef, token)
    {
    my ($self, $indexRef, $lineNumberRef, $token) = @_;
    my $tokens = $self->Tokens();

    while ($$indexRef < scalar @$tokens && $tokens->[$$indexRef] ne $token)
        {  $self->GenericSkip($indexRef, $lineNumberRef);  };

    if ($tokens->[$$indexRef] eq "\n")
        {  $$lineNumberRef++;  };
    $$indexRef++;
    };


#
#   Function: SkipToNextStatement
#
#   Advances the position via <GenericSkip()> until the next statement,
#   which is defined as anything in <declarationEnders> not appearing in
#   brackets or strings.  It will always advance at least one token.
#
sub SkipToNextStatement #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    if ($tokens->[$$indexRef] eq ';')
        {  $$indexRef++;  }

    else
        {
        do
            {
            $self->GenericSkip($indexRef, $lineNumberRef);
            }
        while ( $$indexRef < scalar @$tokens &&
                  !exists $declarationEnders{$tokens->[$$indexRef]} );
        };
    };


#
#   Function: TryToSkipRegExp
#   If the current position is on a regular expression, skip past it and
#   return true.
#
sub TryToSkipRegExp #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    if ($tokens->[$$indexRef] eq '/')
        {
        # A slash can either start a regular expression or be a divide symbol.  Skip backwards to see what the previous symbol is.
        my $index = $$indexRef - 1;

        while ($index >= 0 && $tokens->[$index] =~ /^(?: |\t|\n)/)
            {  $index--;  };

        if ($index < 0 || $tokens->[$index] !~ /^[\:\=\(\[\,]/)
            {  return 0;  };

        $$indexRef++;

        while ($$indexRef < scalar @$tokens && $tokens->[$$indexRef] ne '/')
            {
            if ($tokens->[$$indexRef] eq '\\')
                {  $$indexRef += 2;  }
            elsif ($tokens->[$$indexRef] eq "\n")
                {
                $$indexRef++;
                $$lineNumberRef++;
                }
            else
                {  $$indexRef++;  }
            };

        if ($$indexRef < scalar @$tokens)
            {
            $$indexRef++;

            if ($tokens->[$$indexRef] =~ /^[gimsx]+$/i)
                {  $$indexRef++;  };
            };

        return 1;
        }
    else
        {  return 0;  };
    };


#
#   Function: TryToSkipString
#   If the current position is on a string delimiter, skip past the string
#   and return true.
#
#   Parameters:
#
#       indexRef - A reference to the index of the position to start at.
#       lineNumberRef - A reference to the line number of the position.
#
#   Returns:
#
#       Whether the position was at a string.
#
#   Syntax Support:
#
#       - Supports quotes and apostrophes.
#
sub TryToSkipString #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;

    return ($self->SUPER::TryToSkipString($indexRef, $lineNumberRef, '\'') ||
               $self->SUPER::TryToSkipString($indexRef, $lineNumberRef, '"') );
    };


#
#   Function: TryToSkipWhitespace
#   If the current position is on a whitespace token, a line break token,
#   or a comment, it skips them and returns true.  If there are a number
#   of these in a row, it skips them all.
#
sub TryToSkipWhitespace #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    my $result;

    while ($$indexRef < scalar @$tokens)
        {
        if ($tokens->[$$indexRef] =~ /^[ \t]/)
            {
            $$indexRef++;
            $result = 1;
            }
        elsif ($tokens->[$$indexRef] eq "\n")
            {
            $$indexRef++;
            $$lineNumberRef++;
            $result = 1;
            }
        elsif ($self->TryToSkipComment($indexRef, $lineNumberRef))
            {
            $result = 1;
            }
        else
            {  last;  };
        };

    return $result;
    };


#
#   Function: TryToSkipComment
#   If the current position is on a comment, skip past it and return true.
#
sub TryToSkipComment #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;

    return ( $self->TryToSkipLineComment($indexRef, $lineNumberRef) ||
                $self->TryToSkipMultilineComment($indexRef, $lineNumberRef) );
    };


#
#   Function: TryToSkipLineComment
#   If the current position is on a line comment symbol, skip past it
#   and return true.
#
sub TryToSkipLineComment #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    if ($tokens->[$$indexRef] eq '/' && $tokens->[$$indexRef+1] eq '/')
        {
        $self->SkipRestOfLine($indexRef, $lineNumberRef);
        return 1;
        }
    else
        {  return undef;  };
    };


#
#   Function: TryToSkipMultilineComment
#   If the current position is on an opening comment symbol, skip past it
#   and return true.
#
sub TryToSkipMultilineComment #(indexRef, lineNumberRef)
    {
    my ($self, $indexRef, $lineNumberRef) = @_;
    my $tokens = $self->Tokens();

    if ($tokens->[$$indexRef] eq '/' && $tokens->[$$indexRef+1] eq '*')
        {
        $self->SkipUntilAfter($indexRef, $lineNumberRef, '*', '/');
        return 1;
        }
    else
        {  return undef;  };
    };


#
#   Function: NormalizePrototype
#
#   Normalizes a prototype.  Specifically, condenses spaces, tabs, and line
#   breaks into single spaces and removes leading and trailing ones.  It may
#   also unify the syntax depending on the related topic type.
#
#   Parameters:
#
#       prototype - The original prototype string.
#       type      - The type of the related topic.
#       name      - The function name if the prototype lacks it.
#
#   Returns:
#
#       The normalized prototype.
#
sub NormalizePrototype #(prototype, type, name)
    {
    my ($self, $prototype, $type, $name) = @_;

    $prototype =~ tr/ \t\r\n/ /s;
    $prototype =~ s/^ //;
    $prototype =~ s/ $//;
    $prototype =~ s/function\s*\(/function $name(/;

    return $prototype;
    };


1;
