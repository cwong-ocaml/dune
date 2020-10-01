open! Build_api
open! Build_api.Transparent
open Stdune

val run : env:Env.t -> script:Path.t -> unit Fiber.t

val linkme : unit
