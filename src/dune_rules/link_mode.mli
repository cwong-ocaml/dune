(** Link mode of OCaml programs *)
open! Build_api
open! Build_api.Transparent

type t =
  | Byte
  | Native
  | Byte_with_stubs_statically_linked_in

val mode : t -> Mode.t
