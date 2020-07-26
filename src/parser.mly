%{
  open Syntax
  open MyUtil

  type 'a range_spec =
    | Token of Range.t
    | Ranged of (Range.t * 'a)


  let make_range rs1 rs2 =
    let aux = function
      | Token(rng)       -> rng
      | Ranged((rng, _)) -> rng
    in
    let rng1 = aux rs1 in
    let rng2 = aux rs2 in
      Range.unite rng1 rng2


  let binary e1 op e2 =
    let rng = make_range (Ranged(e1)) (Ranged(e2)) in
    let (rngop, vop) = op in
    (rng, Apply((rngop, Var(vop)), [e1; e2]))

(*
  let syntax_sugar_module_application : Range.t -> untyped_module -> untyped_module -> untyped_module =
    let fresh =
      let r = ref 0 in
      (fun () -> incr r; Printf.sprintf "SesterlInternalModule%d" !r)
    in
    (* TODO: sophisticate how to generate dummy module identifiers *)
    fun rng utmod1 utmod2 ->
    let modident1 = (Range.dummy "appident1", fresh ()) in
    let modident2 = (Range.dummy "appident2", fresh ()) in
    let modidentA = (Range.dummy "appidentA", fresh ()) in
    let utbinds =
      [
        (Range.dummy "appbind1", BindModule(modident1, utmod1));
        (Range.dummy "appbind2", BindModule(modident2, utmod2));
        (Range.dummy "appbindA", BindModule(modidentA, (Range.dummy "appA", ModApply(modident1, modident2))));
      ]
    in
    (rng, ModProjMod((Range.dummy "appB", ModBinds(utbinds)), modidentA))
*)
%}

%token<Range.t> LET LETREC DEFEQ IN LAMBDA ARROW IF THEN ELSE LPAREN RPAREN LSQUARE RSQUARE TRUE FALSE COMMA DO REVARROW RECEIVE BAR WHEN END UNDERSCORE CONS CASE OF TYPE COLON ANDREC VAL MODULE STRUCT SIGNATURE SIG EXTERNAL INCLUDE COERCE
%token<Range.t> GT_SPACES GT_NOSPACE LTLT LT_EXACT
%token<Range.t * string> IDENT DOTIDENT CTOR DOTCTOR TYPARAM BINOP_AMP BINOP_BAR BINOP_EQ BINOP_LT BINOP_GT
%token<Range.t * string> BINOP_TIMES BINOP_DIVIDES BINOP_PLUS BINOP_MINUS
%token<Range.t * int> INT
%token<Range.t * string> STRING STRING_BLOCK
%token EOI

%start main
%type<Syntax.untyped_binding> bindtop
%type<Syntax.module_name Syntax.ranged * Syntax.untyped_module> main
%type<Syntax.manual_type> ty
%type<Syntax.binder list> params
%type<Syntax.untyped_let_binding> bindvalsingle
%type<Range.t * Syntax.internal_or_external> bindvaltop
%type<Range.t * Syntax.rec_or_nonrec> bindvallocal
%type<Syntax.untyped_module> modexprbot

%%
main:
  | bindmod=bindmod; EOI {
        let (_, modident, utmod) = bindmod in
        (modident, utmod)
      }
;
ident:
  | ident=IDENT { ident }
;
bindtop:
  | TYPE; tybind=bindtypesingle; tybinds=list(bindtypesub) {
        let rng = Range.dummy "bindtop-1" in  (* TODO: give appropriate code range *)
        (rng, BindType(tybind :: tybinds))
      }
  | bindval=bindvaltop {
        let rng = Range.dummy "bindtop-1" in  (* TODO: give appropriate code range *)
        let (_, valbinding) = bindval in
        (rng, BindVal(valbinding))
      }
  | bindmod=bindmod {
        let (rng, modident, utmod) = bindmod in
        (rng, BindModule(modident, utmod))
      }
  | tokL=SIGNATURE; sigident=CTOR; DEFEQ; utsig=sigexpr {
        let rng = make_range (Token(tokL)) (Ranged(utsig)) in
        (rng, BindSig(sigident, utsig))
      }
  | tokL=INCLUDE; utmod=modexpr {
        let rng = make_range (Token(tokL)) (Ranged(utmod)) in
        (rng, BindInclude(utmod))
      }
;
bindmod:
  | tokL=MODULE; modident=CTOR; DEFEQ; utmod=modexpr {
        let rng = make_range (Token(tokL)) (Ranged(utmod)) in
        (rng, modident, utmod)
      }
;
bindtypesingle:
  | ident=IDENT; typarams=typarams; DEFEQ; ctorbrs=nonempty_list(ctorbranch) {
        (ident, typarams, BindVariant(ctorbrs))
      }
  | ident=IDENT; typarams=typarams; DEFEQ; mty=ty {
        (ident, typarams, BindSynonym(mty))
      }
;
bindtypesub:
  | ANDREC; tybind=bindtypesingle { tybind }
;
typarams:
  |                                         { [] }
  | tylparen; typarams=typaramssub tyrparen { typarams }
;
typaramssub:
  |                                          { [] }
  | typaram=TYPARAM                          { typaram :: [] }
  | typaram=TYPARAM; COMMA; tail=typaramssub { typaram :: tail }
;
bindvallocal:
  | tok=LET; valbinding=bindvalsingle {
        (tok, NonRec(valbinding))
      }
  | tok=LETREC; valbinding=bindvalsingle; tail=list(recbinds) {
        (tok, Rec(valbinding :: tail))
      }
;
bindvaltop:
  | local=bindvallocal {
        let (rng, rec_or_nonrec) = local in
        (rng, Internal(rec_or_nonrec))
      }
  | tokL=LET; ident=IDENT; bids=typarams; COLON; mty=ty; DEFEQ; EXTERNAL; inttok=INT; strblock=STRING_BLOCK {
        let (tokR, erlang_bind) = strblock in
        let (_, arity) = inttok in
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        let extbind =
          {
            ext_identifier  = ident;
            ext_type_params = bids;
            ext_type_annot  = mty;
            ext_arity       = arity;
            ext_code        = erlang_bind;
          }
        in
        (rng, External(extbind))
      }
;
recbinds:
  | ANDREC; valbinding=bindvalsingle { valbinding }
;
bindvalsingle:
  | ident=IDENT; bids=typarams; LPAREN; params=params; RPAREN; tyannot=tyannot; DEFEQ; e0=exprlet {
        {
          vb_identifier = ident;
          vb_forall     = bids;
          vb_parameters = params;
          vb_return_type = tyannot;
          vb_body       = e0;
        }
      }
;
ctorbranch:
  | BAR; ctor=CTOR; {
        ConstructorBranch(ctor, [])
      }
  | BAR; ctor=CTOR; LPAREN; paramtys=tys; RPAREN {
        ConstructorBranch(ctor, paramtys)
      }
;
params:
  |                                                  { [] }
  | ident=IDENT; tyannot=tyannot                     { (ident, tyannot) :: [] }
  | ident=IDENT; tyannot=tyannot; COMMA; tail=params { (ident, tyannot) :: tail }
;
tyannot:
  |               { None }
  | COLON; mty=ty { Some(mty) }
;
decl:
  | tokL=VAL; ident=IDENT; typarams=typarams; COLON; mty=ty {
        let rng = make_range (Token(tokL)) (Ranged(mty)) in
        (rng, DeclVal(ident, typarams, mty))
      }
  | tokL=TYPE; tyident=IDENT; CONS; inttok=INT {
        let (tokR, mkind) = inttok in
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, DeclTypeOpaque(tyident, mkind))
      }
  | tokL=MODULE; modident=CTOR; COLON; utsig=sigexpr {
        let rng = make_range (Token(tokL)) (Ranged(utsig)) in
        (rng, DeclModule(modident, utsig))
      }
