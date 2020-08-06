open! Stdune
open Import

module Plain = struct
  type t =
    { mutable contents : Sub_dirs.Dir_map.per_dir
    ; for_subdirs : Sub_dirs.Dir_map.t
    }

  (** It's also possible to add GC for:

      - [contents.subdir_status]
      - [consumed nodes of for_subdirs]

      We don't do this for now because the benefits are likely small.*)

  let get_sexp_and_destroy t =
    let result = t.contents.sexps in
    t.contents <- { t.contents with sexps = [] };
    result
end

let fname = "dune"

let jbuild_fname = "jbuild"

type kind =
  | Plain
  | Ocaml_script

type t =
  { path : Path.Source.t
  ; kind : kind
  ; (* for [kind = Ocaml_script], this is the part inserted with subdir *)
    plain : Plain.t
  }

let for_subdirs t = t.plain.for_subdirs

let get_static_sexp_and_possibly_destroy t =
  match t.kind with
  | Ocaml_script -> t.plain.contents.sexps
  | Plain -> Plain.get_sexp_and_destroy t.plain

let kind t = t.kind

let path t = t.path

let sub_dirs (t : t option) =
  match t with
  | None -> Sub_dirs.default
  | Some t -> Sub_dirs.or_default t.plain.contents.subdir_status

let load_plain sexps ~from_parent ~project =
  let decoder = Dune_project.set_parsing_context project Sub_dirs.decode in
  let active =
    let parsed =
      Dune_lang.Decoder.parse decoder Univ_map.empty
        (Dune_lang.Ast.List (Loc.none, sexps))
    in
    match from_parent with
    | None -> parsed
    | Some from_parent -> Sub_dirs.Dir_map.merge parsed from_parent
  in
  let contents = Sub_dirs.Dir_map.root active in
  { Plain.contents; for_subdirs = active }

let load file ~file_exists ~from_parent ~project =
  let kind, plain =
    match file_exists with
    | false -> (Plain, load_plain [] ~from_parent ~project)
    | true ->
      Io.with_lexbuf_from_file (Path.source file) ~f:(fun lb ->
          if Dune_lexer.is_script lb then
            let from_parent = load_plain [] ~from_parent ~project in
            (Ocaml_script, from_parent)
          else
            let sexps = Dune_lang.Parser.parse lb ~mode:Many in
            (Plain, load_plain sexps ~from_parent ~project))
  in
  { path = file; kind; plain }
