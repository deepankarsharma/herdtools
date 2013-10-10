(*********************************************************************)
(*                        Herd                                       *)
(*                                                                   *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                   *)
(* Jade Alglave, University College London, UK.                      *)
(*                                                                   *)
(*  Copyright 2013 Institut National de Recherche en Informatique et *)
(*  en Automatique and the authors. All rights reserved.             *)
(*  This file is distributed  under the terms of the Lesser GNU      *)
(*  General Public License.                                          *)
(*********************************************************************)

open Printf

module type Config = sig
  val m : AST.pp_t
  include Model.Config
end

module Make
    (O:Config)
    (S:Sem.Semantics)
    (B:AllBarrier.S with type a = S.barrier)
    =
  struct

(****************************)
(* Convenient abbreviations *)
(****************************)

    module S = S
    module A = S.A
    module E = S.E
    module U = MemUtils.Make(S)
    module MU = ModelUtils.Make(O)(S)
    module JU = JadeUtils.Make(O)(S)(B)
    module W = Warn.Make(O)

(*  Model interpret *)
    let (pp,model) = O.m

    let find_env env k =
      try StringMap.find k env
      with
      | Not_found -> Warn.user_error "unbound var: %s" k

    let rec stabilised vs ws = match vs,ws with
    | [],[] -> true
    | v::vs,w::ws ->
        E.EventRel.subset w v && stabilised vs ws
    | _,_ -> assert false

    open AST

(* State of interpreter *)
    type st =
        { env : S.event_rel StringMap.t ;
          show : S.event_rel StringMap.t Lazy.t ;
          skipped : StringSet.t ; }

    let rt_loc = if O.verbose <= 1 then S.rt else (fun x -> x)

    let show_to_vbpp st =
      StringMap.fold (fun tag v k -> (tag,v)::k)   (Lazy.force st.show) []
        
    let interpret test conc m id vb_pp =

      let is_dir = function
        | WriteRead -> E.is_mem
        | Write -> E.is_mem_store
        | Read -> E.is_mem_load
        | Atomic -> E.is_atomic
        | Plain -> fun e -> not (E.is_atomic e) in

      let rec eval env = function
        | Konst Empty -> E.EventRel.empty
        | Var k -> find_env env k
        | Op1 (op,e) ->
            begin
              let v = eval env e in
              match op with
              | Plus -> S.tr v
              | Star -> S.union (S.tr v) id
              | Opt -> S.union v id
              | Select (s1,s2) ->
                  let f1 = is_dir s1 and f2 = is_dir s2 in
                  S.restrict f1 f2 v
            end
        | Op (op,es) ->
            begin
              let vs = List.map (eval env) es in
              match op with
              | Union -> S.unions vs
              | Seq -> S.seqs vs
              | Inter ->
                  begin match vs with
                  | [] -> assert false
                  | v::vs ->
                      List.fold_left E.EventRel.inter v vs
                  end
            end in

(* For let *)
      let rec eval_bds env bds = match bds with
      | [] -> env
      | (k,e)::bds ->
          let v = eval env e in
          StringMap.add k v (eval_bds env bds) in

(* For let rec *)
      let rec fix_step env bds = match bds with
      | [] -> env,[]
      | (k,e)::bds ->
          let v = eval env e in
          let env = StringMap.add k v env in
          let env,vs = fix_step env bds in
          env,(v::vs) in

