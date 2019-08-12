Test the various new fields inside the dune-project file.

The `dune build` should work.

  $ dune build @install --root test-fields --auto-promote
  Entering directory 'test-fields'
  $ cat test-fields/cohttp.opam
  # This file is generated by dune, edit dune-project instead
  opam-version: "2.0"
  build: [
    ["dune" "subst"] {pinned}
    ["dune" "build" "-p" name "-j" jobs]
    ["dune" "runtest" "-p" name "-j" jobs] {with-test}
    ["dune" "build" "-p" name "@doc"] {with-doc}
  ]
  authors: ["Anil Madhavapeddy" "Rudi Grinberg"]
  bug-reports: "https://github.com/mirage/ocaml-cohttp/issues"
  homepage: "https://github.com/mirage/ocaml-cohttp"
  license: "ISC"
  dev-repo: "git+https://github.com/mirage/ocaml-cohttp.git"
  synopsis: "An OCaml library for HTTP clients and servers"
  description: "A longer description"
  depends: [
    "alcotest" {with-test}
    "dune" {build & > "1.5"}
    "foo" {dev & > "1.5" & < "2.0"}
    "uri" {>= "1.9.0"}
    "uri" {< "2.0.0"}
    "fieldslib" {> "v0.12"}
    "fieldslib" {< "v0.13"}
  ]
  $ cat test-fields/cohttp-async.opam
  # This file is generated by dune, edit dune-project instead
  opam-version: "2.0"
  build: [
    ["dune" "subst"] {pinned}
    ["dune" "build" "-p" name "-j" jobs]
    ["dune" "runtest" "-p" name "-j" jobs] {with-test}
    ["dune" "build" "-p" name "@doc"] {with-doc}
  ]
  authors: ["Anil Madhavapeddy" "Rudi Grinberg"]
  bug-reports: "https://github.com/mirage/ocaml-cohttp/issues"
  homepage: "https://github.com/mirage/ocaml-cohttp"
  license: "ISC"
  dev-repo: "git+https://github.com/mirage/ocaml-cohttp.git"
  synopsis: "HTTP client and server for the Async library"
  description: "A _really_ long description"
  depends: [
    "cohttp" {>= "1.0.2"}
    "conduit-async" {>= "1.0.3"}
    "async" {>= "v0.10.0"}
    "async" {< "v0.12"}
  ]

Fatal error with opam file that is not listed in the dune-project file:

  $ dune build @install --root bad-opam-file --auto-promote
  Entering directory 'bad-opam-file'
  File "foo.opam", line 1, characters 0-0:
  Error: This opam file doesn't have a corresponding (package ...) stanza in
  the dune-project_file. Since you have at least one other (package ...) stanza
  in your dune-project file, you must a (package ...) stanza for each opam
  package in your project.
  [1]

Version generated in opam and META files
----------------------------------------

After calling `dune subst`, dune should embed the version inside the
generated META and opam files.

### With opam files and no package stanzas

  $ mkdir version

  $ cat > version/dune-project <<EOF
  > (lang dune 1.10)
  > (name foo)
  > EOF

  $ cat > version/foo.opam <<EOF
  > EOF

  $ cat > version/dune <<EOF
  > (library (public_name foo))
  > EOF

  $ (cd version
  >  git init -q
  >  git add .
  >  git commit -qm _
  >  git tag -a 1.0 -m 1.0
  >  dune subst)

  $ dune build --root version foo.opam META.foo
  Entering directory 'version'

  $ grep ^version version/foo.opam
  version: "1.0"

  $ grep ^version version/_build/default/META.foo
  version = "1.0"

### With package stanzas and generating the opam files

  $ rm -rf version
  $ mkdir version

  $ cat > version/dune-project <<EOF
  > (lang dune 1.10)
  > (name foo)
  > (generate_opam_files true)
  > (package (name foo))
  > EOF

  $ cat > version/foo.opam <<EOF
  > EOF

  $ cat > version/dune <<EOF
  > (library (public_name foo))
  > EOF

  $ (cd version
  >  git init -q
  >  git add .
  >  git commit -qm _
  >  git tag -a 1.0 -m 1.0
  >  dune subst)

  $ dune build --root version foo.opam META.foo
  Entering directory 'version'

The following behavior is wrong, the version should be set in stone
after running `dune subst`:

  $ grep ^version version/foo.opam
  version: "1.0"

  $ grep ^version version/_build/default/META.foo
  version = "1.0"

