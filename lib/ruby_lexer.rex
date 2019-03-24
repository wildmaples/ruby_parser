# encoding: UTF-8
#
# lexical scanner definition for ruby

class RubyLexer

macro

  IDENT         /^#{IDENT_CHAR}+/o

  ESC           /\\((?>[0-7]{1,3}|x[0-9a-fA-F]{1,2}|M-[^\\]|(C-|c)[^\\]|u[0-9a-fA-F]{1,4}|u\{[0-9a-fA-F]+\}|[^0-7xMCc]))/
  SIMPLE_STRING /((#{ESC}|\#(#{ESC}|[^\{\#\@\$\"\\])|[^\"\\\#])*)/o
  SSTRING       /((\\.|[^\'])*)/

  INT_DEC       /[+]?(?:(?:[1-9][\d_]*|0)(?!\.\d)(ri|r|i)?\b|0d[0-9_]+)(ri|r|i)?/i
  INT_HEX       /[+]?0x[a-f0-9_]+(ri|r|i)?/i
  INT_BIN       /[+]?0b[01_]+(ri|r|i)?/i
  INT_OCT       /[+]?0o?[0-7_]+(ri|r|i)?|0o(ri|r|i)?/i
  FLOAT         /[+]?\d[\d_]*\.[\d_]+(e[+-]?[\d_]+)?(?:(ri|r|i)\b)?|[+]?[\d_]+e[+-]?[\d_]+(?:(ri|r|i)\b)?/i
  INT_DEC2      /[+]?\d[0-9_]*(?![e])((ri|r|i)\b)?/i

  NUM_BAD       /[+]?0[xbd]\b/i
  INT_OCT_BAD   /[+]?0o?[0-7_]*[89]/i
  FLOAT_BAD     /[+]?\d[\d_]*_(e|\.)/i

start

  return process_string if lex_strterm

  self.cmd_state = self.command_start
  self.command_start = false
  self.space_seen    = false # TODO: rename token_seen?
  self.last_state    = lex_state

rule

# [:state]      pattern                 [actions]

                # \s - \n + \v
                /[\ \t\r\f\v]/          { self.space_seen = true; next }

                /\n|\#/                 process_newline_or_comment

                /[\]\)\}]/              process_brace_close

: /\!/
| is_after_operator? /\!\@/             { result EXPR_ARG, :tUBANG, "!@" }
|               /\![=~]?/               { result :arg_state, TOKENS[text], text }

: /\./
|               /\.\.\.?/               { result EXPR_BEG, TOKENS[text], text }
|               /\.\d/                  { rb_compile_error "no .<digit> floating literal anymore put 0 before dot" }
|               /\./                    { self.lex_state = EXPR_BEG; result EXPR_DOT, :tDOT, "." }

                /\(/                    process_paren

                /\,/                    { result EXPR_PAR, TOKENS[text], text }

: /=/
|               /\=\=\=|\=\=|\=~|\=>|\=(?!begin\b)/ { result arg_state, TOKENS[text], text }
| bol?          /\=begin(?=\s)/         process_begin
|               /\=(?=begin\b)/         { result arg_state, TOKENS[text], text }

ruby22_label?   /\"#{SIMPLE_STRING}\":/o process_label
                /\"(#{SIMPLE_STRING})\"/o { result EXPR_END, :tSTRING, text[1..-2].gsub(ESC) { unescape $1 } }
                /\"/                    { string STR_DQUOTE; result nil, :tSTRING_BEG, text }

                /\@\@?\d/               { rb_compile_error "`#{text}` is not allowed as a variable name" }
                /\@\@?#{IDENT_CHAR}+/o  process_ivar

: /:/
| not_end?      /:([a-zA-Z_]#{IDENT_CHAR}*(?:[?]|[!](?!=)|=(?==>)|=(?![=>]))?)/o process_symbol
| not_end?      /\:\"(#{SIMPLE_STRING})\"/o process_symbol
| not_end?      /\:\'(#{SSTRING})\'/o       process_symbol
|               /\:\:/                      process_colon2
|               /\:/                        process_colon1

                /->/                    { result EXPR_ENDFN, :tLAMBDA, nil }

                /[+-]/                  process_plus_minus

: /[+\d]/
|               /#{NUM_BAD}/o           { rb_compile_error "Invalid numeric format"  }
|               /#{INT_DEC}/o           { int_with_base 10                           }
|               /#{INT_HEX}/o           { int_with_base 16                           }
|               /#{INT_BIN}/o           { int_with_base 2                            }
|               /#{INT_OCT_BAD}/o       { rb_compile_error "Illegal octal digit."    }
|               /#{INT_OCT}/o           { int_with_base 8                            }
|               /#{FLOAT_BAD}/o         { rb_compile_error "Trailing '_' in number." }
|               /#{FLOAT}/o             process_float
|               /#{INT_DEC2}/o          { int_with_base 10                           }
|               /[0-9]/                 { rb_compile_error "Bad number format" }

                /\[/                    process_square_bracket

was_label?        /\'#{SSTRING}\':?/o   process_label_or_string

: /\|/
|               /\|\|\=/                { result EXPR_BEG, :tOP_ASGN, "||" }
|               /\|\|/                  { result EXPR_BEG, :tOROP,    "||" }
|               /\|\=/                  { result EXPR_BEG, :tOP_ASGN, "|" }
|               /\|/                    { state = is_after_operator? ? EXPR_ARG : EXPR_PAR; result state, :tPIPE, "|" }

                /\{/                    process_brace_open

: /\*/
|               /\*\*=/                 { result EXPR_BEG, :tOP_ASGN, "**" }
|               /\*\*/                  { result(:arg_state, space_vs_beginning(:tDSTAR, :tDSTAR, :tPOW), "**") }
|               /\*\=/                  { result(EXPR_BEG, :tOP_ASGN, "*") }
|               /\*/                    { result(:arg_state, space_vs_beginning(:tSTAR, :tSTAR, :tSTAR2), "*") }

# TODO: fix result+process_lchevron to set command_start = true
: /</
|               /\<\=\>/                { result :arg_state, :tCMP, "<=>"    }
|               /\<\=/                  { result :arg_state, :tLEQ, "<="     }
|               /\<\<\=/                { result EXPR_BEG,  :tOP_ASGN, "<<" }
|               /\<\</                  process_lchevron
|               /\</                    { result :arg_state, :tLT, "<"       }

: />/
|               /\>\=/                  { result :arg_state, :tGEQ, ">="     }
|               /\>\>=/                 { result EXPR_BEG,  :tOP_ASGN, ">>" }
|               /\>\>/                  { result :arg_state, :tRSHFT, ">>"   }
|               /\>/                    { result :arg_state, :tGT, ">"       }

: /\`/
| expr_fname?   /\`/                   { result(EXPR_END, :tBACK_REF2, "`") }
| expr_dot?     /\`/                   { result((cmd_state ? EXPR_CMDARG : EXPR_ARG), :tBACK_REF2, "`") }
|               /\`/                   { string STR_XQUOTE, '`'; result(nil, :tXSTRING_BEG, "`") }

                /\?/                    process_questionmark

: /&/
|               /\&\&\=/                { result(EXPR_BEG, :tOP_ASGN, "&&") }
|               /\&\&/                  { result(EXPR_BEG, :tANDOP,   "&&") }
|               /\&\=/                  { result(EXPR_BEG, :tOP_ASGN, "&" ) }
|               /\&\./                  { result(EXPR_DOT, :tLONELY,  "&.") }
|               /\&/                    process_amper

                /\//                    process_slash

: /\^/
|               /\^=/                   { result(EXPR_BEG, :tOP_ASGN, "^") }
|               /\^/                    { result(:arg_state, :tCARET, "^") }

                /\;/                    { self.command_start = true; result(EXPR_BEG, :tSEMI, ";") }

: /~/
| is_after_operator? /\~@/              { result(:arg_state, :tTILDE, "~") }
|               /\~/                    { result(:arg_state, :tTILDE, "~") }

: /\\/
|               /\\\r?\n/               { self.lineno += 1; self.space_seen = true; next }
|               /\\/                    { rb_compile_error "bare backslash only allowed before newline" }

                /\%/                    process_percent

: /\$/
|               /\$_\w+/                         process_gvar
|               /\$_/                            process_gvar
|               /\$[~*$?!@\/\\;,.=:<>\"]|\$-\w?/ process_gvar
| in_fname?     /\$([\&\`\'\+])/                 process_gvar
|               /\$([\&\`\'\+])/                 process_backref
| in_fname?     /\$([1-9]\d*)/                   process_gvar
|               /\$([1-9]\d*)/                   process_nthref
|               /\$0/                            process_gvar
|               /\$\W|\$\z/                      process_gvar_oddity
|               /\$\w+/                          process_gvar

                /\_/                    process_underscore

                /#{IDENT}/o             process_token

                /\004|\032|\000|\Z/     { [RubyLexer::EOF, RubyLexer::EOF] }

                /./                     { rb_compile_error "Invalid char #{text.inspect} in expression" }

end
