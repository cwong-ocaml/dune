open Stdune
open Memo.Build.O
module Caml_lazy = Lazy
open Memo
open Dune_tests_common

let () = init ()

let string_fn_create name =
  Memo.create name
    ~input:(module String)
    ~visibility:(Public Dune_lang.Decoder.string) Async

let int_fn_create name =
  Memo.create name
    ~input:(module Int)
    ~visibility:(Public Dune_lang.Decoder.int) Async

(* to run a computation *)
let run f v = Fiber.run ~iter:(fun () -> assert false) (Memo.Build.run (f v))

let run_memo f v = run (Memo.exec f) v

(* the trivial dependencies are simply the identity function *)
let compdep x = Memo.Build.return (x ^ x)

(* our two dependencies are called some and another *)
let mcompdep1 =
  string_fn_create "some" ~output:(Allow_cutoff (module String)) compdep

let mcompdep2 =
  string_fn_create "another" ~output:(Allow_cutoff (module String)) compdep

(* compute the dependencies once so they are present in the global hash table *)
let () =
  ignore (run_memo mcompdep1 "a");
  ignore (run_memo mcompdep2 "a")

(* define a counter so we can track how often our computation has been run *)
let counter = ref 0

(* our computation increases the counter, adds the two dependencies, "some" and
   "another" and works by multiplying the input by two *)
let comp x =
  let+ a =
    Memo.Build.return x >>= Memo.exec mcompdep1 >>= Memo.exec mcompdep2
  in
  counter := !counter + 1;
  String.sub a ~pos:0 ~len:(String.length a |> min 3)

let mcomp = string_fn_create "test" ~output:(Allow_cutoff (module String)) comp

(* running it the first time should increase the counter, running it again
   should not, but should still return the same result *)
let%expect_test _ =
  Format.printf "%d@." !counter;
  print_endline (run_memo mcomp "a");
  Format.printf "%d@." !counter;
  print_endline (run_memo mcomp "a");
  Format.printf "%d@." !counter;
  [%expect {|
0
aaa
1
aaa
1
|}]

let%expect_test _ =
  let open Dyn.Encoder in
  Memo.get_deps mcomp "a"
  |> option (list (pair (option string) (fun x -> x)))
  |> print_dyn;
  [%expect {|
Some [ (Some "some", "a"); (Some "another", "aa") ]
|}]

let%expect_test _ =
  (* running it on a new input should cause it to recompute the first time it is
     run *)
  print_endline (run_memo mcomp "hello");
  Format.printf "%d@." !counter;
  print_endline (run_memo mcomp "hello");
  Format.printf "%d@." !counter;
  [%expect {|
hel
2
hel
2
|}]

let%expect_test _ =
  (* updating the first dependency should require recomputation of mcomp 7 *)
  print_endline (run_memo mcompdep1 "testtest");
  print_endline (run_memo mcomp "hello");
  Format.printf "%d@." !counter;
  print_endline (run_memo mcomp "hello");
  Format.printf "%d@." !counter;
  [%expect {|
testtesttesttest
hel
2
hel
2
|}]

let stack = ref []

let dump_stack v =
  let s = get_call_stack () in
  stack := s;
  Memo.Build.return v

let mcompcycle =
  let mcompcycle = Fdecl.create Dyn.Encoder.opaque in
  let compcycle x =
    let* x = Memo.Build.return x >>= dump_stack in
    counter := !counter + 1;
    if !counter < 20 then
      (x + 1) mod 3 |> Memo.exec (Fdecl.get mcompcycle)
    else
      failwith "cycle"
  in
  let fn =
    int_fn_create "cycle" ~output:(Allow_cutoff (module String)) compcycle
  in
  Fdecl.set mcompcycle fn;
  fn

let%expect_test _ =
  counter := 0;
  try run_memo mcompcycle 5 |> ignore
  with Cycle_error.E err ->
    let cycle =
      Cycle_error.get err
      |> List.filter_map ~f:(Memo.Stack_frame.as_instance_of ~of_:mcompcycle)
    in
    print (Pp.enumerate cycle ~f:(Pp.textf "%d"));
    print (Pp.textf "%d" !counter);
    !stack
    |> List.map ~f:(fun st ->
           let open Dyn.Encoder in
           pair (option string)
             (fun x -> x)
             (Stack_frame.name st, Stack_frame.input st))
    |> Dyn.Encoder.list (fun x -> x)
    |> print_dyn;
    [%expect
      {|
- 2
- 1
- 0
- 2
4
[ (Some "cycle", 2)
; (Some "cycle", 1)
; (Some "cycle", 0)
; (Some "cycle", 5)
]
|}]

