
open MyUtil
open Syntax
open Errors

exception ConfigError of config_error
exception ParseError  of Range.t


let listup_sources_in_directory (dir : absolute_dir) : absolute_path list =
  let filenames = Core.Sys.ls_dir dir in
  filenames |> List.filter_map (fun filename ->
    if Core.String.is_suffix filename ~suffix:".sest" then
      Some(Filename.concat dir filename)
    else
      None
  )


let make_absolute_path (dir : absolute_dir) (fpath : string) : absolute_path =
  if Filename.is_relative fpath then
    Core.Filename.realpath (Filename.concat dir fpath)
  else
    Core.Filename.realpath fpath


let read_source (fpath_in : absolute_path) : (absolute_path list * (module_name ranged * untyped_module), Range.t) result =
  let inc = open_in fpath_in in
  let lexbuf = Lexing.from_channel inc in
  let fname = Filename.basename fpath_in in
  let res =
    let open ResultMonad in
    ParserInterface.process ~fname:fname lexbuf >>= fun (deps_raw, modident, utmod) ->
    let deps =
      let dir = Filename.dirname fpath_in in
      deps_raw |> List.map (make_absolute_path dir)
    in
    return (deps, (modident, utmod))
  in
  close_in inc;
  res


module ContentMap = Map.Make(String)

type reading_state = {
  loaded : (module_name ranged * untyped_module) ContentMap.t;
  graph  : FileDependencyGraph.t;
}


(* `read_source_recursively abspath` lists up all the parsed source files
   on which `abspath` depends either directly or indirectly,
   and sorts them in a topological order according to the dependency among them. *)
let read_source_recursively (abspath : absolute_path) : (absolute_path * (module_name ranged * untyped_module)) list =
  let rec aux (state : reading_state) (vertex : FileDependencyGraph.vertex) (abspath : absolute_path) : reading_state =
    Logging.begin_to_parse abspath;
    let (deps, content) =
      match read_source abspath with
      | Ok(source) -> source
      | Error(rng) -> raise (ParseError(rng))
    in
    let loaded = state.loaded |> ContentMap.add abspath content in
    deps |> List.fold_left (fun state abspath_sub ->
      let graph = state.graph in
      match graph |> FileDependencyGraph.find_vertex abspath_sub with
      | Some(vertex_sub) ->
        (* If the depended source file has already been parsed *)
          let graph = graph |> FileDependencyGraph.add_edge ~depending:vertex ~depended:vertex_sub in
          { state with graph = graph }

      | None ->
        (* If the depended source file has not been parsed yet *)
          let (graph, vertex_sub) = graph |> FileDependencyGraph.add_vertex abspath_sub in
          let graph = graph |> FileDependencyGraph.add_edge ~depending:vertex ~depended:vertex_sub in
          aux { state with graph = graph } vertex_sub abspath_sub
    ) { state with loaded = loaded }
  in
  let state =
    let (graph, vertex) = FileDependencyGraph.empty |> FileDependencyGraph.add_vertex abspath in
    let state = { graph = graph; loaded = ContentMap.empty } in
    aux state vertex abspath
  in
  match FileDependencyGraph.topological_sort state.graph with
  | Error(cycle) ->
      raise (ConfigError(CyclicFileDependencyFound(cycle)))

  | Ok(sources) ->
      sources |> List.map (fun abspath ->
        match state.loaded |> ContentMap.find_opt abspath with
        | None          -> assert false
        | Some(content) -> (abspath, content)
      )


let main (fpath_in : string) : (absolute_path * (module_name ranged * untyped_module)) list =
  let abspath_in =
    let dir = Sys.getcwd () in
    make_absolute_path dir fpath_in
  in
  let (_, extopt) = Core.Filename.split_extension abspath_in in
  match extopt with
  | Some("sest") ->
      read_source_recursively abspath_in

  | _ ->
      begin
        match ConfigLoader.load abspath_in with
        | Error(e) ->
            raise (ConfigError(ConfigFileError(e)))

        | Ok(config) ->
            let srcdirs = config.ConfigLoader.source_directories in
            let abspaths = srcdirs |> List.map listup_sources_in_directory |> List.concat in
            let _sources = abspaths |> List.map read_source in
            failwith "TODO: SourceLoader.main"
      end
