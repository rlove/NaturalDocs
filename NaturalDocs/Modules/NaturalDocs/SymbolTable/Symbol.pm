###############################################################################
#
#   Package: NaturalDocs::SymbolTable::Symbol
#
###############################################################################
#
#   A class representing a symbol or a potential symbol.
#
###############################################################################

# This file is part of Natural Docs, which is Copyright � 2003 Greg Valure
# Natural Docs is licensed under the GPL

use strict;
use integer;

package NaturalDocs::SymbolTable::Symbol;


###############################################################################
# Group: Implementation

#
#   Constants: Members
#
#   The class is implemented as a blessed arrayref.  The following constants are its members.
#
#       DEFINITIONS             - A hashref of all the files which define this symbol.  The keys are the file names, and the values are
#                                         ( type, prototype) arrayrefs with types being one of the <Topic Types>.  If no files define this
#                                         symbol, this item will be undef.
#       GLOBAL_DEFINITION  - The name of the file which defines the global version of the symbol, which is what is used if
#                                          a file references the symbol but does not have its own definition.  If there are no definitions, this
#                                          item will be undef.
#       REFERENCES  - A hashref of the references that can be interpreted as this symbol.  This doesn't mean these
#                                          references necessarily are.  The keys are the reference strings, and the values are the scores of
#                                          the interpretations.  If no references can be interpreted as this symbol, this item will be undef.
#
use constant DEFINITIONS => 0;
use constant GLOBAL_DEFINITION => 1;
use constant REFERENCES => 2;


###############################################################################
# Group: Modification Functions

#
#   Function: New
#
#   Creates and returns a new object.
#
sub New
    {
    # Let's make it safe, since normally you can pass values to New.  Having them just be ignored would be an obscure error.
    if (scalar @_)
        {  die "You can't pass values to NaturalDocs::SymbolTable::Symbol::New()\n";  };

    my $object = [ undef, undef, undef ];
    bless $object;

    return $object;
    };

#
#   Function: AddDefinition
#
#   Adds a symbol definition.  If this is the first definition for this symbol, it will become the global definition.  If the definition
#   already exists for the file, it will replace the old one.
#
#   Parameters:
#
#       file   - The file that defines the symbol.
#       type - The topic type of the definition.  One of <Topic Types>.
#       prototype - The prototype of the definition, if applicable.  Undef otherwise.
#
sub AddDefinition #(file, type, prototype)
    {
    my ($self, $file, $type, $prototype) = @_;

    if (!defined $self->[DEFINITIONS])
        {
        $self->[DEFINITIONS] = { };
        $self->[GLOBAL_DEFINITION] = $file;
        };

    $self->[DEFINITIONS]{$file} = [ $type, $prototype ];
    };


#
#   Function: DeleteDefinition
#
#   Removes a symbol definition.  If the definition served as the global definition, a new one will be selected.
#
#   Parameters:
#
#       file - The definition to delete.
#
sub DeleteDefinition #(file)
    {
    my ($self, $file) = @_;

    # If there are no definitions...
    if (!defined $self->[DEFINITIONS])
        {  return;  };

    delete $self->[DEFINITIONS]{$file};

    # If there are no more definitions...
    if (!scalar keys %{$self->[DEFINITIONS]})
        {
        $self->[DEFINITIONS] = undef;

        # If definitions was previously defined, and now is empty, we can safely assume that the global definition was just deleted
        # without checking it against $file.

        $self->[GLOBAL_DEFINITION] = undef;
        }

    # If there are more definitions and the global one was just deleted...
    elsif ($self->[GLOBAL_DEFINITION] eq $file)
        {
        # Which one becomes global is pretty much random.
        $self->[GLOBAL_DEFINITION] = (keys %{$self->[DEFINITIONS]})[0];
        };
    };


#
#   Function: AddReference
#
#   Adds a reference that can be interpreted as this symbol.  It can be, but not necessarily is.
#
#   Parameters:
#
#       referenceString - The string of the reference.
#       score                - The score of this interpretation.
#
sub AddReference #(referenceString, score)
    {
    my ($self, $referenceString, $score) = @_;

    if (!defined $self->[REFERENCES])
        {  $self->[REFERENCES] = { };  };

    $self->[REFERENCES]{$referenceString} = $score;
    };


