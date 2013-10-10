(*********************************************************************)
(*                        Memevents                                  *)
(*                                                                   *)
(* Jade Alglave, Luc Maranget, INRIA Paris-Rocquencourt, France.     *)
(* Susmit Sarkar, Peter Sewell, University of Cambridge, UK.         *)
(*                                                                   *)
(*  Copyright 2010 Institut National de Recherche en Informatique et *)
(*  en Automatique and the authors. All rights reserved.             *)
(*  This file is distributed  under the terms of the Lesser GNU      *)
(*  General Public License.                                          *)
(*********************************************************************)


module Make (C:Sem.Config)(V : Value.S)
    =
  struct
    module X86 = X86Arch.Make(C.PC)(V)
    include SemExtra.Make(C)(X86)

(* barrier pretty print *)
    let mfence = {barrier=X86.Mfence; pp="mfence";}
    let sfence = {barrier=X86.Sfence; pp="sfence";}
    let lfence = {barrier=X86.Lfence; pp="lfence";}
    let barriers = [mfence; lfence;sfence;]
    let isync = None

(* semantics proper *)

    let (>>=) = M.(>>=)
    let (>>*=) = M.(>>*=)
    let (>>|) = M.(>>|)
    let (>>!) = M.(>>!)

    let lval_ea ea ii = match ea with
    | X86.Effaddr_rm32 (X86.Rm32_reg r)->
	M.unitT (X86.Location_reg (ii.X86.proc,r))
    | X86.Effaddr_rm32 (X86.Rm32_deref r)     ->
        M.read_reg r ii >>=
	fun vreg -> M.unitT (X86.Location_global vreg)
    | X86.Effaddr_rm32 (X86.Rm32_abs v)->
	M.unitT (X86.maybev_to_location v)
	  
    let rval_ea ea ii =
      lval_ea ea ii >>=  fun loc -> M.read_loc loc ii

    let rval_op op ii = match op with
    | X86.Operand_effaddr ea -> rval_ea ea ii
    | X86.Operand_immediate s -> M.unitT (V.intToV s)

    let flip_flag v = M.op Op.Xor v V.one	
	(* Set flags by comparing v1 v2 *)
    let write_zf v1 v2 ii =  M.write_flag X86.ZF Op.Eq v1 v2 ii
    let write_sf v1 v2 ii =  M.write_flag X86.SF Op.Gt v1 v2 ii

    let write_all_flags v1 v2 ii =
      (write_zf v1 v2 ii >>| write_sf v1 v2 ii >>|
      M.write_flag X86.CF Op.Eq V.zero V.one ii) (* Carry was always zero! *)
	>>! ()

(* Exchange *)
(*
    let xchg ea1 ea2 ii =
      (lval_ea ea1 ii >>| lval_ea ea2 ii) >>=
      fun (l1,l2) ->
	(M.read_loc l1 ii >>| M.read_loc l2 ii) >>=
	fun (v1,v2) -> 
	  (M.write_loc l1 v2 ii >>| M.write_loc l2 v1 ii) >>! B.Next
*)

    let xchg ea1 ea2 ii =
      (lval_ea ea1 ii >>| lval_ea ea2 ii) >>=
      (fun (l1,l2) ->
        let r1 = M.read_loc l1 ii
        and r2 = M.read_loc l2 ii
        and w1 = fun v -> M.write_loc l1 v ii
        and w2 = fun v -> M.write_loc l2 v ii in
        M.exch r1 r2 w1 w2) >>! B.Next

    let rec build_semantics procs i ii = match i with
    |  X86.I_XOR (ea,op) ->
	(lval_ea ea ii >>=
	 fun loc -> M.addT loc (M.read_loc loc ii) >>| rval_op op ii)
	  >>=
	fun ((loc,v_ea),v_op) ->
	  M.op Op.Xor v_ea v_op >>=
	  fun v_result ->
	    (M.write_loc loc v_result ii >>|
	    write_all_flags v_result V.zero ii) >>! B.Next
    |  X86.I_ADD (ea,op) ->
	(lval_ea ea ii >>=
	 fun loc -> M.addT loc (M.read_loc loc ii) >>| rval_op op ii)
	  >>=
	fun ((loc,v_ea),v_op) ->
	  M.add v_ea v_op >>=
	  fun v_result ->
	    (M.write_loc loc v_result ii >>|
	    write_all_flags v_result V.zero ii) >>! B.Next
    |  X86.I_MOV (ea,op)|X86.I_MOVQ (ea,op) ->
	(lval_ea ea ii >>| rval_op op ii) >>=
	fun (loc,v_op) ->
	  M.write_loc loc v_op ii >>! B.Next
    |  X86.I_READ (op) ->
	rval_op op ii >>! B.Next
    |  X86.I_DEC (ea) ->
	lval_ea ea ii >>=
	fun loc -> M.read_loc loc ii >>=
	  fun v ->
	    M.op Op.Sub v V.one >>= 
	    fun v ->
	      (M.write_loc loc v ii >>|
              write_sf v V.zero ii >>|
              write_zf v V.zero ii) >>! B.Next
    | X86.I_INC (ea) ->
	lval_ea ea ii >>=
	fun loc -> M.read_loc loc ii >>=
	  fun v ->
	    M.add v V.one >>=
	    fun v ->
	      (M.write_loc loc v ii >>|
	      write_sf v V.zero ii >>|
	      write_zf v V.zero ii) >>! B.Next
    |  X86.I_CMP (ea,op) ->
	(rval_ea ea ii >>| rval_op op ii) >>=
	fun (v_ea,v_op) ->
	  write_all_flags v_ea v_op ii >>! B.Next
    | X86.I_CMOVC (r,ea) ->
	M.read_reg X86.CF ii >>*=
	(fun vcf ->
	  M.choiceT vcf
	    (rval_ea ea ii >>= fun vea -> M.write_reg r vea ii >>! B.Next)
	    (M.unitT B.Next))
    |  X86.I_JMP lbl -> M.unitT (B.Jump lbl)

