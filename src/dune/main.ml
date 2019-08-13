open! Stdune
open Import
open Fiber.O

let () = Inline_tests.linkme

type workspace =
  { contexts : Context.t list
  ; conf : Dune_load.conf
  ; env : Env.t
  }

type build_system =
  { workspace : workspace
  ; scontexts : Super_context.t String.Map.t
  }

let package_install_file w pkg =
  match Package.Name.Map.find w.conf.packages pkg with
  | None ->
    Error ()
  | Some p ->
    Ok
      (Path.Source.relative p.path
         (Utils.install_file ~package:p.name ~findlib_toolchain:None))

let setup_env ~capture_outputs =
  let env =
    if
      (not capture_outputs)
      || not (Lazy.force Ansi_color.stderr_supports_color)
    then
      Env.initial
    else
      Colors.setup_env_for_colors Env.initial
  in
  Env.add env ~var:"INSIDE_DUNE" ~value:"1"

let scan_workspace ?workspace ?workspace_file ?x ?(capture_outputs = true)
    ?profile ~ancestor_vcs () =
  let env = setup_env ~capture_outputs in
  let conf = Dune_load.load ~ancestor_vcs () in
  let workspace =
    match workspace with
    | Some w ->
      w
    | None -> (
      match workspace_file with
      | Some p ->
        if not (Path.exists p) then
          User_error.raise
            [ Pp.textf "Workspace file %s does not exist"
                (Path.to_string_maybe_quoted p)
            ];
        Workspace.load ?x ?profile p
      | None -> (
        match
          let p = Path.of_string Workspace.filename in
          Option.some_if (Path.exists p) p
        with
        | Some p ->
          Workspace.load ?x ?profile p
        | None ->
          Workspace.default ?x ?profile () ) )
  in
  let+ contexts = Context.create ~env workspace in
  List.iter contexts ~f:(fun (ctx : Context.t) ->
      Log.infof "@[<1>Dune context:@,%a@]@." Pp.render_ignore_tags
        (Dyn.pp (Context.to_dyn ctx)));
  { contexts; conf; env }

let init_build_system ?only_packages ?external_lib_deps_mode
    ~sandboxing_preference w =
  Option.iter only_packages ~f:(fun set ->
      Package.Name.Set.iter set ~f:(fun pkg ->
          if not (Package.Name.Map.mem w.conf.packages pkg) then
            let pkg_name = Package.Name.to_string pkg in
            User_error.raise
              [ Pp.textf
                  "I don't know about package %s (passed through \
                   --only-packages/--release)"
                  pkg_name
              ]
              ~hints:
                (User_message.did_you_mean pkg_name
                   ~candidates:
                     ( Package.Name.Map.keys w.conf.packages
                     |> List.map ~f:Package.Name.to_string ))));
  let rule_done = ref 0 in
  let rule_total = ref 0 in
  let gen_status_line () =
    { Scheduler.message =
        Some (Pp.verbatim (sprintf "Done: %u/%u" !rule_done !rule_total))
    ; show_jobs = true
    }
  in
  let hook (hook : Build_system.hook) =
    match hook with
    | Rule_started ->
      incr rule_total
    | Rule_completed ->
      incr rule_done
  in
  Build_system.reset ();
  Build_system.init ~sandboxing_preference ~contexts:w.contexts
    ~file_tree:w.conf.file_tree ~hook;
  Scheduler.set_status_line_generator gen_status_line;
  let+ scontexts =
    Gen_rules.gen w.conf ~contexts:w.contexts ?only_packages
      ?external_lib_deps_mode
  in
  { workspace = w; scontexts }

