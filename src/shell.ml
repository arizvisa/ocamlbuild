(***********************************************************************)
(*                                                                     *)
(*                             ocamlbuild                              *)
(*                                                                     *)
(*  Nicolas Pouillard, Berke Durak, projet Gallium, INRIA Rocquencourt *)
(*                                                                     *)
(*  Copyright 2007 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)


(* Original author: Nicolas Pouillard *)
open My_std

let is_simple_filename s =
  let ls = String.length s in
  ls <> 0 &&
  let rec loop pos =
    if pos >= ls then true else
    match s.[pos] with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '.' | '-' | '/' | '_' | ':' | '@' | '+' | ',' -> loop (pos + 1)
    | _ -> false in
  loop 0
let quote_filename_if_needed s =
  if is_simple_filename s then s
  (* We should probably be using [Filename.unix_quote] except that function
   * isn't exported. Users on Windows will have to live with not being able to
   * install OCaml into c:\o'caml. Too bad. *)
  else if Sys.os_type = "Win32" then Printf.sprintf "'%s'" s
  else Filename.quote s
let chdir dir =
  reset_filesys_cache ();
  Sys.chdir dir
let run args target =
  reset_readdir_cache ();
  let cmd = String.concat " " (List.map quote_filename_if_needed args) in
  if !*My_unix.is_degraded || Sys.os_type = "Win32" then
    begin
      Log.event cmd target Tags.empty;
      let st = sys_command cmd in
      if st <> 0 then
        failwith (Printf.sprintf "Error during command `%s'.\nExit code %d.\n" cmd st)
      else
        ()
    end
  else
    match My_unix.execute_many ~ticker:Log.update ~display:Log.display [[(fun () -> cmd)]] with
    | None -> ()
    | Some(_, x) ->
      failwith (Printf.sprintf "Error during command %S: %s" cmd (Printexc.to_string x))
let rm = sys_remove
let rm_f x =
  if sys_file_exists x then rm x
let mkdir dir =
  reset_filesys_cache_for_file dir;
  (*Sys.mkdir dir (* MISSING in ocaml *) *)
  (*run ["mkdir"; dir] dir *)
  Unix.mkdir dir 0o777
let try_mkdir dir = if not (sys_file_exists dir) then mkdir dir
let rec mkdir_p dir =
  if sys_file_exists dir then ()
  else (mkdir_p (Filename.dirname dir); mkdir dir)

let cp_pf src dest =
  reset_filesys_cache_for_file dest;
  (*run["cp";"-pf";src;dest] dest*)
  Unix.link src dest

(* Archive files are handled specially during copy *)
let cp src dst =
  if Filename.check_suffix src ".a"
  && Filename.check_suffix dst ".a"
  then cp_pf src dst
  (* try to make a hard link *)
  else copy_file src dst

let readlink = My_unix.readlink
let is_link = My_unix.is_link
let rm_rf x =
  reset_filesys_cache ();
  (*run["rm";"-Rf";x] x *)
  let args = ["rm";"-Rf";x] in
  Log.event (String.concat " " (List.map quote_filename_if_needed args)) x Tags.empty;
  let dir = x in
  let walk dir =
    let rec walk acc = function
    | [] -> acc
    | dir :: tail -> 
        let contents = Array.to_list (Sys.readdir dir) in
        let contents = List.rev_map (Filename.concat dir) contents in
        let dirs, files = List.fold_left (
          fun (dirs, files) f -> 
            match (Unix.stat f).st_kind with
            | Unix.S_REG -> (dirs, f::files)
            | Unix.S_DIR -> (f::dirs, f::files)
            | _ -> (dirs, files)
          ) ([], []) contents
        in 
        walk (files @ acc) (dirs @ tail)
    in (walk [] [dir]) @ [dir]
  in
  if Sys.file_exists dir then (
    let contents = walk dir in
    let err = try
        List.map (fun f ->
            match (Unix.stat f).st_kind with
            | Unix.S_REG -> Unix.unlink f
            | Unix.S_DIR -> Unix.rmdir f
            | _ -> ()         (* FIXME: Warn if unable to remove specific file type *)
        ) contents; None 
      with Unix.Unix_error (error,_,_) -> Some error
    in
    match err with
    | Some error ->
        failwith (Printf.sprintf "Cannot remove %s (error %s)." dir (Unix.error_message error))
    | None -> ()
  )

let mv src dest =
  reset_filesys_cache_for_file src;
  reset_filesys_cache_for_file dest;
  (*run["mv"; src; dest] dest *)
  (*Sys.rename src dest*)
  Unix.rename src dest