;
modexpr:
  | tokL=LAMBDA; LPAREN; modident=CTOR; COLON; utsig=sigexpr; RPAREN; ARROW; utmod=modexpr {
        let rng = make_range (Token(tokL)) (Ranged(utmod)) in
        (rng, ModFunctor(modident, utsig, utmod))
      }
  | modident=CTOR; COERCE; utsig=sigexprbot {
        let rng = make_range (Ranged(modident)) (Ranged(utsig)) in
        (rng, ModCoerce(modident, utsig))
      }
  | utmod=modapp { utmod }
;
modapp:
  | modchain1=modchainraw; LPAREN; modchain2=modchainraw; tokR=RPAREN {
        let (modident1, _) = modchain1 in
        let rng = make_range (Ranged(modident1)) (Token(tokR)) in
        (rng, ModApply(modchain1, modchain2))
      }
  | utmod=modexprbot { utmod }
;
modexprbot:
  | tokL=STRUCT; utbinds=list(bindtop); tokR=END {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, ModBinds(utbinds))
      }
  | tokL=LPAREN; utmod=modexpr; tokR=RPAREN {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        let (_, utmodmain) = utmod in
        (rng, utmodmain)
      }
  | utmod=modchain { utmod }
;
modchain:
  | modchainraw=modchainraw {
        let (modident, projs) = modchainraw in
        let utmod =
          let (rng, modnm) = modident in
          (rng, ModVar(modnm))
        in
        projs |> List.fold_left (fun utmod proj ->
          let rng = make_range (Ranged(utmod)) (Ranged(proj)) in
          (rng, ModProjMod(utmod, proj))
        ) utmod
      }
