open! Stdune
open Dune_engine

module Outputs : sig
  type t =
    | Stdout
    | Stderr
    | Outputs  (** Both Stdout and Stderr *)
end

module Inputs : sig
  type t = Stdin
end

module Simplified : sig
  type destination =
    | Dev_null
    | File of string

  type source = string

  type t =
    | Run of string * string list
    | Chdir of string
    | Setenv of string * string
    | Redirect_out of t list * Outputs.t * destination
    | Redirect_in of t list * Inputs.t * source
    | Pipe of t list list * Outputs.t
    | Sh of string
end

(** result of the lookup of a program, the path to it or information about the
    failure and possibly a hint how to fix it *)
module Prog : sig
  module Not_found : sig
    type t = private
      { context : Context_name.t
      ; program : string
      ; hint : string option
      ; loc : Loc.t option
      }

    val create :
         ?hint:string
      -> context:Context_name.t
      -> program:string
      -> loc:Loc.t option
      -> unit
      -> t

    val raise : t -> _
  end

  type t = (Path.t, Not_found.t) result

  val to_dyn : t -> Dyn.t

  val ok_exn : t -> Path.t
end
