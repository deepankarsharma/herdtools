/*********************************************************************/
/*                        Herd                                       */
/*                                                                   */
/* Luc Maranget, INRIA Paris-Rocquencourt, France.                   */
/* Jade Alglave, University College London, UK.                      */
/*                                                                   */
/*  Copyright 2013 Institut National de Recherche en Informatique et */
/*  en Automatique and the authors. All rights reserved.             */
/*  This file is distributed  under the terms of the Lesser GNU      */
/*  General Public License.                                          */
/*********************************************************************/


%{
open AST

let as_op op = function
  | Op (op0,es) when op0 = op -> es
  | e -> [e]

let do_op op e1 e2 =
  let es1 = as_op op e1
  and es2 = as_op op e2 in
  Op (op,es1@es2)

let pp () =
  let open Lexing in
  let start = Parsing.symbol_start_pos ()
  and fin = symbol_end () in
  let pos = start.pos_cnum in
  let len = fin - pos in
  {pos;len}


%}
%token EOF
%token <string> VAR
%token <string> LOCVAR
%token <string * AST.ext_int * AST.scope> SCOPEVAR
%token <string> STRING
%token LPAR RPAR LBRAC RBRAC
%token EMPTY UNDERSCORE
/* Access direction */
%token MM  MR  MW WM WW WR RM RW RR F
/* Plain/Atomic */
%token AA AP PA PP
%token SEMI UNION INTER COMMA HAT
%token STAR PLUS OPT COMP BACKSLASH NEGONE TWO LOC INT EXT
/*Scopes*/
%token WI SG WG KER DEV
%token LET REC AND ACYCLIC IRREFLEXIVE TESTEMPTY EQUAL SHOW UNSHOW AS FUN IN
%token REQUIRES PROVIDES
%token ARROW
%type <AST.t> main
%start main

/* Precedences */
%right UNION
%right SEMI
%right INTER
%left BACKSLASH
%nonassoc STAR PLUS OPT COMP HAT
%%

main:
| VAR ins_list EOF { $1,$2 }
| STRING ins_list EOF { $1,$2 }

ins_list:
| { [] }
| ins ins_list { $1 :: $2 }

ins:
| LET pat_bind_list { Let $2 }
| LET REC bind_list { Rec $3 }
| test_type test exp AS VAR { Test(pp (),$2,$3,Some $5,$1) }
| test_type test exp  { Test(pp (),$2,$3,None,$1) }
| SHOW exp AS VAR { ShowAs ($2, $4) }
| SHOW var_list { Show $2 }
| UNSHOW var_list { UnShow $2 }

test_type:
|          { Provides }
| PROVIDES { Provides }
| REQUIRES { Requires }

test:
| ACYCLIC { Acyclic }
| IRREFLEXIVE { Irreflexive }
| TESTEMPTY { TestEmpty }

var_list:
| VAR { [$1] }
| VAR commaopt var_list { $1 :: $3 }

commaopt:
| COMMA { () }
|       { () }
    
bind:
| VAR EQUAL exp { ($1,$3) }

bind_list:
| bind { [$1] }
| bind AND bind_list { $1 :: $3 }

pat_bind:
| bind { $1 }
| VAR LPAR formals RPAR EQUAL exp { ($1,Fun ($3,$6)) }

pat_bind_list:
| pat_bind { [$1] }
| pat_bind AND pat_bind_list { $1 :: $3 }


formals:
|  { [] }
| formalsN { $1 }

formalsN:
| VAR { [$1] }
| VAR COMMA formalsN { $1 :: $3 }

setexp:
| VAR { Var $1 }
| UNDERSCORE { Var "_" }
| COMP setexp { Op1(Comp,$2) }
| setexp UNION setexp { do_op Union $1 $3 }
| setexp INTER setexp { do_op Inter $1 $3 }
| setexp BACKSLASH setexp { Op(Inter, [$1; Op1(Comp,$3)]) }
| LPAR setexp RPAR { $2 }

exp:
| LET pat_bind_list IN exp { Bind ($2,$4) }
| LET REC bind_list IN exp { BindRec ($3,$5) }
| FUN LPAR formals RPAR ARROW exp { Fun ($3,$6) }
| base { $1 }

base:
| EMPTY { Konst Empty }
| select LPAR exp RPAR { Op1 ($1,$3) }
|  exp0 { $1 }
| LBRAC setexp STAR setexp RBRAC {Cartesian ($2, $4)}
| LBRAC setexp RBRAC {Op (Inter, [Cartesian ($2, $2); Var "id"])}
| LBRAC setexp HAT TWO RBRAC {Cartesian ($2, $2)}
| base STAR { Op1(Star,$1) }
| base PLUS { Op1(Plus,$1) }
| base OPT { Op1(Opt,$1) }
| COMP base { Op1(Comp,$2) }
| base HAT NEGONE { Op1(Inverse,$1) }
| base SEMI base { do_op Seq $1 $3 }
| base UNION base { do_op Union $1 $3 }
| base BACKSLASH base { do_op Diff $1 $3 }
| base INTER base { do_op Inter $1 $3 }
| LOCVAR { Op(Inter, [Var $1; Var "loc"]) }
| SCOPEVAR { 
    let (x,ext_int,sc) = $1 in
    Op(Inter, [Var x; Konst (Scope_op (sc, ext_int))])
  }
| LPAR exp RPAR { $2 }

exp0:
| VAR { Var $1 }
| exp0 LPAR args RPAR { App ($1,$3) }


args:
| exp  { [ $1 ] }
| exp COMMA args { $1 :: $3 }

select:
| MM { Select (WriteRead,WriteRead) }
| MW { Select (WriteRead,Write) }
| MR { Select (WriteRead,Read) }
| WM { Select (Write,WriteRead) }
| WW { Select (Write,Write) }
| WR { Select (Write,Read) }
| RM { Select (Read,WriteRead) }
| RW { Select (Read,Write) }
| RR { Select (Read,Read) }
/* Atomic/Plain */
| AA { Select (Atomic,Atomic) }
| AP { Select (Atomic,Plain) }
| PA { Select (Plain,Atomic) }
| PP { Select (Plain,Plain) }
/*Generic Filters */
| F LBRAC filter_list_empty RBRAC F LBRAC filter_list_empty RBRAC
   { Select (Filter $3, Filter $7)}

filter_list_empty:
|  {[]}
| filter_list {$1}

filter_list:
| VAR {[$1]}
| VAR COMMA filter_list {$1::$3}
