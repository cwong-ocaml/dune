(** Upgrade projects from jbuilder to Dune *)
open! Build_api
open! Build_api.Transparent

(** Upgrade all projects in this file tree *)
val upgrade : unit -> unit
