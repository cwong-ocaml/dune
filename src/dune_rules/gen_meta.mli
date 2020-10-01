(** Generate a META file *)
open! Build_api
open! Build_api.Transparent

open! Import

(** Generate the meta for a package containing some libraries *)
val gen :
     package:Package.t
  -> add_directory_entry:bool
  -> Super_context.Lib_entry.t list
  -> Meta.t
