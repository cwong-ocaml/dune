(** Rules for setting up cram tests *)
open! Build_api
open! Build_api.Transparent

open Import

val rules :
     sctx:Super_context.t
  -> expander:Expander.t
  -> dir:Path.Build.t
  -> (Cram_test.t, File_tree.Dir.error) result list
  -> unit