;
modchainraw:
  | modchainacc=modchainacc {
        let (modident, projacc) = modchainacc in
        (modident, Alist.to_list projacc)
      }
;
modchainacc:
  | former=modchainacc; proj=DOTCTOR {
        let (modident, projacc) = former in
        (modident, Alist.extend projacc proj)
      }
  | modident=CTOR {
        (modident, Alist.empty)
      }
;
sigexpr:
  | tokL=LAMBDA; LPAREN; sigident=CTOR; COLON; utsig1=sigexpr; RPAREN; ARROW; utsig2=sigexpr {
        let rng = make_range (Token(tokL)) (Ranged(utsig2)) in
        (rng, SigFunctor(sigident, utsig1, utsig2))
      }
  | utsig=sigexprbot { utsig }
;
sigexprbot:
  | sigident=CTOR {
        let (rng, signm) = sigident in
        (rng, SigVar(signm))
      }
  | LPAREN; utmod=modexprbot; sigident=DOTCTOR; RPAREN {
        let rng = make_range (Ranged(utmod)) (Ranged(sigident)) in
        (rng, SigPath(utmod, sigident))
      }
  | tokL=SIG; utdecls=list(decl); tokR=END {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, SigDecls(utdecls))
      }
  | tokL=LPAREN; utsig=sigexpr; tokR=RPAREN {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        let (_, utsigmain) = utsig in
        (rng, utsigmain)
      }
;
exprlet:
  | bindval=bindvallocal; IN; e2=exprlet {
        let (tokL, valbind) = bindval in
        let rng = make_range (Token(tokL)) (Ranged(e2)) in
        (rng, LetIn(valbind, e2))
      }
  | tokL=LET; pat=patcons; DEFEQ; e1=exprlet; IN; e2=exprlet {
        let rng = make_range (Token(tokL)) (Ranged(e2)) in
        (rng, LetPatIn(pat, e1, e2))
      }
  | tokL=IF; e0=exprlet; THEN; e1=exprlet; ELSE; e2=exprlet {
        let rng = make_range (Token(tokL)) (Ranged(e2)) in
        (rng, If(e0, e1, e2))
      }
  | tokL=DO; ident=IDENT; tyannot=tyannot; REVARROW; e1=exprlet; IN; e2=exprlet {
        let rng = make_range (Token(tokL)) (Ranged(e2)) in
        (rng, Do(Some((ident, tyannot)), e1, e2))
      }
  | tokL=DO; e1=exprlet; IN; e2=exprlet {
        let rng = make_range (Token(tokL)) (Ranged(e2)) in
        (rng, Do(None, e1, e2))
      }
  | e=exprfun { e }
;
exprfun:
  | tokL=LAMBDA; LPAREN; params=params; RPAREN; ARROW; e=exprlet {
        let rng = make_range (Token(tokL)) (Ranged(e)) in
        (rng, Lambda(params, e))
      }
  | tokL=RECEIVE; branches=nonempty_list(branch); tokR=END {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, Receive(branches))
      }
  | tokL=CASE; e=exprlet; OF; branches=nonempty_list(branch); tokR=END {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, Case(e, branches))
      }
  | e=exprland { e }
