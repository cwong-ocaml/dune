open Stdune
open Dune_file
open Build_system

let string_of_exts = String.concat ~sep:"-and-"

let lib_files_alias ~dir ~name ~exts =
  Alias.make (sprintf "lib-%s%s-all"
                (Lib_name.to_string name) (string_of_exts exts)) ~dir

let setup_file_deps_alias t ~dir ~exts lib files =
  Super_context.add_alias_deps t
    (lib_files_alias ~dir ~name:(Library.best_name lib) ~exts) files

let setup_file_deps_group_alias t ~dir ~exts lib =
  setup_file_deps_alias t lib ~dir ~exts
    (List.map exts ~f:(fun ext ->
       Alias.stamp_file
         (lib_files_alias ~dir ~name:(Library.best_name lib) ~exts:[ext]))
     |> Path.Set.of_list)

let setup_file_deps sctx ~dir ~lib ~modules =
  let add_cms ~cm_kind ~init = List.fold_left ~init ~f:(fun acc m ->
    match Module.cm_public_file m cm_kind with
    | None -> acc
    | Some fn -> Path.Set.add acc fn)
  in
  List.iter Cm_kind.all ~f:(fun cm_kind ->
    let files = add_cms ~cm_kind ~init:Path.Set.empty modules in
    setup_file_deps_alias sctx ~dir lib ~exts:[Cm_kind.ext cm_kind]
      files);

  setup_file_deps_group_alias sctx ~dir lib ~exts:[".cmi"; ".cmx"];
  setup_file_deps_alias sctx ~dir lib ~exts:[".h"]
    (List.map lib.install_c_headers ~f:(fun header ->
       Path.relative dir (header ^ ".h"))
     |> Path.Set.of_list)

module L = struct
  let file_deps_of_lib t (lib : Lib.t) ~exts =
    if Lib.is_local lib then
      Alias.stamp_file
        (lib_files_alias ~dir:(Lib.src_dir lib) ~name:(Lib.name lib) ~exts)
    else
      (* suppose that all the files of an external lib are at the same place *)
      Build_system.stamp_file_for_files_of (Super_context.build_system t)
        ~dir:(Obj_dir.public_cmi_dir (Lib.obj_dir lib)) ~ext:(string_of_exts exts)

  let file_deps_with_exts t lib_exts =
    List.rev_map lib_exts ~f:(fun (lib, exts) -> file_deps_of_lib t lib ~exts)

  let file_deps t libs ~exts =
    List.rev_map libs ~f:(file_deps_of_lib t ~exts)
end