let mfib =
  let mfib = Fdecl.create Dyn.Encoder.opaque in
  let compfib x =
    let mfib = Memo.exec (Fdecl.get mfib) in
    counter := !counter + 1;
    if x <= 1 then
      Memo.Build.return x
    else
      let* r1 = mfib (x - 1) in
      let+ r2 = mfib (x - 2) in
      r1 + r2
  in
  let fn = int_fn_create "fib" ~output:(Allow_cutoff (module Int)) compfib in
  Fdecl.set mfib fn;
  fn

let%expect_test _ =
  counter := 0;
  Format.printf "%d@." (run_memo mfib 2000);
  Format.printf "%d@." !counter;
  Format.printf "%d@." (run_memo mfib 1800);
  Format.printf "%d@." !counter;
  [%expect {|
2406280077793834213
2001
3080005411477819488
2001
|}]

let sync_int_fn_create name =
  Memo.create name
    ~input:(module Int)
    ~visibility:(Public Dune_lang.Decoder.int) Sync

let counter = ref 0

let sync_fib =
  let mfib = Fdecl.create Dyn.Encoder.opaque in
  let compfib x =
    let mfib = Memo.exec (Fdecl.get mfib) in
    counter := !counter + 1;
    if x <= 1 then
      x
    else
      mfib (x - 1) + mfib (x - 2)
  in
  let fn =
    sync_int_fn_create "sync-fib" ~output:(Allow_cutoff (module Int)) compfib
  in
  Fdecl.set mfib fn;
  fn

let%expect_test _ =
  Format.printf "%d@." (Memo.exec sync_fib 2000);
  Format.printf "%d@." !counter;
  Format.printf "%d@." (Memo.exec sync_fib 1800);
  Format.printf "%d@." !counter;
  [%expect {|
  2406280077793834213
  2001
  3080005411477819488
  2001
  |}]

let make_f name f ~input ~output =
  Memo.create name ~input ~visibility:Hidden ~output:(Allow_cutoff output)
    ~doc:"" Sync f

let id =
  let f =
    make_f "id" (fun s -> s) ~input:(module String) ~output:(module String)
  in
  Memo.exec f