;
exprland:
  | e1=exprlor; op=BINOP_AMP; e2=exprland { binary e1 op e2 }
  | e=exprlor                             { e }
;
exprlor:
  | e1=exprcomp; op=BINOP_BAR; e2=exprlor { binary e1 op e2 }
  | e=exprcomp                            { e }
;
exprcomp:
  | e1=exprcons; op=BINOP_EQ; e2=exprcomp { binary e1 op e2 }
  | e1=exprcons; op=oplt;     e2=exprcomp { binary e1 op e2 }
  | e1=exprcons; op=opgt;     e2=exprcomp { binary e1 op e2 }
  | e=exprcons                            { e }
;
oplt:
  | op=BINOP_LT  { op }
  | rng=LT_EXACT { (rng, "<") }
;
opgt:
  | op=BINOP_GT    { op }
  | rng=GT_SPACES  { (rng, ">") }
  | rng=GT_NOSPACE { (rng, ">") }
;
exprcons:
  | e1=exprtimes; CONS; e2=exprcons {
        let rng = make_range (Ranged(e1)) (Ranged(e2)) in
        (rng, ListCons(e1, e2))
      }
  | e=exprtimes { e }
;
exprtimes:
  | e1=exprplus; op=BINOP_TIMES; e2=exprtimes   { binary e1 op e2 }
  | e1=exprplus; op=BINOP_DIVIDES; e2=exprtimes { binary e1 op e2 }
  | e=exprplus                                  { e }
;
exprplus:
  | e1=exprapp; op=BINOP_PLUS; e2=exprplus  { binary e1 op e2 }
  | e1=exprapp; op=BINOP_MINUS; e2=exprplus { binary e1 op e2 }
  | e=exprapp                               { e }
;
exprapp:
  | efun=exprapp; LPAREN; eargs=exprargs; tokR=RPAREN {
        let rng = make_range (Ranged(efun)) (Token(tokR)) in
        (rng, Apply(efun, eargs))
      }
  | ctor=CTOR; LPAREN; eargs=exprargs; tokR=RPAREN {
        let (tokL, ctornm) = ctor in
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, Constructor(ctornm, eargs))
      }
  | ctor=CTOR {
        let (rng, ctornm) = ctor in
        (rng, Constructor(ctornm, []))
      }
  | modident=CTOR; ident=DOTIDENT {
        let rng = make_range (Ranged(modident)) (Ranged(ident)) in
        (rng, ModProjVal(modident, ident))
      }
  | e=exprbot { e }
;
exprargs:
  |                                 { [] }
  | e=exprlet;                      { e :: [] }
  | e=exprlet; COMMA; tail=exprargs { e :: tail }
;
exprbot:
  | rng=TRUE                  { (rng, BaseConst(Bool(true))) }
  | rng=FALSE                 { (rng, BaseConst(Bool(false))) }
  | tokL=LPAREN; tokR=RPAREN  { let rng = make_range (Token(tokL)) (Token(tokR)) in (rng, BaseConst(Unit)) }
  | c=INT                     { let (rng, n) = c in (rng, BaseConst(Int(n))) }
  | ident=ident               { let (rng, x) = ident in (rng, Var(x)) }
  | LPAREN; e=exprlet; RPAREN { e }
  | tokL=LPAREN; e1=exprlet; COMMA; e2=exprlet; es=list(tuplesub); tokR=RPAREN {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, Tuple(TupleList.make e1 e2 es))
      }
  | tokL=LSQUARE; es=exprargs; tokR=RSQUARE {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        let dr = Range.dummy "list" in
        let (_, emain) =
          List.fold_right (fun e tail -> (dr, ListCons(e, tail))) es (dr, ListNil)
        in
        (rng, emain)
      }
  | tokL=LTLT; ns=bytes tokR=gtgt {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, BinaryByList(ns))
      }
  | tokL=LTLT; strlit=STRING; tokR=gtgt {
        let (_, s) = strlit in
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, BaseConst(BinaryByString(s)))
      }
;
bytes:
  |                            { [] }
  | tok=INT                    { tok :: [] }
  | tok=INT; COMMA; tail=bytes { tok :: tail }
