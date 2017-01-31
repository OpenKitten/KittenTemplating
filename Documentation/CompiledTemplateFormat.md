template    ::= s_list "\x00"		              Template
e_list      ::= element s_list | ""               Element list

element     ::= "\x01" (byte)* "\x00"        Raw data (uint32 for the length of the "(byte)*")
              | "\x02" statement

statement   ::= "\x01" expression true_template_len false_template_len e_list e_list | ""
              | "\x02" cstring expression template_len e_list "\x00"  For value in expression where the expression outcome is an array. Puts the value in the variable with the given cstring name. Execute the expression as a script literal
              | "\x03" expression                        Prints expression outcome

expression  ::= "\x01" str_list                          The variable at this path
              | "\x02" expression expression operation   Equates the expression outcome with another expression using an operation

operation   ::= "\x01"                                   Equal
              | "\x02"                                   Greater than
              | "\x03"                                   Less than
              | "\x04" operation                         Outcome of operation is false


str_list       ::=  cstring str_list | "\x00"
cstring	       ::=	(byte*) "\x00"
