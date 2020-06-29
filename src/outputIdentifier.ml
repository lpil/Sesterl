
type space = IdentifierScheme.t

type local =
  | ReprLocal of {
      number : int;
      hint   : IdentifierScheme.t option;
    }
  | ReprUnused

type global =
  | ReprGlobal of {
      number        : int;
      function_name : IdentifierScheme.t;
      arity         : int;
    }

type operator =
  | ReprOperator of string

type t =
  | Local    of local
  | Global   of global
  | Operator of operator

type global_answer = {
  function_name : string;
  arity         : int;
}


let space : string -> space option =
  IdentifierScheme.from_upper_camel_case


let fresh_number : unit -> int =
  let current_max = ref 0 in
  (fun () ->
    incr current_max;
    !current_max
  )


let fresh () : local =
  let n = fresh_number () in
  ReprLocal{ hint = None; number = n }


let generate_local (s : string) : local option =
  IdentifierScheme.from_snake_case s |> Option.map (fun ident ->
    let n = fresh_number () in
    ReprLocal{ hint = Some(ident); number = n }
  )


let generate_global (s : string) (arity : int) : global option =
  IdentifierScheme.from_snake_case s |> Option.map (fun ident ->
    let n = fresh_number () in
    ReprGlobal{
      number        = n;
      function_name = ident;
      arity         = arity;
    }
  )


let operator (s : string) : operator =
  ReprOperator(s)


let unused : local =
  ReprUnused


let output_space =
  IdentifierScheme.to_snake_case


let output_local = function
  | ReprLocal(r) ->
      let hint =
        match r.hint with
        | None        -> ""
        | Some(ident) -> IdentifierScheme.to_upper_camel_case ident
      in
      Printf.sprintf "S%d%s" r.number hint

  | ReprUnused ->
      "_"


let output_global = function
  | ReprGlobal(r) ->
      {
        function_name = r.function_name |> IdentifierScheme.to_snake_case;
        arity         = r.arity;
      }


let output_operator = function
  | ReprOperator(s) ->
      s


let pp_space =
  IdentifierScheme.pp


let pp_local ppf = function
  | ReprLocal(r) ->
      begin
        match r.hint with
        | None        -> Format.fprintf ppf "L%d" r.number
        | Some(ident) -> Format.fprintf ppf "L%d%a" r.number IdentifierScheme.pp ident
      end

  | ReprUnused ->
      Format.fprintf ppf "UNUSED"


let pp_global ppf = function
  | ReprGlobal(r) ->
      Format.fprintf ppf "G%d%a/%d"
        r.number
        IdentifierScheme.pp r.function_name
        r.arity


let pp_operator ppf = function
  | ReprOperator(s) ->
      Format.fprintf ppf "O\"%s\"" s


let pp ppf = function
  | Local(l)    -> pp_local ppf l
  | Global(g)   -> pp_global ppf g
  | Operator(o) -> pp_operator ppf o