let auto_concurrency =
  let v = ref None in
  fun () ->
    match !v with
    | Some n ->
      Fiber.return n
    | None ->
      let+ n =
        if Sys.win32 then
          match Env.get Env.initial "NUMBER_OF_PROCESSORS" with
          | None ->
            Fiber.return 1
          | Some s -> (
            match int_of_string s with
            | exception _ ->
              Fiber.return 1
            | n ->
              Fiber.return n )
        else
          let commands =
            [ ("nproc", [])
            ; ("getconf", [ "_NPROCESSORS_ONLN" ])
            ; ("getconf", [ "NPROCESSORS_ONLN" ])
            ]
          in
          let rec loop = function
            | [] ->
              Fiber.return 1
            | (prog, args) :: rest -> (
              match Bin.which ~path:(Env.path Env.initial) prog with
              | None ->
                loop rest
              | Some prog -> (
                let* result =
                  Process.run_capture (Accept All) prog args ~env:Env.initial
                    ~stderr_to:(Process.Io.file Config.dev_null Process.Io.Out)
                in
                match result with
                | Error _ ->
                  loop rest
                | Ok s -> (
                  match int_of_string (String.trim s) with
                  | n ->
                    Fiber.return n
                  | exception _ ->
                    loop rest ) ) )
          in
          loop commands
      in
      Log.infof "Auto-detected concurrency: %d" n;
      v := Some n;
      n

let set_concurrency (config : Config.t) =
  let+ n =
    match config.concurrency with
    | Fixed n ->
      Fiber.return n
    | Auto ->
      auto_concurrency ()
  in
  if n >= 1 then Scheduler.set_concurrency n

(* Called by the script generated by ../build.ml *)
let bootstrap () =
  Clflags.promote_install_files := true;
  Colors.setup_err_formatter_colors ();
  Path.set_root Path.External.initial_cwd;
  Path.Build.set_build_dir (Path.Build.Kind.of_string "_boot");
  let main () =
    let anon s =
      raise (Arg.Bad (Printf.sprintf "don't know what to do with %s\n" s))
    in
    let init (config : Config.t) =
      Console.init config.display;
      Log.init ()
    in
    let subst () =
      let config : Config.t =
        { display = Quiet
        ; concurrency = Fixed 1
        ; terminal_persistence = Preserve
        ; sandboxing_preference = []
        }
      in
      init config;
      Scheduler.go ~config Watermarks.subst;
      exit 0
    in
    let display = ref None in
    let display_mode =
      Arg.Symbol
        ( List.map Config.Display.all ~f:fst
        , fun s -> display := List.assoc Config.Display.all s )
    in
    let concurrency = ref None in
    let concurrency_arg x =
      match Config.Concurrency.of_string x with
      | Error msg ->
        raise (Arg.Bad msg)
      | Ok c ->
        concurrency := Some c
    in
    let terminal_persistence = Some Config.Terminal_persistence.Preserve in
    let profile = ref None in
    Arg.parse
      [ ("-j", String concurrency_arg, "JOBS concurrency")
      ; ( "--release"
        , Unit (fun () -> profile := Some Profile.Release)
        , " set release mode" )
      ; ("--display", display_mode, " set the display mode")
      ; ("--subst", Unit subst, " substitute watermarks in source files")
      ; ( "--debug-backtraces"
        , Set Clflags.debug_backtraces
        , " always print exception backtraces" )
      ]
      anon "Usage: boot.exe [-j JOBS] [--dev]\nOptions are:";
    Clflags.debug_dep_path := true;
    let config =
      (* Only load the configuration with --dev *)
      if !profile = Some Profile.Release then
        Config.default
      else
        Config.load_user_config_file ()
    in
    let config =
      Config.merge config
        { display = !display
        ; concurrency = !concurrency
        ; sandboxing_preference = None
        ; terminal_persistence
        }
    in
    let config =
      Config.adapt_display config
        ~output_is_a_tty:(Lazy.force Ansi_color.stderr_supports_color)
    in
    init config;
    Scheduler.go ~config (fun () ->
        let* () = set_concurrency config in
        let* workspace =
          scan_workspace
            ~workspace:(Workspace.default ?profile:!profile ())
            ?profile:!profile ~ancestor_vcs:None ()
        in
        let* _ =
          init_build_system ~sandboxing_preference:config.sandboxing_preference
            workspace
        in
        Build_system.do_build
          ~request:
            (Build.path (Path.relative Path.build_dir "default/dune.install")))
  in
  try main () with
  | Fiber.Never ->
    exit 1
  | exn ->
    let exn = Exn_with_backtrace.capture exn in
    Report_error.report exn;
    exit 1

let find_context_exn t ~name =
  match List.find t.contexts ~f:(fun c -> c.name = name) with
  | Some ctx ->
    ctx
  | None ->
    User_error.raise [ Pp.textf "Context %S not found!" name ]