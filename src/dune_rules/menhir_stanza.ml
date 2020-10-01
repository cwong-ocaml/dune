open! Build_api
open! Build_api.Transparent

let syntax =
  Dune_lang.Syntax.create ~name:"menhir" ~desc:"the menhir extension"
    [ ((1, 0), `Since (1, 0))
    ; ((1, 1), `Since (1, 4))
    ; ((2, 0), `Since (1, 4))
    ; ((2, 1), `Since (2, 2))
    ]
