(** Name TBD. Dune representation of the source tree. *)

open! Stdune
open! Import

val fname : string

val jbuild_fname : string

type kind = private
  | Plain
  | Ocaml_script

type t

(** We release the memory taken by s-exps as soon as it is used, unless
    [kind = Ocaml_script]. In which case that optimization is incorrect as we
    need to re-parse in every context. *)
val get_static_sexp_and_possibly_destroy : t -> Dune_lang.Ast.t list

val kind : t -> kind

val path : t -> Path.Source.t

val for_subdirs : t -> Sub_dirs.Dir_map.t

val load :
     Path.Source.t
  -> file_exists:bool
  -> from_parent:Sub_dirs.Dir_map.t option
  -> project:Dune_project.t
  -> t

val sub_dirs : t option -> Predicate_lang.Glob.t Sub_dirs.Status.Map.t
