(** Represents OCaml and Reason source files *)
open! Build_api.Api

open! Stdune
open! Import

module File : sig
  type t =
    { path : Path.t
    ; dialect : Dialect.t
    }

  val path : t -> Path.t

  val make : Dialect.t -> Path.t -> t
end

module Kind : sig
  type t =
    | Intf_only
    | Virtual
    | Impl
    | Alias
    | Impl_vmodule
    | Wrapped_compat
    | Root

  include Dune_lang.Conv.S with type t := t
end

module Source : sig
  (** Only the source of a module, not yet associated to a library *)
  type t

  val name : t -> Module_name.t

  val make : ?impl:File.t -> ?intf:File.t -> Module_name.t -> t

  val has : t -> ml_kind:Ml_kind.t -> bool

  val src_dir : t -> Path.t
end

type t

val kind : t -> Kind.t

val to_dyn : t -> Dyn.t

(** When you initially construct a [t] using [of_source], it assumes no wrapping
    (so reports an incorrect [obj_name] if wrapping is used) and you might need
    to fix it later with [with_wrapper]. *)
val of_source : visibility:Visibility.t -> kind:Kind.t -> Source.t -> t

val name : t -> Module_name.t

val source : t -> ml_kind:Ml_kind.t -> File.t option

val pp_flags : t -> string list Build.t option

val file : t -> ml_kind:Ml_kind.t -> Path.t option

val obj_name : t -> Module_name.Unique.t

val iter : t -> f:(Ml_kind.t -> File.t -> unit) -> unit

val has : t -> ml_kind:Ml_kind.t -> bool

(** Prefix the object name with the library name. *)
val with_wrapper : t -> main_module_name:Module_name.t -> t

val map_files : t -> f:(Ml_kind.t -> File.t -> File.t) -> t

(** Set preprocessing flags *)
val set_pp : t -> string list Build.t option -> t

val wrapped_compat : t -> t

module Name_map : sig
  type module_

  type t = module_ Module_name.Map.t

  val decode : src_dir:Path.t -> t Dune_lang.Decoder.t

  val encode : t -> Dune_lang.t list

  val to_dyn : t -> Dyn.t

  val impl_only : t -> module_ list

  val of_list_exn : module_ list -> t

  val add : t -> module_ -> t
end
with type module_ := t

module Obj_map : sig
  type module_

  include Map.S with type key = module_

  val find_exn : 'a t -> module_ -> 'a

  val top_closure :
    module_ list t -> module_ list -> (module_ list, module_ list) Result.result
end
with type module_ := t

val sources : t -> Path.t list

val visibility : t -> Visibility.t

val encode : t -> Dune_lang.t list

val decode : src_dir:Path.t -> t Dune_lang.Decoder.t

(** [pped m] return [m] but with the preprocessed source paths paths *)
val pped : t -> t

(** [ml_source m] returns [m] but with the OCaml syntax source paths *)
val ml_source : t -> t

val set_src_dir : t -> src_dir:Path.t -> t

(** Represent a module that is generated by Dune itself. We use a special
    ".ml-gen" extension to indicate this fact and hide it from
    [(glob_files *.ml)].

    XXX should this return the path of the source as well? it will almost always
    be used to create the rule to generate this file *)
val generated : src_dir:Path.t -> Module_name.t -> t

(** Represent the generated alias module. *)
val generated_alias : src_dir:Path.Build.t -> Module_name.t -> t

val generated_root : src_dir:Path.Build.t -> Module_name.t -> t
