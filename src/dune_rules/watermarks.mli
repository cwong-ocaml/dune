(** Watermarking *)
open! Build_api
open! Build_api.Transparent

(** Expand watermarks in source files, similarly to what topkg does.

    This is only used when a package is pinned. *)

val subst : unit -> unit Fiber.t
