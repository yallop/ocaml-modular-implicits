open Btype
open Ctype
open Types
open Typedtree

(* Forward declaration, to be filled in by Typemod.type_package *)

let type_implicit_instance
  : (Env.t -> Typedtree.module_expr -> Path.t -> Longident.t list ->
     type_expr list -> Typedtree.module_expr * type_expr list) ref
  = ref (fun _ -> assert false)

(* Instantiate implicits in a function type

   Given a type expression, find all path refering to an implicit module.
   1. Find any implicit bindings: if none, return the original type.
   2. Generate fresh idents for all implicit bindings, substitute idents in the
      type.
   3. Replace all type constructors referring to an implicit module
      by a fresh type variable and remember the (constr, var) constraint
      association.

   (*If a typed expression is a function containing implicit arguments,
   this produces a new expression corresponding to the function with all
   implicits instantiated together with the hole to be filled with actual
   instances and a set of constraints to be satisfied.*)
*)

type pending_implicit = {
  implicit_id: Ident.t;
  implicit_env: Env.t;
  implicit_loc: Location.t;
  implicit_type: Path.t * Longident.t list * type_expr list;
  mutable implicit_constraints: (Path.t * type_expr) list;
  (* When linking with an implicit module M, a constraint (path, ty) is
     satisfied iff path unify with ty when implicit_id is bound to M in
     implicit_env *)
  implicit_argument: argument;
}

exception Uninstantiable_implicit of pending_implicit

let pending_implicits
  : pending_implicit list ref
  = ref []