;
gtgt:
  | GT_NOSPACE; tokR=GT_NOSPACE { tokR }
  | GT_NOSPACE; tokR=GT_SPACES  { tokR }
;
tuplesub:
  COMMA; e=exprlet { e }
;
branch:
  | BAR; pat=patcons; ARROW; e=exprlet {
        Branch(pat, None, e)
      }
  | BAR; pat=patcons; WHEN; ew=exprlet; ARROW; e=exprlet {
        Branch(pat, Some(ew), e)
      }
;
patcons:
  | p1=patbot; CONS; p2=patcons { let rng = make_range (Ranged(p1)) (Ranged(p2)) in (rng, PListCons(p1, p2)) }
  | p=patbot                    { p }
;
patbot:
  | rng=TRUE                 { (rng, PBool(true)) }
  | rng=FALSE                { (rng, PBool(true)) }
  | tokL=LPAREN; tokR=RPAREN { let rng = make_range (Token(tokL)) (Token(tokR)) in (rng, PUnit) }
  | c=INT                    { let (rng, n) = c in (rng, PInt(n)) }
  | ident=ident              { let (rng, x) = ident in (rng, PVar(x)) }
  | rng=UNDERSCORE           { (rng, PWildCard) }
  | tokL=LSQUARE; tokR=RSQUARE { let rng = make_range (Token(tokL)) (Token(tokR)) in (rng, PListNil) }
  | tokL=LPAREN; p1=patcons; COMMA; p2=patcons; pats=list(pattuplesub); tokR=RPAREN {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, PTuple(TupleList.make p1 p2 pats))
      }
  | ctor=CTOR {
        let (rng, ctornm) = ctor in
        (rng, PConstructor(ctornm, []))
      }
  | ctor=CTOR; LPAREN; pats=pats; tokR=RPAREN {
        let (tokL, ctornm) = ctor in
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, PConstructor(ctornm, pats))
      }
;
pats:
  |                               { [] }
  | pat=patcons                   { pat :: [] }
  | pat=patcons; COMMA; tail=pats { pat :: tail }
;
pattuplesub:
  | COMMA; p=patcons { p }
;
tys:
  |                         { [] }
  | mty=ty                  { mty :: [] }
  | mty=ty; COMMA; tail=tys { mty :: tail }
;
ty:
  | utmod=modchain; tyident=DOTIDENT {
        let rng = make_range (Ranged(utmod)) (Ranged(tyident)) in
        (rng, MModProjType(utmod, tyident, []))
      }
  | utmod=modchain; tyident=DOTIDENT; tylparen; mtyargs=tys; tokR=tyrparen {
        let rng = make_range (Ranged(utmod)) (Token(tokR)) in
        (rng, MModProjType(utmod, tyident, mtyargs))
      }
  | mty=tybot { mty }
;
tybot:
  | tok=TYPARAM {
        let (rng, typaram) = tok in
        (rng, MTypeVar(typaram))
      }
  | ident=IDENT {
        let (rng, tynm) = ident in
        (rng, MTypeName(tynm, []))
      }
  | ident=IDENT; tylparen; mtyargs=tys; tokR=tyrparen {
        let (tokL, tynm) = ident in
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, MTypeName(tynm, mtyargs))
      }
  | tokL=LAMBDA; LPAREN; mtydoms=tys; RPAREN; ARROW; mtycod=ty {
        let rng = make_range (Token(tokL)) (Ranged(mtycod)) in
        (rng, MFuncType(mtydoms, mtycod))
      }
  | tokL=LPAREN; mty1=ty; COMMA; mty2=ty; mtys=list(tytuplesub) tokR=RPAREN {
        let rng = make_range (Token(tokL)) (Token(tokR)) in
        (rng, MProductType(TupleList.make mty1 mty2 mtys))
      }
  | tokL=LSQUARE; mty1=ty; RSQUARE; mty2=ty {
        let rng = make_range (Token(tokL)) (Ranged(mty2)) in
        (rng, MEffType(mty1, mty2))
      }
;
tytuplesub:
  | COMMA; mty=ty; { mty }
;
tylparen:
  | tok=LT_EXACT  { tok }
;
tyrparen:
  | tok=GT_NOSPACE { tok }
  | tok=GT_SPACES  { tok }
;