(* Conditional branZch, I need to look at doc for
   interpretation of conditions *)
    |  X86.I_JCC (X86.C_LE,lbl) ->
	M.read_reg X86.SF ii >>=
        (* control, data ? no event generated after this read anyway *)
	fun sf -> (* LE simply is the negation of GT, given by sign flag *)
	  flip_flag sf >>=
	  fun v -> B.bccT v lbl
    | X86.I_JCC (X86.C_LT,lbl) ->
	(M.read_reg X86.ZF ii >>|
	(M.read_reg X86.SF ii >>= flip_flag)) >>=
	fun (v1,v2) ->
	  M.op Op.Or v1 v2 >>=
	  fun v -> B.bccT v lbl
    | X86.I_JCC (X86.C_GE,lbl) ->
	(M.read_reg X86.ZF ii >>| M.read_reg X86.SF ii) >>=
	fun (v1,v2) ->
	  M.op Op.Or v1 v2 >>=
	  fun v -> B.bccT v lbl 
    | X86.I_JCC (X86.C_GT,lbl) ->
	M.read_reg X86.SF ii >>=
	fun v -> B.bccT v lbl 
    | X86.I_JCC (X86.C_EQ,lbl) -> 
	M.read_reg X86.ZF ii >>=
	fun v -> B.bccT v lbl 
    | X86.I_JCC (X86.C_NE,lbl) -> 
	M.read_reg X86.ZF ii >>= flip_flag >>=
	fun v -> B.bccT v lbl 
    | X86.I_JCC (X86.C_S,lbl) -> 
	M.read_reg X86.SF ii >>=
	fun v -> B.bccT v lbl 
    | X86.I_JCC (X86.C_NS,lbl) -> 
	M.read_reg X86.SF ii >>= flip_flag >>=
	fun v -> B.bccT v lbl 

    | X86.I_LOCK inst ->
	M.lockT (build_semantics procs inst ii)
    | X86.I_SETNB (ea) ->
	(lval_ea ea ii >>| M.read_reg X86.CF ii) >>=
	fun (loc,cf) ->
	  flip_flag cf >>=
	  fun v -> M.write_loc loc v ii >>! B.Next
    | X86.I_XCHG (ea1,ea2) ->
	M.lockT (xchg ea1 ea2 ii)
    | X86.I_XCHG_UNLOCKED (ea1,ea2) ->
	xchg ea1 ea2 ii
    | X86.I_CMPXCHG (_,_) -> Warn.fatal "I_CMPXCHG not implemented"
    | X86.I_LFENCE ->
	M.create_barrier X86.Lfence ii >>! B.Next
    | X86.I_SFENCE ->
	M.create_barrier X86.Sfence ii >>! B.Next
    | X86.I_MFENCE ->
	M.create_barrier X86.Mfence ii >>! B.Next
    |  X86.I_MOVSD -> Warn.fatal "I_MOVSD not implemented"
  end