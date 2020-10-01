open! Build_api
open! Build_api.Transparent
open! Stdune

include Interned.Make
          (struct
            let initial_size = 16

            let resize_policy = Interned.Conservative

            let order = Interned.Natural
          end)
          ()
