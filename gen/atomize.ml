(*********************************************************************)
(*                         Diy                                       *)
(*                                                                   *)
(*   Jade Alglave, Luc Maranget INRIA Paris-Rocquencourt, France.    *)
(*                                                                   *)
(*  Copyright 2011 Institut National de Recherche en Informatique et *)
(*  en Automatique. All rights reserved. This file is distributed    *)
(*  under the terms of the Lesser GNU General Public License.        *)
(*********************************************************************)

open Archs
open Printf
open Code

(* Configuration *)
let arch = ref PPC
 
let opts = [Util.arch_opt arch]

module type Config = sig
  val norm : bool
  val compat : bool
  val lowercase : bool
end

module Make (A:Fence.S) =
    struct
      module E = Edge.Make(A)
      module Namer = Namer.Make(A)(E)
      module Normer =
        Normaliser.Make(struct let lowercase = false end)(E)


      let is_ext e = match E.get_ie e with
      | Ext -> true
      | Int -> false

      let atomic = Some A.default_atom

      let atomize es =
        let open E in
        match es with
        | [] -> []
        | fst::_ ->
            let rec do_rec es = match es with
              | [] -> []
              | [e] ->
                  if is_ext fst || is_ext e then
                    [ { e with a2 = atomic ; } ]
                  else
                    es
              | e1::e2::es ->
                  if is_ext e1 || is_ext e2 then
                    let e1 = { e1 with a2 = atomic; } in
                    let e2 = { e2 with a1 = atomic; } in
                    e1::do_rec (e2::es)
                  else e1::do_rec (e2::es) in
            match do_rec es with
            | [] -> assert false
            | fst::rem as es ->
                let lst = Misc.last es in
                if is_ext fst || is_ext lst then
                  { fst with a1 = atomic;}::rem
                else es
            
      let parse_line s =
        try
          let r = String.index s ':' in
          let name  = String.sub s 0 r
          and es = String.sub s (r+1) (String.length s - (r+1)) in
          let es = E.parse_edges es in
          name,es
        with
        | Not_found | Invalid_argument _ ->
            Warn.fatal "bad line: %s" s

      let pp_edges es = String.concat " " (List.map E.pp_edge es)

      let zyva_stdin () =
        try while true do
          try
            let line = read_line () in
            let _,es = parse_line line in
            let base,es = Normer.normalise_family (atomize es) in
            let name = Namer.mk_name base es in
            printf "%s: %s\n" name (pp_edges es)
          with Misc.Fatal msg -> Warn.warn_always "%s" msg
        done with End_of_file -> ()

      let zyva_argv es =
        let es = List.map E.parse_edge es in
        let es = atomize es in
        printf "%s\n" (pp_edges es)

      let zyva = function
        | [] -> zyva_stdin ()
        | es ->  zyva_argv es
    end

let pp_es = ref []

let () =
  Util.parse_cmdline
    opts
    (fun x -> pp_es := x :: !pp_es)

let pp_es = List.rev !pp_es

let () =
  let module V = SymbConstant in
  (match !arch with
  | X86 ->
      let module M = Make(X86Arch.Make(V)) in
      M.zyva
  | PPC ->
      let module M = Make(PPCArch.Make(V)(PPCArch.Config)) in
      M.zyva
  | ARM ->
      let module M = Make(ARMArch.Make(V)) in
      M.zyva
  | C ->
      let module M = Make(CArch) in
      M.zyva)
     pp_es