module Test_lazy (Lazy : sig
  type 'a t

  val create : (unit -> 'a) -> 'a t

  val force : 'a t -> 'a
end) =
struct
  module Lazy_string = struct
    type t = string Lazy.t

    let to_dyn s =
      ignore (Lazy.force s);
      Dyn.Encoder.string "opaque"

    let equal x y = String.equal (Lazy.force x) (Lazy.force y)

    let hash s = String.hash (Lazy.force s)
  end

  let lazy_memo =
    let f =
      make_f "lazy_memo"
        (fun s -> Lazy.create (fun () -> id ("lazy: " ^ s)))
        ~input:(module String)
        ~output:(module Lazy_string)
    in
    Memo.exec f

  let f1_def, f1 =
    let f =
      make_f "f1"
        (fun s -> "f1: " ^ Lazy.force (lazy_memo s))
        ~input:(module String)
        ~output:(module String)
    in
    (f, Memo.exec f)

  let f2_def, f2 =
    let f =
      make_f "f2"
        (fun s -> "f2: " ^ Lazy.force (lazy_memo s))
        ~input:(module String)
        ~output:(module String)
    in
    (f, Memo.exec f)

  let run () = (f1 "foo", f2 "foo")

  let deps () =
    let open Dyn.Encoder in
    let conv = option (list (pair (option string) (fun x -> x))) in
    pair conv conv (get_deps f1_def "foo", get_deps f2_def "foo")
end

module Builtin_lazy = Test_lazy (struct
  include Caml_lazy

  let create = from_fun
end)

let%expect_test _ =
  Builtin_lazy.run () |> Dyn.Encoder.(pair string string) |> print_dyn;
  [%expect {|
("f1: lazy: foo", "f2: lazy: foo")
|}]

let%expect_test _ =
  (* Bug: dependency on [lazy] is only registered by one of the dependants. This
     means we should never use [lazy] together with [Memo]. We can use
     [Memo.lazy_] though (see below) *)
  Builtin_lazy.deps () |> print_dyn;
  [%expect
    {|
(Some [ (Some "lazy_memo", "foo") ],
Some [ (Some "lazy_memo", "foo"); (Some "id", "lazy: foo") ])
|}]

module Memo_lazy = Test_lazy (struct
  include Memo.Lazy

  (* Here we hide the optional argument [cutoff] of [Memo.Lazy.create]. *)
  let create f = create f
end)

let%expect_test _ =
  Memo_lazy.run () |> Dyn.Encoder.(pair string string) |> print_dyn;
  [%expect {|
("f1: lazy: foo", "f2: lazy: foo")
|}]

let%expect_test _ =
  Memo_lazy.deps () |> print_dyn;
  [%expect
    {|
(Some [ (Some "lazy_memo", "foo"); (None, ()) ],
Some [ (Some "lazy_memo", "foo"); (None, ()) ])
|}]

(* Tests for depending on the current run *)

let depends_on_run =
  Memo.create "foobar" ~doc:"foo123"
    ~input:(module Unit)
    ~output:(Allow_cutoff (module Unit))
    ~visibility:Hidden Sync
    (fun () ->
      let (_ : Memo.Run.t) = Memo.current_run () in
      print_endline "running foobar")

let%expect_test _ =
  Memo.exec depends_on_run ();
  Memo.exec depends_on_run ();
  print_endline "resetting memo";
  Memo.reset ();
  Memo.exec depends_on_run ();
  [%expect {|
    running foobar
    resetting memo
    running foobar |}]

(* Tests for Memo.Cell *)

let%expect_test _ =
  let f x = "*" ^ x in
  let memo =
    Memo.create "for-cell"
      ~input:(module String)
      ~visibility:(Public Dune_lang.Decoder.string)
      ~output:(Allow_cutoff (module String))
      ~doc:"" Sync f
  in
  let cell = Memo.cell memo "foobar" in
  print_endline (Cell.get_sync cell);
  print_endline (Cell.get_sync cell);
  [%expect {|
    *foobar
    *foobar |}]

let printf = Printf.printf

let%expect_test "fib linked list" =
  let module Element = struct
    type t =
      { prev_cell : (int, t, int -> t) Memo.Cell.t
      ; value : int
      ; next_cell : (int, t, int -> t) Memo.Cell.t
      }

    let to_dyn t = Dyn.Int t.value
  end in
  let force cell : Element.t = Memo.Cell.get_sync cell in
  let memo_fdecl = Fdecl.create Dyn.Encoder.opaque in
  let compute_element x =
    let memo = Fdecl.get memo_fdecl in
    printf "computing %d\n" x;
    let prev_cell = Memo.cell memo (x - 1) in
    let value =
      if x < 1 then
        0
      else if x = 1 then
        1
      else
        (force prev_cell).value + (force (force prev_cell).prev_cell).value
    in
    { Element.next_cell = Memo.cell memo (x + 1); prev_cell; value }
  in
  let memo =
    Memo.create "fib"
      ~input:(module Int)
      ~visibility:Hidden Sync
      ~output:(Simple (module Element))
      compute_element ~doc:""
  in
  Fdecl.set memo_fdecl memo;
  let fourth = Memo.exec memo 4 in
  printf "4th: %d\n" fourth.value;
  printf "next: %d\n" (force fourth.next_cell).value;
  let seventh = Memo.exec memo 7 in
  printf "7th: %d\n" seventh.value;
  printf "prev: %d\n" (force seventh.prev_cell).value;
  printf "prev: %d\n" (force (force seventh.prev_cell).prev_cell).value;
  [%expect
    {|
    computing 4
    computing 3
    computing 2
    computing 1
    computing 0
    4th: 3
    computing 5
    next: 5
    computing 7
    computing 6
    7th: 13
    prev: 8
    prev: 5 |}]

module Function = struct
  type 'a input =
    | I : int Type_eq.Id.t * int -> int input
    | S : string Type_eq.Id.t * string -> string input

  type 'a output = 'a list

  let name = "memo-poly-async"

  let id (type a) (x : a input) : a Type_eq.Id.t =
    match x with
    | I (id, _) -> id
    | S (id, _) -> id

  let to_dyn _ = Dyn.Opaque

  let eval (type a) (x : a input) : a output Memo.Build.t =
    match x with
    | I (_, i) ->
      let* () = Memo.Build.return () in
      Printf.printf "Evaluating %d\n" i;
      Memo.Build.return (List.init i ~f:(fun i -> i + 1))
    | S (_, s) ->
      let* () = Memo.Build.return () in
      Printf.printf "Evaluating %S\n" s;
      Memo.Build.return [ s ]

  let get (type a) (x : a input) : a =
    match x with
    | I (_, x) -> x
    | S (_, x) -> x
end

let%expect_test "Memo.Poly.Async" =
  let module M = Memo.Poly.Async (Function) in
  let (i1 : int Function.input) = I (Type_eq.Id.create (), 1) in
  let (i2 : int Function.input) = I (Type_eq.Id.create (), 2) in
  let (s1 : string Function.input) = S (Type_eq.Id.create (), "hi") in
  let (s2 : string Function.input) = S (Type_eq.Id.create (), "hi again") in
  let run_int i =
    let res = run M.eval i in
    Dyn.to_string (Dyn.List (List.map res ~f:Int.to_dyn))
  in
  let run_string s =
    let res = run M.eval s in
    Dyn.to_string (Dyn.List (List.map res ~f:String.to_dyn))
  in
  printf "----- First-time calls -----\n";
  printf "%d -> %s\n" (Function.get i1) (run_int i1);
  printf "%S -> %s\n" (Function.get s1) (run_string s1);
  printf "%d -> %s\n" (Function.get i2) (run_int i2);
  printf "%S -> %s\n" (Function.get s2) (run_string s2);
  printf "----- Repeated calls (memoized) -----\n";
  printf "%d -> %s\n" (Function.get i1) (run_int i1);
  printf "%S -> %s\n" (Function.get s1) (run_string s1);
  printf "%d -> %s\n" (Function.get i2) (run_int i2);
  printf "%S -> %s\n" (Function.get s2) (run_string s2);
  [%expect
    {|
    ----- First-time calls -----
    Evaluating 1
    1 -> [ 1 ]
    Evaluating "hi"
    "hi" -> [ "hi" ]
    Evaluating 2
    2 -> [ 1; 2 ]
    Evaluating "hi again"
    "hi again" -> [ "hi again" ]
    ----- Repeated calls (memoized) -----
    1 -> [ 1 ]
    "hi" -> [ "hi" ]
    2 -> [ 1; 2 ]
    "hi again" -> [ "hi again" ]
    |}]

let%expect_test "error handling and memo - sync" =
  let f =
    sync_int_fn_create "sync f"
      ~output:(Allow_cutoff (module Int))
      (fun x ->
        printf "Calling f %d\n" x;
        if x = 42 then
          failwith "42"
        else
          x)
  in
  let test x =
    let res = Result.try_with (fun () -> Memo.exec f x) in
    Format.printf "f %d = %a@." x Pp.to_fmt
      (Dyn.pp (Result.to_dyn Dyn.Encoder.int Exn.to_dyn res))
  in
  test 20;
  test 20;
  test 42;
  test 42;
  [%expect
    {|
    Calling f 20
    f 20 = Ok 20
    f 20 = Ok 20
    Calling f 42
    f 42 = Error "(Failure 42)"
    f 42 = Error "(Failure 42)" |}]

let print_result f x =
  let res =
    ( try
        Fiber.run
          ~iter:(fun () -> raise Exit)
          (Memo.Build.run (Memo.Build.collect_errors (fun () -> Memo.exec f x)))
      with exn -> Error [ Exn_with_backtrace.capture exn ] )
    |> Result.map_error
         ~f:
           (List.map
              ~f:
                (Exn_with_backtrace.map ~f:(fun exn ->
                     match exn with
                     | Memo.Cycle_error.E cycle_error ->
                       let frames = Memo.Cycle_error.get cycle_error in
                       printf "Dependency cycle detected:\n";
                       List.iteri frames ~f:(fun i frame ->
                           let called_by =
                             match i with
                             | 0 -> ""
                             | _ -> "called by "
                           in
                           printf "- %s%s\n" called_by
                             (Dyn.to_string (Stack_frame.to_dyn frame)));
                       exn
                     | _ -> exn)))
  in
  let open Dyn.Encoder in
  Format.printf "f %d = %a@." x Pp.to_fmt
    (Dyn.pp (Result.to_dyn int (list Exn_with_backtrace.to_dyn) res))

let%expect_test "error handling and memo - async" =
  let f =
    int_fn_create "async f"
      ~output:(Allow_cutoff (module Int))
      (fun x ->
        printf "Calling f %d\n" x;
        if x = 42 then
          failwith "42"
        else if x = 84 then
          Memo.Build.fork_and_join_unit
            (fun () -> failwith "left")
            (fun () -> failwith "right")
        else
          Memo.Build.return x)
  in
  let test x = print_result f x in
  test 20;
  test 20;
  test 42;
  test 42;
  test 84;
  test 84;
  [%expect
    {|
    Calling f 20
    f 20 = Ok 20
    f 20 = Ok 20
    Calling f 42
    f 42 = Error [ { exn = "(Failure 42)"; backtrace = "" } ]
    f 42 = Error [ { exn = "(Failure 42)"; backtrace = "" } ]
    Calling f 84
    f 84 = Error
             [ { exn = "(Failure left)"; backtrace = "" }
             ; { exn = "(Failure right)"; backtrace = "" }
             ]
    f 84 = Error
             [ { exn = "(Failure left)"; backtrace = "" }
             ; { exn = "(Failure right)"; backtrace = "" }
             ] |}]

(* A test function counting runs. *)
let count_runs () =
  let counter = ref 0 in
  fun () ->
    incr counter;
    let result = !counter in
    printf "Evaluating count_runs: %d\n" result;
    let (_ : Run.t) = Memo.current_run () in
    Build.return result

(* A test function incrementing a given memo. *)
let increment which which_memo () =
  printf "Starting evaluating %s\n" which;
  let+ input = Memo.exec which_memo () in
  let result = input + 1 in
  printf "Evaluated %s: %d\n" which result;
  result

(* Create an async node with or without cutoff. *)
let create ~with_cutoff name f =
  let output =
    match with_cutoff with
    | true -> Memo.Output.Allow_cutoff (module Int)
    | false -> Simple (module Int)
  in
  Memo.create name
    ~input:(module Unit)
    ~visibility:Hidden ~output ~doc:"" Async f

let%expect_test "diamond with non-uniform cutoff structure" =
  let base = create ~with_cutoff:true "base" (count_runs ()) in
  let length_of_base which () =
    printf "Starting evaluating %s\n" which;
    let+ base = Memo.exec base () in
    let result = String.length (Int.to_string base) in
    printf "Evaluated %s: %d\n" which result;
    result
  in
  let no_cutoff =
    create ~with_cutoff:false "no_cutoff" (length_of_base "no_cutoff")
  in
  let yes_cutoff =
    create ~with_cutoff:true "yes_cutoff" (length_of_base "yes_cutoff")
  in
  let after_no_cutoff =
    create ~with_cutoff:true "after_no_cutoff"
      (increment "after_no_cutoff" no_cutoff)
  in
  let after_yes_cutoff =
    create ~with_cutoff:true "after_yes_cutoff"
      (increment "after_yes_cutoff" yes_cutoff)
  in
  let summit offset =
    printf "Starting evaluating summit with offset %d\n" offset;
    let+ after_no_cutoff, after_yes_cutoff =
      Memo.Build.both
        (Memo.exec after_no_cutoff ())
        (Memo.exec after_yes_cutoff ())
    in
    let result = after_no_cutoff + after_yes_cutoff + offset in
    printf "Evaluated summit with offset %d: %d\n" offset result;
    result
  in
  let summit =
    Memo.create "summit"
      ~input:(module Int)
      ~visibility:Hidden
      ~output:(Simple (module Int))
      ~doc:"" Async summit
  in
  print_result summit 0;
  [%expect
    {|
    Starting evaluating summit with offset 0
    Starting evaluating after_no_cutoff
    Starting evaluating no_cutoff
    Evaluating count_runs: 1
    Evaluated no_cutoff: 1
    Evaluated after_no_cutoff: 2
    Starting evaluating after_yes_cutoff
    Starting evaluating yes_cutoff
    Evaluated yes_cutoff: 1
    Evaluated after_yes_cutoff: 2
    Evaluated summit with offset 0: 4
    f 0 = Ok 4
    |}];
  print_result summit 1;
  [%expect
    {|
    Starting evaluating summit with offset 1
    Evaluated summit with offset 1: 5
    f 1 = Ok 5
    |}];
  Memo.restart_current_run ();
  print_result summit 0;
  [%expect
    {|
    Evaluating count_runs: 2
    Starting evaluating yes_cutoff
    Evaluated yes_cutoff: 1
    Starting evaluating no_cutoff
    Evaluated no_cutoff: 1
    Starting evaluating after_no_cutoff
    Evaluated after_no_cutoff: 2
    f 0 = Ok 4
    |}];
  print_result summit 1;
  [%expect {|
    f 1 = Ok 5
    |}];
  print_result summit 2;
  [%expect
    {|
    Starting evaluating summit with offset 2
    Evaluated summit with offset 2: 6
    f 2 = Ok 6
    |}]

(* The test below sets up the following situation:

   - In the initial run, there are no dependency cycles.

   - In the second run, [base_or_summit] gets an additional dynamic dependency
   and eventually cycles back to itself.

   - In all subsequent runs, we are back to having no dependency cycles.

   The dependency chains in the new test have alternating cutoff/no-cutoff
   structure, to make sure that cycle detection can handle such cases. *)
let%expect_test "dynamic cycles with non-uniform cutoff structure" =
  let base = create ~with_cutoff:true "base" (count_runs ()) in
  let first_base_then_summit which ~summit_fdecl () =
    printf "Started evaluating %s\n" which;
    let* base = Memo.exec base () in
    match base with
    | input when input = 2 ->
      let summit = Fdecl.get summit_fdecl in
      printf "Cycling to summit from %s...\n" which;
      let+ result = Memo.exec summit input in
      printf "Miraculously evaluated %s: %d\n" which result;
      result
    | input ->
      printf "Evaluated %s: %d\n" which input;
      Build.return input
  in
  let rec incrementing_chain ~end_with_cutoff ~from n =
    match n with
    | 0 -> from
    | _ ->
      let from =
        incrementing_chain ~end_with_cutoff:(not end_with_cutoff) ~from (n - 1)
      in
      let cutoff =
        match end_with_cutoff with
        | false -> "_no_cutoff"
        | true -> "_yes_cutoff"
      in
      let name = "incrementing_chain_" ^ Int.to_string n ^ cutoff in
      create ~with_cutoff:end_with_cutoff name (increment name from)
  in
  let incrementing_chain_plus_input ~end_with_cutoff ~from =
    let chain =
      incrementing_chain ~end_with_cutoff:(not end_with_cutoff) ~from 4
    in
    let plus_input input =
      printf "Started evaluating the summit with input %d\n" input;
      let+ result = Memo.exec chain () in
      let result = result + input in
      printf "Evaluated the summit with input %d: %d\n" input result;
      result
    in
    let output =
      match end_with_cutoff with
      | true -> Memo.Output.Allow_cutoff (module Int)
      | false -> Simple (module Int)
    in
    Memo.create "incrementing_chain_plus_input"
      ~input:(module Int)
      ~visibility:Hidden ~output ~doc:"" Async plus_input
  in
  let summit_fdecl = Fdecl.create (fun _ -> Dyn.Opaque) in
  let cycle_creator_no_cutoff =
    create ~with_cutoff:false "cycle_creator_no_cutoff"
      (first_base_then_summit "cycle_creator_no_cutoff" ~summit_fdecl)
  in
  let summit_no_cutoff =
    incrementing_chain_plus_input ~end_with_cutoff:false
      ~from:cycle_creator_no_cutoff
  in
  Fdecl.set summit_fdecl summit_no_cutoff;
  let summit_fdecl = Fdecl.create (fun _ -> Dyn.Opaque) in
  let cycle_creator_yes_cutoff =
    create ~with_cutoff:true "cycle_creator_yes_cutoff"
      (first_base_then_summit "cycle_creator_yes_cutoff" ~summit_fdecl)
  in
  let summit_yes_cutoff =
    incrementing_chain_plus_input ~end_with_cutoff:true
      ~from:cycle_creator_yes_cutoff
  in
  Fdecl.set summit_fdecl summit_yes_cutoff;
  print_result summit_no_cutoff 0;
  [%expect
    {|
    Started evaluating the summit with input 0
    Starting evaluating incrementing_chain_4_yes_cutoff
    Starting evaluating incrementing_chain_3_no_cutoff
    Starting evaluating incrementing_chain_2_yes_cutoff
    Starting evaluating incrementing_chain_1_no_cutoff
    Started evaluating cycle_creator_no_cutoff
    Evaluating count_runs: 1
    Evaluated cycle_creator_no_cutoff: 1
    Evaluated incrementing_chain_1_no_cutoff: 2
    Evaluated incrementing_chain_2_yes_cutoff: 3
    Evaluated incrementing_chain_3_no_cutoff: 4
    Evaluated incrementing_chain_4_yes_cutoff: 5
    Evaluated the summit with input 0: 5
    f 0 = Ok 5 |}];
  print_result summit_yes_cutoff 0;
  [%expect
    {|
    Started evaluating the summit with input 0
    Starting evaluating incrementing_chain_4_no_cutoff
    Starting evaluating incrementing_chain_3_yes_cutoff
    Starting evaluating incrementing_chain_2_no_cutoff
    Starting evaluating incrementing_chain_1_yes_cutoff
    Started evaluating cycle_creator_yes_cutoff
    Evaluated cycle_creator_yes_cutoff: 1
    Evaluated incrementing_chain_1_yes_cutoff: 2
    Evaluated incrementing_chain_2_no_cutoff: 3
    Evaluated incrementing_chain_3_yes_cutoff: 4
    Evaluated incrementing_chain_4_no_cutoff: 5
    Evaluated the summit with input 0: 5
    f 0 = Ok 5 |}];
  print_result summit_no_cutoff 2;
  [%expect
    {|
    Started evaluating the summit with input 2
    Evaluated the summit with input 2: 7
    f 2 = Ok 7 |}];
  print_result summit_yes_cutoff 2;
  [%expect
    {|
    Started evaluating the summit with input 2
    Evaluated the summit with input 2: 7
    f 2 = Ok 7 |}];
  Memo.restart_current_run ();
  print_result summit_no_cutoff 0;
  [%expect
    {|
    Evaluating count_runs: 2
    Started evaluating cycle_creator_no_cutoff
    Cycling to summit from cycle_creator_no_cutoff...
    Starting evaluating incrementing_chain_1_no_cutoff
    Starting evaluating incrementing_chain_2_yes_cutoff
    Starting evaluating incrementing_chain_3_no_cutoff
    Starting evaluating incrementing_chain_4_yes_cutoff
    Started evaluating the summit with input 0
    Dependency cycle detected:
    - ("incrementing_chain_plus_input", 2)
    - called by ("cycle_creator_no_cutoff", ())
    - called by ("incrementing_chain_1_no_cutoff", ())
    - called by ("incrementing_chain_2_yes_cutoff", ())
    - called by ("incrementing_chain_3_no_cutoff", ())
    - called by ("incrementing_chain_4_yes_cutoff", ())
    - called by ("incrementing_chain_plus_input", 2)
    f 0 = Error [ { exn = "Memo.Cycle_error.E(_)"; backtrace = "" } ] |}];
  print_result summit_yes_cutoff 0;
  [%expect
    {|
    Started evaluating cycle_creator_yes_cutoff
    Cycling to summit from cycle_creator_yes_cutoff...
    Starting evaluating incrementing_chain_1_yes_cutoff
    Starting evaluating incrementing_chain_2_no_cutoff
    Starting evaluating incrementing_chain_3_yes_cutoff
    Starting evaluating incrementing_chain_4_no_cutoff
    Started evaluating the summit with input 0
    Dependency cycle detected:
    - ("incrementing_chain_plus_input", 2)
    - called by ("cycle_creator_yes_cutoff", ())
    - called by ("incrementing_chain_1_yes_cutoff", ())
    - called by ("incrementing_chain_2_no_cutoff", ())
    - called by ("incrementing_chain_3_yes_cutoff", ())
    - called by ("incrementing_chain_4_no_cutoff", ())
    - called by ("incrementing_chain_plus_input", 2)
    f 0 = Error [ { exn = "Memo.Cycle_error.E(_)"; backtrace = "" } ] |}];
  print_result summit_no_cutoff 2;
  [%expect
    {|
    Dependency cycle detected:
    - ("incrementing_chain_plus_input", 2)
    - called by ("cycle_creator_no_cutoff", ())
    - called by ("incrementing_chain_1_no_cutoff", ())
    - called by ("incrementing_chain_2_yes_cutoff", ())
    - called by ("incrementing_chain_3_no_cutoff", ())
    - called by ("incrementing_chain_4_yes_cutoff", ())
    - called by ("incrementing_chain_plus_input", 2)
    f 2 = Error [ { exn = "Memo.Cycle_error.E(_)"; backtrace = "" } ] |}];
  print_result summit_yes_cutoff 2;
  [%expect
    {|
    Dependency cycle detected:
    - ("incrementing_chain_plus_input", 2)
    - called by ("cycle_creator_yes_cutoff", ())
    - called by ("incrementing_chain_1_yes_cutoff", ())
    - called by ("incrementing_chain_2_no_cutoff", ())
    - called by ("incrementing_chain_3_yes_cutoff", ())
    - called by ("incrementing_chain_4_no_cutoff", ())
    - called by ("incrementing_chain_plus_input", 2)
    f 2 = Error [ { exn = "Memo.Cycle_error.E(_)"; backtrace = "" } ] |}];
  Memo.restart_current_run ();
  print_result summit_no_cutoff 0;
  [%expect
    {|
    Started evaluating the summit with input 0
    Starting evaluating incrementing_chain_4_yes_cutoff
    Starting evaluating incrementing_chain_3_no_cutoff
    Starting evaluating incrementing_chain_2_yes_cutoff
    Starting evaluating incrementing_chain_1_no_cutoff
    Started evaluating cycle_creator_no_cutoff
    Evaluating count_runs: 3
    Evaluated cycle_creator_no_cutoff: 3
    Evaluated incrementing_chain_1_no_cutoff: 4
    Evaluated incrementing_chain_2_yes_cutoff: 5
    Evaluated incrementing_chain_3_no_cutoff: 6
    Evaluated incrementing_chain_4_yes_cutoff: 7
    Evaluated the summit with input 0: 7
    f 0 = Ok 7 |}];
  print_result summit_yes_cutoff 0;
  [%expect
    {|
    Started evaluating the summit with input 0
    Starting evaluating incrementing_chain_4_no_cutoff
    Starting evaluating incrementing_chain_3_yes_cutoff
    Starting evaluating incrementing_chain_2_no_cutoff
    Starting evaluating incrementing_chain_1_yes_cutoff
    Started evaluating cycle_creator_yes_cutoff
    Evaluated cycle_creator_yes_cutoff: 3
    Evaluated incrementing_chain_1_yes_cutoff: 4
    Evaluated incrementing_chain_2_no_cutoff: 5
    Evaluated incrementing_chain_3_yes_cutoff: 6
    Evaluated incrementing_chain_4_no_cutoff: 7
    Evaluated the summit with input 0: 7
    f 0 = Ok 7 |}];
  print_result summit_no_cutoff 2;
  [%expect
    {|
    Started evaluating the summit with input 2
    Evaluated the summit with input 2: 9
    f 2 = Ok 9 |}];
  print_result summit_yes_cutoff 2;
  [%expect
    {|
    Started evaluating the summit with input 2
    Evaluated the summit with input 2: 9
    f 2 = Ok 9 |}]

let print_exns f =
  let res =
    match
      Fiber.run
        ~iter:(fun () -> raise Exit)
        (Memo.Build.run (Memo.Build.collect_errors f))
    with
    | Ok _ -> assert false
    | Error exns ->
      Error (List.map exns ~f:(fun (e : Exn_with_backtrace.t) -> e.exn))
    | exception exn -> Error [ exn ]
  in
  let open Dyn.Encoder in
  Format.printf "%a@." Pp.to_fmt
    (Dyn.pp (Result.to_dyn unit (list Exn.to_dyn) res))

let%expect_test "error handling and async diamond" =
  Printexc.record_backtrace true;
  let f_impl = Fdecl.create Dyn.Encoder.opaque in
  let f =
    int_fn_create "async-error-diamond: f"
      ~output:(Allow_cutoff (module Unit))
      (fun x -> Fdecl.get f_impl x)
  in
  Fdecl.set f_impl (fun x ->
      printf "Calling f %d\n" x;
      if x = 0 then
        failwith "reached 0"
      else
        Memo.Build.fork_and_join_unit
          (fun () -> Memo.exec f (x - 1))
          (fun () -> Memo.exec f (x - 1)));
  let test x = print_exns (fun () -> Memo.exec f x) in
  test 0;
  [%expect {|
    Calling f 0
    Error [ "(Failure \"reached 0\")" ]
    |}];
  test 1;
  [%expect {|
    Calling f 1
    Error [ "(Failure \"reached 0\")" ]
    |}];
  test 2;
  [%expect {|
    Calling f 2
    Error [ "(Failure \"reached 0\")" ]
    |}]

let%expect_test "error handling and duplicate sync exceptions" =
  Printexc.record_backtrace true;
  let f_impl = Fdecl.create Dyn.Encoder.opaque in
  let f =
    int_fn_create "test8: async-duplicate-sync-exception: f"
      ~output:(Allow_cutoff (module Unit))
      (fun x -> Fdecl.get f_impl x)
  in
  let fail =
    sync_int_fn_create "test8: fail"
      ~output:(Allow_cutoff (module Unit))
      (fun _x -> failwith "42")
  in
  let forward_fail =
    sync_int_fn_create "test8: forward fail"
      ~output:(Allow_cutoff (module Unit))
      (fun x -> Memo.exec fail x)
  in
  let forward_fail2 =
    sync_int_fn_create "test8: forward fail2"
      ~output:(Allow_cutoff (module Unit))
      (fun x -> Memo.exec fail x)
  in
  Fdecl.set f_impl (fun x ->
      printf "Calling f %d\n" x;

      match x with
      | 0 -> Memo.Build.return (Memo.exec forward_fail x)
      | 1 -> Memo.Build.return (Memo.exec forward_fail2 x)
      | _ ->
        Memo.Build.fork_and_join_unit
          (fun () -> Memo.exec f (x - 1))
          (fun () -> Memo.exec f (x - 2)));
  let test x = print_exns (fun () -> Memo.exec f x) in
  test 2;
  [%expect
    {|
    Calling f 2
    Calling f 1
    Calling f 0
    Error [ "(Failure 42)" ]
    |}]