(* Execute one instruction *)

      let rec exec st i c =  match i with
      | Show xs ->
          let show = lazy begin              
            List.fold_left
              (fun show x ->
                StringMap.add x (rt_loc (eval st.env (Var x))) show)
              (Lazy.force st.show) xs
          end in
          run { st with show;} c
      | UnShow xs ->
          let show = lazy begin
            List.fold_left
              (fun show x -> StringMap.remove x show)
              (Lazy.force st.show) xs
          end in
          run { st with show;} c
      | ShowAs (e,id) ->
          let show = lazy begin
            StringMap.add id
              (rt_loc (eval st.env e)) (Lazy.force st.show)
          end in
          run { st with show; } c
      | Test (pos,t,e,name) ->
          let skip_this_check =
            match name with
            | Some name -> StringSet.mem name O.skipchecks
            | None -> false in
          if
            O.strictskip || not skip_this_check
          then
            let v = eval st.env e in
            let pred = match t with
            | Acyclic -> E.EventRel.is_acyclic
            | Irreflexive -> E.EventRel.is_irreflexive
            | TestEmpty -> E.EventRel.is_empty in
            let ok = pred v in
            let ok = MU.check_through ok in
            if ok then run st c
            else if skip_this_check then begin
              assert O.strictskip ;
              run 
                { st with
                  skipped = StringSet.add (Misc.as_some name) st.skipped;}
                c
            end else begin
              if (O.debug && O.verbose > 0) then begin
                let pp = String.sub pp pos.pos pos.len in
                MU.pp_failure test conc
                  (sprintf "%s: Failure of '%s'" test.Test.name.Name.name pp)
                  (show_to_vbpp st)
              end ;
              None
            end
          else begin
            W.warn "Skipping check %s" (Misc.as_some name) ;
            run st c
          end
      | Let bds -> 
          let env = eval_bds st.env bds in
          run { st with env } c
      | Rec bds ->
          let rec fix k env vs =
            if O.debug && O.verbose > 1 then begin
              let vb_pp =
                List.map2
                  (fun (x,_) v -> x,rt_loc v)
                  bds vs@show_to_vbpp st in
              MU.pp_failure test conc
                (sprintf "Fix %i" k)
                vb_pp
            end ;
            let env,ws = fix_step env bds in
            if stabilised vs ws then env
            else fix (k+1) env ws in
          let env =
            fix 0
              (List.fold_left
                 (fun env (k,_) -> StringMap.add k E.EventRel.empty env)
                 st.env bds)
              (List.map (fun _ -> E.EventRel.empty) bds) in
          run {st with env} c

      and run st = function
        | [] ->  Some st 
        | i::c -> exec st i c in

      let _,prog = model in
      let show =
        lazy begin
          List.fold_left
            (fun show (tag,v) -> StringMap.add tag v show)
            StringMap.empty (Lazy.force vb_pp)
        end in
      run {env=m; show=show; skipped=StringSet.empty;} prog
        
    let check_event_structure test conc kont res =
      let prb = JU.make_procrels conc in
      let pr = prb.JU.pr in
      let vb_pp = lazy (JU.vb_pp_procrels prb) in
      let evts = E.EventSet.filter E.is_mem conc.S.str.E.events in
      let id =
        E.EventRel.of_list
          (List.rev_map
             (fun e -> e,e)
             (E.EventSet.elements evts)) in
(* Initial env *)
      let m =
        List.fold_left
          (fun m (k,v) -> StringMap.add k v m)
          StringMap.empty
          ["id",id;
           "atom",conc.S.atomic_load_store;
           "po",S.restrict E.is_mem E.is_mem conc.S.po;
           "pos", conc.S.pos;
           "po-loc", conc.S.pos;
           "addr", pr.S.addr;
           "data", pr.S.data;
           "ctrl", pr.S.ctrl;
           "ctrlisync", pr.S.ctrlisync;
           "ctrlisb", pr.S.ctrlisync;
           "rf", pr.S.rf;
           "rfe", U.ext pr.S.rf;
           "rfi", U.internal pr.S.rf;
(* Power fences *)
           "lwsync", prb.JU.lwsync;
           "eieio", prb.JU.eieio;
           "sync", prb.JU.sync;
           "isync", prb.JU.isync;
(* ARM fences *)
           "dmb",prb.JU.dmb;
           "dsb",prb.JU.dsb;
           "dmbst",prb.JU.dmbst;
           "dmb.st",prb.JU.dmbst;
           "dsbst",prb.JU.dsbst;
           "dsb.st",prb.JU.dsbst;
           "isb",prb.JU.isb;
(* X86 fences *)
           "mfence",prb.JU.mfence;
           "sfence",prb.JU.sfence;
           "lfence",prb.JU.lfence;
         ] in

      let process_co co0 res =
        let co = S.tr co0 in
        let fr = U.make_fr conc co in
        let vb_pp =
          lazy begin
            if S.O.PC.showfr then
              ("fr",fr)::("co",co0)::Lazy.force vb_pp
            else
              ("co",co0)::Lazy.force vb_pp
          end in

        let m =
          List.fold_left
            (fun m (k,v) -> StringMap.add k v m)
            m
            [
             "fr", fr; "fre", U.ext fr; "fri", U.internal fr;
             "co", co; "coe", U.ext co; "coi", U.internal co;
           ] in
        match interpret test conc m id vb_pp with
        | Some st ->
            if not O.strictskip || StringSet.equal st.skipped O.skipchecks then
              let vb_pp = lazy (show_to_vbpp st) in
              kont conc conc.S.fs vb_pp  res
            else res
        | None -> res in
      U.apply_process_co test  conc process_co res
  end