open Printf

(** GPU memory space map *)


type gpu_memory_space = 
| GlobalMem
| LocalMem

let pp_gpu_memory_space x =
  match x with
  | GlobalMem -> "global"
  | LocalMem -> "local"

type mem_space_map = (string * gpu_memory_space) list

(* let mem_space_map = ref No_mem_space_map *)

let pp_memory_space_map m = 
  let str_list = 
    List.map 
      (fun (x,y) -> sprintf "%s:%s" x (pp_gpu_memory_space y)) m 
  in
  String.concat "; " str_list

let is_global msm x = 
  let ms =
    try
      List.assoc x msm
    with 
      Not_found -> 
      Warn.fatal "Location %s not in memory space map" x
  in match ms with
  | GlobalMem -> true
  | LocalMem -> false

let is_local msm x = 
  let ms =
    try
      List.assoc x msm
    with 
      Not_found -> 
      Warn.fatal "Location %s not in memory space map" x
  in match ms with
  | GlobalMem -> false
  | LocalMem -> true
  
        