open! Base
open Import

(* TODO: Consider flipping direction to match ordinary fzf behavior *)
(* TODO: Fix selection: now the last filtered thing is shown, but
   really it should be the selection *)
(* TODO: Make incremental version *)
(* TODO: Show filter count *)

module Model = struct
  type t =
    { items: string Map.M(Int).t
    ; filter: string
    ; closed_at: Time.t option
    ; dim: Tty_text.Dimensions.t
    }

  let empty =
    { items = Map.empty (module Int)
    ; filter = ""
    ; closed_at = None
    ; dim = { width = 80; height = 40 }
    }

  let matches t =
    match t.filter with
    | "" -> t.items
    | _ ->
      let re = Re.compile (Re.str t.filter) in
      Map.filter t.items ~f:(fun line -> Re.execp re line)

  let to_widget t ~start ~now =
    let open Tty_text in
    let matches = matches t in
    let matches_to_display =
      Map.to_sequence matches
      |> (fun matches -> Sequence.take matches (t.dim.height - 1))
      |> Sequence.map ~f:snd
      |> Sequence.map ~f:(fun s ->
          String.sub s ~pos:0 ~len:(Int.min (String.length s) t.dim.width))
      |> Sequence.to_list
    in
    let prompt = Widget.of_string ("> " ^ t.filter) in
    let extra_lines = t.dim.height - 1 - List.length matches_to_display in
    let spinner =
      match t.closed_at with
      | Some closed_at ->
        [ Widget.of_string (Time.Span.to_string (Time.diff closed_at start))
        ; Widget.of_string " "]
      | None ->
        [ Widget.of_string (String.of_char (Spinner.char ~spin_every:(Time.Span.of_sec 0.5) ~start ~now))
        ; Widget.of_string " "]
    in
    Widget.vbox
      (List.init extra_lines ~f:(fun _ -> Widget.of_string "")
       @ List.map matches_to_display ~f:Widget.of_string
       @ [ Widget.hbox (spinner @ [prompt])])
end

module Action = struct
  type t =
    | Exit
    | Exit_and_print
end

let handle_user_input (m:Model.t) (input:Tty_text.User_input.t) =
  match input with
  | Backspace ->
    let m = { m with filter = String.drop_suffix m.filter 1 } in
    (m,None)
  | Char x ->
    let m = { m with filter = m.filter ^ String.of_char x } in
    (m,None)
  | Return -> (m,Some Action.Exit_and_print)
  | Escape | Ctrl_c -> (m, Some Action.Exit)
  | Up -> (m, None)
  | Down -> (m, None)

let handle_line (m:Model.t) line =
  let lnum =
    match Map.max_elt m.items with
    | None -> 1
    | Some (num,_) -> num + 1
  in
  { m with items = Map.set m.items ~key:lnum ~data:line }

let handle_closed (m:Model.t) time =
  { m with closed_at = Some time }

let set_dim (m:Model.t) dim =
  { m with dim }
