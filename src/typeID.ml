
module type S = sig

  type t

  val fresh : string -> t

  val hash : t -> int

  val compare : t -> t -> int

  val equal : t -> t -> bool

  val pp : Format.formatter -> t -> unit

end


module Internal = struct

  type t = {
    number : int;
    name   : string;
  }

  let fresh =
    let current_max = ref 0 in
    (fun name ->
      incr current_max;
      {
        number = !current_max;
        name   = name;
      }
    )

  let hash =
    Hashtbl.hash

  let compare tyid1 tyid2 =
    tyid2.number - tyid1.number

  let equal tyid1 tyid2 =
    tyid1.number = tyid2.number

  let pp ppf tyid =
    Format.fprintf ppf "%s" tyid.name

end


module Variant = Internal

module Synonym = Internal

type t =
  | Variant of Variant.t
  | Synonym of Synonym.t


let hash =
  Hashtbl.hash


let compare tyid1 tyid2 =
  match (tyid1, tyid2) with
  | (Variant(vid1), Variant(vid2)) -> Variant.compare vid1 vid2
  | (Variant(_)   , Synonym(_)   ) -> 1
  | (Synonym(_)   , Variant(_)   ) -> -1
  | (Synonym(sid1), Synonym(sid2)) -> Synonym.compare sid1 sid2


let equal tyid1 tyid2 =
  match (tyid1, tyid2) with
  | (Variant(vid1), Variant(vid2)) -> Variant.equal vid1 vid2
  | (Synonym(sid1), Synonym(sid2)) -> Synonym.equal sid1 sid2
  | _                              -> false


let pp ppf tyid =
  match tyid with
  | Variant(vid) -> Variant.pp ppf vid
  | Synonym(sid) -> Synonym.pp ppf sid