#
#   Function: DeleteReference
#
#   Deletes a reference that can be interpreted as this symbol.
#
#   Parameters:
#
#       referenceString - The string of the reference to delete.
#
sub DeleteReference #(referenceString)
    {
    my ($self, $referenceString) = @_;

    # If there are no definitions...
    if (!defined $self->[REFERENCES])
        {  return;  };

    delete $self->[REFERENCES]{$referenceString};

    # If there are no more definitions...
    if (!scalar keys %{$self->[REFERENCES]})
        {
        $self->[REFERENCES] = undef;
        };
    };


#
#   Function: DeleteAllReferences
#
#   Removes all references that can be interpreted as this symbol.
#
sub DeleteAllReferences
    {
    $_[0]->[REFERENCES] = undef;
    };


###############################################################################
# Group: Information Functions

#
#   Function: IsDefined
#
#   Returns whether the symbol is defined anywhere or not.  If it's not, that means it's just a potential interpretation of a
#   reference.
#
sub IsDefined
    {
    return defined $_[0]->[GLOBAL_DEFINITION];
    };

#
#   Function: IsDefinedIn
#
#   Returns whether the symbol is defined in the passed file.
#
sub IsDefinedIn #(file)
    {
    my ($self, $file) = @_;
    return ($self->IsDefined() && exists $self->[DEFINITIONS]{$file});
    };


#
#   Function: Definitions
#
#   Returns an array of all the files that define this symbol.  If none do, will return an empty array.
#
sub Definitions
    {
    my $self = shift;

    if ($self->IsDefined())
        {  return keys %{$self->[DEFINITIONS]};  }
    else
        {  return ( );  };
    };


#
#   Function: GlobalDefinition
#
#   Returns the file that contains the global definition of this symbol, or undef if the symbol isn't defined.
#
sub GlobalDefinition
    {
    return $_[0]->[GLOBAL_DEFINITION];
    };


#
#   Function: TypeDefinedIn
#
#   Returns the type of symbol defined in the passed file, or undef if it's not defined in that file.
#
sub TypeDefinedIn #(file)
    {
    my ($self, $file) = @_;

    if ($self->IsDefined())
        {  return $self->[DEFINITIONS]{$file}[0];  }
    else
        {  return undef;  };
    };


#
#   Function: GlobalType
#
#   Returns the type of the global definition.  Will be one of <Topic Types> or undef if the symbol isn't defined.
#
sub GlobalType
    {
    my $self = shift;

    my $globalDefinition = $self->GlobalDefinition();

    if (!defined $globalDefinition)
        {  return undef;  }
    else
        {  return $self->[DEFINITIONS]{$globalDefinition}[0];  };
    };


#
#   Function: PrototypeTypeDefinedIn
#
#   Returns the prototype of symbol defined in the passed file, or undef if it doesn't exist or is not defined in that file.
#
sub PrototypeDefinedIn #(file)
    {
    my ($self, $file) = @_;

    if ($self->IsDefined())
        {  return $self->[DEFINITIONS]{$file}[1];  }
    else
        {  return undef;  };
    };


#
#   Function: GlobalPrototype
#
#   Returns the prototype of the global definition.  Will be undef if it doesn't exist or the symbol isn't defined.
#
sub GlobalPrototype
    {
    my $self = shift;

    my $globalDefinition = $self->GlobalDefinition();

    if (!defined $globalDefinition)
        {  return undef;  }
    else
        {  return $self->[DEFINITIONS]{$globalDefinition}[1];  };
    };


#
#   Function: HasReferences
#
#   Returns whether the symbol can be interpreted as any references.
#
sub HasReferences
    {
    return defined $_[0]->[REFERENCES];
    };

#
#   Function: References
#
#   Returns an array of all the references that can be interpreted as this symbol.  If none, will return an empty array.
#
sub References
    {
    if (defined $_[0]->[REFERENCES])
        {  return keys %{$_[0]->[REFERENCES]};  }
    else
        {  return ( );  };
    };

#
#   Function: ReferencesAndScores
#
#   Returns a hash of all the references that can be interpreted as this symbol and their scores.  The keys are the reference
#   strings, and the values are the scores.  If none, will return an empty hash.
#
sub ReferencesAndScores
    {
    if (defined $_[0]->[REFERENCES])
        {  return %{$_[0]->[REFERENCES]};  }
    else
        {  return ( );  };
    };

1;