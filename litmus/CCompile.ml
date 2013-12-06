(*********************************************************************)
(*                          Litmus                                   *)
(*                                                                   *)
(*     Jacques-Pascal Deplaix, INRIA Paris-Rocquencourt, France.     *)
(*                                                                   *)
(*  Copyright 2010 Institut National de Recherche en Informatique et *)
(*  en Automatique and the authors. All rights reserved.             *)
(*  This file is distributed  under the terms of the Lesser GNU      *)
(*  General Public License.                                          *)
(*********************************************************************)

module type Config = sig
  val numeric_labels : bool
  val signaling : bool
  val timeloop : int
  val barrier : Barrier.t
end

module Make
    (O:Config)
    (T:Test.S with type P.code = CAst.t and type A.reg = string) =
  struct

    module A = T.A
    module C = T.C

    let add_addr_type a ty env =
      try
        let tz = StringMap.find a env in
        let ty =
          match ty,tz with
          | RunType.Int,RunType.Int -> RunType.Int
          | (RunType.Pointer,_)|(_,RunType.Pointer) -> RunType.Pointer in
        StringMap.add a ty env
      with
        Not_found -> StringMap.add a ty env

    let add_value v env = match v with
    | Constant.Concrete _ -> env
    | Constant.Symbolic a -> add_addr_type a RunType.Int env

    let typeof v = match v with
    | Constant.Concrete _ -> RunType.Int
    | Constant.Symbolic _ -> RunType.Pointer

    let add_param {CAst.param_ty; param_name} =
      let ty_of_cty = function
        | CAst.Int_ptr -> RunType.Pointer
      in
      StringMap.add param_name (ty_of_cty param_ty)

    let add_params = List.fold_right add_param

    let comp_globals init code =
      let env =
        List.fold_right
          (fun (loc,v) env ->
            let env = add_value v env in
            match loc with
            | A.Location_global (a) ->
                add_addr_type a (typeof v) env
            | _ -> env)
          init StringMap.empty in
      let env =
        List.fold_right
          (fun (_, {CAst.params; _}) -> add_params params)
          code
          env
      in
      StringMap.fold
        (fun a ty k -> (a,ty)::k)
        env []

    let get_globals proc =
      let f acc = function
        | A.Location_reg (p, name) when p = proc -> name :: acc
        | A.Location_reg _
        | A.Location_global _ -> acc
      in
      List.fold_left f []

    let comp_template proc final =
      { A.Out.init = []
      ; addrs = []
      ; final
      ; code = []
      }

    let comp_code final =
      List.fold_left
        (fun acc (proc, _) ->
           let final = get_globals proc (C.locations final) in
           let regs = List.map (fun x -> (x, RunType.Pointer)) final in
           (proc, (comp_template proc final, regs)) :: acc
        )
        []

    let compile t =
      let
        { MiscParser.init = init ;
          info = info;
          prog = code;
          condition = final;
          locations = locs ; _
        } = t in
      { T.init = init;
        info = info;
        code = comp_code final code;
        condition = final;
        globals = comp_globals init code;
        flocs = List.map fst locs;
        src = t;
      }

  end