Generation of opam files with lang dune >= 1.11
-----------------------------------------------

  $ mkdir gen-v1.11
  $ cat > gen-v1.11/dune-project <<EOF
  > (lang dune 1.11)
  > (name test)
  > (generate_opam_files true)
  > (package (name test))
  > EOF

  $ dune build @install --root gen-v1.11
  Entering directory 'gen-v1.11'
  $ cat gen-v1.11/test.opam
  # This file is generated by dune, edit dune-project instead
  opam-version: "2.0"
  depends: [
    "dune" {>= "1.11"}
  ]
  build: [
    ["dune" "subst"] {pinned}
    [
      "dune"
      "build"
      "-p"
      name
      "-j"
      jobs
      "@install"
      "@runtest" {with-test}
      "@doc" {with-doc}
    ]
  ]

Templates should also be respected with extension fields, in this
case "x-foo":

  $ dune build @install --root test-fields-with-tmpl --auto-promote
  Entering directory 'test-fields-with-tmpl'
  $ cat test-fields-with-tmpl/github.opam
  # This file is generated by dune, edit dune-project instead
  opam-version: "2.0"
  synopsis: "GitHub APIv3 OCaml library"
  description: """
  This library provides an OCaml interface to the
  [GitHub APIv3](https://developer.github.com/v3/) (JSON).
  
  It is compatible with [MirageOS](https://mirage.io) and also compiles to pure
  JavaScript via [js_of_ocaml](http://ocsigen.org/js_of_ocaml)."""
  maintainer: ["Anil Madhavapeddy <anil@recoil.org>"]
  authors: [
    "Anil Madhavapeddy"
    "David Sheets"
    "Andy Ray"
    "Jeff Hammerbacher"
    "Thomas Gazagnaire"
    "Rudi Grinberg"
    "Qi Li"
    "Jeremy Yallop"
    "Dave Tucker"
  ]
  license: "MIT"
  tags: ["org:mirage" "org:xapi-project" "git"]
  homepage: "https://github.com/mirage/ocaml-github"
  doc: "https://mirage.github.io/ocaml-github/"
  bug-reports: "https://github.com/mirage/ocaml-github/issues"
  depends: [
    "dune" {>= "2.0"}
    "ocaml" {>= "4.03.0"}
    "uri" {>= "1.9.0"}
    "cohttp" {>= "0.99.0"}
    "cohttp-lwt" {>= "0.99"}
    "lwt" {>= "2.4.4"}
    "atdgen" {>= "2.0.0"}
    "yojson" {>= "1.6.0"}
    "stringext"
  ]
  build: [
    ["dune" "subst"] {pinned}
    [
      "dune"
      "build"
      "-p"
      name
      "-j"
      jobs
      "@install"
      "@runtest" {with-test}
      "@doc" {with-doc}
    ]
  ]
  dev-repo: "git+https://github.com/mirage/ocaml-github.git"
  x-foo: "an extension field"

And this file should contains a "libraries" field at the end.
It is not sorted since its in a template, which always comes at
the end.

  $ cat test-fields-with-tmpl/github-unix.opam
  # This file is generated by dune, edit dune-project instead
  opam-version: "2.0"
  synopsis: "GitHub APIv3 Unix library"
  description: """
  This library provides an OCaml interface to the [GitHub APIv3](https://developer.github.com/v3/)
  (JSON).  This package installs the Unix (Lwt) version."""
  maintainer: ["Anil Madhavapeddy <anil@recoil.org>"]
  authors: [
    "Anil Madhavapeddy"
    "David Sheets"
    "Andy Ray"
    "Jeff Hammerbacher"
    "Thomas Gazagnaire"
    "Rudi Grinberg"
    "Qi Li"
    "Jeremy Yallop"
    "Dave Tucker"
  ]
  license: "MIT"
  tags: ["org:mirage" "org:xapi-project" "git"]
  homepage: "https://github.com/mirage/ocaml-github"
  doc: "https://mirage.github.io/ocaml-github/"
  bug-reports: "https://github.com/mirage/ocaml-github/issues"
  depends: [
    "dune" {>= "2.0"}
    "ocaml" {>= "4.03.0"}
    "github" {= version}
    "cohttp" {>= "0.99.0"}
    "cohttp-lwt-unix" {>= "0.99.0"}
    "stringext"
    "lambda-term" {>= "2.0"}
    "cmdliner" {>= "0.9.8"}
    "base-unix"
  ]
  build: [
    ["dune" "subst"] {pinned}
    [
      "dune"
      "build"
      "-p"
      name
      "-j"
      jobs
      "@install"
      "@runtest" {with-test}
      "@doc" {with-doc}
    ]
  ]
  dev-repo: "git+https://github.com/mirage/ocaml-github.git"
  libraries: [ "github_unix" ]
