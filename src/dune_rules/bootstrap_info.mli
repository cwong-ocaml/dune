(** Generate bootstrap info *)
open! Build_api
open! Build_api.Transparent

(** Generate an OCaml file containing a description of the dune sources for the
    bootstrap procedure *)

open Stdune

(** Generate the rules to handle the stanza *)
val gen_rules :
     Super_context.t
  -> Dune_file.Executables.t
  -> dir:Path.Build.t
  -> Lib.Compile.t
  -> unit
