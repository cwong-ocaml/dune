(** Convert an action to a shell command suitable for [/bin/sh] *)
open! Build_api
open! Build_api.Transparent

open Stdune

val echo : Action_intf.Simplified.source -> Action_intf.Simplified.t list

val pp : Action.For_shell.t -> unit Pp.t
