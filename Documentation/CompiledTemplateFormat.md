template    ::= s_list "\x00"		              Template
e_list      ::= element s_list | ""               Element list

element     ::= "\x01" len (byte)*       Raw data (uint32 for the length of the "(byte)*")
              | "\x02" statement

statement   ::= "\x01" expression true_template_len false_template_len e_list e_list | ""
              | "\x02" cstring expression template_len e_list "\x00"  For value in expression where the expression outcome is an array. Puts the value in the variable with the given cstring name. Execute the expression as a script literal
              | "\x03" expression                        Prints expression outcome

expression  ::= "\x01" str_list                          The variable at this path


str_list       ::=  cstring str_list | "\x00"
cstring	       ::=	(byte*) "\x00"