let instantiate_implicits_ty loc env ty =
  let rec has_implicit ty = match ty.desc with
    | Tarrow (Tarr_implicit id,_,_,_) -> true
    | Tarrow (_,_,rhs,_) -> has_implicit rhs
    | _ -> false
  in
  if not (has_implicit ty) then [], Ident.empty, ty
  else
    let fresh_implicit id ty =
      let ty = repr ty in
      match ty.desc with
      | Tpackage (p,nl,tl) -> {
          implicit_id = id;
          implicit_env = env;
          implicit_loc = loc;
          implicit_type = (p,nl,tl);
          implicit_constraints = [];
          implicit_argument = {
            arg_flag = Tapp_implicit;
            arg_expression = None
          };
        }
      | _ -> assert false
    in
    let rec extract_implicits ty =
      let ty = repr ty in
      match ty.desc with
      | Tarrow (Tarr_implicit id, lhs, rhs, comm) ->
          (*prerr_endline "found one";*)
          let id' = Ident.rename id in
          let inst = fresh_implicit id' lhs in
          let arguments, instances, subst, rhs' = extract_implicits rhs in
          inst.implicit_argument :: arguments,
          Ident.add id' inst instances,
          Subst.add_implicit id (Path.Pident id') subst,
          rhs'
          (*{ty with desc = Tarrow (Tarr_implicit id', lhs, rhs', comm)}*)
      | Tarrow (arr, lhs, rhs, comm) ->
          let arguments, instances, subst, rhs' = extract_implicits rhs in
          {arg_flag = (tapp_of_tarr arr); arg_expression = None} :: arguments,
          instances, subst,
          {ty with desc = Tarrow (arr, lhs, rhs', comm)}
      | _ -> [], Ident.empty, Subst.identity, ty
    in
    let arguments, instances, subst, ty = extract_implicits ty in
    let ty = Subst.type_expr subst ty in
    (* Set of constraints : maintain a table mapping implicit binding
       identifier to a list of type variable pairs.
       An implicit instance is correct only iff, in an environment where the
       ident is bound to the instance, all pairs in the list unify.
    *)
    let linked = Hashtbl.create 7 in
    let add_constraint inst ~path ~var =
      begin try
        let var' = Hashtbl.find linked path in
        link_type var var'
      with Not_found ->
        Hashtbl.add linked path var
      end;
      inst.implicit_constraints <- (path,var) :: inst.implicit_constraints
    in
    let rec unlink_constructors ty =
      (* First recurse in sub expressions *)
      iter_type_expr unlink_constructors ty;
      (* Then replace current type if it is a constructor referring to an
         implicit *)
      match ty.desc with
      | Tconstr (path,[],_) ->
          begin try
            let inst = Ident.find_same (Path.head path) instances in
            (* Replace `ty' by a fresh variable *)
            let {desc = desc'; level = lv'; id = id'} = newvar() in
            ty.desc   <- desc';
            ty.level  <- lv';
            ty.id     <- id';
            add_constraint inst ~path ~var:ty
          with Not_found -> ()
          end
      (* No HKT *)
      | Tconstr (path,_,_)
        when (try ignore (Ident.find_same (Path.head path) instances); true
              with Not_found -> false) ->
          assert false
      | _ -> ()
    in
    unlink_constructors ty;
    arguments, instances, ty

let instantiate_implicits_expr env expr =
  (*prerr_endline "instantiate_implicits_expr";*)
  match
    instantiate_implicits_ty expr.exp_loc env expr.exp_type
  with
  | [], implicits, _ ->
      (*prerr_endline "none";*)
      implicits,expr
  | arguments, implicits, ty ->
      implicits,
      { exp_desc = Texp_apply (expr, arguments);
        exp_type = ty;
        exp_loc = expr.exp_loc;
        exp_extra = [];
        exp_env = env;
        exp_attributes = []
      }


(* Pack module at given path to match a given implicit instance and
   update the instance to point to this module.
   Return the correct package if any.
*)
let pack_implicit inst path =
  let { implicit_type = p,nl,tl;
        implicit_env  = env;
        implicit_loc  = loc } = inst in
  let md = Env.find_module path env in
  let lident = Location.mkloc (Path.to_longident path) loc in
  let modl = {
    mod_desc = Tmod_ident (path, lident);
    mod_loc = loc;
    mod_type = md.md_type;
    mod_env = env;
    mod_attributes = [];
  } in
  let (modl, tl') = !type_implicit_instance env modl p nl tl in
  {
    exp_desc = Texp_pack modl;
    exp_loc = loc; exp_extra = [];
    exp_type = newty (Tpackage (p, nl, tl'));
    exp_attributes = [];
    exp_env = env;
  }

(* Link a pending implicit to the module at specified path.
   May fail with unifications or module subtyping errors.
*)
let link_implicit_to_path inst path =
  (* Check that all constraints are satisfied *)
  let subst = Subst.add_module inst.implicit_id path Subst.identity in
  List.iter (fun (tpath,ty') ->
      let tpath = Subst.type_path subst tpath in
      let ty = newconstr tpath [] in
      let ty' = Subst.type_expr subst ty' in
      unify inst.implicit_env ty ty'
    )
    inst.implicit_constraints;
  (* Pack the module to appropriate signature *)
  let expr = pack_implicit inst path in
  (* Update the argument *)
  inst.implicit_argument.arg_expression <- Some expr

let link_implicit_to_expr inst expr =
  (* An implicit instance always have to be a path to a module in scope *)
  let rec mod_path me = match me.mod_desc with
    | Tmod_ident (path,_) -> path
    | Tmod_constraint (me,_,_,_) ->
        mod_path me
    | _ -> assert false
  in
  let path = match expr.exp_desc with
    | Texp_pack me -> mod_path me
    | _ -> assert false
  in
  link_implicit_to_path inst path

(* Naive resolution procedure *)
let find_instance inst =
  let snapshot = Btype.snapshot () in
  let modules = Env.implicit_instances inst.implicit_env in
  let module_match (path,_) =
    try
      (*prerr_endline ("try " ^ Path.last path);*)
      link_implicit_to_path inst path;
      true
    with _ ->
      Btype.backtrack snapshot;
      false
  in
  List.exists module_match modules

let generalize_implicits () =
  (*Printf.eprintf "generalize_implicits %d\n%!" (List.length !pending_implicits);*)

  let current_level = get_current_level () in
  let _not_linked = function
    | {implicit_argument = {arg_expression = Some _}} -> false
    | _ -> true
  in
  let pending = (*List.filter not_linked*) !pending_implicits in
  let need_generalization inst =
    List.exists
      (fun (ty,var) ->
         assert (var.level <> generic_level);
         var.level >= current_level)
      inst.implicit_constraints
    || inst.implicit_constraints = []
  in
  let to_generalize, rest =
    List.partition need_generalization pending
  in
  pending_implicits := rest;
  try
    let not_instantiable inst = not (find_instance inst) in
    let inst = List.find not_instantiable to_generalize in
    raise (Uninstantiable_implicit inst)
  with Not_found -> ()

(* Extraction of pending implicit arguments *)
let extract_pending_implicits expr =
  let rec traverse acc = function
    | {exp_desc = Texp_apply (exp,args); _} ->
        let is_pending = function
          | {arg_flag = Tapp_implicit; arg_expression = None} -> true
          | _ -> false
        in
        traverse (List.filter is_pending args @ acc) exp
    | _ -> acc
  in
  List.map (fun argument ->
      List.find (fun inst -> inst.implicit_argument == argument)
        !pending_implicits)
    (traverse [] expr)